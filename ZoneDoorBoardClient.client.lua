-- ZoneDoorBoardClient.client.lua
-- World tag on each ZoneDoor + modal: first exterior gate — 4 inner boss Legendaries; further gates — Arena Pass from latest unlocked biome's Gym.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
if GameConfig.ZoneDoorsDisabled == true then
	return
end
local CreatureData = require(ReplicatedStorage.Modules:WaitForChild("CreatureData"))
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local Events = ReplicatedStorage:WaitForChild("Events", 20)
if not Events then return end

local getInventory = Events:WaitForChild("GetInventory", 60)
local spendLegendariesForZoneDoor = Events:FindFirstChild("SpendLegendariesForZoneDoor")
local unlockDoorWithKey = Events:FindFirstChild("UnlockDoorWithKey")
local sigilEarned = Events:FindFirstChild("SigilEarned")
local ZONE_IDS = GameConfig.ZoneDoorZoneIds or { "Ocean", "Desert", "Electric", "Cave" }
local GYM_NAMES = GameConfig.ZoneDoorGymNames or {}

local INFO = GameConfig.ZoneDoorInfoBoard or {}
local TAG = GameConfig.ZoneDoorTag or {}

local ZONE_TITLES = INFO.ZoneTitles or {}
local ELEMENTAL_ELEMENTS = GameConfig.ElementalBossElements or { "Fire", "Ice", "Wind", "Earth" }
local SLOT_ELEMENT_ORDER = { "Fire", "Ice", "Wind", "Earth" }

local tagsByPart = {}
local attrHooked = setmetatable({}, { __mode = "k" })

local cacheTime = 0
local cacheData = nil
local CACHE_TTL = 2

local COL = {
	bg = Color3.fromRGB(12, 14, 28),
	bgDeep = Color3.fromRGB(8, 10, 20),
	card = Color3.fromRGB(24, 28, 44),
	cardHi = Color3.fromRGB(32, 38, 58),
	stroke = Color3.fromRGB(70, 75, 110),
	gold = Color3.fromRGB(255, 200, 90),
	text = Color3.fromRGB(245, 245, 252),
	textSec = Color3.fromRGB(165, 175, 205),
	textMut = Color3.fromRGB(130, 138, 168),
	ok = Color3.fromRGB(72, 195, 130),
	okDeep = Color3.fromRGB(28, 110, 72),
	element = {
		Fire = Color3.fromRGB(255, 115, 70),
		Ice = Color3.fromRGB(120, 210, 255),
		Wind = Color3.fromRGB(120, 255, 185),
		Earth = Color3.fromRGB(200, 155, 95),
		Shadow = Color3.fromRGB(150, 110, 210),
		Lightning = Color3.fromRGB(255, 220, 90),
		Water = Color3.fromRGB(70, 165, 255),
		Poison = Color3.fromRGB(140, 230, 120),
	},
}

local function truthy(v)
	return v == true or v == "true"
end

local function zoneDisplayName(zoneId)
	return ZONE_TITLES[zoneId] or zoneId
end

local function getLastUnlockedExteriorZoneFromData(data)
	if not data or not data.doorsUnlocked then
		return nil
	end
	local last = nil
	for _, zid in ipairs(ZONE_IDS) do
		if truthy(data.doorsUnlocked[zid]) then
			last = zid
		end
	end
	return last
end

local function gymNameForZone(zoneId)
	if not zoneId then
		return "Gym"
	end
	local n = GYM_NAMES[zoneId]
	if type(n) == "string" and #n > 0 then
		return n
	end
	return zoneDisplayName(zoneId) .. " Gym"
end

local function getRequiredBossIdSet()
	local set = {}
	for _, el in ipairs(ELEMENTAL_ELEMENTS) do
		local bid = CreatureData.GetBossCreatureId(el, false)
		if bid then
			set[bid] = true
		end
	end
	return set
end

-- Slot i matches SLOT_ELEMENT_ORDER[i] (Fire, Ice, Wind, Earth). Place by creature element, not fill order.
local function slotIndexForGateElement(element)
	if type(element) ~= "string" then
		return nil
	end
	for i, el in ipairs(SLOT_ELEMENT_ORDER) do
		if el == element then
			return i
		end
	end
	return nil
end

-- Inventory uids may be numbers or strings from replication; always key/compare as string.
local function uidKey(uid)
	if uid == nil or uid == "" then
		return nil
	end
	return tostring(uid)
end

local function fetchInventory(force)
	local now = tick()
	if not force and cacheData and (now - cacheTime) < CACHE_TTL then
		return cacheData
	end
	cacheTime = now
	if not getInventory or not getInventory:IsA("RemoteFunction") then
		return nil
	end
	local ok, data = pcall(function()
		return getInventory:InvokeServer()
	end)
	if ok and type(data) == "table" then
		cacheData = data
		return data
	end
	return cacheData
end

local function staticBriefingText()
	local lines = INFO.Lines
	if type(lines) ~= "table" or #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n\n")
end

local function buildModalLoreText()
	local hint = GameConfig.ZoneDoorModalSigilsHint
	if type(hint) == "string" and #hint > 0 then
		return hint
	end
	return staticBriefingText()
end

