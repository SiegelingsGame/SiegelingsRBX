-- DecorSystem.lua - ServerScriptService (ModuleScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Floor 4 Creature Statue Decoration System
--
-- Allows players with Floor 4 to place creature model statues on DecorPoint
-- parts as gold-sink cosmetic items. Each DecorPoint gets a scaled-down clone
-- of a creature model on a small pedestal.
--
-- Workspace structure:
--   Plot1/Floor4/DecorPoints/
--     DecorPoint1..6 (BaseParts — pedestals for creature statues)
--
-- Player data (in PlayerDataManager):
--   decorSlots = { [slotIndex] = { creatureId = "firsky" }, ... }
--
-- Gold cost scales by creature rarity (GameConfig.DecorCostByRarity):
--   Common=500, Uncommon=1000, Rare=2500, Epic=5000, Legendary=10000
--
-- Remote events:
--   PlaceDecor(slotIndex, creatureId) — place a statue (deducts gold)
--   RemoveDecor(slotIndex) — remove a statue (no refund)
--   GetDecorSlots() → table — client queries current decor state
--
-- Architecture:
--   - Statues are small display models (scaled to ~2 studs) with no collision
--   - Models cloned from ReplicatedStorage.CreatureModels via CreatureModelLoader
--   - Each statue tagged "DecorStatue" for easy cleanup
--   - PlaceAllDecor(player) called after floor purchase or server join
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)

local DecorSystem = {}

-- ═══════════════════════════════════════════════════════════════════════════════
-- Dependencies (set in Init)
-- ═══════════════════════════════════════════════════════════════════════════════
local PlayerDataManager

-- ═══════════════════════════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════════════════════════
local DECOR_TAG = "DecorStatue"
local STATUE_DISPLAY_SIZE = 2.5  -- studs; scale all creature models to this
local STATUE_Y_OFFSET = 1.5     -- studs above the DecorPoint surface
local MAX_DECOR_SLOTS = GameConfig.DecorPointsPerFloor4 or 6

