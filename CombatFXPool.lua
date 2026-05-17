-- CombatFXPool.lua - Server-side pooled combat bolts and damage popups

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CombatFXPool = {}

local initialized = false
local fxFolder
local boltPool = {}
local popupPool = {}
local activeBolts = {}
local activePopups = {}

local DEFAULT_BOLT_SIZE = Vector3.new(1.2, 1.2, 1.2)
local DEFAULT_BOLT_DURATION = 0.2
local DEFAULT_POPUP_STEPS = 12
local DEFAULT_POPUP_RISE = 0.1

local function getFxFolder()
	if fxFolder and fxFolder.Parent then return fxFolder end
	fxFolder = Workspace:FindFirstChild("CombatFX")
	if not fxFolder then
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "CombatFX"
		fxFolder.Parent = Workspace
	end
	return fxFolder
end

local function buildBolt()
	local part = Instance.new("Part")
	part.Name = "PooledBolt"
	part.Shape = Enum.PartType.Ball
	part.Size = DEFAULT_BOLT_SIZE
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = getFxFolder()

	local light = Instance.new("PointLight")
	light.Name = "BoltLight"
	light.Brightness = 2
	light.Range = 8
	light.Parent = part
	return part
end

local function buildPopup()
	local anchor = Instance.new("Part")
	anchor.Name = "PooledDamagePopup"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = getFxFolder()

	local bb = Instance.new("BillboardGui")
	bb.Name = "DamageBillboard"
	bb.Size = UDim2.new(0, 60, 0, 24)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = anchor
	bb.Parent = anchor

	local lbl = Instance.new("TextLabel")
	lbl.Name = "DamageLabel"
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 14
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = bb

	return anchor
end

local function acquireBolt()
	local part = table.remove(boltPool)
	if part and part.Parent then return part end
	return buildBolt()
end

local function releaseBolt(part)
	if not part then return end
	part.Transparency = 1
	part.Parent = getFxFolder()
	activeBolts[part] = nil
	boltPool[#boltPool + 1] = part
end

local function acquirePopup()
	local part = table.remove(popupPool)
	if part and part.Parent then return part end
	return buildPopup()
end

local function releasePopup(part)
	if not part then return end
	part.Parent = getFxFolder()
	activePopups[part] = nil
	popupPool[#popupPool + 1] = part
end

function CombatFXPool.Prewarm(boltCount, popupCount)
	local bolts = math.max(0, tonumber(boltCount) or tonumber(GameConfig.CombatFXPrewarmBolts) or 24)
	local popups = math.max(0, tonumber(popupCount) or tonumber(GameConfig.CombatFXPrewarmPopups) or 20)
	for _ = #boltPool + 1, bolts do
		boltPool[#boltPool + 1] = buildBolt()
	end
	for _ = #popupPool + 1, popups do
		popupPool[#popupPool + 1] = buildPopup()
	end
end

function CombatFXPool.FireBolt(fromPos, toPos, color, duration, onHit, size)
	if not initialized then CombatFXPool.Init() end
	local bolt = acquireBolt()
	bolt.Size = size or DEFAULT_BOLT_SIZE
	bolt.Color = color or Color3.fromRGB(255, 255, 255)
	bolt.Position = fromPos
	bolt.Transparency = 0
	local light = bolt:FindFirstChild("BoltLight")
	if light and light:IsA("PointLight") then
		light.Color = bolt.Color
	end
	activeBolts[bolt] = {
		fromPos = fromPos,
		toPos = toPos,
		startAt = os.clock(),
		duration = math.max(0.05, tonumber(duration) or DEFAULT_BOLT_DURATION),
		onHit = onHit,
	}
end

function CombatFXPool.ShowDamage(position, damage, color)
	if not initialized then CombatFXPool.Init() end
	local popup = acquirePopup()
	local lbl = popup:FindFirstChild("DamageBillboard") and popup.DamageBillboard:FindFirstChild("DamageLabel")
	if not lbl then
		releasePopup(popup)
		return
	end
	lbl.Text = "-" .. tostring(math.floor(tonumber(damage) or 0))
	lbl.TextColor3 = color or Color3.fromRGB(220, 60, 70)
	lbl.TextTransparency = 0
	lbl.TextStrokeTransparency = 0.3
	popup.Position = position + Vector3.new(0, 2, 0)
	activePopups[popup] = {
		step = 0,
		steps = math.max(4, tonumber(GameConfig.CombatFXPopupSteps) or DEFAULT_POPUP_STEPS),
		rise = tonumber(GameConfig.CombatFXPopupRisePerStep) or DEFAULT_POPUP_RISE,
	}
end

function CombatFXPool.Init()
	if initialized then return end
	initialized = true
	getFxFolder()
	CombatFXPool.Prewarm()

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for part, state in pairs(activeBolts) do
			local alpha = math.clamp((now - state.startAt) / state.duration, 0, 1)
			part.Position = state.fromPos:Lerp(state.toPos, alpha)
			if alpha >= 1 then
				if state.onHit then
					pcall(state.onHit)
				end
				releaseBolt(part)
			end
		end

		for part, state in pairs(activePopups) do
			local lbl = part:FindFirstChild("DamageBillboard") and part.DamageBillboard:FindFirstChild("DamageLabel")
			if not lbl then
				releasePopup(part)
				continue
			end
			state.step += 1
			part.Position = part.Position + Vector3.new(0, state.rise, 0)
			local alpha = state.step / state.steps
			lbl.TextTransparency = alpha
			lbl.TextStrokeTransparency = 0.3 + alpha * 0.7
			if state.step >= state.steps then
				releasePopup(part)
			end
		end
	end)
end

return CombatFXPool