local function buildModalGateText()
	local lines = GameConfig.ZoneDoorModalGateLines
	if type(lines) ~= "table" or #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n\n")
end

-- Tagline + features + gym (intro / outpost / progression blurb stay out of the modal).
local function buildZonePitchText(zoneId)
	local pitch = GameConfig.ZoneDoorZonePitch and GameConfig.ZoneDoorZonePitch[zoneId]
	if type(pitch) ~= "table" then
		return ""
	end
	local parts = {}
	local tag = type(pitch.tagline) == "string" and pitch.tagline or ""
	if tag ~= "" then
		table.insert(parts, string.format("%s — %s", zoneDisplayName(zoneId), tag))
	end
	if type(pitch.features) == "string" and pitch.features ~= "" then
		table.insert(parts, pitch.features)
	end
	if type(pitch.gym) == "string" and pitch.gym ~= "" then
		table.insert(parts, pitch.gym)
	end
	return table.concat(parts, "\n\n")
end

local function zoneTagline(zoneId)
	local pitch = GameConfig.ZoneDoorZonePitch and GameConfig.ZoneDoorZonePitch[zoneId]
	if type(pitch) == "table" and type(pitch.tagline) == "string" and pitch.tagline ~= "" then
		return pitch.tagline
	end
	return type(TAG.Subtitle) == "string" and TAG.Subtitle or "Interact to open gate"
end

local function colorForElement(el)
	return COL.element[el] or COL.gold
end

local headerAccentGrad
local panelStrokeRef
local acceptGrad
local panelPadRef
local modalUIScale
local flavorLbl
local gateBodyLbl
local zonePitchLbl
local elementStripFrame

local function applyZoneAccent(zoneId)
	local acc = GameConfig.ZoneDoorGateAccent and GameConfig.ZoneDoorGateAccent[zoneId]
	local top, bot = COL.gold, Color3.fromRGB(80, 60, 20)
	if type(acc) == "table" and acc.top and acc.bottom then
		top, bot = acc.top, acc.bottom
	end
	if headerAccentGrad then
		headerAccentGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, top),
			ColorSequenceKeypoint.new(1, bot),
		})
	end
	if panelStrokeRef then
		panelStrokeRef.Color = top
	end
	if acceptGrad then
		acceptGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, COL.ok),
			ColorSequenceKeypoint.new(1, COL.okDeep),
		})
	end
end

local function destroyTagForPart(part)
	local bb = tagsByPart[part]
	if bb and bb.Parent then
		bb:Destroy()
	end
	local legacy = part:FindFirstChild("ZoneDoorTag")
	if legacy and legacy:IsA("BillboardGui") then
		legacy:Destroy()
	end
	tagsByPart[part] = nil
end

local function computeTagStudsOffset(part)
	if TAG.UseBottomWorldAnchor ~= false then
		local doorH = part.Size.Y
		local rise = tonumber(TAG.HeightAboveDoorBottomStuds) or 8
		local bottomWorld = part.CFrame:PointToWorldSpace(Vector3.new(0, -doorH / 2, 0))
		local targetWorld = bottomWorld + Vector3.new(0, rise, 0)
		return true, targetWorld - part.Position
	end
	local worldSpace = TAG.StudsOffsetWorldSpace == true
	local off = type(TAG.StudsOffset) == "Vector3" and TAG.StudsOffset or Vector3.new(0, -20, 0)
	return worldSpace, off
end

local function applyTagLayout(bb, part)
	local ws, off = computeTagStudsOffset(part)
	bb.StudsOffsetWorldSpace = ws
	bb.StudsOffset = off
	bb.MaxDistance = tonumber(TAG.MaxDistance) or 160
	local w = tonumber(TAG.WidthPx) or 240
	local h = tonumber(TAG.HeightPx) or 58
	bb.Size = UDim2.fromOffset(w, h)
end

local function updateTagText(card, zoneId)
	if not card then
		return
	end
	local titleTpl = type(TAG.TitleTemplate) == "string" and TAG.TitleTemplate or "%s — Zone gate"
	local t = card:FindFirstChild("Title")
	if t and t:IsA("TextLabel") then
		t.Text = string.format(titleTpl, zoneDisplayName(zoneId))
	end
	local s = card:FindFirstChild("Subtitle")
	if s and s:IsA("TextLabel") then
		s.Text = zoneTagline(zoneId)
	end
end

local function createOrRefreshTag(part, zoneId)
	if TAG.Enabled == false then
		destroyTagForPart(part)
		return
	end

	local existing = part:FindFirstChild("ZoneDoorTag")
	if existing and existing:IsA("BillboardGui") then
		applyTagLayout(existing, part)
		updateTagText(existing:FindFirstChild("Card"), zoneId)
		tagsByPart[part] = existing
		return
	end

	local w = tonumber(TAG.WidthPx) or 240
	local h = tonumber(TAG.HeightPx) or 58
	local bb = Instance.new("BillboardGui")
	bb.Name = "ZoneDoorTag"
	bb.Adornee = part
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(w, h)
	applyTagLayout(bb, part)
	bb.LightInfluence = 0
	bb.ResetOnSpawn = false
	bb.Parent = part

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = COL.card
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = COL.gold
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = card

	local titleTpl = type(TAG.TitleTemplate) == "string" and TAG.TitleTemplate or "%s — Zone gate"
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.TextColor3 = COL.gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = string.format(titleTpl, zoneDisplayName(zoneId))
	title.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Size = UDim2.new(1, -16, 0, 18)
	sub.Position = UDim2.new(0, 8, 0, 30)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 11
	sub.TextColor3 = COL.textSec
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Text = zoneTagline(zoneId)
	sub.Parent = card

	tagsByPart[part] = bb
	updateTagText(card, zoneId)
