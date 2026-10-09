local _, ns = ...
local Book = ns.Book

-- Duels tab: every duel of this character. Left page: filters (opponent, result, how it
-- ended, class, time, Elo or not) and the record of the duels they let through. Right
-- page: those duels as a paged table, newest first; a logged duel opens on the Log tab.
-- Clicking a name on the Opponents tab opens this tab filtered to that player.
local ROW_HEIGHT = 22
local CONTENT_X = Book.CONTENT_X
-- Table columns after the opponent's name: result with the Elo badge and change, talent
-- points, length on the right
local RESULT_WIDTH = 130
local SPEC_WIDTH = 70
local LENGTH_WIDTH = 64
local COL_GAP = 8
local FORM_TOP = -100
local FORM_ROW_HEIGHT = 34
local FORM_LABEL_WIDTH = 90
local CONTROL_WIDTH = 190
local TABLE_TOP = -100
local ROWS_PER_PAGE = floor((TABLE_TOP - Book.CONTENT_BOTTOM) / ROW_HEIGHT) - 1
local DAY = 24 * 60 * 60
local UNKNOWN_SPEC = "?" -- spec filter value for duels where the spec wasn't recorded

local panel, tabIndex = ns.AddTab("Duels")
local left, right = panel.left, panel.right

-- Filters; nil means any
local filters = {
	text = nil, -- part of the opponent's name
	opp = nil, -- exactly this opponent (full name), set by a link from the Opponents tab
	result = nil, -- "won" or "lost"
	how = nil, -- "knockout" or "fled"
	class = nil, -- class file name
	spec = nil, -- spec name of that class, or UNKNOWN_SPEC for duels without one
	days = nil, -- only duels of the last this many days
	elo = nil, -- true: only Elo duels
}
local page = 1
local Refresh

local function Text(page, font, y, x)
	local text = Book.CreateText(page, font or Book.SMALL_FONT)
	text:SetPoint("TOPLEFT", x or CONTENT_X, y)
	return text
end

---------------------------------------------------------------------------
-- Filtering
---------------------------------------------------------------------------

local function Matches(duel)
	if filters.opp and duel.opp ~= filters.opp then
		return false
	end
	if filters.text and not ns.ShortName(duel.opp):lower():find(filters.text, 1, true) then
		return false
	end
	if filters.result and (filters.result == "won") ~= duel.won then
		return false
	end
	if filters.how and (duel.how or "knockout") ~= filters.how then
		return false
	end
	if filters.class and duel.oppClass ~= filters.class then
		return false
	end
	if filters.spec then
		local spec = duel.oppSpec and duel.oppSpec.name or UNKNOWN_SPEC
		if spec ~= filters.spec then
			return false
		end
	end
	if filters.days and duel.t < GetServerTime() - filters.days * DAY then
		return false
	end
	if filters.elo and not duel.elo then
		return false
	end
	return true
end

local function GetFilteredDuels()
	local list = {}
	for _, duel in ipairs(ns.GetDuels()) do
		if Matches(duel) then
			list[#list + 1] = duel
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Left page: filter form
---------------------------------------------------------------------------

Book.CreateHeader(left, "Filter")

-- One labeled row of the form: "Result    [control]"
local formRows = 0
local function CreateFormRow(label)
	formRows = formRows + 1
	local row = CreateFrame("Frame", nil, left)
	row:SetHeight(FORM_ROW_HEIGHT)
	row:SetPoint("TOPLEFT", CONTENT_X, FORM_TOP - (formRows - 1) * FORM_ROW_HEIGHT)
	row:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
	local text = Book.CreateText(row, Book.SMALL_FONT)
	text:SetPoint("LEFT")
	text:SetWidth(FORM_LABEL_WIDTH)
	text:SetText(label)
	return row
end

-- Opponent: search box, part of the name
local nameRow = CreateFormRow("Opponent")
local searchBox = CreateFrame("EditBox", "DuelTrackerDuelSearchBox", nameRow,
	Book.TemplateExists("SearchBoxTemplate") and "SearchBoxTemplate" or "InputBoxTemplate")
searchBox:SetSize(CONTROL_WIDTH - 6, 22)
searchBox:SetPoint("LEFT", FORM_LABEL_WIDTH + 6, 0)
searchBox:SetAutoFocus(false)
if searchBox.Instructions then
	searchBox.Instructions:SetText("Any name")
end
searchBox:SetScript("OnEscapePressed", searchBox.ClearFocus)
searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)
searchBox:HookScript("OnTextChanged", function(self, userInput)
	if userInput or self:GetText() == "" then
		-- Typing replaces the exact player from a link with a search
		filters.opp = nil
		local text = self:GetText():trim():lower()
		filters.text = text ~= "" and text or nil
		page = 1
		Refresh()
	end
end)

