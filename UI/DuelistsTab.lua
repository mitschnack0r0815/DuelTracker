local _, ns = ...
local Book = ns.Book

-- Duelists tab: the players we play Elo duels with, like a friends list. Left page: add
-- a player by name or target, challenge the target, and how many Elo duels there were.
-- Right page: the list with our Elo record against each; click one to see the duels,
-- the swords challenge them to an Elo duel, the x removes them.
local ROW_HEIGHT = 24
local CONTENT_X = Book.CONTENT_X
local COL_WIDTH = 70 -- ratings carry a rank badge
local BUTTON_SIZE = 18
local ACTIONS_WIDTH = 2 * BUTTON_SIZE + 20 -- challenge and remove buttons right of the rows

local panel, tabIndex = ns.AddTab("Duelists")
local left, right = panel.left, panel.right
local Refresh

local function Text(page, font, y, x)
	local text = Book.CreateText(page, font or Book.SMALL_FONT)
	text:SetPoint("TOPLEFT", x or CONTENT_X, y)
	return text
end

-- Right-aligned number column; col 1 is the rightmost, left of the row buttons
local function Number(page, font, y, col)
	local text = Book.CreateText(page, font or Book.SMALL_FONT)
	text:SetWidth(COL_WIDTH)
	text:SetJustifyH("RIGHT")
	text:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN - ACTIONS_WIDTH - (col - 1) * COL_WIDTH, y)
	return text
end

---------------------------------------------------------------------------
-- Left page: adding duelists
---------------------------------------------------------------------------

Book.CreateHeader(left, "Duelists")

local intro = Text(left, Book.TEXT_FONT, -100)
intro:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
intro:SetWordWrap(true)
intro:SetText("Challenge the players on this list to Elo duels, when they have you on "
	.. "their list too. Only duels you both agreed on count for Elo.")

local addLabel = Text(left, nil, -170)
addLabel:SetText("Add a player")

local nameBox = CreateFrame("EditBox", "DuelTrackerDuelistNameBox", left, "InputBoxTemplate")
nameBox:SetSize(200, 22)
nameBox:SetPoint("TOPLEFT", CONTENT_X + 6, -192)
nameBox:SetAutoFocus(false)
nameBox:SetMaxLetters(64)

local function AddFromBox()
	local added, name = ns.AddDuelist(nameBox:GetText())
	if added then
		nameBox:SetText("")
		nameBox:ClearFocus()
		print(("Duel Tracker: %s is now one of your duelists."):format(ns.InkName(name)))
	end
end

local addButton = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
addButton:SetSize(80, 24)
addButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
addButton:SetText("Add")
addButton:SetScript("OnClick", AddFromBox)

nameBox:SetScript("OnEnterPressed", AddFromBox)
nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)
nameBox:HookScript("OnTextChanged", function(self)
	addButton:SetEnabled(self:GetText():trim() ~= "")
end)

local targetButton = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
targetButton:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -6, -10)
targetButton:SetSize(140, 24)
targetButton:SetText("Add your target")
targetButton:SetScript("OnClick", function()
	local added, name = ns.AddDuelist(GetUnitName("target", true), select(2, UnitClass("target")))
	if added then
		print(("Duel Tracker: %s is now one of your duelists."):format(ns.InkName(name)))
	end
end)

local challengeButton = CreateFrame("Button", nil, left, "UIPanelButtonTemplate")
challengeButton:SetPoint("LEFT", targetButton, "RIGHT", 8, 0)
challengeButton:SetSize(170, 24)
challengeButton:SetText("Challenge your target")
challengeButton:SetScript("OnClick", function()
	local name = GetUnitName("target", true)
	local ok, reason = ns.ChallengeElo(name)
	print("Duel Tracker: " .. (ok and ("challenged %s to an Elo duel."):format(ns.InkName(ns.FullName(name))) or reason))
end)

local function UpdateTargetButton()
	local player = UnitIsPlayer("target") and not UnitIsUnit("target", "player")
	local duelist = player and ns.FindDuelist(GetUnitName("target", true))
	targetButton:SetEnabled(player and not duelist and true or false)
	challengeButton:SetEnabled(duelist and not ns.GetOutgoingChallenge() and true or false)
end

local slashHint = Text(left, nil, -262)
slashHint:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
slashHint:SetWordWrap(true)
slashHint:SetAlpha(0.7)
slashHint:SetText("Or type /duels add <name>, /duels elo <name> (both use your target "
	.. "without a name) and /duels remove <name>.")

local SUMMARY_TOP = -320
local summaryHeader = Book.CreateSubHeader(left, "Elo duels")
summaryHeader:SetPoint("TOPLEFT", CONTENT_X, SUMMARY_TOP)
summaryHeader:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
local ratingLine = Text(left, Book.BOLD_NAME_FONT, SUMMARY_TOP - 40)
local summary = Text(left, Book.TEXT_FONT, SUMMARY_TOP - 66)