end

-- ProximityPrompt is parented to ZoneDoorPromptAnchor (see ZoneDoorSystem). Track anchors and move them to the
-- surface point closest to the local player so the bubble sits on the near face of wide doors.
local trackedZoneDoorPromptAnchors = {}

local function registerZoneDoorPromptAnchor(att)
	if not att or not att:IsA("Attachment") or att.Name ~= "ZoneDoorPromptAnchor" then
		return
	end
	local part = att.Parent
	if not part or not part:IsA("BasePart") then
		return
	end
	local zid = part:GetAttribute("ZoneDoorZoneId")
	if type(zid) ~= "string" or zid == "" then
		return
	end
	if trackedZoneDoorPromptAnchors[att] then
		return
	end
	trackedZoneDoorPromptAnchors[att] = true
end

local function unregisterZoneDoorPromptAnchor(att)
	trackedZoneDoorPromptAnchors[att] = nil
end

local function tryRegisterZoneDoorPromptAnchorInst(inst)
	if not inst:IsA("Attachment") or inst.Name ~= "ZoneDoorPromptAnchor" then
		return
	end
	registerZoneDoorPromptAnchor(inst)
end

local function updateZoneDoorPromptAnchorsToClosest()
	if GameConfig.ZoneDoorPromptTrackClosestToPlayer == false then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local pPos = hrp.Position
	for att in pairs(trackedZoneDoorPromptAnchors) do
		if not att.Parent then
			unregisterZoneDoorPromptAnchor(att)
		else
			local part = att.Parent
			if not part:IsA("BasePart") then
				unregisterZoneDoorPromptAnchor(att)
			else
				local zid = part:GetAttribute("ZoneDoorZoneId")
				if type(zid) ~= "string" or zid == "" then
					unregisterZoneDoorPromptAnchor(att)
				else
					local prompt = att:FindFirstChild("ZoneDoorPrompt")
					local maxDist = 80
					if prompt and prompt:IsA("ProximityPrompt") then
						maxDist = prompt.MaxActivationDistance + 8
					end
					if (pPos - part.Position).Magnitude <= maxDist + part.Size.Magnitude * 0.5 then
						local okSurf, surfWorld = pcall(function()
							return part:GetClosestPointOnSurface(pPos)
						end)
						if okSurf and typeof(surfWorld) == "Vector3" then
							att.Position = part.CFrame:PointToObjectSpace(surfWorld)
						end
					end
				end
			end
		end
	end
end

RunService.RenderStepped:Connect(updateZoneDoorPromptAnchorsToClosest)

local function tryRegisterZoneDoorPart(inst)
	if not inst:IsA("BasePart") then
		return
	end
	if not attrHooked[inst] then
		attrHooked[inst] = true
		inst:GetAttributeChangedSignal("ZoneDoorZoneId"):Connect(function()
			tryRegisterZoneDoorPart(inst)
		end)
	end
	local zid = inst:GetAttribute("ZoneDoorZoneId")
	if type(zid) ~= "string" or zid == "" then
		return
	end
	if TAG.Enabled == false then
		destroyTagForPart(inst)
		return
	end
	createOrRefreshTag(inst, zid)
	local att = inst:FindFirstChild("ZoneDoorPromptAnchor")
	if att and att:IsA("Attachment") then
		registerZoneDoorPromptAnchor(att)
	end
end

-- ── Modal (responsive + Sigils lore + elemental theming) ────────────────────
local modalGui = Instance.new("ScreenGui")
modalGui.Name = "ZoneDoorBriefingModal"
modalGui.ResetOnSpawn = false
modalGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
modalGui.DisplayOrder = 62
modalGui.IgnoreGuiInset = false
modalGui.Enabled = false
modalGui.Parent = playerGui

local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Size = UDim2.fromScale(1, 1)
dimmer.BackgroundColor3 = Color3.new(0, 0, 0)
dimmer.BackgroundTransparency = 0.5
dimmer.BorderSizePixel = 0
dimmer.Text = ""
dimmer.AutoButtonColor = false
dimmer.Parent = modalGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.92, 0, 0.82, 0)
panel.BackgroundColor3 = COL.bg
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = modalGui

modalUIScale = Instance.new("UIScale")
modalUIScale.Parent = panel

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COL.gold
panelStroke.Thickness = 2
panelStroke.Transparency = 0.25
panelStroke.Parent = panel
panelStrokeRef = panelStroke

panelPadRef = Instance.new("UIPadding")
panelPadRef.PaddingLeft = UDim.new(0, 12)
panelPadRef.PaddingRight = UDim.new(0, 12)
panelPadRef.PaddingTop = UDim.new(0, 0)
panelPadRef.PaddingBottom = UDim.new(0, 0)
panelPadRef.Parent = panel

