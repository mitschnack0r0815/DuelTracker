local _, ns = ...
local Book = ns.Book

-- Main window, styled like the spellbook: an open book with one tab per panel (Opponents,
-- Duels) along the bottom edge. Each file adds its own tab via ns.AddTab and fills the
-- tab's two pages.
local window = CreateFrame("Frame", "DuelTrackerMainFrame", UIParent,
	Book.TemplateExists("PortraitFrameTemplate") and "PortraitFrameTemplate" or "BasicFrameTemplate")
local WIDTH, HEIGHT = 1060, 760
window:SetSize(WIDTH, HEIGHT)
window:SetPoint("TOP", UIParent, "TOP", 0, -60)
window:SetFrameStrata("HIGH")
window:SetToplevel(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:SetMovable(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
tinsert(UISpecialFrames, "DuelTrackerMainFrame") -- close with Escape

if window.SetTitle then
	window:SetTitle("Duel Tracker")
elseif window.TitleText then
	window.TitleText:SetText("Duel Tracker")
end
if window.SetPortraitToAsset then
	window:SetPortraitToAsset(ns.ICON)
end

local book = CreateFrame("Frame", nil, window)
book:SetPoint("TOPLEFT", 2, -21)
book:SetPoint("BOTTOMRIGHT", -2, 2)
Book.CreateBookArt(book)

-- Test data buttons in the top bar, like /duels test and /duels cleartest
local clearTestButton = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
clearTestButton:SetSize(130, 24)
clearTestButton:SetPoint("TOPRIGHT", -24, -14)
clearTestButton:SetText("Clear test duels")
clearTestButton:SetScript("OnClick", function()
	print(("Duel Tracker: removed %d test duels."):format(ns.ClearTestData()))
end)

local addTestButton = CreateFrame("Button", nil, book, "UIPanelButtonTemplate")
addTestButton:SetSize(130, 24)
addTestButton:SetPoint("RIGHT", clearTestButton, "LEFT", -6, 0)
addTestButton:SetText("Add test duels")
addTestButton:SetScript("OnClick", function()
	ns.AddTestData(ns.TEST_DUELS)
	print(("Duel Tracker: added %d test duels."):format(ns.TEST_DUELS))
end)

window:SetScript("OnShow", function()
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
end)
window:SetScript("OnHide", function()
	PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
end)

---------------------------------------------------------------------------
-- Shared look for the tabs
---------------------------------------------------------------------------

Book.CONTENT_X = Book.PAGE_MARGIN + 12 -- left edge of page content, lined up with the headers
-- Lowest y on a page that content may reach, above the pager (pages start 74 below the
-- window's top, the pager takes the bottom 66)
Book.CONTENT_BOTTOM = -(HEIGHT - 74 - 76)
Book.MUTED = "|cff6b5a45" -- faded ink for less important text
Book.MINE = "|cff1f3f8f" -- us in the combat log
Book.THEIRS = "|cff8f3f1f" -- the opponent

-- Game fonts have no bold version: a shadow in the ink color, one pixel to the right,
-- makes the letters thicker. Used for names, which read badly on parchment otherwise.
local function BoldFont(name, base)
	local font = CreateFont(name)
	font:CopyFontObject(_G[base] or GameFontNormal)
	font:SetTextColor(Book.FONT_COLOR:GetRGB())
	font:SetShadowColor(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 1)
	font:SetShadowOffset(1, 0)
	return name
end
Book.BOLD_FONT = BoldFont("DuelTrackerBoldFont", Book.TEXT_FONT)
Book.BOLD_SMALL_FONT = BoldFont("DuelTrackerBoldSmallFont", Book.SMALL_FONT)
Book.BOLD_NAME_FONT = BoldFont("DuelTrackerBoldNameFont", Book.NAME_FONT)

-- Player name without our own realm. Plain ink: darkened class colors are hard to read on
-- parchment, the spec or class icon next to the name shows the class.
function ns.InkName(name)
	return ns.FullName(ns.ShortName(name)) == ns.FullName(name) and ns.ShortName(name) or name
end

-- Spec icon on a texture (the talent tree with the most points), the class icon when the
-- spec isn't known or two trees are tied, or the addon's icon when the class isn't known
function ns.SetDuelistIcon(texture, class, spec)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if spec and spec.icon then
		texture:SetTexture(spec.icon)
		texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- cut the icon's border
	elseif coords then
		texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
		texture:SetTexCoord(unpack(coords))
	else
		texture:SetTexture(ns.ICON)
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

function ns.FormatDuration(seconds)
	if not seconds then
		return "-"
	end
	return ("%d:%02d"):format(math.floor(seconds / 60), math.floor(seconds % 60))
end

-- Health snapshots of a duel as two lines, or nil when it has none:
-- "You: 3200/3200 at the start, 1100 at the end" and the same for the opponent
function ns.DescribeHealth(duel)
	local health = duel.health
	if not health then
		return nil
	end
	local function Side(key, name)
		local first = health.start and health.start[key]
		local last = health.ends and health.ends[key]
		local startText = first and ("%d/%d"):format(first.hp, first.max) or "?"
		local endText = "?"
		if last then
			-- The max only when it changed, say by a buff during the fight
			endText = (first and first.max == last.max) and tostring(last.hp) or ("%d/%d"):format(last.hp, last.max)
		end
		return ("%s: %s at the start, %s at the end"):format(name, startText, endText)
	end
	return Side("me", "You"), Side("opp", ns.InkName(duel.opp))
end

-- How one-sided the duel was ("Fair fight" ... "Obliterated", see ns.VERDICTS), the
-- health gap at the end in percent, and its color: a shade of green when we won, red when
-- we lost. nil when either side's end health is missing.
function ns.GetVerdict(duel)
	local ends = duel.health and duel.health.ends
	if not ends or not ends.me or not ends.opp then
		return nil
	end
	local gap = math.abs(ends.me.hp / ends.me.max - ends.opp.hp / ends.opp.max) * 100
	local found = ns.VERDICTS[#ns.VERDICTS]
	for _, verdict in ipairs(ns.VERDICTS) do
		if gap <= verdict.limit then
			found = verdict
			break
		end
	end
	return found.text, gap, CreateColor(unpack(duel.won and found.win or found.loss))
end

-- The verdict color darkened so it reads on parchment, as a "|cff......" code
function ns.InkVerdictColor(color)
	return ("|cff%02x%02x%02x"):format(color.r * 0.6 * 255, color.g * 0.6 * 255, color.b * 0.6 * 255)
end

-- "knockout", "they fled", "you fled"
function ns.DescribeHow(duel)
	if duel.how == "fled" then
		return duel.won and "they fled" or "you fled"
	end
	return "knockout"
end

---------------------------------------------------------------------------
-- Choice menu
---------------------------------------------------------------------------

-- Our own small dropdown. Blizzard's menus (MenuUtil) crash this beta client when opened
-- from the filter buttons, so this is a plain frame with one button per choice.
local MENU_ROW_HEIGHT = 20
local MENU_PADDING = 8

local menu = CreateFrame("Frame", "DuelTrackerChoiceMenu", window, "BackdropTemplate")
menu:SetFrameStrata("DIALOG")
menu:SetClampedToScreen(true)
menu:EnableMouse(true)
menu:Hide()
menu:SetBackdrop({
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
menu.rows = {}
tinsert(UISpecialFrames, "DuelTrackerChoiceMenu") -- close with Escape

local function GetMenuRow(i)
	local row = menu.rows[i]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, menu)
	row:SetHeight(MENU_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", MENU_PADDING, -MENU_PADDING - (i - 1) * MENU_ROW_HEIGHT)
	row:SetPoint("RIGHT", -MENU_PADDING, 0)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.check = row:CreateTexture(nil, "ARTWORK")
	row.check:SetSize(16, 16)
	row.check:SetPoint("LEFT")
	row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 20, 0)
	row.text:SetJustifyH("LEFT")
	row:SetScript("OnClick", function(self)
		menu:Hide()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		menu.onSelect(self.value)
	end)
	menu.rows[i] = row
	return row
end

-- Close when clicking anywhere outside the menu (the owner's own click toggles it)
menu:SetScript("OnShow", function(self)
	self:RegisterEvent("GLOBAL_MOUSE_DOWN")
end)
menu:SetScript("OnHide", function(self)
	self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
end)
menu:SetScript("OnEvent", function(self)
	if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
		self:Hide()
	end
end)

-- Menu of choices under owner; a second click on the same owner closes it.
-- choices = { { text = "Won", value = "won" }, ... }; the first is "Any ..." with no value
function ns.ShowMenu(owner, choices, current, onSelect)
	if menu:IsShown() and menu.owner == owner then
		menu:Hide()
		return
	end
	menu.owner, menu.onSelect = owner, onSelect
	local width = owner:GetWidth() - 2 * MENU_PADDING
	for i, choice in ipairs(choices) do
		local row = GetMenuRow(i)
		row.value = choice.value
		row.text:SetText(choice.text)
		row.check:SetShown(choice.value == current)
		row:Show()
		width = math.max(width, row.text:GetStringWidth() + 28)
	end
	for i = #choices + 1, #menu.rows do
		menu.rows[i]:Hide()
	end
	menu:SetSize(width + 2 * MENU_PADDING, #choices * MENU_ROW_HEIGHT + 2 * MENU_PADDING)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
	menu:Show()
	menu:Raise()
end

-- A duel the Log tab can show: it has a combat log, or the log file has it
function ns.HasLog(duel)
	return duel.log ~= nil or duel.logged == true
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

-- Bottom tabs (as on the talents/spellbook window); plain buttons if the client doesn't have them
local hasTabTemplate = Book.TemplateExists("PanelTabButtonTemplate")

local tabs = {}
local panels = {}
local currentTab

local function SelectTab(index)
	currentTab = index
	for i, panel in ipairs(panels) do
		panel:SetShown(i == index)
	end
	if hasTabTemplate then
		PanelTemplates_SetTab(window, index)
	else
		for i, tab in ipairs(tabs) do
			tab:SetEnabled(i ~= index)
		end
	end
end

-- Adds a tab and returns its panel. panel.left and panel.right are the two pages to fill.
-- panel.Refresh, when set, is called when the duels change while the panel is shown.
function ns.AddTab(text)
	local index = #panels + 1

	-- PanelTemplates expects tabs named <window>Tab<n>
	local tab = CreateFrame("Button", "DuelTrackerMainFrameTab" .. index, window,
		hasTabTemplate and "PanelTabButtonTemplate" or "UIPanelButtonTemplate")
	tab:SetID(index)
	tab:SetText(text)
	if index == 1 then
		tab:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 22, 2)
	else
		tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", 3, 0)
	end
	if hasTabTemplate then
		PanelTemplates_TabResize(tab, 0)
	else
		tab:SetSize(100, 24)
	end
	tab:SetScript("OnClick", function()
		SelectTab(index)
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
	end)
	tabs[index] = tab

	local panel = CreateFrame("Frame", nil, book)
	panel:SetAllPoints()
	panel:Hide()
	panel.left = CreateFrame("Frame", nil, panel)
	panel.left:SetAllPoints(book.leftPage)
	panel.right = CreateFrame("Frame", nil, panel)
	panel.right:SetAllPoints(book.rightPage)
	panels[index] = panel

	if hasTabTemplate then
		PanelTemplates_SetNumTabs(window, index)
	end
	return panel, index
end

-- Opens the window on the given tab, or closes it if that tab is already showing
function ns.ToggleTab(index)
	if window:IsShown() and currentTab == index then
		window:Hide()
		return
	end
	window:Show()
	SelectTab(index)
end

-- Opens the window on the given tab, leaves it open if it already shows it
function ns.ShowTab(index)
	window:Show()
	SelectTab(index)
end

function ns.ToggleWindow()
	ns.ToggleTab(currentTab or 1)
end

function ns.OnDuelsChanged()
	for _, panel in ipairs(panels) do
		if panel:IsVisible() and panel.Refresh then
			panel:Refresh()
		end
	end
end

---------------------------------------------------------------------------
-- Combat log file test (/duels logtest <seconds>)
---------------------------------------------------------------------------

-- Addons can't read the combat log any more, but the game can still write it to
-- Logs\WoWCombatLog-*.txt for outside tools. Tests whether we may switch that on.
function ns.TestCombatLogFile(seconds)
	seconds = seconds or 3
	print(("Duel Tracker: combat log file was %s, switching it on for %d seconds.")
		:format(LoggingCombat() and "on" or "off", seconds))
	LoggingCombat(true)
	print(("Duel Tracker: combat log file is now %s."):format(LoggingCombat() and "on" or "off"))
	C_Timer.After(seconds, function()
		LoggingCombat(false)
		print(("Duel Tracker: switched it off, it's now %s. Look in Logs for WoWCombatLog*.txt.")
			:format(LoggingCombat() and "on" or "off"))
	end)
end
