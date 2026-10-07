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
--     sum, log  only on test duels for now; later filled in from the combat log file
--     sum       { [1] = our side, [2] = theirs }, side = { dmg, heal, hits, crits,
--               spells = { [spell name] = damage } }
--     log       combat log, only on the newest ns.KEEP_LOGS duels: list of
--               { t = seconds after the first hit, e = combat log event, s = source,
--                 d = destination (1 us, 2 opponent, nil none), n = spell name,
--                 a = amount, c = true on crits, x = miss type, aura type or other spell }
--   }
--   settings = { combatLog = true to write the combat log file during duels (off by default) }
--   logging = true while we have the combat log file on (switched off again after a reload)
--   minimap = { angle, hide }
--
-- Wins and losses are counted from the duel list, so a future rating (like Elo) can be
-- computed from the same list; confirmed duels are the ones both sides agree on.

function ns.GetDB()
	DuelTrackerDB = DuelTrackerDB or {}
	DuelTrackerDB.duels = DuelTrackerDB.duels or {}
	DuelTrackerDB.settings = DuelTrackerDB.settings or {}
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

-- Everyone our current character dueled: { { name, class, spec, wins, losses, last }, ... },
-- most duels first, then the latest fought; spec from the latest duel
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

-- Name in its class color, without the realm when it's ours
function ns.ColorName(name, class)
	local short = ns.FullName(name) == ns.FullName(ns.ShortName(name)) and ns.ShortName(name) or name
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color and color.colorStr then
		return ("|c%s%s|r"):format(color.colorStr, short)
	end
	return short
end
