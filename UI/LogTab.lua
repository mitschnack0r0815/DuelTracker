local _, ns = ...
local Book = ns.Book

-- Log tab. Left page: the last ns.KEEP_LOGS duels that have a log, as spellbook entries,
-- paged. Right page: the picked duel in depth, its totals for both
-- sides, top damage and its combat log; or, with the info button or while there are no
-- duels, how logging works.
local ROW_HEIGHT = 20
local CONTENT_X = Book.CONTENT_X
local COL_WIDTH = 70
local ENTRY_SPACING = 62
local LIST_TOP = -100
local LIST_BOTTOM = Book.CONTENT_BOTTOM
local ENTRIES_PER_PAGE = floor((LIST_TOP - LIST_BOTTOM) / ENTRY_SPACING)
local TOP_SPELLS = 3

local panel, tabIndex = ns.AddTab("Log")
local left, right = panel.left, panel.right

local showInfo = false -- the info button was clicked: how logging works instead of the duel
local selected -- the duel shown on the right page
local page = 1
local duels = {}

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

local function Stripe(page, y)
	local stripe = page:CreateTexture(nil, "BACKGROUND", nil, 3)
	stripe:SetPoint("TOPLEFT", CONTENT_X - 6, y + 3)
	stripe:SetPoint("RIGHT", -Book.PAGE_MARGIN + 6, 0)
	stripe:SetHeight(ROW_HEIGHT)
	stripe:SetColorTexture(Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.07)
	return stripe
end

local Refresh, ShowDuel

---------------------------------------------------------------------------
-- Left page: duel list
---------------------------------------------------------------------------

Book.CreateHeader(left, ("Last %d logged duels"):format(ns.KEEP_LOGS))

local empty = Text(left, Book.TEXT_FONT, LIST_TOP)
empty:SetAlpha(0.7)
empty:SetText("No logged duels yet.")

local pager = Book.CreatePager(left, function(delta)
	page = page + delta
	Refresh()
end)
pager:EnableWheel(left)

-- Combat log file on or off, bottom left across from the pager
local combatLogCheck = CreateFrame("CheckButton", nil, left, "UICheckButtonTemplate")
combatLogCheck:SetSize(26, 26)
combatLogCheck:SetPoint("BOTTOMLEFT", CONTENT_X - 4, 37)
local combatLogLabel = Book.CreateText(left, Book.SMALL_FONT)
combatLogLabel:SetPoint("LEFT", combatLogCheck, "RIGHT", 2, 1)
combatLogLabel:SetText("Write the combat log file during duels")
combatLogCheck:SetScript("OnShow", function(self)
	self:SetChecked(ns.IsCombatLogEnabled())
end)
combatLogCheck:SetScript("OnClick", function(self)
	ns.SetCombatLogEnabled(self:GetChecked())
	PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end)
combatLogCheck:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
	GameTooltip:AddLine("Combat log file")
	GameTooltip:AddLine("Switches the game's combat log file on when a duel is asked for and off after it ends. "
		.. "Off by default; the info button on the right explains more.", 1, 1, 1, true)
	GameTooltip:Show()
end)
combatLogCheck:SetScript("OnLeave", GameTooltip_Hide)

local entries = {}
for i = 1, ENTRIES_PER_PAGE do
	local entry = Book.CreateEntry(left)
	entry.name:SetFontObject(_G[Book.BOLD_NAME_FONT])
	entry:SetPoint("TOPLEFT", CONTENT_X, LIST_TOP - (i - 1) * ENTRY_SPACING)
	entry:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
	entry:SetScript("OnClick", function(self)
		selected = self.duel
		showInfo = false
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Refresh()
	end)
	entries[i] = entry
end