local headerAccent = Instance.new("Frame")
headerAccent.Name = "HeaderAccent"
headerAccent.Size = UDim2.new(1, 0, 0, 5)
headerAccent.Position = UDim2.new(0, 0, 0, 0)
headerAccent.BorderSizePixel = 0
headerAccent.BackgroundColor3 = COL.gold
headerAccent.Parent = panel
headerAccentGrad = Instance.new("UIGradient")
headerAccentGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 170, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(25, 55, 110)),
})
headerAccentGrad.Parent = headerAccent

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 52)
header.Position = UDim2.new(0, 0, 0, 5)
header.BackgroundTransparency = 1
header.Parent = panel

local modalTitle = Instance.new("TextLabel")
modalTitle.Name = "Title"
modalTitle.Size = UDim2.new(1, -88, 1, 0)
modalTitle.Position = UDim2.new(0, 12, 0, 0)
modalTitle.BackgroundTransparency = 1
modalTitle.Font = Enum.Font.GothamBold
modalTitle.TextSize = 19
modalTitle.TextColor3 = COL.text
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.TextWrapped = true
modalTitle.TextYAlignment = Enum.TextYAlignment.Center
modalTitle.Text = "Zone gate"
modalTitle.Parent = header
local applyZoneDoorTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(modalTitle, {
	Position = UDim2.new(0, 12, 0, 0),
	Size = UDim2.new(1, -88, 1, 0),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.new(0, 72, 0, 34)
closeBtn.Position = UDim2.new(1, -78, 0.5, -17)
closeBtn.BackgroundColor3 = COL.cardHi
closeBtn.TextColor3 = COL.text
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Text = "Close"
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
local closeStr = Instance.new("UIStroke")
closeStr.Color = COL.stroke
closeStr.Thickness = 1
closeStr.Transparency = 0.5
closeStr.Parent = closeBtn

local bodyScroll = Instance.new("ScrollingFrame")
bodyScroll.Name = "BodyScroll"
bodyScroll.Position = UDim2.new(0, 0, 0, 58)
bodyScroll.Size = UDim2.new(1, 0, 1, -118)
bodyScroll.BackgroundColor3 = COL.bgDeep
bodyScroll.BackgroundTransparency = 0.35
bodyScroll.BorderSizePixel = 0
bodyScroll.ScrollBarThickness = 5
bodyScroll.ScrollBarImageColor3 = COL.gold
bodyScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
bodyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
bodyScroll.ScrollingDirection = Enum.ScrollingDirection.Y
bodyScroll.Parent = panel
Instance.new("UICorner", bodyScroll).CornerRadius = UDim.new(0, 10)

local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingLeft = UDim.new(0, 10)
bodyPad.PaddingRight = UDim.new(0, 10)
bodyPad.PaddingTop = UDim.new(0, 10)
bodyPad.PaddingBottom = UDim.new(0, 12)
bodyPad.Parent = bodyScroll

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Padding = UDim.new(0, 10)
bodyLayout.Parent = bodyScroll

flavorLbl = Instance.new("TextLabel")
flavorLbl.Name = "SigilsFlavor"
flavorLbl.Size = UDim2.new(1, -4, 0, 0)
flavorLbl.BackgroundTransparency = 1
flavorLbl.Font = Enum.Font.GothamMedium
flavorLbl.TextSize = 11
flavorLbl.TextColor3 = COL.textMut
flavorLbl.TextXAlignment = Enum.TextXAlignment.Left
flavorLbl.TextWrapped = true
flavorLbl.AutomaticSize = Enum.AutomaticSize.Y
flavorLbl.Text = ""
flavorLbl.LayoutOrder = 1
flavorLbl.Parent = bodyScroll

gateBodyLbl = Instance.new("TextLabel")
gateBodyLbl.Name = "GateBody"
gateBodyLbl.Size = UDim2.new(1, -4, 0, 0)
gateBodyLbl.BackgroundTransparency = 1
gateBodyLbl.Font = Enum.Font.GothamMedium
gateBodyLbl.TextSize = 13
gateBodyLbl.TextColor3 = COL.textSec
gateBodyLbl.TextXAlignment = Enum.TextXAlignment.Left
gateBodyLbl.TextWrapped = true
gateBodyLbl.AutomaticSize = Enum.AutomaticSize.Y
gateBodyLbl.Text = ""
gateBodyLbl.LayoutOrder = 2
gateBodyLbl.Parent = bodyScroll

zonePitchLbl = Instance.new("TextLabel")
zonePitchLbl.Name = "ZonePitch"
zonePitchLbl.Size = UDim2.new(1, -4, 0, 0)
zonePitchLbl.BackgroundColor3 = COL.cardHi
zonePitchLbl.BackgroundTransparency = 0.65
zonePitchLbl.BorderSizePixel = 0
zonePitchLbl.Font = Enum.Font.GothamMedium
zonePitchLbl.TextSize = 12
zonePitchLbl.TextColor3 = COL.text
zonePitchLbl.TextXAlignment = Enum.TextXAlignment.Left
zonePitchLbl.TextWrapped = true
zonePitchLbl.AutomaticSize = Enum.AutomaticSize.Y
zonePitchLbl.Text = ""
zonePitchLbl.LayoutOrder = 3
zonePitchLbl.Parent = bodyScroll
Instance.new("UICorner", zonePitchLbl).CornerRadius = UDim.new(0, 10)
local zonePitchPad = Instance.new("UIPadding")
zonePitchPad.PaddingLeft = UDim.new(0, 10)
zonePitchPad.PaddingRight = UDim.new(0, 10)
zonePitchPad.PaddingTop = UDim.new(0, 10)
zonePitchPad.PaddingBottom = UDim.new(0, 10)
zonePitchPad.Parent = zonePitchLbl
local zonePitchStroke = Instance.new("UIStroke")
zonePitchStroke.Color = COL.gold
zonePitchStroke.Thickness = 1
zonePitchStroke.Transparency = 0.55
zonePitchStroke.Parent = zonePitchLbl

local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.Size = UDim2.new(1, 0, 0, 2)
divider.BackgroundColor3 = COL.stroke
divider.BackgroundTransparency = 0.4
divider.BorderSizePixel = 0
divider.LayoutOrder = 4
divider.Parent = bodyScroll
Instance.new("UICorner", divider).CornerRadius = UDim.new(1, 0)

elementStripFrame = Instance.new("Frame")
elementStripFrame.Name = "ElementStrip"
elementStripFrame.Size = UDim2.new(1, 0, 0, 30)
elementStripFrame.BackgroundTransparency = 1
elementStripFrame.LayoutOrder = 5
elementStripFrame.Parent = bodyScroll

local stripLayout = Instance.new("UIListLayout")
stripLayout.FillDirection = Enum.FillDirection.Horizontal
stripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
stripLayout.Padding = UDim.new(0, 6)
stripLayout.Parent = elementStripFrame

for _, el in ipairs(SLOT_ELEMENT_ORDER) do
	local chip = Instance.new("Frame")
	chip.Size = UDim2.new(0.23, -5, 1, 0)
	chip.BackgroundColor3 = COL.cardHi
	chip.BackgroundTransparency = 0.15
	chip.BorderSizePixel = 0
	chip.Parent = elementStripFrame
	Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 6)
	local cs = Instance.new("UIStroke")
	cs.Color = colorForElement(el)
	cs.Thickness = 1.5
	cs.Transparency = 0.25
	cs.Parent = chip
	local chipGrad = Instance.new("UIGradient")
	chipGrad.Rotation = 90
	chipGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colorForElement(el)),
		ColorSequenceKeypoint.new(1, COL.bgDeep),
	})
	chipGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.92),
		NumberSequenceKeypoint.new(1, 1),
	})
	chipGrad.Parent = chip
	local chipTxt = Instance.new("TextLabel")
	chipTxt.Size = UDim2.fromScale(1, 1)
	chipTxt.BackgroundTransparency = 1
	chipTxt.Text = el
	chipTxt.Font = Enum.Font.GothamBold
	chipTxt.TextSize = 12
	chipTxt.TextColor3 = colorForElement(el)
	chipTxt.Parent = chip