-- The other filters open a menu of choices
local function MenuFilter(label, key, getChoices)
	local button = CreateFrame("Button", nil, CreateFormRow(label), "UIPanelButtonTemplate")
	button:SetSize(CONTROL_WIDTH, 24)
	button:SetPoint("LEFT", FORM_LABEL_WIDTH, 0)
	button:SetScript("OnClick", function(self)
		ns.ShowMenu(self, getChoices(), filters[key], function(value)
			filters[key] = value
			if key == "class" then
				filters.spec = nil -- specs belong to one class
			end
			page = 1
			Refresh()
		end)
	end)
	-- Button text: the chosen choice's text
	function button:Update()
		for _, choice in ipairs(getChoices()) do
			if choice.value == filters[key] then
				self:SetText(choice.text)
			end
		end
	end
	return button
end

local RESULT_CHOICES = { { text = "Any result" }, { text = "Won", value = "won" }, { text = "Lost", value = "lost" } }
local HOW_CHOICES = {
	{ text = "Any ending" }, { text = "Knockout", value = "knockout" }, { text = "Someone fled", value = "fled" },
}
local DAYS_CHOICES = {
	{ text = "Any time" }, { text = "Today", value = 1 }, { text = "Last 7 days", value = 7 },
	{ text = "Last 30 days", value = 30 }, { text = "Last 90 days", value = 90 },
}

