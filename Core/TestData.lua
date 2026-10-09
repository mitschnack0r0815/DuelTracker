local _, ns = ...

-- Made-up duels to try the window with: /duels test adds some, /duels cleartest removes
-- them. They're marked test = true and belong to the character that made them.
-- Opponents with duelist = true go on the duelists list (marked test = true there too,
-- unless they were on it already) and their duels are confirmed Elo duels.

local OPPONENTS = {
	{ name = "Grimbash", class = "WARRIOR", level = 60, duelist = true },
	{ name = "Lunaria", class = "PRIEST", level = 58, duelist = true },
	{ name = "Shadowstep", class = "ROGUE", level = 60, duelist = true },
	{ name = "Frostbyte", class = "MAGE", level = 55 },
	{ name = "Thornpaw", class = "DRUID", level = 60 },
	{ name = "Holyhammer", class = "PALADIN", level = 47 },
	{ name = "Boltzmann", class = "SHAMAN", level = 60 },
}

local SPELLS = {
	WARRIOR = { "Mortal Strike", "Heroic Strike", "Overpower", "Hamstring" },
	PRIEST = { "Mind Blast", "Shadow Word: Pain", "Smite", "Mind Flay" },
	ROGUE = { "Sinister Strike", "Backstab", "Eviscerate", "Ambush" },
	MAGE = { "Frostbolt", "Fireball", "Fire Blast", "Arcane Missiles" },
	DRUID = { "Wrath", "Moonfire", "Shred", "Claw" },
	PALADIN = { "Seal of Righteousness", "Judgement", "Holy Shock", "Exorcism" },
	SHAMAN = { "Lightning Bolt", "Earth Shock", "Flame Shock", "Stormstrike" },
	HUNTER = { "Arcane Shot", "Aimed Shot", "Multi-Shot", "Serpent Sting" },
	WARLOCK = { "Shadow Bolt", "Corruption", "Immolate", "Searing Pain" },
}

local HEALS = {
	PRIEST = "Flash Heal", DRUID = "Healing Touch", PALADIN = "Holy Light", SHAMAN = "Healing Wave",
}

local MISSES = { "MISS", "DODGE", "PARRY", "RESIST" }
local MAX_HEALTH = 3000

-- Talent trees with their tab icons
local function Icon(name)
	return "Interface\\Icons\\" .. name
end
local TREES = {
	WARRIOR = { { "Arms", Icon("Ability_Warrior_SavageBlow") }, { "Fury", Icon("Ability_Warrior_InnerRage") }, { "Protection", Icon("INV_Shield_06") } },
	PRIEST = { { "Discipline", Icon("Spell_Holy_WordFortitude") }, { "Holy", Icon("Spell_Holy_HolyBolt") }, { "Shadow", Icon("Spell_Shadow_ShadowWordPain") } },
	ROGUE = { { "Assassination", Icon("Ability_Rogue_Eviscerate") }, { "Combat", Icon("Ability_BackStab") }, { "Subtlety", Icon("Ability_Stealth") } },
	MAGE = { { "Arcane", Icon("Spell_Holy_MagicalSentry") }, { "Fire", Icon("Spell_Fire_FireBolt02") }, { "Frost", Icon("Spell_Frost_FrostBolt02") } },
	DRUID = { { "Balance", Icon("Spell_Nature_StarFall") }, { "Feral Combat", Icon("Ability_Racial_BearForm") }, { "Restoration", Icon("Spell_Nature_HealingTouch") } },
	PALADIN = { { "Holy", Icon("Spell_Holy_HolyBolt") }, { "Protection", Icon("Spell_Holy_DevotionAura") }, { "Retribution", Icon("Spell_Holy_AuraOfLight") } },
	SHAMAN = { { "Elemental", Icon("Spell_Nature_Lightning") }, { "Enhancement", Icon("Spell_Nature_LightningShield") }, { "Restoration", Icon("Spell_Nature_MagicImmunity") } },
	HUNTER = { { "Beast Mastery", Icon("Ability_Hunter_BeastTaming") }, { "Marksmanship", Icon("Ability_Marksmanship") }, { "Survival", Icon("Ability_Hunter_SwiftStrike") } },
	WARLOCK = { { "Affliction", Icon("Spell_Shadow_DeathCoil") }, { "Demonology", Icon("Spell_Shadow_Metamorphosis") }, { "Destruction", Icon("Spell_Shadow_RainOfFire") } },
}