end

local statusLbl = Instance.new("TextLabel")
statusLbl.Name = "Status"
statusLbl.Size = UDim2.new(1, -4, 0, 0)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.GothamBold
statusLbl.TextSize = 14
statusLbl.TextColor3 = COL.ok
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.TextWrapped = true
statusLbl.AutomaticSize = Enum.AutomaticSize.Y
statusLbl.Text = ""
statusLbl.LayoutOrder = 6
statusLbl.Parent = bodyScroll

local slotsFrame = Instance.new("Frame")
slotsFrame.Name = "Slots"
slotsFrame.Size = UDim2.new(1, 0, 0, 0)
slotsFrame.BackgroundTransparency = 1
slotsFrame.AutomaticSize = Enum.AutomaticSize.Y
slotsFrame.LayoutOrder = 7
slotsFrame.Parent = bodyScroll

local slotsLayout = Instance.new("UIListLayout")
slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotsLayout.Padding = UDim.new(0, 6)
slotsLayout.Parent = slotsFrame

local pickHeader = Instance.new("TextLabel")
pickHeader.Name = "PickHeader"
pickHeader.Size = UDim2.new(1, -4, 0, 0)
pickHeader.BackgroundTransparency = 1
pickHeader.Font = Enum.Font.GothamBold
pickHeader.TextSize = 13
pickHeader.TextColor3 = COL.gold
pickHeader.TextXAlignment = Enum.TextXAlignment.Left
pickHeader.TextWrapped = true
pickHeader.AutomaticSize = Enum.AutomaticSize.Y
pickHeader.Text = "Your legendaries"
pickHeader.LayoutOrder = 8
pickHeader.Parent = bodyScroll

local creatureList = Instance.new("Frame")
creatureList.Name = "CreatureList"
creatureList.Size = UDim2.new(1, 0, 0, 0)
creatureList.BackgroundTransparency = 1
creatureList.AutomaticSize = Enum.AutomaticSize.Y
creatureList.LayoutOrder = 9
creatureList.Parent = bodyScroll

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 5)
listLayout.Parent = creatureList

local currentZoneId = ""
local modalMode = "legendary" -- "legendary" | "arena"
local slots = { nil, nil, nil, nil }
local slotButtons = {}