-- Events folder
local eventsFolder = nil

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Find the plot model for a player
-- ═══════════════════════════════════════════════════════════════════════════════
local function findPlotModel(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return nil end
	local plotsFolder = Workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return nil end
	return plotsFolder:FindFirstChild("Plot" .. data.plotId)
		or plotsFolder:FindFirstChild("Part" .. data.plotId)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Find a specific DecorPoint part on a plot
-- @param plotModel Model
-- @param slotIndex number (1-6)
-- @return BasePart|nil
-- ═══════════════════════════════════════════════════════════════════════════════
local function findDecorPoint(plotModel, slotIndex)
	local name = "DecorPoint" .. slotIndex
	-- Search all descendants (points may be inside Floor4/DecorPoints/ subfolder)
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == name then
			return desc
		end
	end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Clear all statue models on a specific DecorPoint
-- @param point BasePart — the DecorPoint part
-- ═══════════════════════════════════════════════════════════════════════════════
local function clearStatueOnPoint(point)
	for _, child in ipairs(point:GetChildren()) do
		if CollectionService:HasTag(child, DECOR_TAG) then
			child:Destroy()
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- spawnStatue(point, creatureId)
-- Clones a creature model, scales it down, and places it on the DecorPoint.
--
-- @param point      BasePart — the DecorPoint part
-- @param creatureId string   — creature ID (e.g. "firsky")
-- @return Model|nil — the spawned statue model
-- ═══════════════════════════════════════════════════════════════════════════════
local function spawnStatue(point, creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local model = CreatureModelLoader.LoadTemplate(creatureId, info.displayName or creatureId)
	if not model then return nil end

	-- Scale the model to display size
	if model:IsA("Model") and model.ScaleTo then
		-- Use Roblox Model scaling if available
		pcall(function()
			local body = CreatureModelLoader.GetBodyPart(model)
			if body then
				local currentSize = body.Size.Magnitude
				local scale = STATUE_DISPLAY_SIZE / math.max(currentSize, 0.1)
				model:ScaleTo(scale)
			end
		end)
	end

	-- Position on top of the DecorPoint
	local body = CreatureModelLoader.GetBodyPart(model)
	if body then
		body.Anchored = true
		body.CanCollide = false
	end

	local spawnPos = point.Position + Vector3.new(0, STATUE_Y_OFFSET, 0)
	if model:IsA("Model") then
		model:PivotTo(CFrame.new(spawnPos))
	elseif body then
		body.CFrame = CFrame.new(spawnPos)
	end

	-- Tag for cleanup and parent to the DecorPoint
	CollectionService:AddTag(model, DECOR_TAG)
	model.Name = "DecorStatue_" .. creatureId
	model.Parent = point

	return model
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- PlaceAllDecor(player)
-- Spawns all saved decor statues for a player's plot. Called on Floor 4
-- purchase and on server join (for returning players).
--
-- @param player Player
-- ═══════════════════════════════════════════════════════════════════════════════
function DecorSystem.PlaceAllDecor(player)
	local plotModel = findPlotModel(player)
	if not plotModel then return end

	-- Check Floor 4 ownership
	if not PlayerDataManager.OwnsFloor(player, 4) then return end

	local decorSlots = PlayerDataManager.GetDecorSlots(player)

	for slotIndex, slotData in pairs(decorSlots) do
		local idx = tonumber(slotIndex)
		if idx and slotData and slotData.creatureId then
			local point = findDecorPoint(plotModel, idx)
			if point then
				clearStatueOnPoint(point)
				spawnStatue(point, slotData.creatureId)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ClearAllDecor(player)
-- Removes all decor statues from a player's plot (used on disconnect).
-- @param player Player
-- ═══════════════════════════════════════════════════════════════════════════════
function DecorSystem.ClearAllDecor(player)
	local plotModel = findPlotModel(player)
	if not plotModel then return end

	for i = 1, MAX_DECOR_SLOTS do
		local point = findDecorPoint(plotModel, i)
		if point then clearStatueOnPoint(point) end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Notify client
-- ═══════════════════════════════════════════════════════════════════════════════
local function notifyClient(player, msg, level)
	if not eventsFolder then return end
	local evt = eventsFolder:FindFirstChild("ShowNotification")
	if evt then evt:FireClient(player, msg, level or "info") end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Init(playerDataMgr)
-- Sets up remote events for decor placement/removal. Called from MainServer.
-- @param playerDataMgr PlayerDataManager module
-- ═══════════════════════════════════════════════════════════════════════════════
function DecorSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")

	-- Create remote events for client interaction
	if eventsFolder then
		-- PlaceDecor remote
		local placeEvt = eventsFolder:FindFirstChild("PlaceDecor")
		if not placeEvt then
			placeEvt = Instance.new("RemoteEvent")
			placeEvt.Name = "PlaceDecor"
			placeEvt.Parent = eventsFolder
		end
		placeEvt.OnServerEvent:Connect(function(player, slotIndex, creatureId)
			if type(slotIndex) ~= "number" or type(creatureId) ~= "string" then return end

			local ok, msg = PlayerDataManager.PlaceDecor(player, slotIndex, creatureId)
			if ok then
				-- Spawn the statue
				local plotModel = findPlotModel(player)
				if plotModel then
					local point = findDecorPoint(plotModel, slotIndex)
					if point then
						clearStatueOnPoint(point)
						spawnStatue(point, creatureId)
					end
				end
				notifyClient(player, "Statue placed!", "info")
				-- Update coins
				local coinsEvt = eventsFolder:FindFirstChild("CoinsUpdate")
				if coinsEvt then coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player)) end
			else
				notifyClient(player, msg or "Failed to place statue", "error")
			end
		end)

		-- RemoveDecor remote
		local removeEvt = eventsFolder:FindFirstChild("RemoveDecor")
		if not removeEvt then
			removeEvt = Instance.new("RemoteEvent")
			removeEvt.Name = "RemoveDecor"
			removeEvt.Parent = eventsFolder
		end
		removeEvt.OnServerEvent:Connect(function(player, slotIndex)
			if type(slotIndex) ~= "number" then return end

			local ok, msg = PlayerDataManager.RemoveDecor(player, slotIndex)
			if ok then
				local plotModel = findPlotModel(player)
				if plotModel then
					local point = findDecorPoint(plotModel, slotIndex)
					if point then clearStatueOnPoint(point) end
				end
				notifyClient(player, "Statue removed", "info")
			else
				notifyClient(player, msg or "Failed", "error")
			end
		end)

		-- GetDecorSlots remote function
		local getDecor = eventsFolder:FindFirstChild("GetDecorSlots")
		if not getDecor then
			getDecor = Instance.new("RemoteFunction")
			getDecor.Name = "GetDecorSlots"
			getDecor.Parent = eventsFolder
		end
		getDecor.OnServerInvoke = function(player)
			return PlayerDataManager.GetDecorSlots(player)
		end
	end

	-- Spawn decor for players who already own Floor 4 (Studio hot-reload)
	for _, player in ipairs(Players:GetPlayers()) do
		if PlayerDataManager.OwnsFloor(player, 4) then
			pcall(function() DecorSystem.PlaceAllDecor(player) end)
		end
	end

	print("[DecorSystem] DecorSystem initialized")
end

return DecorSystem
