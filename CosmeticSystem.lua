-- CosmeticSystem.lua - ServerScriptService (ModuleScript)
-- Handles cosmetic purchases, equipping, and visual application.
-- Trails, auras, and name colors applied to player characters.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CosmeticSystem = {}

local PlayerDataManager

-- Cosmetic config lookup
local function getCosmeticConfig(cosmeticId)
	for _, item in ipairs(GameConfig.CosmeticItems) do
		if item.id == cosmeticId then return item end
	end
	return nil
end

-- -- TRAIL VISUALS --

local trailColors = {
	trail_fire    = {Color3.fromRGB(255, 80, 20),  Color3.fromRGB(255, 180, 40)},
	trail_ice     = {Color3.fromRGB(100, 200, 255), Color3.fromRGB(220, 240, 255)},
	trail_rainbow = {Color3.fromRGB(255, 50, 50), Color3.fromRGB(255, 255, 50), Color3.fromRGB(50, 255, 50), Color3.fromRGB(50, 50, 255)},
	trail_shadow  = {Color3.fromRGB(30, 10, 40),   Color3.fromRGB(80, 20, 100)},
	trail_nature  = {Color3.fromRGB(60, 180, 80),  Color3.fromRGB(140, 220, 120)},
	trail_poison  = {Color3.fromRGB(100, 255, 80), Color3.fromRGB(120, 60, 180)},
	trail_void    = {Color3.fromRGB(40, 20, 80),   Color3.fromRGB(140, 60, 200)},
	trail_sunset  = {Color3.fromRGB(255, 100, 60), Color3.fromRGB(255, 80, 180)},
	trail_candy   = {Color3.fromRGB(255, 120, 200), Color3.fromRGB(180, 100, 255)},
	trail_galaxy  = {Color3.fromRGB(40, 60, 140),  Color3.fromRGB(160, 80, 220)},
}

local function applyTrail(character, trailId)
	-- Remove existing trail
	local old = character:FindFirstChild("CosmeticTrail")
	if old then old:Destroy() end
	if not trailId then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local colors = trailColors[trailId]
	if not colors then return end

	local att0 = Instance.new("Attachment")
	att0.Name = "TrailAtt0"; att0.Position = Vector3.new(0, 1, 0)
	att0.Parent = root

	local att1 = Instance.new("Attachment")
	att1.Name = "TrailAtt1"; att1.Position = Vector3.new(0, -1, 0)
	att1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "CosmeticTrail"
	trail.Attachment0 = att0; trail.Attachment1 = att1
	trail.Lifetime = 0.8; trail.MinLength = 0.1
	trail.LightEmission = 0.5; trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)
	})

	-- Color sequence from colors table
	local keypoints = {}
	for i, c in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((i-1) / math.max(1, #colors-1), c))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, colors[1]))
	end
	trail.Color = ColorSequence.new(keypoints)
	trail.Parent = root
end

-- -- AURA VISUALS --

local auraConfigs = {
	aura_flame    = {color = Color3.fromRGB(255, 100, 30),  rate = 25, speed = 4, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)})},
	aura_electric = {color = Color3.fromRGB(80, 180, 255),  rate = 30, speed = 5, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0)})},
	aura_divine   = {color = Color3.fromRGB(255, 220, 100), rate = 20, speed = 3, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 0)})},
	aura_nature   = {color = Color3.fromRGB(80, 200, 100),  rate = 22, speed = 3.5, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0)})},
	aura_void     = {color = Color3.fromRGB(100, 40, 180),  rate = 28, speed = 4, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0)})},
	aura_ice      = {color = Color3.fromRGB(160, 220, 255),  rate = 24, speed = 3, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.65), NumberSequenceKeypoint.new(1, 0)})},
	aura_poison   = {color = Color3.fromRGB(120, 255, 80),  rate = 26, speed = 4.5, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0)})},
	aura_sakura   = {color = Color3.fromRGB(255, 180, 200), rate = 18, speed = 2.5, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(1, 0)})},
	aura_star     = {color = Color3.fromRGB(255, 240, 150), rate = 32, speed = 5, size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0)})},
}