local acceptBtn = Instance.new("TextButton")
acceptBtn.Name = "Accept"
acceptBtn.AnchorPoint = Vector2.new(0.5, 1)
acceptBtn.Size = UDim2.new(1, -24, 0, 46)
acceptBtn.Position = UDim2.new(0.5, 0, 1, -10)
acceptBtn.BackgroundColor3 = COL.ok
acceptBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
acceptBtn.Font = Enum.Font.GothamBold
acceptBtn.TextSize = 15
acceptBtn.Text = "Open the gate"
acceptBtn.BorderSizePixel = 0
acceptBtn.Visible = false
acceptBtn.AutoButtonColor = true
acceptBtn.Parent = panel
Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 12)
acceptGrad = Instance.new("UIGradient")
acceptGrad.Rotation = 90
acceptGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, COL.ok),
	ColorSequenceKeypoint.new(1, COL.okDeep),
})
acceptGrad.Parent = acceptBtn
local acceptStr = Instance.new("UIStroke")
acceptStr.Color = Color3.fromRGB(40, 100, 65)
acceptStr.Thickness = 1
acceptStr.Transparency = 0.3
acceptStr.Parent = acceptBtn

local function refreshModalLayout()
	local cam = workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 800
	local vh = cam and cam.ViewportSize.Y or 600
	local narrow = vw < 520
	local pad = narrow and 6 or 12
	panelPadRef.PaddingLeft = UDim.new(0, pad)
	panelPadRef.PaddingRight = UDim.new(0, pad)
	if narrow then
		panel.Size = UDim2.new(1, -math.clamp(math.floor(vw * 0.06), 8, 28), 0, math.floor(vh * 0.88))
		modalTitle.TextSize = 15
		closeBtn.Size = UDim2.new(0, 64, 0, 32)
		closeBtn.TextSize = 13
		acceptBtn.TextSize = 14
		bodyPad.PaddingLeft = UDim.new(0, 8)
		bodyPad.PaddingRight = UDim.new(0, 8)
	else
		local maxW = math.min(500, math.floor(vw * 0.9))
		panel.Size = UDim2.new(0, maxW, 0, math.floor(vh * 0.82))
		modalTitle.TextSize = 19
		closeBtn.Size = UDim2.new(0, 72, 0, 34)
		closeBtn.TextSize = 14
		acceptBtn.TextSize = 15
		bodyPad.PaddingLeft = UDim.new(0, 10)
		bodyPad.PaddingRight = UDim.new(0, 10)
	end
	applyZoneDoorTitleLayout()
end

local viewportConn
local function bindViewportResize()
	if viewportConn then
		viewportConn:Disconnect()
		viewportConn = nil
	end
	refreshModalLayout()
	local cam = workspace.CurrentCamera
	if cam then
		viewportConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(refreshModalLayout)
	end
end
bindViewportResize()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewportResize)

local function closeModal()
	modalGui.Enabled = false
end

local function creatureDisplayName(creatureId)
	local c = CreatureData.GetById and CreatureData.GetById(creatureId)
	if c and c.displayName then
		return c.displayName
	end
	return creatureId
end

local openModal
local openModalRefresh
local openModalRefreshArena

local function refreshSlotButtons()
	for _, b in ipairs(slotButtons) do
		if b and b.Parent then
			b:Destroy()
		end
	end
	slotButtons = {}
	for i = 1, 4 do
		local row = Instance.new("TextButton")
		row.Size = UDim2.new(1, 0, 0, 36)
		row.BackgroundColor3 = COL.cardHi
		row.BackgroundTransparency = 0.1
		row.BorderSizePixel = 0
		row.AutoButtonColor = true
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 13
		row.TextColor3 = COL.text
		row.TextXAlignment = Enum.TextXAlignment.Left
		local elName = SLOT_ELEMENT_ORDER[i] or "Fire"
		local uid = slots[i]
		if uid then
			local data = fetchInventory(false)
			local id = ""
			if data and data.inventory then
				for _, e in ipairs(data.inventory) do
					if e and tostring(e.uid) == tostring(uid) then
						id = e.id or ""
						break
					end
				end
			end
			row.Text = "  " .. i .. " · " .. creatureDisplayName(id) .. "  (clear)"
		else
			row.Text = "  " .. i .. " · " .. elName
		end
		row.Parent = slotsFrame
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
		local rs = Instance.new("UIStroke")
		rs.Color = colorForElement(elName)
		rs.Thickness = 1.5
		rs.Transparency = 0.35
		rs.Parent = row
		table.insert(slotButtons, row)
		local idx = i
		row.MouseButton1Click:Connect(function()
			if slots[idx] then
				slots[idx] = nil
				openModalRefresh()
			end
		end)
	end
end

local function clearCreatureList()
	for _, ch in ipairs(creatureList:GetChildren()) do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
end