local function Pick(list)
	return list[math.random(#list)]
end

-- A made-up spec like a real one; sometimes nil, as for a tie or a failed inspect
local function MakeSpec(class)
	local trees = TREES[class]
	if not trees or math.random(6) == 1 then
		return nil
	end
	local main = math.random(3)
	local points = { 0, 0, 0 }
	points[main] = math.random(31, 41)
	points[main % 3 + 1] = math.random(0, 51 - points[main])
	return { name = trees[main][1], icon = trees[main][2], points = table.concat(points, "/") }
end

local function NewSide()
	return { dmg = 0, heal = 0, hits = 0, crits = 0, spells = {} }
end

-- A fight where the loser runs out of health first (or runs away at the end)
local function MakeFight(myClass, oppClass, won, how)
	local classes = { myClass, oppClass }
	local health = { MAX_HEALTH, MAX_HEALTH }
	local sum = { NewSide(), NewSide() }
	local log = {}
	local loser = won and 2 or 1
	local t = 0
	-- The winner hits a bit harder, so the fight ends the right way round
	while health[loser] > 0 and #log < 300 do
		t = t + math.random(5, 20) / 10
		local src = math.random(2)
		local dst = 3 - src
		local class = classes[src]
		if HEALS[class] and health[src] < 1500 and math.random(4) == 1 then
			local amount = math.random(400, 900)
			health[src] = math.min(MAX_HEALTH, health[src] + amount)
			sum[src].heal = sum[src].heal + amount
			log[#log + 1] = { t = t, e = "SPELL_HEAL", s = src, d = src, n = HEALS[class], a = amount }
		elseif math.random(8) == 1 then
			local melee = math.random(2) == 1
			log[#log + 1] = { t = t, e = melee and "SWING_MISSED" or "SPELL_MISSED", s = src, d = dst,
				n = melee and (MELEE or "Melee") or Pick(SPELLS[class] or SPELLS.WARRIOR), x = Pick(MISSES) }
		else
			local melee = math.random(3) == 1
			local spell = melee and (MELEE or "Melee") or Pick(SPELLS[class] or SPELLS.WARRIOR)
			local crit = math.random(5) == 1
			local amount = math.random(80, 320) * (crit and 2 or 1) + (dst == loser and 60 or 0)
			health[dst] = health[dst] - amount
			local side = sum[src]
			side.dmg = side.dmg + amount
			side.hits = side.hits + 1
			side.crits = side.crits + (crit and 1 or 0)
			side.spells[spell] = (side.spells[spell] or 0) + amount
			log[#log + 1] = { t = t, e = melee and "SWING_DAMAGE" or "SPELL_DAMAGE", s = src, d = dst,
				n = spell, a = amount, c = crit or nil }
		end
		if how == "fled" and health[loser] < 1200 then
			break -- the loser runs off
		end
	end
	-- Duels end at 1 health, never below
	return sum, log, t, { math.max(1, health[1]), math.max(1, health[2]) }
end

-- Puts the test duelists on the list; ones already there stay real
local function AddTestDuelists()
	local duelists = ns.GetDB().duelists
	for _, opponent in ipairs(OPPONENTS) do
		local name = ns.FullName(opponent.name)
		if opponent.duelist and not duelists[name] then
			duelists[name] = { added = GetServerTime(), class = opponent.class, test = true }
		end
	end
end

function ns.AddTestData(count)
	AddTestDuelists()
	local me = ns.GetMyName()
	local myClass = select(2, UnitClass("player"))
	local now = GetServerTime()
	local duels = {}
	for i = 1, count do
		local opponent = Pick(OPPONENTS)
		local won = math.random(100) <= 55
		local how = math.random(6) == 1 and "fled" or "knockout"
		local sum, log, duration, health = MakeFight(myClass, opponent.class, won, how)
		local peer = math.random(3) > 1 and ns.VERSION or nil
		duels[i] = {
			test = true,
			t = now - math.random(60, 30 * 24 * 3600),
			me = me,
			opp = ns.FullName(opponent.name),
			myClass = myClass,
			myLevel = UnitLevel("player"),
			oppClass = opponent.class,
			oppLevel = opponent.level,
			mySpec = MakeSpec(myClass),
			oppSpec = MakeSpec(opponent.class),
			won = won,
			how = how,
			dur = math.floor(duration * 10 + 0.5) / 10,
			peer = peer,
			confirmed = peer and math.random(10) > 1 or nil,
			sum = sum,
			log = log,
			health = {
				start = { me = { hp = MAX_HEALTH, max = MAX_HEALTH }, opp = { hp = MAX_HEALTH, max = MAX_HEALTH } },
				ends = { me = { hp = health[1], max = MAX_HEALTH }, opp = { hp = health[2], max = MAX_HEALTH } },
			},
		}
		-- Elo duels against duelists, both sides agreeing on the result
		if opponent.duelist or ns.IsDuelist(duels[i].opp) then
			duels[i].elo = true
			duels[i].peer = ns.VERSION
			duels[i].confirmed = true
		end
		duels[i].disputed = duels[i].peer and not duels[i].confirmed or nil
	end
	-- Oldest first, like real duels, then through AddDuel so old logs get dropped
	table.sort(duels, function(a, b)
		return a.t < b.t
	end)
	-- Elo in that order, the duelists starting somewhere around the default rating
	local mine = ns.GetMyRating()
	local theirs = {}
	for _, duel in ipairs(duels) do
		if duel.elo then
			theirs[duel.opp] = theirs[duel.opp] or ns.ELO_START + math.random(-150, 150)
			duel.myElo, duel.oppElo = mine, theirs[duel.opp]
			duel.eloChange = ns.EloChange(mine, theirs[duel.opp], duel.won)
			mine = mine + duel.eloChange
			theirs[duel.opp] = theirs[duel.opp] - duel.eloChange
		end
	end
	for _, duel in ipairs(duels) do
		ns.AddDuel(duel)
	end
end

-- Also takes the test duelists off the list. Returns how many duels were removed
function ns.ClearTestData()
	local duels = ns.GetDB().duels
	local removed = 0
	for i = #duels, 1, -1 do
		if duels[i].test then
			table.remove(duels, i)
			removed = removed + 1
		end
	end
	local duelists = ns.GetDB().duelists
	for name, duelist in pairs(duelists) do
		if duelist.test then
			duelists[name] = nil
		end
	end
	ns.NotifyChanged()
	return removed
end
