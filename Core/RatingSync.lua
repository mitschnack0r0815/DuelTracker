local _, ns = ...

-- Swaps Elo ratings with a duelist when we target them, by addon whisper (nobody sees
-- it in chat). Only with players on our duelists list, at most every
-- ns.RATING_ASK_INTERVAL seconds per player. Messages (see Comm.lua):
--   ASKRATING:<protocol>:<rating>   our rating, asking for theirs
--   RATING:<protocol>:<rating>      their answer
-- Both sides only take ratings from their own duelists, and only answer them.

local asked = {} -- [full name] = GetTime() we last asked them

local function ReadRating(field)
	local rating = tonumber(field)
	return rating and math.floor(rating)
end

local function AskTarget()
	if not UnitIsPlayer("target") or UnitIsUnit("target", "player") or not UnitIsConnected("target")
		or UnitFactionGroup("target") ~= UnitFactionGroup("player") then
		return -- whispers don't reach the other faction
	end
	local name = ns.FindDuelist(GetUnitName("target", true))
	if not name or GetTime() - (asked[name] or -math.huge) < ns.RATING_ASK_INTERVAL then
		return
	end
	asked[name] = GetTime()
	ns.Send(name, "ASKRATING", (ns.GetMyRating()))
end

local function Learn(sender, field)
	local name = ns.FindDuelist(sender)
	local rating = ReadRating(field)
	if name and rating then
		ns.SetDuelistRating(name, rating)
		ns.NotifyChanged()
	end
	return name
end

ns.OnMessage("ASKRATING", function(sender, fields)
	local name = Learn(sender, fields[1])
	if name then
		asked[name] = GetTime() -- we know each other's ratings now, no need to ask back
		ns.Send(name, "RATING", (ns.GetMyRating()))
	end
end)

ns.OnMessage("RATING", function(sender, fields)
	Learn(sender, fields[1])
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", AskTarget)