local function RefreshList()
	duels = {}
	for _, duel in ipairs(ns.GetDuels()) do
		if #duels >= ns.KEEP_LOGS then
			break
		end
		if ns.HasLog(duel) then
			duels[#duels + 1] = duel
		end
	end

	-- Keep the picked duel if it's still listed, otherwise pick the newest
	local found = false
	for _, duel in ipairs(duels) do
		found = found or duel == selected
	end
	if not found then
		selected = duels[1]
	end

	local pages = math.max(1, math.ceil(#duels / ENTRIES_PER_PAGE))
	page = math.max(1, math.min(page, pages))
	pager:Update(page, pages)

	local first = (page - 1) * ENTRIES_PER_PAGE
	for i, entry in ipairs(entries) do
		local duel = duels[first + i]
		entry.duel = duel
		entry:SetShown(duel ~= nil)
		if duel then
			ns.SetDuelistIcon(entry.icon, duel.oppClass, duel.oppSpec)
			entry.name:SetText(ns.InkName(duel.opp))
			entry.sub:SetText(("%s, %s   %s   %s%s"):format(
				duel.won and (Book.GOOD .. "Won|r") or (Book.BAD .. "Lost|r"),
				ns.DescribeHow(duel), date("%d.%m. %H:%M", duel.t), ns.FormatDuration(duel.dur),
				duel.oppLevel and ("   Level " .. duel.oppLevel) or ""))
			entry.isSelected = duel == selected
			Book.UpdateEntry(entry)
		end
	end
	empty:SetShown(#duels == 0)
end

---------------------------------------------------------------------------
-- Right page: the picked duel
---------------------------------------------------------------------------

-- Holds everything about the picked duel; the logging info replaces it
local view = CreateFrame("Frame", nil, right)
view:SetAllPoints()

local duelHeader = Book.CreateHeader(view)
local info = Text(view, Book.TEXT_FONT, -100)

-- Matchup: [icon] You (Arms 31/20/0)  vs  [icon] Grimbash (Frost 0/5/46), names in bold
local matchup = CreateFrame("Frame", nil, view)
matchup:SetPoint("TOPLEFT", CONTENT_X, -122)
matchup:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
matchup:SetHeight(20)

-- Icon, bold name and spec, after the given region (or at the start)
local function Duelist(after)
	local duelist = {}
	duelist.icon = matchup:CreateTexture(nil, "ARTWORK")
	duelist.icon:SetSize(18, 18)
	if after then
		duelist.icon:SetPoint("LEFT", after, "RIGHT", 8, 0)
	else
		duelist.icon:SetPoint("LEFT")
	end
	duelist.name = Book.CreateText(matchup, Book.BOLD_SMALL_FONT)
	duelist.name:SetPoint("LEFT", duelist.icon, "RIGHT", 5, 0)
	duelist.spec = Book.CreateText(matchup, Book.SMALL_FONT)
	duelist.spec:SetPoint("LEFT", duelist.name, "RIGHT", 4, 0)
	duelist.spec:SetAlpha(0.7)
	return duelist
end

local me = Duelist()
local versus = Book.CreateText(matchup, Book.SMALL_FONT)
versus:SetPoint("LEFT", me.spec, "RIGHT", 8, 0)
versus:SetText(Book.MUTED .. "vs|r")
local them = Duelist(versus)

-- spec: "(Arms 31/20/0)", empty when the spec isn't known
local function ShowDuelist(duelist, name, class, spec)
	ns.SetDuelistIcon(duelist.icon, class, spec)
	duelist.name:SetText(name)
	duelist.spec:SetText(spec and spec.name and ("(%s %s)"):format(spec.name, spec.points or "") or "")
end

local confirmLine = Text(view, nil, -146)

-- Health at the start and end, two lines
local healthText = Text(view, nil, -170)
healthText:SetSpacing(3)

-- Everything below only shows for duels with combat details
local details = CreateFrame("Frame", nil, view)
details:SetAllPoints()

local TABLE_TOP = -216
Number(details, nil, TABLE_TOP, 2):SetText(Book.MINE .. "You|r")
local theirLabel = Number(details, nil, TABLE_TOP, 1)
local statRows = {}
for i, stat in ipairs({ { "dmg", "Damage" }, { "heal", "Healing" }, { "hits", "Hits" }, { "crits", "Crits" } }) do
	local y = TABLE_TOP - i * ROW_HEIGHT
	if i % 2 == 1 then
		Stripe(details, y)
	end
	Text(details, Book.TEXT_FONT, y):SetText(stat[2])
	statRows[i] = { key = stat[1], mine = Number(details, Book.TEXT_FONT, y, 2), theirs = Number(details, Book.TEXT_FONT, y, 1) }
end

local TOP_TOP = TABLE_TOP - 4 * ROW_HEIGHT - 28
SubHeader(details, "Top damage", TOP_TOP)
-- Ours on the left, theirs in a second column
local topLines = {}
for i = 1, TOP_SPELLS do
	local y = TOP_TOP - 16 - i * 18
	local mine = Text(details, nil, y)
	mine:SetWidth(150)
	mine:SetWordWrap(false)
	local theirs = Text(details, nil, y, CONTENT_X + 165)
	theirs:SetWidth(150)
	theirs:SetWordWrap(false)
	topLines[i] = { mine = mine, theirs = theirs }
end

local LOG_TOP = TOP_TOP - 16 - TOP_SPELLS * 18 - 22
SubHeader(view, "Combat log", LOG_TOP)

local log = CreateFrame("ScrollingMessageFrame", nil, view)
log:SetPoint("TOPLEFT", CONTENT_X, LOG_TOP - 36)
log:SetPoint("BOTTOMRIGHT", -Book.PAGE_MARGIN, 40)
log:SetFontObject(_G[Book.SMALL_FONT] or GameFontNormalSmall)
log:SetJustifyH("LEFT")
log:SetFading(false)
log:SetMaxLines(ns.MAX_LOG_EVENTS + 10)
log:EnableMouseWheel(true)
log:SetScript("OnMouseWheel", function(self, delta)
	for _ = 1, 3 do
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end
end)

local logHint = Book.CreateText(view, Book.SMALL_FONT)
logHint:SetPoint("BOTTOMLEFT", CONTENT_X, 20)
logHint:SetAlpha(0.7)
logHint:SetText("Scroll the log with the mouse wheel.")

local function AddLogLine(text)
	log:AddMessage(text, Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b)
end

-- Top spells by damage: "Mortal Strike 820"
local function GetTopSpells(spells)
	local list = {}
	for name, damage in pairs(spells) do
		list[#list + 1] = { name = name, damage = damage }
	end
	table.sort(list, function(a, b)
		return a.damage > b.damage
	end)
	return list
end

local function FormatEntry(entry, oppName)
	local function Who(side)
		if side == 1 then
			return Book.MINE .. "You|r"
		elseif side == 2 then
			return Book.THEIRS .. oppName .. "|r"
		end
		return ""
	end
	local src, dst, spell = Who(entry.s), Who(entry.d), entry.n or "?"
	local crit = entry.c and (Book.BAD .. " crit|r") or ""
	local e = entry.e
	local text
	if e:find("_DAMAGE$") then
		text = ("%s %s %s %d%s"):format(src, spell, dst, entry.a or 0, crit)
	elseif e:find("_MISSED$") then
		text = ("%s %s %s %s"):format(src, spell, dst, Book.MUTED .. (entry.x or "miss"):lower() .. "|r")
	elseif e:find("_HEAL$") then
		text = ("%s %s heals %s %s%d|r%s"):format(src, spell, dst, Book.GOOD, entry.a or 0, crit)
	elseif e == "SPELL_AURA_APPLIED" then
		text = entry.s == entry.d and ("%s gains %s"):format(dst, spell)
			or ("%s %s on %s"):format(src, spell, dst)
	elseif e == "SPELL_AURA_REMOVED" then
		text = Book.MUTED .. spell .. " fades from|r " .. dst
	elseif e == "SPELL_CAST_START" then
		text = ("%s begins %s"):format(src, spell)
	elseif e == "SPELL_CAST_SUCCESS" then
		text = ("%s casts %s"):format(src, spell)
	elseif e == "SPELL_INTERRUPT" then
		text = ("%s %s interrupts %s %s"):format(src, spell, dst, entry.x or "")
	else
		text = ("%s %s removes %s from %s"):format(src, spell, entry.x or "?", dst)
	end
	return ("%s%5.1f|r  %s"):format(Book.MUTED, entry.t, text)
end

---------------------------------------------------------------------------
-- Right page: how logging works (info button, or while there are no duels)
---------------------------------------------------------------------------

local LOGGING_INFO = table.concat({
	"Every duel you fight is recorded by itself: who won, how it ended, when, and against whom. "
		.. "When your opponent has Duel Tracker too, both sides compare results and the duel counts as confirmed.",
	"",
	"To start, ask someone for a duel: right-click their portrait and pick Duel, or type /duel while you target them.",
}, "\n")

local COMBAT_LOG_INFO = table.concat({
	"WoW doesn't let addons read the combat log while you play. The game can still write it to a file: "
		.. "tick \"Write the combat log file during duels\" at the bottom left, and Duel Tracker switches "
		.. "combat logging on when a duel is asked for, and off a few seconds after it ends. It's off by default. "
		.. "If you switched logging on yourself with /combatlog, it stays on.",
	"",
	"The file is in the Logs folder of your WoW installation, next to Interface and WTF: "
		.. "WoWCombatLog-<date>_<time>.txt. Each duel here shows the time range it's in.",
	"",
	"Reading that file into this tab takes a small tool outside the game, which is still to come. "
		.. "Until then, /duels test adds made-up duels that show what a full log looks like.",
}, "\n")

local infoPage = CreateFrame("Frame", nil, right)
infoPage:SetAllPoints()
infoPage:Hide()

Book.CreateHeader(infoPage, "How logging works")

local loggingText = Book.CreateText(infoPage, Book.TEXT_FONT)
loggingText:SetPoint("TOPLEFT", CONTENT_X, -100)
loggingText:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
loggingText:SetJustifyV("TOP")
loggingText:SetSpacing(3)
loggingText:SetText(LOGGING_INFO)

local combatLogHeader = SubHeader(infoPage, "Combat log", -100)
combatLogHeader:ClearAllPoints()
combatLogHeader:SetPoint("TOPLEFT", loggingText, "BOTTOMLEFT", 0, -22)
combatLogHeader:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)

local combatLogText = Book.CreateText(infoPage, Book.TEXT_FONT)
combatLogText:SetPoint("TOPLEFT", combatLogHeader, "BOTTOMLEFT", 0, -12)
combatLogText:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
combatLogText:SetJustifyV("TOP")
combatLogText:SetSpacing(3)
combatLogText:SetText(COMBAT_LOG_INFO)

local infoButton = CreateFrame("Button", nil, right)
infoButton:SetSize(30, 30)
infoButton:SetPoint("TOPRIGHT", -Book.PAGE_MARGIN + 10, -38)
infoButton:SetNormalTexture("Interface\\Common\\help-i")
infoButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
infoButton:SetFrameLevel(view:GetFrameLevel() + 5)
infoButton:SetScript("OnClick", function()
	showInfo = not showInfo
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	Refresh()
end)
infoButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("How logging works")
	if showInfo then
		GameTooltip:AddLine("Click to go back to the duel.", 1, 1, 1)
	end
	GameTooltip:Show()
end)
infoButton:SetScript("OnLeave", GameTooltip_Hide)

---------------------------------------------------------------------------

local function ConfirmText(duel, oppName)
	if duel.confirmed then
		return Book.GOOD .. oppName .. "'s Duel Tracker agrees on the result.|r"
	elseif duel.disputed then
		return Book.BAD .. oppName .. "'s Duel Tracker reported another result.|r"
	elseif duel.peer then
		return oppName .. " has Duel Tracker, no report from them yet."
	end
	return Book.MUTED .. oppName .. " doesn't seem to have Duel Tracker.|r"
end

function ShowDuel(duel)
	log:Clear()
	local hasDetails = duel and duel.sum ~= nil
	details:SetShown(hasDetails)
	info:SetShown(duel ~= nil)
	matchup:SetShown(duel ~= nil)
	confirmLine:SetShown(duel ~= nil)
	healthText:SetShown(duel ~= nil)
	if not duel then
		duelHeader.Text:SetText("")
		AddLogLine(Book.MUTED .. "Pick a duel on the left.|r")
		logHint:Hide()
		return
	end

	local oppName = ns.ShortName(duel.opp)
	duelHeader.Text:SetText((duel.won and "Won against " or "Lost against ") .. oppName)
	info:SetText(("%s, %s, %s fighting"):format(
		date("%d.%m.%Y %H:%M", duel.t), ns.DescribeHow(duel), ns.FormatDuration(duel.dur)))
	confirmLine:SetText(ConfirmText(duel, oppName))
	local myHealth, oppHealth = ns.DescribeHealth(duel)
	healthText:SetText(myHealth and (myHealth .. "\n" .. oppHealth) or (Book.MUTED .. "No health recorded.|r"))
	local verdict, _, color = ns.GetVerdict(duel)
	if verdict then
		info:SetText(info:GetText() .. ", " .. ns.InkVerdictColor(color) .. verdict:lower() .. "|r")
	end
	ShowDuelist(me, "You", duel.myClass, duel.mySpec)
	ShowDuelist(them, ns.InkName(duel.opp), duel.oppClass, duel.oppSpec)

	if hasDetails then
		theirLabel:SetText(Book.THEIRS .. oppName .. "|r")
		for _, row in ipairs(statRows) do
			row.mine:SetText(duel.sum[1][row.key] or 0)
			row.theirs:SetText(duel.sum[2][row.key] or 0)
		end
		local mine, theirs = GetTopSpells(duel.sum[1].spells), GetTopSpells(duel.sum[2].spells)
		for i, line in ipairs(topLines) do
			line.mine:SetText(mine[i] and ("%s %s%d|r"):format(mine[i].name, Book.MINE, mine[i].damage) or "")
			line.theirs:SetText(theirs[i] and ("%s %s%d|r"):format(theirs[i].name, Book.THEIRS, theirs[i].damage) or "")
		end
	end

	logHint:SetShown(duel.log ~= nil)
	if duel.log then
		for _, entry in ipairs(duel.log) do
			AddLogLine(FormatEntry(entry, oppName))
		end
		log:ScrollToTop()
	elseif duel.logged then
		AddLogLine("This duel is in the combat log file")
		AddLogLine(Book.MUTED .. "Logs\\WoWCombatLog-*.txt|r")
		AddLogLine(("from %s to %s. It isn't read into Duel Tracker yet."):format(
			date("%H:%M:%S", duel.start or duel.ends), date("%H:%M:%S", duel.ends)))
	else
		AddLogLine(Book.MUTED .. "No combat log for this duel.|r")
	end
end

---------------------------------------------------------------------------

function Refresh()
	RefreshList()
	-- With no duels to show, the info is what this page is for
	local info = showInfo or #duels == 0
	infoPage:SetShown(info)
	view:SetShown(not info)
	infoButton:SetShown(#duels > 0)
	ShowDuel(selected)
end

function panel:Refresh()
	-- Keep the log where it was scrolled to, say when a report confirms the shown duel
	local shown, scroll = selected, log:GetScrollOffset()
	Refresh()
	if selected == shown then
		log:SetScrollOffset(scroll)
	end
end

panel:SetScript("OnShow", Refresh)

-- Opens the Log tab on that duel, on the page of the list that has it
function ns.ShowDuelLog(duel)
	selected = duel
	showInfo = false
	ns.ShowTab(tabIndex)
	RefreshList()
	for i, listed in ipairs(duels) do
		if listed == duel then
			page = math.ceil(i / ENTRIES_PER_PAGE)
		end
	end
	Refresh()
end