local function applyAura(character, auraId)
	local old = character:FindFirstChild("CosmeticAura")
	if old then old:Destroy() end
	if not auraId then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local config = auraConfigs[auraId]
	if not config then return end

	local att = Instance.new("Attachment")
	att.Name = "CosmeticAura"; att.Parent = root

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = config.rate
	emitter.Speed = NumberRange.new(config.speed * 0.5, config.speed)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Size = config.size
	emitter.Color = ColorSequence.new(config.color)
	emitter.LightEmission = 0.6
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1)
	})
	emitter.Parent = att
end

-- -- NAME COLOR --

local nameColors = {
	name_gold    = Color3.fromRGB(255, 200, 50),
	name_red     = Color3.fromRGB(255, 60, 60),
	name_rainbow = nil, -- special handling
	name_blue    = Color3.fromRGB(80, 160, 255),
	name_green   = Color3.fromRGB(80, 220, 100),
	name_purple  = Color3.fromRGB(180, 100, 255),
	name_cyan    = Color3.fromRGB(60, 220, 255),
	name_pink    = Color3.fromRGB(255, 120, 200),
	name_orange  = Color3.fromRGB(255, 160, 50),
	name_white   = Color3.fromRGB(240, 240, 255),
	name_lime    = Color3.fromRGB(180, 255, 80),
	name_coral   = Color3.fromRGB(255, 120, 100),
}

local function applyNameColor(character, humanoid, nameColorId)
	-- Remove old billboard
	local oldBb = character:FindFirstChild("CosmeticNameTag")
	if oldBb then oldBb:Destroy() end
	if not nameColorId then return end

	local head = character:FindFirstChild("Head")
	if not head then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "CosmeticNameTag"; bb.Size = UDim2.new(0, 150, 0, 24)
	bb.StudsOffset = Vector3.new(0, 2.5, 0); bb.AlwaysOnTop = false
	bb.Adornee = head; bb.Parent = character

	local player = Players:GetPlayerFromCharacter(character)
	local displayName = player and player.DisplayName or "Player"

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
	lbl.Text = displayName; lbl.Font = Enum.Font.GothamBlack; lbl.TextSize = 16
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0); lbl.TextStrokeTransparency = 0.3
	lbl.Parent = bb

	if nameColorId == "name_rainbow" then
		-- Cycle rainbow colors
		task.spawn(function()
			local hue = 0
			while lbl.Parent do
				hue = (hue + 0.5) % 360
				lbl.TextColor3 = Color3.fromHSV(hue / 360, 1, 1)
				RunService.Heartbeat:Wait()
			end
		end)
	else
		local color = nameColors[nameColorId]
		if color then lbl.TextColor3 = color end
	end
end

-- -- APPLY ALL COSMETICS FOR PLAYER --

local function applyAllCosmetics(player)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")

	local cosmetics = PlayerDataManager.GetCosmetics(player)
	if not cosmetics or not cosmetics.equipped then return end

	applyTrail(character, cosmetics.equipped.trail)
	applyAura(character, cosmetics.equipped.aura)
	if humanoid then
		applyNameColor(character, humanoid, cosmetics.equipped.nameColor)
	end
end

-- -- INIT --

