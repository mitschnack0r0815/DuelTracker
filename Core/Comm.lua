local _, ns = ...

-- Talks to other Duel Trackers by addon whisper. Fields are separated by ":".
--   HELLO:<protocol>:<version>
--       sent to the opponent when a duel is asked for, so both know the other has the addon
--   RESULT:<protocol>:<server time>:<winner>:<loser>:<how>:<elo>
--       sent after the duel, elo is 1 for an Elo duel; when both sides report the same
--       result (and both or neither call it an Elo duel) the duel is confirmed
--   CHALLENGE, ACCEPT, DECLINE, WAIT: asking for an Elo duel, see Challenge.lua
--   ASKRATING, RATING: swapping Elo ratings when targeting a duelist, see RatingSync.lua
--
-- The game drops addon messages sent too fast, so everything goes through a queue that
-- sends ns.SEND_BURST at once and then ns.SEND_RATE per second.

local peers = {} -- [full name] = their version, everyone who said hello this session
local reports = {} -- [full name] = their RESULT that arrived before our own result
local handlers = {} -- [kind] = function(sender, fields), see ns.OnMessage
local whispered = {} -- [full name] = GetTime() of our last whisper to them

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

local queue = {}
local tokens, refilled = ns.SEND_BURST, GetTime()
local pumping = false

local function Pump()
	pumping = false
	local now = GetTime()
	tokens = math.min(ns.SEND_BURST, tokens + (now - refilled) * ns.SEND_RATE)
	refilled = now
	while tokens >= 1 and #queue > 0 do
		local message = table.remove(queue, 1)
		whispered[message.target] = now
		C_ChatInfo.SendAddonMessage(ns.PREFIX, message.text, "WHISPER", message.target)
		tokens = tokens - 1
	end
	if #queue > 0 then
		pumping = true
		C_Timer.After(1 / ns.SEND_RATE, Pump)
	end
end

-- Send(target, kind, ...): the protocol goes after the kind
function ns.Send(target, kind, ...)
	queue[#queue + 1] = { target = target, text = table.concat({ kind, ns.PROTOCOL, ... }, ":") }
	if not pumping then
		Pump()
	end
end

-- Handles messages of that kind: handler(sender, fields), fields split at ":"
function ns.OnMessage(kind, handler)
	handlers[kind] = handler
end

---------------------------------------------------------------------------
-- Offline players
---------------------------------------------------------------------------

-- Whispering someone offline makes the game say so in chat. For our own addon whispers
-- that's noise: hide it and tell ns.OnPlayerOffline instead.
local NOT_FOUND = (ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.")
	:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)")
local OFFLINE_WINDOW = 5 -- seconds after our whisper the message may arrive

local function FilterOffline(self, event, message)
	local name = message:match("^" .. NOT_FOUND .. "$")
	name = name and ns.FullName(name)
	local sent = name and whispered[name]
	if sent and GetTime() - sent <= OFFLINE_WINDOW then
		if ns.OnPlayerOffline then
			ns.OnPlayerOffline(name)
		end
		return true
	end
	return false
end

local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddFilter then
	AddFilter("CHAT_MSG_SYSTEM", FilterOffline)
end

---------------------------------------------------------------------------
-- Duel results
---------------------------------------------------------------------------

function ns.SendHello(target)
	ns.Send(target, "HELLO", ns.VERSION)
end

function ns.SendResult(target, duel)
	local me = ns.GetMyName()
	local winner = duel.won and me or duel.opp
	local loser = duel.won and duel.opp or me
	ns.Send(target, "RESULT", duel.t, winner, loser, duel.how, duel.elo and 1 or 0)
end

-- Their version when the player has Duel Tracker (as far as we know this session)
function ns.GetPeerVersion(name)
	return peers[ns.FullName(name)]
end

-- Compares their report with our duel; true when it was about this duel
local function Check(duel, report)
	if duel.me ~= ns.GetMyName() or duel.opp ~= report.sender
		or math.abs(duel.t - report.t) > ns.RESULT_MATCH_WINDOW
		or duel.confirmed or duel.disputed then
		return false
	end
	local winner = duel.won and duel.me or duel.opp
	local loser = duel.won and duel.opp or duel.me
	if ns.SameName(report.winner, winner) and ns.SameName(report.loser, loser)
		and (duel.elo == true) == report.elo then
		duel.confirmed = true
	else
		duel.disputed = true
	end
	return true
end

-- Called with our own new duel: picks up a report that arrived first
function ns.CheckReport(duel)
	local report = reports[duel.opp]
	if report and Check(duel, report) then
		reports[duel.opp] = nil
	end
end

ns.OnMessage("HELLO", function(sender, fields)
	peers[sender] = fields[1] or "?"
	if ns.OnPeerHello then
		ns.OnPeerHello(sender, peers[sender])
	end
end)

ns.OnMessage("RESULT", function(sender, fields)
	peers[sender] = peers[sender] or "?"
	local report = { sender = sender, t = tonumber(fields[1]) or 0, winner = fields[2], loser = fields[3],
		how = fields[4], elo = fields[5] == "1" }
	local duels = ns.GetDB().duels
	for i = #duels, math.max(1, #duels - 20), -1 do
		if Check(duels[i], report) then
			ns.NotifyChanged()
			return
		end
	end
	reports[sender] = report
end)

---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
	if prefix ~= ns.PREFIX then
		return
	end
	sender = ns.FullName(sender)
	local kind, protocol, rest = message:match("^(%u+):(%d+):?(.*)$")
	if not kind or tonumber(protocol) > ns.PROTOCOL then
		return -- a newer version we can't read
	end
	local handler = handlers[kind]
	if handler then
		handler(sender, { strsplit(":", rest) })
	end
end)

C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