local function fillCreatureList()
	clearCreatureList()
	local req = getRequiredBossIdSet()
	local data = fetchInventory(true)
	if not data or not data.inventory then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 28)
		empty.BackgroundTransparency = 1
		empty.TextColor3 = COL.textSec
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 13
		empty.Text = "Could not load inventory."
		empty.Parent = creatureList
		return
	end
	-- Must not use ipairs(slots): it stops at the first nil index, so a gap (e.g. Wind empty, Earth filled) would skip later slots.
	local used = {}
	for si = 1, 4 do
		local k = uidKey(slots[si])
		if k then
			used[k] = true
		end
	end
	local any = false
	for _, e in ipairs(data.inventory) do
		if e and e.id and req[e.id] and not used[uidKey(e.uid)] then
			any = true
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, 34)
			row.BackgroundColor3 = COL.cardHi
			row.BackgroundTransparency = 0.12
			row.BorderSizePixel = 0
			local cre = CreatureData.GetById and CreatureData.GetById(e.id)
			local elem = cre and cre.element or "Fire"
			local ec = colorForElement(elem)
			row.Text = "  " .. creatureDisplayName(e.id)
			row.Font = Enum.Font.GothamMedium
			row.TextSize = 13
			row.TextColor3 = COL.text
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Parent = creatureList
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
			local rs = Instance.new("UIStroke")
			rs.Color = ec
			rs.Thickness = 1.5
			rs.Transparency = 0.45
			rs.Parent = row
			local uid = uidKey(e.uid)
			row.MouseButton1Click:Connect(function()
				local cre = CreatureData.GetById and CreatureData.GetById(e.id)
				local elem = cre and cre.element
				local si = slotIndexForGateElement(elem)
				if not si or not uid then
					return
				end
				for j = 1, 4 do
					if uidKey(slots[j]) == uid then
						slots[j] = nil
					end
				end
				slots[si] = uid
				openModalRefresh()
			end)
		end
	end
	if not any then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 28)
		empty.BackgroundTransparency = 1
		empty.TextColor3 = COL.textSec
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 13
		empty.Text = "Need the four inner bosses (Fire, Ice, Wind, Earth) as legendaries in your inventory."
		empty.TextWrapped = true
		empty.AutomaticSize = Enum.AutomaticSize.Y
		empty.Parent = creatureList
	end
end

openModalRefreshArena = function()
	if currentZoneId == "" or modalMode ~= "arena" then
		return
	end
	local data = fetchInventory(true)
	local doors = data and data.doorsUnlocked or {}
	if truthy(doors[currentZoneId]) then
		openModal(currentZoneId)
		return
	end
	local passZone = getLastUnlockedExteriorZoneFromData(data)
	local keys = data and data.zoneKeysFromGyms or {}
	local hasPass = passZone and truthy(keys[passZone])
	local srcName = gymNameForZone(passZone)
	if hasPass then
		statusLbl.TextColor3 = COL.ok
		statusLbl.Text = "You have an Arena Pass from "
			.. srcName
			.. ". Use it to open this gate."
	else
		statusLbl.TextColor3 = COL.textSec
		statusLbl.Text = "Win at "
			.. srcName
			.. " to earn an Arena Pass for the next exterior gate."
	end
	acceptBtn.Visible = hasPass
	acceptBtn.Text = "Use Arena Pass"
	acceptBtn.Active = hasPass
	acceptBtn.AutoButtonColor = hasPass
	acceptBtn.BackgroundTransparency = hasPass and 0 or 0.5
end

openModalRefresh = function()
	if currentZoneId == "" then
		return
	end
	if modalMode == "arena" then
		openModalRefreshArena()
		return
	end
	local data = fetchInventory(true)
	local doors = data and data.doorsUnlocked or {}
	if truthy(doors[currentZoneId]) then
		openModal(currentZoneId)
		return
	end
	refreshSlotButtons()
	fillCreatureList()
	local filled = 0
	for si = 1, 4 do
		if slots[si] then
			filled = filled + 1
		end
	end
	acceptBtn.Active = filled == 4
	acceptBtn.AutoButtonColor = filled == 4
	acceptBtn.BackgroundTransparency = filled == 4 and 0 or 0.5
end

