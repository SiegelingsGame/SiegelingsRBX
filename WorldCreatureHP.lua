-- WorldCreatureHP.lua - ServerScriptService (ModuleScript)
-- Tracks HP for world-spawned creatures. When HP reaches 0, sets Fainted attribute.
-- Both PlayerCombatSystem and FavoriteCreatureSystem call DamageCreature here.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
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

-- Only show damage number to the player who is attacking (not all players in open world)
local function fireDamageNumberToAttacker(model, damage, attackerModel)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body then return end

	local player = nil
	if attackerModel then
		if attackerModel:IsA("Model") then
			local char = attackerModel
			if char:FindFirstChild("Humanoid") then
				player = Players:GetPlayerFromCharacter(char)
			else
				local ownerId = char:GetAttribute("OwnerUserId")
				if ownerId then player = Players:GetPlayerByUserId(ownerId) end
			end
		end
	end
	if player and player.Parent then
		local evt = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("ShowDamageNumber")
		if evt and evt:IsA("RemoteEvent") then
			evt:FireClient(player, body.Position, damage)
		end
	end
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
	fireDamageNumberToAttacker(model, damage, attackerModel)

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
