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