local function RefreshSummary()
	local wins, losses = 0, 0
	for _, duel in ipairs(ns.GetDuels()) do
		if duel.elo then
			if duel.won then
				wins = wins + 1
			else
				losses = losses + 1
			end
		end
	end
	local rating, games = ns.GetMyRating()
	ratingLine:SetText(("Your rating: %s  %s"):format(ns.RatingText(rating, 20), ns.GetRankName(ns.GetRank(rating))))
	local total = wins + losses
	if total == 0 then
		summary:SetText("No Elo duels yet.")
	else
		summary:SetText(("%d Elo duels, %s%d won|r, %s%d lost|r"):format(total, Book.GOOD, wins, Book.BAD, losses))
		if games < total then
			-- Disputed ones, and ones from before ratings were swapped
			summary:SetText(summary:GetText() .. (", %d of them rated"):format(games))
		end
	end
end

---------------------------------------------------------------------------
-- Right page: the list
---------------------------------------------------------------------------

Book.CreateHeader(right, "Ranking")

local TABLE_TOP = -100
local ROWS_PER_PAGE = floor((TABLE_TOP - Book.CONTENT_BOTTOM) / ROW_HEIGHT) - 1

local RANK_WIDTH = 28 -- "12." before the icon
Text(right, nil, TABLE_TOP):SetText("#")
Text(right, nil, TABLE_TOP, CONTENT_X + RANK_WIDTH):SetText("Player")
Number(right, nil, TABLE_TOP, 3):SetText("Rating")
Number(right, nil, TABLE_TOP, 2):SetText("Won")
Number(right, nil, TABLE_TOP, 1):SetText("Lost")
local empty = Text(right, Book.TEXT_FONT, TABLE_TOP - ROW_HEIGHT - 4)
empty:SetAlpha(0.7)
empty:SetText("Nobody yet. Add the players you want to play Elo duels with.")
empty:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
empty:SetWordWrap(true)

local hint = Book.CreateText(right, Book.SMALL_FONT)
hint:SetPoint("BOTTOMLEFT", CONTENT_X, 40)
hint:SetPoint("RIGHT", -Book.PAGE_MARGIN - 160, 0) -- left of the pager, wraps upwards
hint:SetWordWrap(true)
hint:SetAlpha(0.7)
hint:SetText("Ratings as last heard, won and lost in Elo duels. Click a player to see your duels.")

local rows = {}
local page = 1

local pager = Book.CreatePager(right, function(delta)
	page = page + delta
	Refresh()
end)
pager:EnableWheel(right)

-- Asks before removing; the popup's data is the player's full name
StaticPopupDialogs["DUELTRACKER_REMOVE_DUELIST"] = {
	text = "Remove %s from your duelists?\n\nYour duels against them stay, but you can't challenge each other to Elo duels any more.",
	button1 = REMOVE or "Remove",
	button2 = CANCEL or "Cancel",
	OnAccept = function(self, name)
		if ns.RemoveDuelist(name) then
			print(("Duel Tracker: removed %s from your duelists."):format(ns.InkName(name)))
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3, -- avoids the taint of the first popup slots
}

