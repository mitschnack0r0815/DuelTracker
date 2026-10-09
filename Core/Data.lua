local _, ns = ...

-- DuelTrackerDB (account-wide, so alts can be compared later; every duel says who fought it):
--   duels = list, oldest first, of {
--     t         finished, server time (GetServerTime)
--     start, ends   asked for and finished, local clock (time()) like the combat log file;
--               start is missing when we didn't see the duel being asked for
--     logged    true when the combat log file was on, Logs\WoWCombatLog-*.txt has the duel
--     me, opp   "Name-Realm" of our character and the opponent
--     myGUID, oppGUID   to find the two of us in the combat log file (oppGUID if known)
--     myClass, myLevel, oppClass, oppLevel   class file names ("WARRIOR"), levels if known
--     mySpec, oppSpec   talent tree with the most points, { name, icon, points = "31/20/0" };
--               nil when two trees are tied or the opponent couldn't be inspected
--     won       true when we won
--     how       "knockout" or "fled"
--     dur       seconds from the start of the fight (entering combat) to the end
--     health    { start = snapshot, ends = snapshot }, snapshot = { me = { hp, max },
--               opp = { hp, max } }; a side is missing when its health couldn't be read
--     peer      the opponent's Duel Tracker version, when they have it
--     confirmed true when the opponent's Duel Tracker reported the same result,
--     disputed  true when it reported a different one (both nil: no report)
--     elo       true for an Elo duel: both sides agreed on it before (Challenge.lua)
--     myElo, oppElo   both ratings before an Elo duel, as swapped when it was agreed on
--     eloChange how much our rating moved (theirs moved the other way); missing on
--               Elo duels from before ratings were swapped
--     sum, log  only on test duels for now; later filled in from the combat log file
--     sum       { [1] = our side, [2] = theirs }, side = { dmg, heal, hits, crits,
--               spells = { [spell name] = damage } }
--     log       combat log, only on the newest ns.KEEP_LOGS duels: list of
--               { t = seconds after the first hit, e = combat log event, s = source,
--                 d = destination (1 us, 2 opponent, nil none), n = spell name,
--                 a = amount, c = true on crits, x = miss type, aura type or other spell }
--   }
--   settings = { combatLog = true for extended logging: the combat log file during duels
--                and the Log tab (off by default),
--                rankFrom = { [2] .. [14] = lowest rating of each rank } when changed
--                on the Config tab, testTab = true while the Test tab is shown }
--   logging = true while we have the combat log file on (switched off again after a reload)
--   minimap = { angle, hide }
--   duelists = { ["Name-Realm"] = { added = server time, class, test, rating, ratingT } },
--               the players we can challenge to Elo duels (when they have us on their
--               list too). rating is theirs as last heard (ratingT, server time) from
--               them. test = true when the test data put them there
--
-- Wins, losses and our Elo rating are counted from the duel list: the rating is
-- ns.ELO_START plus the eloChange of every Elo duel the opponent didn't dispute.

function ns.GetDB()
	DuelTrackerDB = DuelTrackerDB or {}
	DuelTrackerDB.duels = DuelTrackerDB.duels or {}
	DuelTrackerDB.settings = DuelTrackerDB.settings or {}
	DuelTrackerDB.duelists = DuelTrackerDB.duelists or {}
	return DuelTrackerDB
end

-- "Name" -> "Name-Realm"; names that already have a realm stay as they are
function ns.FullName(name)
	if not name or name:find("-", 1, true) then
		return name
	end
	return name .. "-" .. GetNormalizedRealmName()
end

function ns.ShortName(name)
	return (name:gsub("%-.*$", ""))
end

function ns.SameName(a, b)
	return a and b and ns.FullName(a) == ns.FullName(b)
end

function ns.GetMyName()
	return ns.FullName(UnitName("player"))
end

