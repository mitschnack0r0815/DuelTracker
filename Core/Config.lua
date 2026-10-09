local _, ns = ...

ns.ICON = "Interface\\Icons\\Ability_DualWield" -- two swords
ns.ELO_ICON = "Interface\\PvPRankBadges\\PvPRank06" -- badge behind the names in Elo duels
ns.LOG_ICON = "Interface\\Icons\\INV_Scroll_03" -- before the length of duels with a log

local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.VERSION = GetAddOnMetadata("DuelTracker", "Version") or "?"

-- Addon messages between Duel Tracker users. PROTOCOL goes up when the messages change
-- in a way older versions can't read; they ignore messages with a higher protocol.
ns.PREFIX = "DuelTracker"
ns.PROTOCOL = 1

-- Only the newest duels keep their combat log, it's by far the biggest part of the data.
-- Older duels keep their result and the damage and healing totals.
ns.KEEP_LOGS = 50
ns.MAX_LOG_EVENTS = 1500 -- per duel, the totals keep counting after that

-- The combat log file is written from the duel request until this many seconds after the
-- result, or at most MAX_DUEL_SECONDS when no result ever comes
ns.LOG_AFTER_DUEL = 3
ns.MAX_DUEL_SECONDS = 600

-- The opponent's starting health is taken when the fight starts, or when they first show
-- up as a unit (target, mouseover, nameplate) at most this many seconds later
ns.START_HEALTH_GRACE = 3

-- How one-sided a duel was, by the gap between both players' health at the end in percent
-- of their max health: the first entry whose limit the gap is within. Colors (r, g, b)
-- go from pale for a close fight to fluorescent green when you won big and deep red when
-- you lost big.
ns.VERDICTS = {
	{ limit = 15, text = "Close fight", win = { 0.75, 0.95, 0.7 }, loss = { 1, 0.75, 0.7 } },
	{ limit = 30, text = "Fair fight", win = { 0.55, 0.92, 0.5 }, loss = { 1, 0.55, 0.5 } },
	{ limit = 60, text = "Comfortable win", win = { 0.35, 0.95, 0.3 }, loss = { 0.95, 0.35, 0.3 } },
	{ limit = 90, text = "Clear winner", win = { 0.2, 1, 0.15 }, loss = { 0.85, 0.15, 0.1 } },
	{ limit = 100, text = "Obliterated", win = { 0.3, 1, 0 }, loss = { 0.65, 0, 0 } },
}

-- Made-up duels added by the "Add test duels" button and /duels test
ns.TEST_DUELS = 25

-- Seconds between tries to inspect the opponent for their talents
ns.INSPECT_INTERVAL = 3

-- DUEL_FINISHED also fires when a duel is declined or cancelled; when no result message
-- arrives within this many seconds the duel didn't happen
ns.CANCEL_DELAY = 2

-- The opponent's result report has to be at most this many seconds off our own
ns.RESULT_MATCH_WINDOW = 120

-- Elo duel challenges: seconds the challenged player has to answer, seconds to wait for
-- their Duel Tracker to say it got the challenge at all, and seconds after accepting
-- in which the next duel between the two has to be asked for to be an Elo duel
ns.CHALLENGE_ANSWER_SECONDS = 60
ns.CHALLENGE_REPLY_SECONDS = 5
ns.CHALLENGE_START_SECONDS = 60

-- Addon messages: how many may go out at once, then how many per second
ns.SEND_BURST = 8
ns.SEND_RATE = 1

-- Elo ratings: everyone starts at ELO_START, ELO_K is how much one duel can move it
ns.ELO_START = 1500
ns.ELO_K = 32

-- Targeting a duelist asks for their Elo rating, at most every this many seconds each
ns.RATING_ASK_INTERVAL = 300
