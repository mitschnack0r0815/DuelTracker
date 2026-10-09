local _, ns = ...

-- Shared art for the spellbook look: an open book with parchment pages, headers with the
-- ornate divider, spellbook style entries and page arrows. Uses the new spellbook's atlases;
-- on a client without them the art falls back to plain colors.
local Book = {}
ns.Book = Book

Book.PAGE_MARGIN = 56 -- space between a page's edges and its content
Book.ENTRY_HEIGHT = 58
local BLIZZARD_BOOK_HEIGHT = 832 -- height of the spellbook pages, to scale the ribbon

Book.FONT_COLOR = SPELLBOOK_FONT_COLOR or CreateColor(0.25, 0.16, 0.08)
-- Darker than the usual green/red so they stay readable on parchment
Book.GOOD = "|cff1f6b1f"
Book.BAD = "|cff8f1f1f"

local function Font(name, fallback)
	return _G[name] and name or fallback
end
Book.HEADER_FONT = Font("SystemFont_Huge2", "GameFontNormalHuge")
Book.NAME_FONT = Font("SystemFont_Large", "GameFontNormalLarge")
Book.SMALL_FONT = Font("SystemFont_Med1", "GameFontNormal")
Book.TEXT_FONT = Font("SystemFont_Med3", "GameFontNormal")

function Book.TemplateExists(name)
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(name) ~= nil
end

