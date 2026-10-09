local _, ns = ...
local Book = ns.Book

-- Config tab: settings each player can change for themselves. Right page: every rank's
-- badge and name with one field for its lowest rating; it ends where the next rank
-- starts, so ranges can't overlap. Left page: apply, undo, defaults, filling the fields
-- evenly between two ratings, and extended logging (combat log file and Log tab).
local CONTENT_X = Book.CONTENT_X
local ROW_HEIGHT = 26
local BOX_WIDTH = 60
local TO_WIDTH = 70 -- "up to" column on the right

local panel = ns.AddTab("Config")
local left, right = panel.left, panel.right
local Refresh, Validate

local edited = false -- the fields hold changes that aren't applied yet

local function Text(page, font, y, x)
	local text = Book.CreateText(page, font or Book.SMALL_FONT)
	text:SetPoint("TOPLEFT", x or CONTENT_X, y)
	return text
end

local function NumberBox(parent)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(BOX_WIDTH, 20)
	box:SetAutoFocus(false)
	box:SetNumeric(true)
	box:SetMaxLetters(5)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	return box
end

---------------------------------------------------------------------------
-- Right page: one row per rank, highest first
---------------------------------------------------------------------------

Book.CreateHeader(right, "Ranks")

local TABLE_TOP = -100
Text(right, nil, TABLE_TOP):SetText("Rank")
local fromHeader = Book.CreateText(right, Book.SMALL_FONT)
fromHeader:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN - TO_WIDTH - 8, TABLE_TOP)
fromHeader:SetWidth(BOX_WIDTH)
fromHeader:SetText("From")
local toHeader = Book.CreateText(right, Book.SMALL_FONT)
toHeader:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN, TABLE_TOP)
toHeader:SetWidth(TO_WIDTH)
toHeader:SetJustifyH("RIGHT")
toHeader:SetText("To")

local rows = {}
for rank = ns.RANKS, 1, -1 do
	local y = TABLE_TOP - (ns.RANKS - rank + 1) * ROW_HEIGHT
	local row = {}
	if rank % 2 == 1 then
		local stripe = right:CreateTexture(nil, "BACKGROUND", nil, 3)
		stripe:SetPoint("TOPLEFT", CONTENT_X - 6, y + 4)
		stripe:SetPoint("RIGHT", -Book.PAGE_MARGIN + 6, 0)
		stripe:SetHeight(ROW_HEIGHT)
		stripe:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.07)
	end
	row.icon = right:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(20, 20)
	row.icon:SetPoint("TOPLEFT", CONTENT_X, y + 1)
	row.icon:SetTexture(ns.GetRankIcon(rank))
	row.name = Text(right, Book.BOLD_SMALL_FONT, y - 2, CONTENT_X + 28)
	row.to = Book.CreateText(right, Book.SMALL_FONT)
	row.to:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN, y - 2)
	row.to:SetWidth(TO_WIDTH)
	row.to:SetJustifyH("RIGHT")
	if rank == 1 then
		-- Everything below rank 2: no field of its own
		row.from = Text(right, nil, y - 2, 0)
		row.from:ClearAllPoints()
		row.from:SetPoint("TOPLEFT", fromHeader, "TOPLEFT", 0, y - 2 - TABLE_TOP)
		row.from:SetAlpha(0.7)
		row.from:SetText("-")
	else
		row.box = NumberBox(right)
		row.box:SetPoint("TOPLEFT", fromHeader, "TOPLEFT", 4, y + 3 - TABLE_TOP)
		row.box:SetScript("OnTextChanged", function(self, userInput)
			if userInput then
				edited = true
			end
			Validate()
		end)
	end
	rows[rank] = row
end

-- Tab between the fields, top to bottom
for rank = ns.RANKS, 2, -1 do
	local box, nextBox = rows[rank].box, rows[rank > 2 and rank - 1 or ns.RANKS].box
	box:SetScript("OnTabPressed", function()
		nextBox:SetFocus()
	end)
end

---------------------------------------------------------------------------
-- Left page: buttons and the even fill
---------------------------------------------------------------------------

Book.CreateHeader(left, "Rank badges")

local intro = Text(left, Book.TEXT_FONT, -100)
intro:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
intro:SetWordWrap(true)
intro:SetText("Ratings show a PvP rank badge. On the right, type the rating each rank starts "
	.. "at; it ends where the next one starts, and the lowest rank is everything below. Each "
	.. "rank has to start higher than the one below it. Only you see these badges.")

local message = Text(left, nil, -196)
message:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
message:SetWordWrap(true)

local function Button(text, width)
	local button = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
	button:SetSize(width or 100, 24)
	button:SetText(text)
	return button
end

local applyButton = Button("Apply")
applyButton:SetPoint("TOPLEFT", CONTENT_X, -226)
local undoButton = Button("Undo")
undoButton:SetPoint("LEFT", applyButton, "RIGHT", 8, 0)
local defaultsButton = Button("Defaults")
defaultsButton:SetPoint("LEFT", undoButton, "RIGHT", 8, 0)

-- Fill evenly: rank 2 starts at the first number, the top rank at the second
local FILL_TOP = -290
local fillHeader = Book.CreateSubHeader(left, "Fill evenly")
fillHeader:SetPoint("TOPLEFT", CONTENT_X, FILL_TOP)
fillHeader:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)

