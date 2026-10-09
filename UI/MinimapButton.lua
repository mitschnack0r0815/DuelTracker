local _, ns = ...

-- Round button on the minimap edge. Drag to move it around the minimap; the angle and
-- hidden state are saved in DuelTrackerDB.minimap.
local DEFAULT_ANGLE = 160

local button = CreateFrame("Button", "DuelTrackerMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Same textures and offsets as standard minimap buttons
local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexture(ns.ICON)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
icon:SetPoint("TOPLEFT", 7, -6)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function GetMinimapSettings()
	local db = ns.GetDB()
	db.minimap = db.minimap or { angle = DEFAULT_ANGLE }
	return db.minimap
end

local function UpdatePosition()
	local angle = math.rad(GetMinimapSettings().angle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

-- While dragging, follow the cursor around the minimap edge
local function FollowCursor()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	GetMinimapSettings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	UpdatePosition()
end

button:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", FollowCursor)
	GameTooltip:Hide()
end)
button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
end)

button:SetScript("OnClick", function(self, mouseButton)
	if mouseButton == "RightButton" then
		if ns.ToggleTestTab then -- only when the Test tab exists (ns.SHOW_TEST_TAB)
			ns.ToggleTestTab()
		end
	else
		ns.ToggleWindow()
	end
end)

button:SetScript("OnEnter", function(self)
	local wins, losses = ns.GetRecord()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Duel Tracker")
	GameTooltip:AddLine(("%d wins, %d losses"):format(wins, losses), 1, 1, 1)
	GameTooltip:AddLine("Click: Open", 0.7, 0.7, 0.7)
	if ns.ToggleTestTab then
		GameTooltip:AddLine("Right-click: Show or hide the Test tab", 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
	GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

function ns.ToggleMinimapButton()
	local settings = GetMinimapSettings()
	settings.hide = not settings.hide
	button:SetShown(not settings.hide)
	if settings.hide then
		print("Duel Tracker: minimap button hidden. Type /duels minimap to show it again.")
	end
end

-- SavedVariables are only available after login
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	UpdatePosition()
	button:SetShown(not GetMinimapSettings().hide)
end)
