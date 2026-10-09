local _, ns = ...

SLASH_DUELTRACKER1 = "/dueltracker"
SLASH_DUELTRACKER2 = "/duels"
SlashCmdList["DUELTRACKER"] = function(msg)
	msg = msg:trim()
	if msg == "minimap" then
		ns.ToggleMinimapButton()
	elseif msg == "record" then
		local wins, losses = ns.GetRecord()
		print(("Duel Tracker: %d wins, %d losses."):format(wins, losses))
		for _, opponent in ipairs(ns.GetOpponents()) do
			print(("  %s  %d-%d"):format(ns.ColorName(opponent.name, opponent.class), opponent.wins, opponent.losses))
		end
	elseif msg:match("^test%s*%d*$") then
		local count = tonumber(msg:match("%d+")) or ns.TEST_DUELS
		ns.AddTestData(count)
		print(("Duel Tracker: added %d test duels. Type /duels cleartest to remove them."):format(count))
	elseif msg:match("^logtest%s*%d*$") then
		-- Writes the combat log file for that many seconds (default 3)
		ns.TestCombatLogFile(tonumber(msg:match("%d+")))
	elseif msg:match("^add%s") or msg == "add" then
		-- /duels add <name>, or your target without a name
		local name, class = msg:match("^add%s+(.+)$"), nil
		if not name and UnitIsPlayer("target") then
			name, class = GetUnitName("target", true), select(2, UnitClass("target"))
		end
		local added, fullName = ns.AddDuelist(name, class)
		if added then
			print(("Duel Tracker: %s is now one of your duelists."):format(ns.InkName(fullName)))
		else
			print("Duel Tracker: /duels add <name>, or target a player.")
		end
	elseif msg:match("^remove%s+.+$") then
		local name = msg:match("^remove%s+(.+)$")
		if ns.RemoveDuelist(name) then
			print(("Duel Tracker: removed %s from your duelists."):format(name))
		else
			print(("Duel Tracker: %s isn't one of your duelists."):format(name))
		end
	elseif msg:match("^elo%s") or msg == "elo" then
		-- /duels elo <name>, or your target without a name
		local name = msg:match("^elo%s+(.+)$") or (UnitIsPlayer("target") and GetUnitName("target", true))
		local ok, reason = ns.ChallengeElo(name)
		if ok then
			print(("Duel Tracker: challenged %s to an Elo duel."):format(ns.InkName(ns.FindDuelist(name))))
		else
			print("Duel Tracker: " .. (name and reason or "/duels elo <name>, or target a duelist."))
		end
	elseif msg == "duelists" then
		ns.ShowDuelistsTab()
	elseif msg == "cleartest" then
		print(("Duel Tracker: removed %d test duels."):format(ns.ClearTestData()))
	elseif msg ~= "" then
		-- /duels <name>: record against that player
		local wins, losses = ns.GetRecord(ns.FullName(msg))
		print(("Duel Tracker: %d-%d against %s."):format(wins, losses, msg))
	else
		ns.ToggleWindow()
	end
end
