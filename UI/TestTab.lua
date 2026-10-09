local _, ns = ...
local Book = ns.Book

-- Test tab, only when ns.SHOW_TEST_TAB is on; right-click on the minimap button shows
-- or hides it (saved, hidden by default). Left page: add and clear made-up duels and
-- duelists (like /duels test and /duels cleartest). Right page: try writing the combat
-- log file (like /duels logtest).
if not ns.SHOW_TEST_TAB then
	return
end

local CONTENT_X = Book.CONTENT_X
local BUTTON_WIDTH = 150

local panel, tabIndex = ns.AddTab("Test")
local left, right = panel.left, panel.right

local function Text(page, font, y)
	local text = Book.CreateText(page, font or Book.SMALL_FONT)
	text:SetPoint("TOPLEFT", CONTENT_X, y)
	text:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
	text:SetWordWrap(true)
	return text
end

local function Button(page, text, y, onClick)
	local button = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	button:SetSize(BUTTON_WIDTH, 24)
	button:SetPoint("TOPLEFT", CONTENT_X, y)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

---------------------------------------------------------------------------
-- Left page: test data
---------------------------------------------------------------------------

Book.CreateHeader(left, "Test data")

Text(left, Book.TEXT_FONT, -100):SetText(("Made-up duels to try the window with, %d at a time. Some are Elo "
	.. "duels against three test duelists, who go on your Duelists list. Clearing removes all of "
	.. "them again; your real duels and duelists stay."):format(ns.TEST_DUELS))

local addButton = Button(left, "Add test duels", -180, function()
	ns.AddTestData(ns.TEST_DUELS)
	print(("Duel Tracker: added %d test duels."):format(ns.TEST_DUELS))
end)

local clearButton = Button(left, "Clear test data", -180, function()
	print(("Duel Tracker: removed %d test duels."):format(ns.ClearTestData()))
end)
clearButton:ClearAllPoints()
clearButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)

local counts = Text(left, nil, -222)

local function RefreshCounts()
	local duels, duelists = 0, 0
	for _, duel in ipairs(ns.GetDB().duels) do
		duels = duels + (duel.test and 1 or 0)
	end
	for _, duelist in pairs(ns.GetDB().duelists) do
		duelists = duelists + (duelist.test and 1 or 0)
	end
	counts:SetText(("Test data now: %d duels, %d duelists."):format(duels, duelists))
	clearButton:SetEnabled(duels + duelists > 0)
end

---------------------------------------------------------------------------
-- Right page: combat log file
---------------------------------------------------------------------------

Book.CreateHeader(right, "Combat log file")

Text(right, Book.TEXT_FONT, -100):SetText("Switches the game's combat log file on for 3 seconds and "
	.. "off again, and says in chat whether that worked. Look for WoWCombatLog*.txt in the "
	.. "game's Logs folder afterwards.")

Button(right, "Test for 3 seconds", -180, function()
	ns.TestCombatLogFile(3)
end)

---------------------------------------------------------------------------

panel.Refresh = RefreshCounts
panel:SetScript("OnShow", RefreshCounts)

---------------------------------------------------------------------------
-- Shown or hidden from the minimap button
---------------------------------------------------------------------------

-- Shows or hides the Test tab; shown, the window opens on it
function ns.ToggleTestTab()
	local settings = ns.GetDB().settings
	settings.testTab = not settings.testTab or nil
	ns.SetTabShown(tabIndex, settings.testTab == true)
	if settings.testTab then
		ns.ShowTab(tabIndex)
	end
end

-- Hidden until the saved settings are there (login)
ns.SetTabShown(tabIndex, false)
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
	ns.SetTabShown(tabIndex, ns.GetDB().settings.testTab == true)
end)
