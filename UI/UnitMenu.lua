local _, ns = ...

-- Duel Tracker entries in Blizzard's right-click menus on players (target and focus
-- portraits, party and raid frames, names in chat): add to duelists, challenge to an
-- Elo duel, remove from duelists. Only on clients with Menu.ModifyMenu; others simply
-- don't get the entries.
if not (Menu and Menu.ModifyMenu) then
	return
end

local MENUS = {
	"MENU_UNIT_TARGET",
	"MENU_UNIT_FOCUS",
	"MENU_UNIT_PLAYER",
	"MENU_UNIT_PARTY",
	"MENU_UNIT_RAID_PLAYER",
	"MENU_UNIT_FRIEND", -- names in chat
}

-- Full name of the player the menu is for, nil when it's no player or us
local function GetPlayer(contextData)
	if not contextData then
		return nil
	end
	local unit = contextData.unit
	local name
	if unit and UnitExists(unit) then
		if not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then
			return nil
		end
		name = GetUnitName(unit, true)
	elseif contextData.name then
		name = contextData.server and contextData.server ~= ""
			and contextData.name .. "-" .. contextData.server or contextData.name
	end
	if not name or ns.SameName(name, ns.GetMyName()) then
		return nil
	end
	return ns.FullName(name), unit and select(2, UnitClass(unit)) or nil
end

local function AddEntries(owner, rootDescription, contextData)
	local name, class = GetPlayer(contextData)
	if not name then
		return
	end
	rootDescription:CreateDivider()
	rootDescription:CreateTitle("Duel Tracker")

	local duelist = ns.FindDuelist(name)
	if not duelist then
		rootDescription:CreateButton("Add to duelists", function()
			local added, fullName = ns.AddDuelist(name, class)
			if added then
				print(("Duel Tracker: %s is now one of your duelists."):format(ns.InkName(fullName)))
			end
		end)
		return
	end

	local challenge = rootDescription:CreateButton("Challenge to an Elo duel", function()
		local ok, reason = ns.ChallengeElo(duelist)
		print("Duel Tracker: " .. (ok and ("challenged %s to an Elo duel."):format(ns.InkName(duelist)) or reason))
	end)
	if ns.GetOutgoingChallenge() and challenge.SetEnabled then
		challenge:SetEnabled(false) -- still waiting for an answer to another one
	end
	rootDescription:CreateButton("Remove from duelists", function()
		StaticPopup_Show("DUELTRACKER_REMOVE_DUELIST", ns.InkName(duelist), nil, duelist)
	end)
end

for _, tag in ipairs(MENUS) do
	Menu.ModifyMenu(tag, AddEntries)
end
