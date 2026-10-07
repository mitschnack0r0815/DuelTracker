local _, ns = ...
local Book = ns.Book

-- Opponents tab, the home tab. Left page: your overall record, how duels ended and the
-- latest duels. Right page: everyone you dueled with your record against them; click one
-- to see those duels on the Log tab.
local ROW_HEIGHT = 20
local CONTENT_X = Book.CONTENT_X
local COL_WIDTH = 60 -- width of each number column

local panel = ns.AddTab("Opponents")
local left, right = panel.left, panel.right

local function Text(page, font, y, x)
	local text = Book.CreateText(page, font or Book.SMALL_FONT)
	text:SetPoint("TOPLEFT", x or CONTENT_X, y)
	return text
end

-- Right-aligned number column; col 1 is the rightmost
local function Number(page, font, y, col)
	local text = Book.CreateText(page, font or Book.SMALL_FONT)
	text:SetWidth(COL_WIDTH)
	text:SetJustifyH("RIGHT")
	text:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN - (col - 1) * COL_WIDTH, y)
	return text
end

local function SubHeader(page, text, y)
	local header = Book.CreateSubHeader(page, text)
	header:SetPoint("TOPLEFT", CONTENT_X, y)
	header:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
	return header
end

-- Faint stripe behind every other table row
local function Stripe(page, y)
	local stripe = page:CreateTexture(nil, "BACKGROUND", nil, 3)
	stripe:SetPoint("TOPLEFT", CONTENT_X - 6, y + 3)
	stripe:SetPoint("RIGHT", -Book.PAGE_MARGIN + 6, 0)
	stripe:SetHeight(ROW_HEIGHT)
	stripe:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.07)
	return stripe
end

---------------------------------------------------------------------------
-- Left page: record
---------------------------------------------------------------------------

Book.CreateHeader(left, "Overview")
local summary = Text(left, Book.TEXT_FONT, -100)
local confirmedLine = Text(left, nil, -122)

-- Recent duels: one row each, green when won and red when lost, the opponent's spec or
-- class icon and name, the date on the right. The latest ns.KEEP_LOGS duels, scrolled with
-- the mouse wheel; the numbers above count every duel.
local RECENT_TOP = -152
local RECENT_ROW_HEIGHT = 24
local RECENT_GAP = 2
local RECENT_FIRST = RECENT_TOP - 40
local RECENT_COUNT = floor((RECENT_FIRST - Book.CONTENT_BOTTOM) / (RECENT_ROW_HEIGHT + RECENT_GAP))
local RECENT_SCROLL_STEP = 3
-- Light tints, so the dark ink of the names stays readable on them
local WON_COLOR = CreateColor(0.3, 0.6, 0.2, 0.22)
local LOST_COLOR = CreateColor(0.7, 0.2, 0.15, 0.22)

local recent = {} -- the duels in the list
local recentOffset = 0 -- duels scrolled past
local RefreshRecent

SubHeader(left, "Recent duels", RECENT_TOP)

-- "1-12 of 50" at the end of the header line
local recentPosition = Book.CreateText(left, Book.SMALL_FONT)
recentPosition:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN, RECENT_TOP - 6)
recentPosition:SetJustifyH("RIGHT")
recentPosition:SetAlpha(0.7)