function CosmeticSystem.Init(pdm)
	PlayerDataManager = pdm

	local events = ReplicatedStorage:FindFirstChild("Events")
	local buyCosmeticEvt = events and events:FindFirstChild("BuyCosmetic")
	local equipCosmeticEvt = events and events:FindFirstChild("EquipCosmetic")

	-- #region agent log
	pcall(function()
		HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
			location = "CosmeticSystem.lua:Init", message = "CosmeticSystem binding",
			data = { hasEvents = events ~= nil, hasBuyCosmeticEvt = buyCosmeticEvt ~= nil },
			timestamp = math.floor(tick() * 1000), hypothesisId = "H3"
		}))
	end)
	-- #endregionkhj

	if buyCosmeticEvt then
		buyCosmeticEvt.OnServerInvoke = function(player, cosmeticId, currency)
			-- #region agent log
			pcall(function()
				HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
					location = "CosmeticSystem.lua:BuyCosmeticInvoke", message = "BuyCosmetic invoked",
					data = { playerName = player and player.Name, cosmeticId = cosmeticId, currency = currency },
					timestamp = math.floor(tick() * 1000), hypothesisId = "H3"
				}))
			end)
			-- #endregion
			local config = getCosmeticConfig(cosmeticId)
			if not config then return false, "Invalid cosmetic" end

			if PlayerDataManager.OwnsCosmetic(player, cosmeticId) then
				return false, "Already owned!"
			end

			-- Charge
			if currency == "coins" then
				if config.coinCost <= 0 then return false, "Not for coins" end
				local d = PlayerDataManager.GetData(player)
				if not d or d.coins < config.coinCost then return false, "Not enough coins!" end
				PlayerDataManager.SpendCoins(player, config.coinCost)
			elseif currency == "gems" then
				if config.gemCost <= 0 then return false, "Not for gems" end
				if not PlayerDataManager.SpendGems(player, config.gemCost) then
					return false, "Not enough gems!"
				end
			else
				return false, "Invalid currency"
			end

			PlayerDataManager.PurchaseCosmetic(player, cosmeticId)

			-- Auto-equip on purchase
			PlayerDataManager.EquipCosmetic(player, config.slot, cosmeticId)
			applyAllCosmetics(player)

			-- Update coins
			local d = PlayerDataManager.GetData(player)
			local coinsEvt = events and events:FindFirstChild("CoinsUpdate")
			if coinsEvt and d then coinsEvt:FireClient(player, d.coins) end

			print("[Cosmetic] " .. player.Name .. " bought " .. cosmeticId)
			-- #region agent log
			pcall(function()
				HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
					location = "CosmeticSystem.lua:BuyCosmeticReturn", message = "BuyCosmetic return success",
					data = { cosmeticId = cosmeticId }, timestamp = math.floor(tick() * 1000), hypothesisId = "H4"
				}))
			end)
			-- #endregion
			return true, "Purchased!"
		end
		-- Log when we return false (so we can see rejections)
		buyCosmeticEvt.OnServerInvoke = (function(original)
			return function(player, cosmeticId, currency)
				local ok, msg = original(player, cosmeticId, currency)
				if not ok then
					pcall(function()
						HttpService:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", HttpService:JSONEncode({
							location = "CosmeticSystem.lua:BuyCosmeticReject", message = "BuyCosmetic return false",
							data = { cosmeticId = cosmeticId, msg = tostring(msg) }, timestamp = math.floor(tick() * 1000), hypothesisId = "H4"
						}))
					end)
				end
				return ok, msg
			end
		end)(buyCosmeticEvt.OnServerInvoke)
	end

	if equipCosmeticEvt then
		equipCosmeticEvt.OnServerInvoke = function(player, slot, cosmeticId)
			if cosmeticId and not PlayerDataManager.OwnsCosmetic(player, cosmeticId) then
				return false, "Not owned"
			end
			PlayerDataManager.EquipCosmetic(player, slot, cosmeticId)
			applyAllCosmetics(player)
			return true, cosmeticId and "Equipped!" or "Unequipped"
		end
	end

	-- Reapply cosmetics on character spawn
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			task.wait(1)
			applyAllCosmetics(p)
		end)
	end)
	-- For players already in
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then task.spawn(function() applyAllCosmetics(p) end) end
		p.CharacterAdded:Connect(function()
			task.wait(1); applyAllCosmetics(p)
		end)
	end

	print("[CosmeticSystem] Initialized - " .. #GameConfig.CosmeticItems .. " cosmetics available")
end

return CosmeticSystem