local function GetRow(i)
	if rows[i] then
		return rows[i]
	end
	local y = TABLE_TOP - i * ROW_HEIGHT - 4
	local row = CreateFrame("Button", nil, right)
	row:SetPoint("TOPLEFT", CONTENT_X - 6, y + 5)
	row:SetPoint("RIGHT", -Book.PAGE_MARGIN - ACTIONS_WIDTH, 0)
	row:SetHeight(ROW_HEIGHT)
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.12)
	if i % 2 == 1 then
		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetPoint("TOPLEFT")
		stripe:SetPoint("BOTTOMRIGHT", ACTIONS_WIDTH + 6, 0)
		stripe:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.07)
	end
	-- Our own row stands out in gold
	row.mine = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	row.mine:SetPoint("TOPLEFT")
	row.mine:SetPoint("BOTTOMRIGHT", ACTIONS_WIDTH + 6, 0)
	row.mine:SetColorTexture(0.85, 0.65, 0.2, 0.3)
	row.rank = Book.CreateText(row, Book.TEXT_FONT)
	row.rank:SetPoint("LEFT", 6, 0)
	row.rank:SetWidth(RANK_WIDTH - 6)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW_HEIGHT - 6, ROW_HEIGHT - 6)
	row.icon:SetPoint("LEFT", RANK_WIDTH + 6, 0)
	row.name = Book.CreateText(row, Book.BOLD_FONT)
	row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.name:SetWordWrap(false)
	-- Lined up with the column headers: the row ends where the number columns do
	local function RowNumber(col)
		local text = Book.CreateText(row, Book.TEXT_FONT)
		text:SetWidth(COL_WIDTH)
		text:SetJustifyH("RIGHT")
		text:SetPoint("RIGHT", -(col - 1) * COL_WIDTH, 0)
		return text
	end
	row.rating = RowNumber(3)
	row.won = RowNumber(2)
	row.lost = RowNumber(1)
	row:SetScript("OnClick", function(self)
		if not self.duelist.isMe then
			ns.ShowDuelsAgainst(self.duelist.name)
		end
	end)

	row.challenge = CreateFrame("Button", nil, row)
	row.challenge:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	row.challenge:SetPoint("LEFT", row, "RIGHT", 8, 0)
	row.challenge:SetNormalTexture(ns.ICON)
	row.challenge:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	row.challenge:SetScript("OnClick", function()
		local ok, reason = ns.ChallengeElo(row.duelist.name)
		print("Duel Tracker: " .. (ok and ("challenged %s to an Elo duel."):format(ns.InkName(row.duelist.name)) or reason))
	end)
	row.challenge:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Challenge to an Elo duel")
		GameTooltip:AddLine("They get a yes/no popup. When they accept, your next duel with them within a minute is an Elo duel.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.challenge:SetScript("OnLeave", GameTooltip_Hide)

	row.remove = CreateFrame("Button", nil, row)
	row.remove:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	row.remove:SetPoint("LEFT", row.challenge, "RIGHT", 6, 0)
	row.remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
	row.remove:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	row.remove:SetScript("OnClick", function()
		local name = row.duelist.name
		StaticPopup_Show("DUELTRACKER_REMOVE_DUELIST", ns.InkName(name), nil, name)
	end)
	row.remove:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Remove from duelists")
		GameTooltip:AddLine("Your duels against them stay.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	row.remove:SetScript("OnLeave", GameTooltip_Hide)

	rows[i] = row
	return row
end

-- Our duelists and us, by rating; the ones we haven't heard a rating from last, by name.
-- rank is set on the rated ones.
local function GetRanking()
	local list = ns.GetDuelists()
	if #list == 0 then
		return list -- nobody to rank against
	end
	local me = { name = ns.GetMyName(), class = select(2, UnitClass("player")), isMe = true, wins = 0, losses = 0 }
	me.rating = ns.GetMyRating()
	for _, duel in ipairs(ns.GetDuels()) do
		if duel.elo and not duel.disputed then
			me.wins = me.wins + (duel.won and 1 or 0)
			me.losses = me.losses + (duel.won and 0 or 1)
		end
	end
	list[#list + 1] = me
	table.sort(list, function(a, b)
		if (a.rating ~= nil) ~= (b.rating ~= nil) then
			return a.rating ~= nil
		end
		if a.rating and a.rating ~= b.rating then
			return a.rating > b.rating
		end
		return a.name < b.name
	end)
	for i, entry in ipairs(list) do
		entry.rank = entry.rating and i or nil
	end
	return list
end

local function RefreshList()
	local duelists = GetRanking()
	local pages = math.max(1, math.ceil(#duelists / ROWS_PER_PAGE))
	page = math.max(1, math.min(page, pages))
	pager:Update(page, pages)

	local first = (page - 1) * ROWS_PER_PAGE
	for i = 1, ROWS_PER_PAGE do
		local duelist = duelists[first + i]
		if duelist then
			local row = GetRow(i)
			row.duelist = duelist
			ns.SetDuelistIcon(row.icon, duelist.class)
			row.rank:SetText(duelist.rank and duelist.rank .. "." or "")
			row.name:SetText(ns.InkName(duelist.name) .. (duelist.isMe and " (you)" or ""))
			row.mine:SetShown(duelist.isMe == true)
			row.challenge:SetShown(not duelist.isMe)
			row.remove:SetShown(not duelist.isMe)
			row.won:SetText(duelist.wins)
			row.lost:SetText(duelist.losses)
			row.rating:SetText(duelist.rating and ns.RatingText(duelist.rating) or "-")
			local waiting = ns.GetOutgoingChallenge()
			row.challenge:SetEnabled(not waiting)
			row.challenge:GetNormalTexture():SetDesaturated(waiting and true or false)
			row:Show()
		elseif rows[i] then
			rows[i]:Hide()
		end
	end
	empty:SetShown(#duelists == 0)
	hint:SetShown(#duelists > 0)
end

---------------------------------------------------------------------------

function Refresh()
	RefreshSummary()
	RefreshList()
	UpdateTargetButton()
	addButton:SetEnabled(nameBox:GetText():trim() ~= "")
end

panel.Refresh = Refresh
panel:SetScript("OnShow", Refresh)
panel:RegisterEvent("PLAYER_TARGET_CHANGED")
panel:SetScript("OnEvent", function()
	if panel:IsVisible() then
		UpdateTargetButton()
	end
end)

function ns.ShowDuelistsTab()
	ns.ShowTab(tabIndex)
end
