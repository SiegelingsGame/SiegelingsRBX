-- WorldCreatureHP.lua - ServerScriptService (ModuleScript)
-- Tracks HP for world-spawned creatures. When HP reaches 0, sets Fainted attribute.
-- Both PlayerCombatSystem and FavoriteCreatureSystem call DamageCreature here.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local WorldCreatureHP = {}

local WORLD_TAG = "WorldCreature"

-- Track HP per creature model: [model] = { hp, maxHp }
local creatureHP = {}

-- Get or create HP entry for a world creature
local function getHP(model)
	if creatureHP[model] then return creatureHP[model] end

	local creatureId = model:GetAttribute("CreatureId")
	if not creatureId then return nil end

	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local maxHP = info.health or 50
	creatureHP[model] = { hp = maxHP, maxHp = maxHP }
	return creatureHP[model]
end

-- Update the HP bar on a creature's billboard GUI
-- Reuses the HPBar created by CreatureSpawner (no duplicates)
local function updateHPBar(model, hpData)
	local bb = model:FindFirstChild("NameTag")
	if not bb then return end

	-- Use the existing HPBar from CreatureSpawner
	local hpBg = bb:FindFirstChild("HPBar") or bb:FindFirstChild("HPBarBG")
	if not hpBg then return end

	local fill = hpBg:FindFirstChild("Fill")
	if fill then
		local ratio = math.clamp(hpData.hp / hpData.maxHp, 0, 1)
		fill.Size = UDim2.new(ratio, 0, 1, 0)

		-- Color: green > yellow > red
		if ratio > 0.5 then
			fill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
		elseif ratio > 0.25 then
			fill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
		else
			fill.BackgroundColor3 = Color3.fromRGB(255, 60, 50)
		end
	end
end

-- Show floating damage number above creature
local function showDamageNumber(model, damage)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then return end

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 80, 0, 30)
	bb.StudsOffset = Vector3.new(math.random(-2, 2), 5 + math.random()*2, 0)
	bb.Adornee = body
	bb.AlwaysOnTop = true
	bb.Parent = model

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "-" .. math.floor(damage)
	lbl.TextColor3 = Color3.fromRGB(255, 80, 60)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 18
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = bb

	-- Float up and fade
	task.spawn(function()
		local startOffset = bb.StudsOffset
		for i = 1, 15 do
			task.wait(0.06)
			bb.StudsOffset = startOffset + Vector3.new(0, i * 0.2, 0)
			lbl.TextTransparency = i / 15
			lbl.TextStrokeTransparency = 0.3 + (i / 15) * 0.7
		end
		if bb.Parent then bb:Destroy() end
	end)
end

-- Faint the creature (fallback only - CreatureAI.FaintCreature is preferred)
-- Only sets the attribute; visual effects are handled by CreatureAI
local function faintCreature(model)
	if model:GetAttribute("Fainted") then return end -- already fainted by CreatureAI
	model:SetAttribute("Fainted", true)

	-- Minimal visual: update nametag text
	local bb = model:FindFirstChild("NameTag")
	if bb then
		local rarityLabel = bb:FindFirstChild("RarityLabel")
		if rarityLabel then
			rarityLabel.Text = "FAINTED - Click to Capture!"
			rarityLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
		end
	end

	print("[WorldCreatureHP] Creature fainted (fallback): " .. (model:GetAttribute("CreatureId") or "?"))
end

-- Public: deal damage to a world creature
function WorldCreatureHP.DamageCreature(model, damage, attackerModel)
	if not model or not model.Parent then return end
	if model:GetAttribute("Fainted") then return end
	if not CollectionService:HasTag(model, WORLD_TAG) then return end

	local hpData = getHP(model)
	if not hpData then return end

	hpData.hp = math.max(0, hpData.hp - damage)
	updateHPBar(model, hpData)
	showDamageNumber(model, damage)

	if hpData.hp <= 0 then
		faintCreature(model)
	end
end

-- Public: get current HP of a world creature
function WorldCreatureHP.GetHP(model)
	local hpData = getHP(model)
	if not hpData then return 0, 0 end
	return hpData.hp, hpData.maxHp
end

-- Cleanup when creature is removed
function WorldCreatureHP.Cleanup(model)
	creatureHP[model] = nil
end

-- Auto-cleanup on destroy
CollectionService:GetInstanceRemovedSignal(WORLD_TAG):Connect(function(model)
	creatureHP[model] = nil
end)

function WorldCreatureHP.Init()
	print("[WorldCreatureHP] Initialized - world creature damage tracking active")
end

return WorldCreatureHP