function ns.AddDuel(duel)
	local duels = ns.GetDB().duels
	duels[#duels + 1] = duel
	for i = #duels - ns.KEEP_LOGS, 1, -1 do
		duels[i].log = nil
	end
	ns.NotifyChanged()
end

function ns.NotifyChanged()
	if ns.OnDuelsChanged then
		ns.OnDuelsChanged()
	end
end

-- Duels of our current character, newest first; only against opp when given
function ns.GetDuels(opp)
	local me = ns.GetMyName()
	local list = {}
	local duels = ns.GetDB().duels
	for i = #duels, 1, -1 do
		local duel = duels[i]
		if duel.me == me and (not opp or duel.opp == opp) then
			list[#list + 1] = duel
		end
	end
	-- Test duels are added after real ones with older times
	table.sort(list, function(a, b)
		return a.t > b.t
	end)
	return list
end

-- The opponent's rating after an Elo duel that counts (not disputed), else nil
local function RatingAfter(duel)
	if duel.eloChange and not duel.disputed then
		return duel.oppElo - duel.eloChange
	end
end

-- Everyone our current character dueled: { { name, class, spec, wins, losses, last,
-- rating }, ... }, most duels first, then the latest fought; spec from the latest duel.
-- rating is theirs as last heard: after our latest Elo duel or from a newer swap with
-- them as a duelist; nil when we never heard one.
function ns.GetOpponents()
	local byName = {}
	local list = {}
	for _, duel in ipairs(ns.GetDuels()) do
		local opponent = byName[duel.opp]
		if not opponent then
			opponent = { name = duel.opp, class = duel.oppClass, spec = duel.oppSpec, wins = 0, losses = 0, last = duel.t }
			byName[duel.opp] = opponent
			list[#list + 1] = opponent
		end
		opponent.class = opponent.class or duel.oppClass
		if duel.won then
			opponent.wins = opponent.wins + 1
		else
			opponent.losses = opponent.losses + 1
		end
		-- Newest first: the first Elo duel that counts has their latest rating
		if not opponent.rating and RatingAfter(duel) then
			opponent.rating, opponent.ratingT = RatingAfter(duel), duel.t
		end
	end
	local duelists = ns.GetDB().duelists
	for _, opponent in ipairs(list) do
		local duelist = duelists[ns.FindDuelist(opponent.name) or ""]
		if duelist and duelist.rating and (duelist.ratingT or 0) > (opponent.ratingT or 0) then
			opponent.rating = duelist.rating
		end
	end
	table.sort(list, function(a, b)
		local countA, countB = a.wins + a.losses, b.wins + b.losses
		if countA ~= countB then
			return countA > countB
		end
		return a.last > b.last
	end)
	return list
end

-- Wins and losses of our current character, against opp or everyone
function ns.GetRecord(opp)
	local wins, losses = 0, 0
	for _, duel in ipairs(ns.GetDuels(opp)) do
		if duel.won then
			wins = wins + 1
		else
			losses = losses + 1
		end
	end
	return wins, losses
end

---------------------------------------------------------------------------
-- Duelists: the players we play Elo duels with
---------------------------------------------------------------------------

function ns.IsDuelist(name)
	return name ~= nil and ns.GetDB().duelists[ns.FullName(name)] ~= nil
end

-- The list's spelling of name ("Name-Realm") when they're on it, in any case
function ns.FindDuelist(name)
	if not name then
		return nil
	end
	local wanted = ns.FullName(name:trim()):lower()
	for key in pairs(ns.GetDB().duelists) do
		if key:lower() == wanted then
			return key
		end
	end
end

-- "name" or "Name-Realm"; capitalized like the game does. false when it's us or no name.
function ns.AddDuelist(name, class)
	name = name and name:trim()
	if not name or name == "" then
		return false
	end
	local short, realm = name:match("^([^%-]+)(.*)$") -- the realm keeps its spelling
	if not short then
		return false
	end
	name = ns.FullName(short:sub(1, 1):upper() .. short:sub(2):lower() .. realm)
	if ns.SameName(name, ns.GetMyName()) then
		return false
	end
	local duelists = ns.GetDB().duelists
	duelists[name] = duelists[name] or { added = GetServerTime() }
	duelists[name].class = class or duelists[name].class
	duelists[name].test = nil -- added by hand: stays when the test data goes
	ns.NotifyChanged()
	return true, name
end

-- false when they weren't on the list
function ns.RemoveDuelist(name)
	local key = ns.FindDuelist(name) -- typed names may be spelled in any case
	if not key then
		return false
	end
	ns.GetDB().duelists[key] = nil
	ns.NotifyChanged()
	return true
end

-- { { name, class, added, wins, losses, rating }, ... } by name; wins and losses of our
-- current character in Elo duels against them, their rating as last heard (nil: never)
function ns.GetDuelists()
	local list = {}
	local byName = {}
	for name, info in pairs(ns.GetDB().duelists) do
		local duelist = { name = name, class = info.class, added = info.added, wins = 0, losses = 0,
			rating = info.rating, ratingT = info.ratingT or 0 }
		byName[name] = duelist
		list[#list + 1] = duelist
	end
	for _, duel in ipairs(ns.GetDuels()) do
		local duelist = byName[duel.opp]
		if duelist then
			duelist.class = duelist.class or duel.oppClass
			-- Newest first: the first Elo duel tells their rating after it, unless they
			-- told us a newer one. Disputed duels count neither way.
			if RatingAfter(duel) and duel.t > duelist.ratingT then
				duelist.rating, duelist.ratingT = RatingAfter(duel), duel.t
			end
			if duel.elo and not duel.disputed then
				if duel.won then
					duelist.wins = duelist.wins + 1
				else
					duelist.losses = duelist.losses + 1
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

---------------------------------------------------------------------------
-- Elo
---------------------------------------------------------------------------

-- How much our rating moves in a duel between these two ratings (theirs moves the other
-- way by the same amount, so both sides get the same numbers)
function ns.EloChange(mine, theirs, won)
	-- Always rounded from the winner's side, so both addons get exactly the same number
	local winner, loser = mine, theirs
	if not won then
		winner, loser = theirs, mine
	end
	local expected = 1 / (1 + 10 ^ ((loser - winner) / 400))
	local gain = math.floor(ns.ELO_K * (1 - expected) + 0.5)
	return won and gain or -gain
end

-- Our current character's rating and how many Elo duels it's made of
function ns.GetMyRating()
	local rating, games = ns.ELO_START, 0
	for _, duel in ipairs(ns.GetDuels()) do
		if duel.eloChange and not duel.disputed then
			rating = rating + duel.eloChange
			games = games + 1
		end
	end
	return rating, games
end

---------------------------------------------------------------------------
-- Rank badges: the PvP rank badges 1-14 by rating
---------------------------------------------------------------------------

local RANK_NAMES = {
	Alliance = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major", "Knight",
		"Knight-Lieutenant", "Knight-Captain", "Knight-Champion", "Lieutenant Commander", "Commander",
		"Marshal", "Field Marshal", "Grand Marshal" },
	Horde = { "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant", "Stone Guard",
		"Blood Guard", "Legionnaire", "Centurion", "Champion", "Lieutenant General", "General",
		"Warlord", "High Warlord" },
}

-- The lowest rating of each rank, rankFrom[2] .. rankFrom[ns.RANKS], spread evenly so
-- that rank 2 starts at min and the top rank at max
function ns.EvenRankThresholds(min, max)
	local from = {}
	local step = (max - min) / (ns.RANKS - 2)
	for rank = 2, ns.RANKS do
		from[rank] = math.ceil(min + (rank - 2) * step)
	end
	return from
end

-- The lowest rating of each rank 2 .. ns.RANKS (rank 1 is everything below rank 2): as
-- set on the Config tab, else spread evenly between ns.RANK_MIN and ns.RANK_MAX
function ns.GetRankThresholds()
	return ns.GetDB().settings.rankFrom or ns.EvenRankThresholds(ns.RANK_MIN, ns.RANK_MAX)
end

-- nil when every rank starts above the one before it, else the first rank that doesn't
-- (or has no number). Each rank ends where the next starts, so ranges can't overlap.
function ns.CheckRankThresholds(from)
	for rank = 2, ns.RANKS do
		if type(from[rank]) ~= "number" or (rank > 2 and from[rank] <= from[rank - 1]) then
			return rank
		end
	end
end

-- Saves the lowest rating of each rank; nil goes back to the defaults. false when they
-- don't go up rank by rank.
function ns.SetRankThresholds(from)
	if from and ns.CheckRankThresholds(from) then
		return false
	end
	local saved
	if from then
		saved = {}
		for rank = 2, ns.RANKS do
			saved[rank] = from[rank]
		end
	end
	ns.GetDB().settings.rankFrom = saved
	ns.NotifyChanged()
	return true
end

function ns.GetRank(rating)
	local from = ns.GetRankThresholds()
	for rank = ns.RANKS, 2, -1 do
		if rating >= from[rank] then
			return rank
		end
	end
	return 1
end

-- Lowest and highest whole rating of a rank; nil for the open end
function ns.GetRankRange(rank)
	local from = ns.GetRankThresholds()
	if rank == 1 then
		return nil, from[2] - 1
	elseif rank == ns.RANKS then
		return from[rank], nil
	end
	return from[rank], from[rank + 1] - 1
end

function ns.GetRankIcon(rank)
	return ("Interface\\PvPRankBadges\\PvPRank%02d"):format(rank)
end

-- The rank's name for our faction
function ns.GetRankName(rank)
	local names = RANK_NAMES[UnitFactionGroup("player")] or RANK_NAMES.Alliance
	return names[rank]
end

-- "[badge] 1546": a rating with its rank badge; size is the badge's size
function ns.RatingText(rating, size)
	size = size or 16
	return ("|T%s:%d:%d|t %d"):format(ns.GetRankIcon(ns.GetRank(rating)), size, size, rating)
end

-- Remembers a duelist's rating as they told it
function ns.SetDuelistRating(name, rating)
	local key = ns.FindDuelist(name) -- the game's spelling may differ from the list's
	local duelist = key and ns.GetDB().duelists[key]
	if duelist and rating then
		duelist.rating, duelist.ratingT = rating, GetServerTime()
	end
end

-- Name in its class color, without the realm when it's ours
function ns.ColorName(name, class)
	local short = ns.FullName(name) == ns.FullName(ns.ShortName(name)) and ns.ShortName(name) or name
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color and color.colorStr then
		return ("|c%s%s|r"):format(color.colorStr, short)
	end
	return short
end