local recentArea = CreateFrame("Frame", nil, left)
recentArea:SetPoint("TOPLEFT", CONTENT_X - 6, RECENT_FIRST)
recentArea:SetPoint("RIGHT", -Book.PAGE_MARGIN + 6, 0)
recentArea:SetHeight(RECENT_COUNT * (RECENT_ROW_HEIGHT + RECENT_GAP))
recentArea:EnableMouseWheel(true)
recentArea:SetScript("OnMouseWheel", function(_, delta)
	local maxOffset = math.max(0, #recent - RECENT_COUNT)
	local offset = math.max(0, math.min(maxOffset, recentOffset - delta * RECENT_SCROLL_STEP))
	if offset ~= recentOffset then
		recentOffset = offset
		RefreshRecent()
	end
end)

local recentLines = {}
for i = 1, RECENT_COUNT do
	local line = CreateFrame("Frame", nil, recentArea)
	line:SetPoint("TOPLEFT", 0, -(i - 1) * (RECENT_ROW_HEIGHT + RECENT_GAP))
	line:SetPoint("RIGHT")
	line:SetHeight(RECENT_ROW_HEIGHT)

	line.background = line:CreateTexture(nil, "BACKGROUND")
	line.background:SetAllPoints()

	line.icon = line:CreateTexture(nil, "ARTWORK")
	line.icon:SetSize(RECENT_ROW_HEIGHT - 4, RECENT_ROW_HEIGHT - 4)
	line.icon:SetPoint("LEFT", 4, 0)

	line.name = Book.CreateText(line, Book.BOLD_FONT)
	line.name:SetPoint("LEFT", line.icon, "RIGHT", 6, 0)
	line.name:SetWordWrap(false)

	line.when = Book.CreateText(line, Book.SMALL_FONT)
	line.when:SetPoint("RIGHT", -6, 0)
	line.when:SetJustifyH("RIGHT")
	line.when:SetAlpha(0.7)

	-- Spec behind the name, in the lighter normal font
	line.spec = Book.CreateText(line, Book.SMALL_FONT)
	line.spec:SetPoint("LEFT", line.name, "RIGHT", 6, 0)
	line.spec:SetPoint("RIGHT", line.when, "LEFT", -6, 0)
	line.spec:SetWordWrap(false)
	line.spec:SetAlpha(0.7)

	recentLines[i] = line
end
local noRecent = Text(left, Book.TEXT_FONT, RECENT_FIRST)
noRecent:SetAlpha(0.7)
noRecent:SetText("Nothing yet.")

function RefreshRecent()
	recentOffset = math.max(0, math.min(recentOffset, #recent - RECENT_COUNT))
	for i, line in ipairs(recentLines) do
		local duel = recent[recentOffset + i]
		line:SetShown(duel ~= nil)
		if duel then
			-- The verdict's shade when the health is known, stronger the more one-sided
			local verdict, gap, color = ns.GetVerdict(duel)
			if verdict then
				line.background:SetColorTexture(color.r, color.g, color.b, 0.15 + gap / 100 * 0.25)
			else
				line.background:SetColorTexture((duel.won and WON_COLOR or LOST_COLOR):GetRGBA())
			end
			ns.SetDuelistIcon(line.icon, duel.oppClass, duel.oppSpec)
			-- Plain ink: class colors are hard to read on the tint, the icon shows the class
			line.name:SetText(ns.InkName(duel.opp))
			local spec = duel.oppSpec
			line.spec:SetText(spec and spec.name and ("(%s %s)"):format(spec.name, spec.points or "") or "")
			line.when:SetText(date("%d.%m. %H:%M", duel.t))
		end
	end
	noRecent:SetShown(#recent == 0)
	recentPosition:SetShown(#recent > RECENT_COUNT)
	recentPosition:SetText(("%d-%d of %d"):format(recentOffset + 1,
		math.min(#recent, recentOffset + RECENT_COUNT), #recent))
end

local function RefreshRecord()
	local duels = ns.GetDuels()
	local wins, losses = ns.GetRecord()

	local total = wins + losses
	if total == 0 then
		summary:SetText("No duels yet. Ask someone for a duel!")
	else
		summary:SetText(("%d duels, %s%d won|r, %s%d lost|r (%d%%)"):format(
			total, Book.GOOD, wins, Book.BAD, losses, math.floor(wins / total * 100)))
	end

	local confirmed, withAddon = 0, 0
	for _, duel in ipairs(duels) do
		if duel.peer then
			withAddon = withAddon + 1
			confirmed = confirmed + (duel.confirmed and 1 or 0)
		end
	end
	confirmedLine:SetText(("%d of %d duels confirmed by the opponent's Duel Tracker"):format(confirmed, withAddon))
	confirmedLine:SetShown(withAddon > 0)

	recent = {}
	for i = 1, math.min(#duels, ns.KEEP_LOGS) do
		recent[i] = duels[i]
	end
	RefreshRecent()
end

---------------------------------------------------------------------------
-- Right page: opponents table
---------------------------------------------------------------------------

Book.CreateHeader(right, "Opponents")

local TABLE_TOP = -100
local TABLE_BOTTOM = Book.CONTENT_BOTTOM
local ROWS_PER_PAGE = floor((TABLE_TOP - TABLE_BOTTOM) / ROW_HEIGHT) - 1

Text(right, nil, TABLE_TOP):SetText("Player")
Number(right, nil, TABLE_TOP, 2):SetText("Won")
Number(right, nil, TABLE_TOP, 1):SetText("Lost")
local empty = Text(right, Book.TEXT_FONT, TABLE_TOP - ROW_HEIGHT - 4)
empty:SetAlpha(0.7)
empty:SetText("Nobody yet.")

local hint = Book.CreateText(right, Book.SMALL_FONT)
hint:SetPoint("BOTTOMLEFT", CONTENT_X, 44)
hint:SetAlpha(0.7)
hint:SetText("Click a player to see your duels against them.")

local rows = {}
local page = 1
local RefreshOpponents

local pager = Book.CreatePager(right, function(delta)
	page = page + delta
	RefreshOpponents()
end)
pager:EnableWheel(right)

local function GetRow(i)
	if not rows[i] then
		local y = TABLE_TOP - i * ROW_HEIGHT - 4
		local row = CreateFrame("Button", nil, right)
		row:SetPoint("TOPLEFT", CONTENT_X - 6, y + 3)
		row:SetPoint("RIGHT", -Book.PAGE_MARGIN + 6, 0)
		row:SetHeight(ROW_HEIGHT)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.12)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
		row.icon:SetPoint("LEFT", 6, 0)
		row.name = Text(right, Book.BOLD_FONT, y, CONTENT_X + ROW_HEIGHT + 4)
		row.won = Number(right, Book.TEXT_FONT, y, 2)
		row.lost = Number(right, Book.TEXT_FONT, y, 1)
		row.stripe = i % 2 == 1 and Stripe(right, y) or nil
		row:SetScript("OnClick", function(self)
			ns.ShowDuelsAgainst(self.opponent.name)
		end)
		rows[i] = row
	end
	return rows[i]
end

local function ShowRow(row, shown)
	row:SetShown(shown)
	row.name:SetShown(shown)
	row.won:SetShown(shown)
	row.lost:SetShown(shown)
	if row.stripe then
		row.stripe:SetShown(shown)
	end
end

function RefreshOpponents()
	local opponents = ns.GetOpponents()
	local pages = math.max(1, math.ceil(#opponents / ROWS_PER_PAGE))
	page = math.max(1, math.min(page, pages))
	pager:Update(page, pages)

	local first = (page - 1) * ROWS_PER_PAGE
	for i = 1, ROWS_PER_PAGE do
		local opponent = opponents[first + i]
		if opponent then
			local row = GetRow(i)
			row.opponent = opponent
			-- Class, not spec: one player can show up in different specs across duels
			ns.SetDuelistIcon(row.icon, opponent.class)
			row.name:SetText(ns.InkName(opponent.name))
			row.won:SetText(opponent.wins)
			row.lost:SetText(opponent.losses)
			ShowRow(row, true)
		elseif rows[i] then
			ShowRow(rows[i], false)
		end
	end
	empty:SetShown(#opponents == 0)
	hint:SetShown(#opponents > 0)
end

---------------------------------------------------------------------------

function panel:Refresh()
	RefreshRecord()
	RefreshOpponents()
end

panel:SetScript("OnShow", panel.Refresh)
