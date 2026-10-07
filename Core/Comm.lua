local _, ns = ...

-- Talks to the opponent's Duel Tracker by addon whisper. Fields are separated by ":".
--   HELLO:<protocol>:<version>
--       sent to the opponent when a duel is asked for, so both know the other has the addon
--   RESULT:<protocol>:<server time>:<winner>:<loser>:<how>
--       sent after the duel; when both sides report the same result the duel is confirmed.
--       Confirmed duels are the ones a shared rating (like Elo) can trust later on.

local peers = {} -- [full name] = their version, everyone who said hello this session
local reports = {} -- [full name] = their RESULT that arrived before our own result

local function Send(target, ...)
	local message = table.concat({ ... }, ":")
	C_ChatInfo.SendAddonMessage(ns.PREFIX, message, "WHISPER", target)
end

function ns.SendHello(target)
	Send(target, "HELLO", ns.PROTOCOL, ns.VERSION)
end

function ns.SendResult(target, duel)
	local me = ns.GetMyName()
	local winner = duel.won and me or duel.opp
	local loser = duel.won and duel.opp or me
	Send(target, "RESULT", ns.PROTOCOL, duel.t, winner, loser, duel.how)
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
	if ns.SameName(report.winner, winner) and ns.SameName(report.loser, loser) then
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

local function OnResult(sender, t, winner, loser, how)
	local report = { sender = sender, t = tonumber(t) or 0, winner = winner, loser = loser, how = how }
	local duels = ns.GetDB().duels
	for i = #duels, math.max(1, #duels - 20), -1 do
		if Check(duels[i], report) then
			ns.NotifyChanged()
			return
		end
	end
	reports[sender] = report
end

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
	local fields = { strsplit(":", rest) }
	if kind == "HELLO" then
		peers[sender] = fields[1] or "?"
		if ns.OnPeerHello then
			ns.OnPeerHello(sender, peers[sender])
		end
	elseif kind == "RESULT" then
		peers[sender] = peers[sender] or "?"
		OnResult(sender, fields[1], fields[2], fields[3], fields[4])
	end
end)

C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
