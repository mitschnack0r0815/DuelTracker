local _, ns = ...

-- Elo duels are agreed on before the duel, between two players who have each other on
-- their duelists lists. Both send their rating along, so after the duel both sides
-- compute the same change from the same two numbers. Messages (see Comm.lua):
--   CHALLENGE:<protocol>:<rating>   we ask them for an Elo duel
--   WAIT:<protocol>                 their Duel Tracker shows the yes/no popup now
--   ACCEPT:<protocol>:<rating>      they clicked Accept
--   DECLINE:<protocol>:<reason>     "declined" (or no answer in time), "notfriend" when
--                                   we're not on their list, "busy" when another
--                                   challenge is open
-- No WAIT or DECLINE at all: they don't have Duel Tracker, or are offline.
-- After an accept either of the two asks for the duel the usual way; the next duel
-- between them asked for within ns.CHALLENGE_START_SECONDS is an Elo duel. A declined
-- duel request doesn't use the agreement up, a fought duel does (Duels.lua).

local POPUP = "DUELTRACKER_ELO_CHALLENGE"

local outgoing -- { opp, answered }, our challenge waiting for an answer
local agreements = {} -- [full name] = { untilTime = GetTime(), rating = theirs }

local function Name(name)
	local duelist = ns.GetDB().duelists[ns.FindDuelist(name) or name]
	return ns.ColorName(name, duelist and duelist.class)
end

-- A rating from a message; ns.ELO_START when it's missing or garbled
local function ReadRating(field)
	local rating = tonumber(field)
	return rating and math.floor(rating) or ns.ELO_START
end

-- name is the game's spelling (like the duel's opponent), not necessarily the list's
local function Agree(name, rating)
	ns.SetDuelistRating(name, rating)
	agreements[name] = { untilTime = GetTime() + ns.CHALLENGE_START_SECONDS, rating = rating }
	ns.MarkCurrentElo(name, rating) -- the duel may have been asked for already
end

-- Their rating when we agreed on an Elo duel with name a short while ago, else nil.
-- Stays valid when a duel request is declined, until ns.EndEloAgreement after a duel.
function ns.GetEloAgreement(name)
	local agreement = agreements[name]
	if agreement and GetTime() <= agreement.untilTime then
		return agreement.rating
	end
end

-- An Elo duel with name was fought: the agreement is used up
function ns.EndEloAgreement(name)
	agreements[name] = nil
end

-- Full name of the player we challenged and wait for, if any
function ns.GetOutgoingChallenge()
	return outgoing and outgoing.opp
end

local function EndChallenge(challenge, message)
	if challenge and outgoing == challenge then
		outgoing = nil
		print("Duel Tracker: " .. message)
		ns.NotifyChanged()
	end
end

-- Challenges a duelist to an Elo duel; false and the reason when we can't
function ns.ChallengeElo(name)
	local opp = ns.FindDuelist(name)
	if not opp then
		return false, "you can only challenge players on your duelists list."
	end
	if outgoing then
		return false, ("still waiting for %s to answer."):format(Name(outgoing.opp))
	end
	local challenge = { opp = opp }
	outgoing = challenge
	ns.Send(opp, "CHALLENGE", (ns.GetMyRating()))
	C_Timer.After(ns.CHALLENGE_REPLY_SECONDS, function()
		if not challenge.answered then
			EndChallenge(challenge, ("no answer from %s. They need Duel Tracker and have to be online."):format(Name(opp)))
		end
	end)
	C_Timer.After(ns.CHALLENGE_REPLY_SECONDS + ns.CHALLENGE_ANSWER_SECONDS, function()
		EndChallenge(challenge, ("%s didn't answer your Elo duel challenge."):format(Name(opp)))
	end)
	ns.NotifyChanged()
	return true
end

-- The game says they're offline (Comm.lua)
function ns.OnPlayerOffline(name)
	if outgoing and outgoing.opp == name then
		EndChallenge(outgoing, ("%s is offline."):format(Name(name)))
	end
end

---------------------------------------------------------------------------
-- Being challenged
---------------------------------------------------------------------------

-- data = { name = the challenger's full name, rating = theirs }. OnCancel also runs when
-- the popup times out.
StaticPopupDialogs[POPUP] = {
	text = "%s challenges you to an Elo duel.\n\nWhen you accept, your next duel with them within a minute counts for your Elo ratings.",
	button1 = ACCEPT or "Accept",
	button2 = DECLINE or "Decline",
	OnAccept = function(self, data)
		Agree(data.name, data.rating)
		ns.Send(data.name, "ACCEPT", (ns.GetMyRating()))
		print(("Duel Tracker: Elo duel agreed with %s, start the duel within a minute."):format(Name(data.name)))
	end,
	OnCancel = function(self, data)
		ns.Send(data.name, "DECLINE", "declined")
	end,
	timeout = ns.CHALLENGE_ANSWER_SECONDS,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3, -- avoids the taint of the first popup slots
}

ns.OnMessage("CHALLENGE", function(sender, fields)
	local name = ns.FindDuelist(sender)
	if not name then
		ns.Send(sender, "DECLINE", "notfriend")
	elseif StaticPopup_FindVisible(POPUP) then
		ns.Send(sender, "DECLINE", "busy")
	else
		local rating = ReadRating(fields[1])
		ns.Send(sender, "WAIT")
		-- The sender's spelling: the duel is recorded under the game's spelling too
		StaticPopup_Show(POPUP, ("%s (%d)"):format(Name(sender), rating), nil, { name = sender, rating = rating })
		PlaySound(SOUNDKIT.READY_CHECK)
	end
end)

---------------------------------------------------------------------------
-- Answers to our challenge
---------------------------------------------------------------------------

local DECLINED = {
	declined = "%s declined your Elo duel challenge.",
	notfriend = "%s doesn't have you on their duelists list, so you can't challenge them yet.",
	busy = "%s is answering another challenge right now, try again in a moment.",
}

-- An answer to a challenge we're not waiting for (any more) is ignored
local function IsOurs(sender)
	return outgoing ~= nil and outgoing.opp == sender
end

ns.OnMessage("WAIT", function(sender)
	if IsOurs(sender) then
		outgoing.answered = true
	end
end)

ns.OnMessage("ACCEPT", function(sender, fields)
	if IsOurs(sender) then
		outgoing = nil
		local rating = ReadRating(fields[1])
		Agree(sender, rating)
		print(("Duel Tracker: %s (%d) accepted your Elo duel challenge, start the duel within a minute.")
			:format(Name(sender), rating))
		ns.NotifyChanged()
	end
end)

ns.OnMessage("DECLINE", function(sender, fields)
	if IsOurs(sender) then
		EndChallenge(outgoing, (DECLINED[fields[1]] or DECLINED.declined):format(Name(sender)))
	end
end)