function Book.GetAtlas(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
end

-- Sets a spellbook atlas, or a plain color when this client doesn't have it
function Book.SetArt(texture, atlas, r, g, b, a)
	if Book.GetAtlas(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetColorTexture(r or 0, g or 0, b or 0, a or 0)
	end
end

function Book.CreateText(parent, font)
	local text = parent:CreateFontString(nil, "ARTWORK", font or Book.TEXT_FONT)
	text:SetTextColor(Book.FONT_COLOR:GetRGB())
	text:SetJustifyH("LEFT")
	return text
end

-- Two parchment pages filling frame. Sets frame.leftPage and frame.rightPage to them.
function Book.CreateBookArt(frame)
	local leftBG = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	leftBG:SetPoint("TOPLEFT")
	leftBG:SetPoint("BOTTOMRIGHT", frame, "BOTTOM")
	Book.SetArt(leftBG, "spellbook-background-evergreen-left", 0.82, 0.72, 0.54, 1)

	local rightBG = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
	rightBG:SetPoint("TOPLEFT", frame, "TOP")
	rightBG:SetPoint("BOTTOMRIGHT")
	Book.SetArt(rightBG, "spellbook-background-evergreen-right", 0.82, 0.72, 0.54, 1)

	-- Bookmark ribbon hanging over the spine, scaled down with the book
	local ribbonInfo = Book.GetAtlas("spellbook-background-evergreen-ribbon")
	if ribbonInfo then
		local ribbon = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
		ribbon:SetAtlas("spellbook-background-evergreen-ribbon")
		frame:SetScript("OnSizeChanged", function(self, width, height)
			local scale = height / BLIZZARD_BOOK_HEIGHT
			ribbon:SetSize(ribbonInfo.width * scale, ribbonInfo.height * scale)
			ribbon:ClearAllPoints()
			ribbon:SetPoint("TOPRIGHT", leftBG, "TOPRIGHT", 62 * scale, 0)
		end)
	end

	frame.leftPage = leftBG
	frame.rightPage = rightBG
end

-- Page title with the ornate divider underneath, like the spellbook's "General".
-- Anchored at the top of page; header.Text holds the title.
function Book.CreateHeader(page, text)
	local header = CreateFrame("Frame", nil, page)
	header:SetPoint("TOPLEFT", Book.PAGE_MARGIN + 12, -34)
	header:SetPoint("RIGHT", -Book.PAGE_MARGIN, 0)
	header:SetHeight(51)

	if Book.GetAtlas("spellbook-list-backplate") then
		local backplate = header:CreateTexture(nil, "BACKGROUND")
		backplate:SetAtlas("spellbook-list-backplate")
		backplate:SetAlpha(0.65)
		backplate:SetSize(416, 106)
		backplate:SetPoint("LEFT", -85, 10)
	end

	header.Text = Book.CreateText(header, Book.HEADER_FONT)
	header.Text:SetPoint("TOPLEFT", -8, 0)
	header.Text:SetPoint("BOTTOMRIGHT", 0, 11)
	header.Text:SetWordWrap(false)
	header.Text:SetText(text or "")

	local divider = header:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(11)
	divider:SetPoint("BOTTOMLEFT", -32, 0)
	divider:SetPoint("BOTTOMRIGHT")
	Book.SetArt(divider, "spellbook-divider", Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.4)
	return header
end

-- Smaller section title with a faint divider; the caller anchors it
function Book.CreateSubHeader(parent, text)
	local header = CreateFrame("Frame", nil, parent)
	header:SetHeight(28)

	header.Text = Book.CreateText(header, Book.NAME_FONT)
	header.Text:SetPoint("TOPLEFT")
	header.Text:SetText(text)

	local divider = header:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(8)
	divider:SetPoint("BOTTOMLEFT", -16, 0)
	divider:SetPoint("BOTTOMRIGHT")
	Book.SetArt(divider, "spellbook-divider", Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.3)
	divider:SetAlpha(0.6)
	return header
end

---------------------------------------------------------------------------
-- Spellbook style entries: framed icon, name and a small line underneath
---------------------------------------------------------------------------

-- Lit while hovered or selected (entry.isSelected), dimmed when entry.isDisabled
function Book.UpdateEntry(entry)
	local lit = entry.isSelected or entry:IsMouseOver()
	entry.backplate:SetAlpha(lit and 1 or 0.25)
	entry.iconHighlight:SetAlpha(entry.isSelected and 0.65 or (lit and 0.35 or 0))
	entry.icon:SetDesaturated(entry.isDisabled and true or false)
	entry.icon:SetAlpha(entry.isDisabled and 0.6 or 1)
	entry.name:SetAlpha(entry.isDisabled and 0.55 or 1)
	entry.sub:SetAlpha(entry.isDisabled and 0.55 or 1)
end

function Book.CreateEntry(parent, iconTexture)
	local entry = CreateFrame("Button", nil, parent)
	entry:SetHeight(Book.ENTRY_HEIGHT)

	entry.backplate = entry:CreateTexture(nil, "BACKGROUND")
	entry.backplate:SetPoint("TOPLEFT", -14, 4)
	entry.backplate:SetPoint("BOTTOMRIGHT", 10, -8)
	Book.SetArt(entry.backplate, "spellbook-item-backplate", Book.FONT_COLOR.r, Book.FONT_COLOR.g, Book.FONT_COLOR.b, 0.12)

	local iconFrame = CreateFrame("Frame", nil, entry)
	iconFrame:SetSize(40, 40)
	iconFrame:SetPoint("LEFT", 4, 0)

	entry.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	entry.icon:SetSize(36, 36)
	entry.icon:SetPoint("CENTER")
	entry.icon:SetTexture(iconTexture)
	if Book.GetAtlas("spellbook-item-spellicon-mask") then
		local mask = iconFrame:CreateMaskTexture()
		mask:SetAtlas("spellbook-item-spellicon-mask")
		mask:SetAllPoints(entry.icon)
		entry.icon:AddMaskTexture(mask)
	end

	if Book.GetAtlas("spellbook-item-iconframe") then
		local border = iconFrame:CreateTexture(nil, "OVERLAY", nil, 1)
		border:SetAtlas("spellbook-item-iconframe")
		border:SetPoint("TOPLEFT", -11, 1)
		border:SetPoint("BOTTOMRIGHT", 1, -7)
	end

	entry.iconHighlight = iconFrame:CreateTexture(nil, "OVERLAY", nil, 2)
	entry.iconHighlight:SetAllPoints()
	entry.iconHighlight:SetBlendMode("ADD")
	Book.SetArt(entry.iconHighlight, "spellbook-item-iconframe-hover", 1, 1, 1, 0.3)

	entry.name = Book.CreateText(entry, Book.NAME_FONT)
	entry.name:SetPoint("BOTTOMLEFT", iconFrame, "RIGHT", 10, 1)
	entry.name:SetPoint("RIGHT")
	entry.name:SetWordWrap(false)

	entry.sub = Book.CreateText(entry, Book.SMALL_FONT)
	entry.sub:SetPoint("TOPLEFT", entry.name, "BOTTOMLEFT", 0, -2)
	entry.sub:SetPoint("RIGHT")
	entry.sub:SetWordWrap(false)

	entry:HookScript("OnEnter", Book.UpdateEntry)
	entry:HookScript("OnLeave", Book.UpdateEntry)
	return entry
end

---------------------------------------------------------------------------
-- "Page 1/2" with arrows in a page's bottom corner, as in the spellbook
---------------------------------------------------------------------------

-- onTurn(delta) is called with -1 or 1; call pager:Update(current, total) after refreshing
function Book.CreatePager(page, onTurn)
	local pager = CreateFrame("Frame", nil, page)
	pager:SetSize(1, 32)
	pager:SetPoint("BOTTOMRIGHT", -Book.PAGE_MARGIN, 34)

	local function Arrow(kind)
		local button = CreateFrame("Button", nil, pager)
		button:SetSize(32, 32)
		button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Up")
		button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Down")
		button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Disabled")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		return button
	end

	local nextButton = Arrow("Next")
	nextButton:SetPoint("RIGHT")
	local prevButton = Arrow("Prev")
	prevButton:SetPoint("RIGHT", nextButton, "LEFT", -4, 0)
	local text = Book.CreateText(pager, Book.SMALL_FONT)
	text:SetPoint("RIGHT", prevButton, "LEFT", -8, 0)

	local function Turn(delta)
		onTurn(delta)
		PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
	end
	prevButton:SetScript("OnClick", function() Turn(-1) end)
	nextButton:SetScript("OnClick", function() Turn(1) end)

	function pager:Update(current, total)
		self.current, self.total = current, total
		text:SetText(("Page %d/%d"):format(current, total))
		prevButton:SetEnabled(current > 1)
		nextButton:SetEnabled(current < total)
	end

	-- Mouse wheel over area turns pages too
	function pager:EnableWheel(area)
		area:EnableMouseWheel(true)
		area:SetScript("OnMouseWheel", function(_, delta)
			if (delta > 0 and self.current > 1) or (delta < 0 and self.current < self.total) then
				Turn(-delta)
			end
		end)
	end

	return pager
end