-- Classes of the players dueled, plus the one filtered for
local function GetClassChoices()
	local choices = { { text = "Any class" } }
	local seen = {}
	for _, duel in ipairs(ns.GetDuels()) do
		local class = duel.oppClass
		if class and not seen[class] then
			seen[class] = true
			choices[#choices + 1] = {
				text = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class,
				value = class,
			}
		end
	end
	if filters.class and not seen[filters.class] then
		choices[#choices + 1] = { text = filters.class, value = filters.class }
	end
	table.sort(choices, function(a, b)
		if not a.value or not b.value then
			return not a.value and b.value ~= nil
		end
		return a.text < b.text
	end)
	return choices
end

-- Specs met in duels against the chosen class, plus the one filtered for; only with a class
local function GetSpecChoices()
	local choices = { { text = "Any spec" } }
	if not filters.class then
		return choices
	end
	local seen = {}
	local specs = {}
	for _, duel in ipairs(ns.GetDuels()) do
		if duel.oppClass == filters.class then
			local spec = duel.oppSpec and duel.oppSpec.name or UNKNOWN_SPEC
			if not seen[spec] then
				seen[spec] = true
				specs[#specs + 1] = spec
			end
		end
	end
	if filters.spec and not seen[filters.spec] then
		specs[#specs + 1] = filters.spec
	end
	table.sort(specs, function(a, b)
		if (a == UNKNOWN_SPEC) ~= (b == UNKNOWN_SPEC) then
			return b == UNKNOWN_SPEC -- unknown last
		end
		return a < b
	end)
	for _, spec in ipairs(specs) do
		choices[#choices + 1] = { text = spec == UNKNOWN_SPEC and "Unknown spec" or spec, value = spec }
	end
	return choices
end

local menuButtons = {
	MenuFilter("Result", "result", function() return RESULT_CHOICES end),
	MenuFilter("Ended", "how", function() return HOW_CHOICES end),
	MenuFilter("Class", "class", GetClassChoices),
	MenuFilter("Spec", "spec", GetSpecChoices),
	MenuFilter("Time", "days", function() return DAYS_CHOICES end),
}
local specButton = menuButtons[4]

-- Elo: a checkbox, it's either only Elo duels or all of them
local eloCheck = CreateFrame("CheckButton", nil, CreateFormRow("Elo"), "UICheckButtonTemplate")
eloCheck:SetSize(26, 26)
eloCheck:SetPoint("LEFT", FORM_LABEL_WIDTH - 2, 0)
local eloLabel = Book.CreateText(eloCheck, Book.SMALL_FONT)
eloLabel:SetPoint("LEFT", eloCheck, "RIGHT", 2, 1)
eloLabel:SetText("Only Elo duels")
eloCheck:SetScript("OnClick", function(self)
	PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	filters.elo = self:GetChecked() or nil
	page = 1
	Refresh()
end)
function eloCheck:Update()
	self:SetChecked(filters.elo == true)
end
menuButtons[#menuButtons + 1] = eloCheck -- updated with the menu buttons

-- Greyed out until a class is picked
local updateSpec = specButton.Update
function specButton:Update()
	updateSpec(self)
	self:SetEnabled(filters.class ~= nil)
	if not filters.class then
		self:SetText("Pick a class first")
	end
end

local resetButton = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
resetButton:SetSize(CONTROL_WIDTH, 24)
resetButton:SetPoint("TOPLEFT", CONTENT_X + FORM_LABEL_WIDTH, FORM_TOP - formRows * FORM_ROW_HEIGHT - 4)
resetButton:SetText("Reset filters")
resetButton:SetScript("OnClick", function()
	for key in pairs(filters) do
		filters[key] = nil
	end
	searchBox:SetText("")
	searchBox:ClearFocus()
	page = 1
	Refresh()
end)

-- Record of the duels the filters let through
local SUMMARY_TOP = FORM_TOP - formRows * FORM_ROW_HEIGHT - 50
local summaryHeader = Book.CreateSubHeader(left, "These duels")
summaryHeader:SetPoint("TOPLEFT", CONTENT_X, SUMMARY_TOP)
summaryHeader:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
local summary = Text(left, Book.TEXT_FONT, SUMMARY_TOP - 40)
summary:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
summary:SetJustifyV("TOP")
summary:SetSpacing(4)

local function RefreshSummary(list)
	local wins, total, fought, timed = 0, #list, 0, 0
	for _, duel in ipairs(list) do
		wins = wins + (duel.won and 1 or 0)
		if duel.dur then
			fought = fought + duel.dur
			timed = timed + 1
		end
	end
	if total == 0 then
		summary:SetText("No duels match.")
		return
	end
	local lines = {
		("%d duels, %s%d won|r, %s%d lost|r (%d%%)"):format(total, Book.GOOD, wins, Book.BAD, total - wins,
			math.floor(wins / total * 100)),
	}
	if timed > 0 then
		lines[#lines + 1] = "Average fight: " .. ns.FormatDuration(fought / timed)
	end
	summary:SetText(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- Right page: duel table
---------------------------------------------------------------------------

local tableHeader = Book.CreateHeader(right)

Text(right, nil, TABLE_TOP):SetText("Date")
Text(right, nil, TABLE_TOP, CONTENT_X + 84):SetText("Opponent")
-- Lined up with the row columns below (the rows end at the page margin)
local lengthHeader = Book.CreateText(right, Book.SMALL_FONT)
lengthHeader:SetWidth(LENGTH_WIDTH)
lengthHeader:SetJustifyH("RIGHT")
lengthHeader:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN, TABLE_TOP)
lengthHeader:SetText("Length")
local specHeader = Book.CreateText(right, Book.SMALL_FONT)
specHeader:SetWidth(SPEC_WIDTH)
specHeader:SetPoint("TOPRIGHT", lengthHeader, "TOPLEFT", -COL_GAP, 0)
specHeader:SetText("Spec")
local resultHeader = Book.CreateText(right, Book.SMALL_FONT)
resultHeader:SetWidth(RESULT_WIDTH)
resultHeader:SetPoint("TOPRIGHT", specHeader, "TOPLEFT", -COL_GAP, 0)
resultHeader:SetText("Result")

local empty = Text(right, Book.TEXT_FONT, TABLE_TOP - ROW_HEIGHT - 4)
empty:SetAlpha(0.7)

local hint = Book.CreateText(right, Book.SMALL_FONT)
hint:SetPoint("BOTTOMLEFT", CONTENT_X, 44)
hint:SetAlpha(0.7)
hint:SetText(("Click a logged duel (|T%s:14:14|t) to open its log."):format(ns.LOG_ICON))

local pager = Book.CreatePager(right, function(delta)
	page = page + delta
	Refresh()
end)
pager:EnableWheel(right)

local rows = {}

local function GetRow(i)
	if rows[i] then
		return rows[i]
	end
	local y = TABLE_TOP - i * ROW_HEIGHT - 4
	local row = CreateFrame("Button", nil, right)
	row:SetPoint("TOPLEFT", CONTENT_X - 6, y + 4)
	row:SetPoint("RIGHT", -Book.PAGE_MARGIN + 6, 0)
	row:SetHeight(ROW_HEIGHT)

	if i % 2 == 1 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.07)
	end
	row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
	row.highlight:SetAllPoints()
	row.highlight:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.12)

	row.when = Book.CreateText(row, Book.SMALL_FONT)
	row.when:SetPoint("LEFT", 6, 0)
	row.when:SetAlpha(0.7)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
	row.icon:SetPoint("LEFT", 90, 0)

	row.length = Book.CreateText(row, Book.SMALL_FONT)
	row.length:SetPoint("RIGHT", -6, 0)
	row.length:SetWidth(LENGTH_WIDTH)
	row.length:SetJustifyH("RIGHT")

	row.spec = Book.CreateText(row, Book.SMALL_FONT)
	row.spec:SetPoint("RIGHT", row.length, "LEFT", -COL_GAP, 0)
	row.spec:SetWidth(SPEC_WIDTH)
	row.spec:SetWordWrap(false)
	row.spec:SetAlpha(0.7)

	-- Right after the name: "Won", then the Elo badge and change
	row.result = Book.CreateText(row, Book.SMALL_FONT)
	row.result:SetPoint("RIGHT", row.spec, "LEFT", -COL_GAP, 0)
	row.result:SetWidth(RESULT_WIDTH)
	row.result:SetWordWrap(false)

	row.name = Book.CreateText(row, Book.BOLD_SMALL_FONT)
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
	row.name:SetPoint("RIGHT", row.result, "LEFT", -COL_GAP, 0)
	row.name:SetWordWrap(false)

	row:SetScript("OnClick", function(self)
		if ns.HasLog(self.duel) then
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			ns.ShowDuelLog(self.duel)
		end
	end)
	-- Tooltip: health at the start and end
	row:SetScript("OnEnter", function(self)
		local duel = self.duel
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(ns.DuelName(duel, true))
		local verdict, gap, color = ns.GetVerdict(duel)
		if verdict then
			GameTooltip:AddLine(("%s (%d%% apart at the end)"):format(verdict, math.floor(gap + 0.5)), color:GetRGB())
		end
		local myHealth, oppHealth = ns.DescribeHealth(duel)
		if myHealth then
			GameTooltip:AddLine(myHealth, 1, 1, 1)
			GameTooltip:AddLine(oppHealth, 1, 1, 1)
		else
			GameTooltip:AddLine("No health recorded.", 0.7, 0.7, 0.7)
		end
		if ns.HasLog(duel) then
			GameTooltip:AddLine("Click to open its log.", 0.7, 0.7, 0.7)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	rows[i] = row
	return row
end

local function FillRow(row, duel)
	row.duel = duel
	row.when:SetText(date("%d.%m. %H:%M", duel.t))
	ns.SetDuelistIcon(row.icon, duel.oppClass, duel.oppSpec)
	row.name:SetText(ns.DuelName(duel))
	row.spec:SetText(ns.SpecText(duel.oppSpec))
	local result = duel.won and (Book.GOOD .. "Won|r") or (Book.BAD .. "Lost|r")
	if duel.how == "fled" then
		result = result .. ", fled"
	end
	if duel.elo then
		result = result .. "  " .. ns.EloText(duel)
	end
	row.result:SetText(result)
	-- A scroll before the length when the duel has a log
	local length = ns.FormatDuration(duel.dur)
	row.length:SetText(ns.HasLog(duel) and ("|T%s:14:14|t %s"):format(ns.LOG_ICON, length) or length)
	-- Only logged duels can be clicked
	row.highlight:SetShown(ns.HasLog(duel))
end

---------------------------------------------------------------------------

function Refresh()
	for _, button in ipairs(menuButtons) do
		button:Update()
	end

	local list = GetFilteredDuels()
	RefreshSummary(list)

	if filters.opp then
		tableHeader.Text:SetText(ns.InkName(filters.opp))
	else
		tableHeader.Text:SetText("Duels")
	end

	local pages = math.max(1, math.ceil(#list / ROWS_PER_PAGE))
	page = math.max(1, math.min(page, pages))
	pager:Update(page, pages)

	local first = (page - 1) * ROWS_PER_PAGE
	for i = 1, ROWS_PER_PAGE do
		local duel = list[first + i]
		if duel then
			local row = GetRow(i)
			FillRow(row, duel)
			row:Show()
		elseif rows[i] then
			rows[i]:Hide()
		end
	end
	empty:SetShown(#list == 0)
	empty:SetText(#ns.GetDuels() == 0 and "No duels yet." or "No duels match the filters.")
	hint:SetShown(#list > 0)
end

panel.Refresh = Refresh
panel:SetScript("OnShow", Refresh)

-- Opens the Duels tab with only the duels against that player
function ns.ShowDuelsAgainst(name)
	for key in pairs(filters) do
		filters[key] = nil
	end
	filters.opp = name
	searchBox:SetText(ns.ShortName(name)) -- not typed, so the exact player stays
	page = 1
	ns.ShowTab(tabIndex)
	Refresh()
end