openModal = function(zoneId)
	currentZoneId = zoneId
	modalMode = "legendary"
	slots = { nil, nil, nil, nil }
	local disp = zoneDisplayName(zoneId)
	modalTitle.Text = disp .. " — Zone gate"
	local lore = buildModalLoreText()
	local gateTxt = buildModalGateText()
	local pitchTxt = buildZonePitchText(zoneId)
	flavorLbl.Text = lore
	gateBodyLbl.Text = gateTxt
	flavorLbl.Visible = lore ~= ""
	gateBodyLbl.Visible = gateTxt ~= ""
	if zonePitchLbl then
		zonePitchLbl.Text = pitchTxt
		zonePitchLbl.Visible = pitchTxt ~= ""
	end
	applyZoneAccent(zoneId)
	refreshModalLayout()

	local data = fetchInventory(true)
	local doors = data and data.doorsUnlocked or {}
	local gateOpen = truthy(doors[zoneId])

	if gateOpen then
		statusLbl.TextColor3 = COL.ok
		statusLbl.Text = "Open — walk through when you're ready."
		flavorLbl.Visible = lore ~= ""
		gateBodyLbl.Visible = false
		if zonePitchLbl then
			zonePitchLbl.Visible = pitchTxt ~= ""
		end
		divider.Visible = false
		elementStripFrame.Visible = false
		slotsFrame.Visible = false
		pickHeader.Visible = false
		creatureList.Visible = false
		acceptBtn.Visible = false
	else
		local passZone = getLastUnlockedExteriorZoneFromData(data)
		if passZone ~= nil then
			modalMode = "arena"
			modalTitle.Text = disp .. " — Arena Pass gate"
			local passFlavor = GameConfig.ZoneDoorArenaPassFlavor
			if type(passFlavor) == "string" and #passFlavor > 0 then
				flavorLbl.Text = passFlavor
				flavorLbl.Visible = true
			else
				flavorLbl.Visible = false
			end
			local srcName = gymNameForZone(passZone)
			gateBodyLbl.Text = "Requires an Arena Pass from "
				.. srcName
				.. " (your latest unlocked exterior biome). Each pass opens one more gate."
			gateBodyLbl.Visible = true
			if zonePitchLbl then
				zonePitchLbl.Text = pitchTxt
				zonePitchLbl.Visible = pitchTxt ~= ""
			end
			pickHeader.Visible = false
			divider.Visible = true
			elementStripFrame.Visible = false
			slotsFrame.Visible = false
			creatureList.Visible = false
			acceptBtn.Visible = true
			openModalRefreshArena()
			modalGui.Enabled = true
			return
		end

		statusLbl.TextColor3 = COL.textSec
		statusLbl.Text = "Offer one legendary boss per element — then open the gate."
		flavorLbl.Visible = lore ~= ""
		gateBodyLbl.Visible = gateTxt ~= ""
		if zonePitchLbl then
			zonePitchLbl.Visible = pitchTxt ~= ""
		end
		divider.Visible = true
		elementStripFrame.Visible = true
		slotsFrame.Visible = true
		pickHeader.Visible = true
		pickHeader.Text = "Your legendaries"
		creatureList.Visible = true
		acceptBtn.Visible = true
		acceptBtn.Text = "Open the gate"
		openModalRefresh()
	end

	modalGui.Enabled = true
end

acceptBtn.MouseButton1Click:Connect(function()
	if currentZoneId == "" then
		return
	end
	if modalMode == "arena" then
		if not unlockDoorWithKey or not unlockDoorWithKey:IsA("RemoteFunction") then
			return
		end
		local ok, errMsg = unlockDoorWithKey:InvokeServer(currentZoneId)
		if ok then
			cacheData = nil
			cacheTime = 0
			openModal(currentZoneId)
		else
			statusLbl.TextColor3 = Color3.fromRGB(255, 120, 100)
			statusLbl.Text = tostring(errMsg or "Could not open gate.")
		end
		return
	end
	if not spendLegendariesForZoneDoor or not spendLegendariesForZoneDoor:IsA("RemoteFunction") then
		return
	end
	local uids = {}
	for i = 1, 4 do
		if slots[i] then
			table.insert(uids, slots[i])
		end
	end
	if #uids ~= 4 then
		return
	end
	local success, errMsg = spendLegendariesForZoneDoor:InvokeServer(currentZoneId, uids)
	if success then
		cacheData = nil
		cacheTime = 0
		openModal(currentZoneId)
	else
		statusLbl.TextColor3 = Color3.fromRGB(255, 120, 100)
		statusLbl.Text = tostring(errMsg or "Could not open gate.")
	end
end)

closeBtn.MouseButton1Click:Connect(closeModal)
dimmer.MouseButton1Click:Connect(closeModal)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.Escape and modalGui.Enabled then
		closeModal()
	end
end)

local function getZoneDoorBasePartFromPrompt(prompt)
	local p = prompt.Parent
	if p and p:IsA("Attachment") then
		p = p.Parent
	end
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then
		return
	end
	if prompt.Name ~= "ZoneDoorPrompt" then
		return
	end
	local p = getZoneDoorBasePartFromPrompt(prompt)
	if not p then
		return
	end
	local zid = p:GetAttribute("ZoneDoorZoneId")
	if type(zid) ~= "string" or zid == "" then
		return
	end
	openModal(zid)
end)

for _, d in ipairs(workspace:GetDescendants()) do
	tryRegisterZoneDoorPart(d)
	tryRegisterZoneDoorPromptAnchorInst(d)
end
workspace.DescendantAdded:Connect(function(inst)
	task.defer(function()
		tryRegisterZoneDoorPart(inst)
		tryRegisterZoneDoorPromptAnchorInst(inst)
	end)
end)
workspace.DescendantRemoving:Connect(function(inst)
	if trackedZoneDoorPromptAnchors[inst] then
		unregisterZoneDoorPromptAnchor(inst)
	end
	if inst:IsA("BasePart") and tagsByPart[inst] then
		destroyTagForPart(inst)
	end
end)

if sigilEarned and sigilEarned:IsA("RemoteEvent") then
	sigilEarned.OnClientEvent:Connect(function()
		cacheData = nil
		cacheTime = 0
	end)
end

local gymArenaReward = Events:FindFirstChild("GymArenaReward")
if gymArenaReward and gymArenaReward:IsA("RemoteEvent") then
	gymArenaReward.OnClientEvent:Connect(function()
		cacheData = nil
		cacheTime = 0
		if modalGui.Enabled and currentZoneId ~= "" and modalMode == "arena" then
			openModalRefreshArena()
		end
	end)
end
