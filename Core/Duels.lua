local _, ns = ...

-- A duel starts when someone asks for it: DUEL_REQUESTED when we're asked, our StartDuel()
-- call when we ask. The game announces the result as a system message ("X has defeated Y
-- in a duel"), which is also shown for duels nearby, so only messages naming us count.
-- DUEL_FINISHED without such a message means the duel was declined or cancelled.
--
-- Addons can't read the combat log on this client, but the game can still write it to
-- Logs\WoWCombatLog-*.txt. So we switch that file on when a duel is asked for and off
-- after it ends, and save the duel's local start and end times and both GUIDs; a tool
-- outside the game can then cut each duel out of the file.

local current -- the duel asked for or being fought, see Begin

---------------------------------------------------------------------------
-- Result messages
---------------------------------------------------------------------------

-- "%2$s has fled from %1$s in a duel" -> a pattern capturing the names, and for each
-- capture which argument of the format it is
local function ToPattern(format)
	local order = {}
	local pattern = format:gsub("%%(%d)%$s", function(n)
		order[#order + 1] = tonumber(n)
		return "\001"
	end)
	pattern = pattern:gsub("%%s", function()
		order[#order + 1] = #order + 1
		return "\001"
	end)
	pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	return "^" .. pattern:gsub("\001", "(.+)") .. "$", order
end

-- Both formats take the winner first and the loser second
local RESULTS = {}
for how, format in pairs({
	knockout = DUEL_WINNER_KNOCKOUT or "%1$s has defeated %2$s in a duel",
	fled = DUEL_WINNER_RETREAT or "%2$s has fled from %1$s in a duel",
}) do
	local pattern, order = ToPattern(format)
	RESULTS[#RESULTS + 1] = { how = how, pattern = pattern, order = order }
end

-- winner, loser, how; nil when it's not a duel result
local function ParseResult(message)
	for _, result in ipairs(RESULTS) do
		local captures = { message:match(result.pattern) }
		if #captures == #result.order then
			local args = {}
			for i, n in ipairs(result.order) do
				args[n] = captures[i]
			end
			return args[1], args[2], result.how
		end
	end
end

---------------------------------------------------------------------------
-- Combat log file
---------------------------------------------------------------------------

-- Only when the setting is on (Log tab, off by default). Only switches it off when we
-- switched it on; DuelTrackerDB.logging remembers that across a reload in a duel.
local function StartLogging()
	if ns.IsCombatLogEnabled() and not ns.GetDB().logging and not LoggingCombat() then
		LoggingCombat(true)
		ns.GetDB().logging = true
	end
end

local function StopLogging()
	if ns.GetDB().logging then
		ns.GetDB().logging = nil
		LoggingCombat(false)
	end
end

function ns.IsCombatLogEnabled()
	return ns.GetDB().settings.combatLog == true
end

-- Switching it off also stops a file we're writing right now
function ns.SetCombatLogEnabled(enabled)
	ns.GetDB().settings.combatLog = enabled or nil
	if not enabled then
		StopLogging()
	end
end

-- Keeps writing a little longer, so the last hits make it into the file
local function StopLoggingSoon()
	local stopping = current
	C_Timer.After(ns.LOG_AFTER_DUEL, function()
		if not current or current == stopping then
			StopLogging()
		end
	end)
end

---------------------------------------------------------------------------
-- Duels
---------------------------------------------------------------------------

-- Class file name and level of a player, when the client knows them
local function GetInfo(guid)
	if not guid then
		return nil, nil
	end
	local _, class = GetPlayerInfoByGUID(guid)
	for _, unit in ipairs({ "target", "focus", "mouseover", "targettarget" }) do
		if UnitGUID(unit) == guid then
			return class, UnitLevel(unit)
		end
	end
	return class, nil
end

---------------------------------------------------------------------------
-- Specs
---------------------------------------------------------------------------

-- The talent tree with the most points: { name, icon, points = "31/20/0" }, nil when two
-- trees are tied (or no talents spent). inspect reads the inspected player's talents.
local function ReadSpec(inspect)
	if not GetNumTalentTabs or not GetTalentTabInfo then
		return nil
	end
	local best, bestPoints, tied = nil, 0, false
	local points = {}
	for i = 1, GetNumTalentTabs(inspect) do
		-- Classic returns name, icon, points; later clients id, name, description, icon, points
		local info = { GetTalentTabInfo(i, inspect) }
		local name, icon, spent
		if type(info[1]) == "number" then
			name, icon, spent = info[2], info[4], info[5]
		else
			name, icon, spent = info[1], info[2], info[3]
		end
		spent = tonumber(spent) or 0
		points[i] = spent
		if spent > bestPoints then
			best, bestPoints, tied = { name = name, icon = icon }, spent, false
		elseif spent == bestPoints then
			tied = true
		end
	end
	if not best or tied then
		return nil
	end
	best.points = table.concat(points, "/")
	return best
end

-- Asks the server for the opponent's talents; INSPECT_READY brings them. Only works
-- close by, so it's tried whenever we see them as a unit, at most every few seconds.
local function TryInspect(unit)
	if not current or current.oppSpec or not current.oppGUID or UnitGUID(unit) ~= current.oppGUID
		or not CanInspect(unit) or GetTime() - (current.inspected or 0) < ns.INSPECT_INTERVAL then
		return
	end
	-- Don't take over the inspect window when it's open
	if InspectFrame and InspectFrame:IsShown() then
		return
	end
	current.inspected = GetTime()
	NotifyInspect(unit)
end

local function OnInspectReady(guid)
	if current and guid == current.oppGUID and current.inspected and not current.oppSpec then
		current.oppSpec = ReadSpec(true)
		if not (InspectFrame and InspectFrame:IsShown()) then
			ClearInspectPlayer()
		end
	end
end

-- Learns the opponent's GUID, class and level from a unit that is them
local function LearnFromUnit(unit)
	if current and UnitIsPlayer(unit) and ns.FullName(GetUnitName(unit, true)) == current.opp then
		current.oppGUID = UnitGUID(unit)
		current.oppClass = select(2, UnitClass(unit))
		current.oppLevel = UnitLevel(unit)
		TryInspect(unit)
	end
end

local function Begin(name, guid)
	current = {
		opp = ns.FullName(name),
		oppGUID = guid,
		start = time(), -- local clock, like the combat log file
	}
	current.oppClass, current.oppLevel = GetInfo(guid)
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		LearnFromUnit(unit)
	end
	current.peer = ns.GetPeerVersion(current.opp)
	ns.SendHello(current.opp)
	StartLogging()
	-- A request nobody answers may never finish: stop the file after a while
	local fight = current
	C_Timer.After(ns.MAX_DUEL_SECONDS, function()
		if current == fight then
			current = nil
			StopLogging()
		end
	end)
end

function ns.OnPeerHello(sender, version)
	if current and current.opp == sender then
		current.peer = version
	end
end

---------------------------------------------------------------------------
-- Health snapshots
---------------------------------------------------------------------------

-- { hp, max } of a unit; nil when unknown or when the client hides the numbers
-- (secret values can be shown but not stored or compared)
local function ReadHealth(unit)
	local hp, max = UnitHealth(unit), UnitHealthMax(unit)
	if issecretvalue and (issecretvalue(hp) or issecretvalue(max)) then
		return nil
	end
	if not hp or not max or max <= 0 then
		return nil
	end
	return { hp = hp, max = max }
end

-- A unit token for that GUID, if the opponent is one right now
local function FindUnit(guid)
	if not guid then
		return nil
	end
	for _, unit in ipairs({ "target", "focus", "mouseover", "targettarget" }) do
		if UnitGUID(unit) == guid then
			return unit
		end
	end
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if UnitGUID(unit) == guid then
			return unit
		end
	end
end

-- { me = { hp, max }, opp = { hp, max } }; opp is missing when they're no unit right now
local function SnapshotHealth(oppGUID)
	local unit = FindUnit(oppGUID)
	return { me = ReadHealth("player"), opp = unit and ReadHealth(unit) or nil }
end

-- Entering combat after the duel was asked for: the fight starts
local function OnFightStart()
	if current and not current.fightStart then
		current.fightStart = GetTime()
		current.healthStart = SnapshotHealth(current.oppGUID)
	end
end

-- The opponent wasn't a unit when the fight started: take their health the first time
-- they are, if that's still close to the start
local function FillStartHealth(unit)
	local fight = current
	if fight and fight.healthStart and not fight.healthStart.opp and fight.oppGUID
		and UnitGUID(unit) == fight.oppGUID and GetTime() - fight.fightStart <= ns.START_HEALTH_GRACE then
		fight.healthStart.opp = ReadHealth(unit)
	end
end

---------------------------------------------------------------------------

local function Finish(winner, loser, how)
	local me = UnitName("player")
	local won = ns.SameName(winner, me)
	if not won and not ns.SameName(loser, me) then
		return -- someone else's duel nearby
	end
	local opp = ns.FullName(won and loser or winner)
	-- A result without a duel we saw start (say after a /reload) still counts
	local fight = current and current.opp == opp and current or nil

	local duel = {
		t = GetServerTime(),
		ends = time(),
		me = ns.GetMyName(),
		myGUID = UnitGUID("player"),
		opp = opp,
		myClass = select(2, UnitClass("player")),
		myLevel = UnitLevel("player"),
		won = won,
		how = how,
		mySpec = ReadSpec(false),
	}
	if fight then
		duel.oppSpec = fight.oppSpec
		local oppClass, oppLevel = GetInfo(fight.oppGUID)
		duel.start = fight.start
		duel.oppGUID = fight.oppGUID
		duel.oppClass = fight.oppClass or oppClass
		duel.oppLevel = oppLevel or fight.oppLevel
		duel.peer = fight.peer
		if fight.fightStart then
			duel.dur = math.floor((GetTime() - fight.fightStart) * 10 + 0.5) / 10
			duel.health = { start = fight.healthStart, ends = SnapshotHealth(fight.oppGUID) }
		end
	end
	duel.peer = duel.peer or ns.GetPeerVersion(opp)
	if ns.GetDB().logging or LoggingCombat() then
		duel.logged = true -- the combat log file has it
	end

	StopLoggingSoon()
	current = nil
	ns.AddDuel(duel)
	ns.CheckReport(duel)
	ns.SendResult(opp, duel)

	local wins, losses = ns.GetRecord(opp)
	print(("Duel Tracker: you %s %s (%d-%d against them)."):format(
		won and "beat" or "lost to", ns.ColorName(opp, duel.oppClass), wins, losses))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- We ask: StartDuel(unit) from the unit menu, or StartDuel(name) from /duel
hooksecurefunc("StartDuel", function(unit)
	unit = (unit == nil or unit == "") and "target" or unit
	if UnitExists(unit) then
		if UnitIsPlayer(unit) then
			Begin(GetUnitName(unit, true), UnitGUID(unit))
		end
	else
		Begin(unit, nil)
	end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("DUEL_REQUESTED")
frame:RegisterEvent("DUEL_FINISHED")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("INSPECT_READY")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "CHAT_MSG_SYSTEM" then
		local winner, loser, how = ParseResult((...))
		if winner then
			Finish(winner, loser, how)
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		OnFightStart()
	elseif event == "PLAYER_TARGET_CHANGED" then
		LearnFromUnit("target")
		FillStartHealth("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		LearnFromUnit("mouseover")
		FillStartHealth("mouseover")
	elseif event == "NAME_PLATE_UNIT_ADDED" then
		FillStartHealth((...))
	elseif event == "INSPECT_READY" then
		OnInspectReady((...))
	elseif event == "DUEL_REQUESTED" then
		Begin((...), nil)
	elseif event == "DUEL_FINISHED" then
		local fight = current
		C_Timer.After(ns.CANCEL_DELAY, function()
			if fight and current == fight then
				current = nil -- no result: declined or cancelled
				StopLogging()
			end
		end)
	elseif event == "PLAYER_LOGIN" then
		-- We switched the file on before a reload or logout and the duel is gone now
		StopLogging()
	end
end)