local fillText = Text(left, nil, FILL_TOP - 40)
fillText:SetText("Rank 2 starts at")
local fillMin = NumberBox(left)
fillMin:SetPoint("LEFT", fillText, "RIGHT", 10, 0)
local fillText2 = Book.CreateText(left, Book.SMALL_FONT)
fillText2:SetPoint("LEFT", fillMin, "RIGHT", 6, 0)
fillText2:SetText(("rank %d at"):format(ns.RANKS))
local fillMax = NumberBox(left)
fillMax:SetPoint("LEFT", fillText2, "RIGHT", 10, 0)
fillMin:SetText(ns.RANK_MIN)
fillMax:SetText(ns.RANK_MAX)

local fillButton = Button("Fill")
fillButton:SetPoint("TOPLEFT", CONTENT_X, FILL_TOP - 70)
local fillHint = Book.CreateText(left, Book.SMALL_FONT)
fillHint:SetPoint("LEFT", fillButton, "RIGHT", 8, 0)
fillHint:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
fillHint:SetWordWrap(true)
fillHint:SetAlpha(0.7)
fillHint:SetText("Fills the fields on the right, Apply saves them.")

-- Extended logging: writes the game's combat log file during duels and shows the Log tab
local LOGGING_TOP = FILL_TOP - 130
local loggingHeader = Book.CreateSubHeader(left, "Logging")
loggingHeader:SetPoint("TOPLEFT", CONTENT_X, LOGGING_TOP)
loggingHeader:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)

local loggingCheck = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
loggingCheck:SetSize(26, 26)
loggingCheck:SetPoint("TOPLEFT", CONTENT_X - 4, LOGGING_TOP - 34)
local loggingLabel = Book.CreateText(left, Book.SMALL_FONT)
loggingLabel:SetPoint("LEFT", loggingCheck, "RIGHT", 2, 1)
loggingLabel:SetText("Extended logging")
loggingCheck:SetScript("OnClick", function(self)
	PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	ns.SetCombatLogEnabled(self:GetChecked())
end)

local loggingText = Text(left, nil, LOGGING_TOP - 64)
loggingText:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
loggingText:SetWordWrap(true)
loggingText:SetAlpha(0.7)
loggingText:SetText("Writes the game's combat log file (Logs folder) from each duel request until "
	.. "shortly after the duel, and shows the Log tab. Off by default.")

---------------------------------------------------------------------------
-- Fields
---------------------------------------------------------------------------

local function ReadFields()
	local from = {}
	for rank = 2, ns.RANKS do
		from[rank] = tonumber(rows[rank].box:GetText())
	end
	return from
end

local function FillFields(from)
	for rank = 2, ns.RANKS do
		rows[rank].box:SetText(from[rank] or "")
	end
end

-- Marks every field that doesn't start above the rank below it (or is empty), updates
-- the "To" column from the fields as they are, and whether Apply is possible
function Validate()
	local from = ReadFields()
	local bad = false
	for rank = 2, ns.RANKS do
		local value, below = from[rank], from[rank - 1]
		local wrong = not value or (rank > 2 and below and value <= below)
		if wrong then
			rows[rank].box:SetTextColor(1, 0.25, 0.25)
		else
			rows[rank].box:SetTextColor(1, 1, 1)
		end
		bad = bad or wrong
	end
	for rank = 1, ns.RANKS do
		local nextFrom = from[rank + 1]
		if rank == ns.RANKS then
			rows[rank].to:SetText("and up")
		else
			rows[rank].to:SetText(nextFrom and tostring(nextFrom - 1) or "?")
		end
	end
	if bad then
		message:SetText(Book.BAD .. "The red ranks have to start higher than the rank below them.|r")
	elseif edited then
		message:SetText("Not saved yet: Apply saves, Undo goes back.")
	else
		message:SetText("")
	end
	applyButton:SetEnabled(edited and not bad)
	undoButton:SetEnabled(edited)
end

applyButton:SetScript("OnClick", function()
	if ns.SetRankThresholds(ReadFields()) then
		edited = false
		Refresh()
	end
end)

undoButton:SetScript("OnClick", function()
	edited = false
	Refresh()
end)

defaultsButton:SetScript("OnClick", function()
	ns.SetRankThresholds(nil)
	edited = false
	Refresh()
end)

fillButton:SetScript("OnClick", function()
	local min, max = tonumber(fillMin:GetText()), tonumber(fillMax:GetText())
	if not min or not max or max - min < ns.RANKS - 2 then
		message:SetText(("%sFor filling evenly the second number has to be at least %d above the first.|r")
			:format(Book.BAD, ns.RANKS - 2))
		return
	end
	FillFields(ns.EvenRankThresholds(min, max))
	edited = true
	Validate()
end)

---------------------------------------------------------------------------

function Refresh()
	loggingCheck:SetChecked(ns.IsCombatLogEnabled())
	if not edited then
		FillFields(ns.GetRankThresholds())
	end
	local myRank = ns.GetRank((ns.GetMyRating()))
	for rank, row in pairs(rows) do
		-- Our own rank (by the saved ranges) stands out
		row.name:SetText(ns.GetRankName(rank) .. (rank == myRank and "  (you)" or ""))
	end
	Validate()
end

panel.Refresh = Refresh
panel:SetScript("OnShow", Refresh)
