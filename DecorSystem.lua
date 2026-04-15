-- DecorSystem.lua — base furnishing: statues + furniture on DecorPoint parts per floor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local FurnitureCatalog = require(ReplicatedStorage.Modules.FurnitureCatalog)

local DecorSystem = {}

local PlayerDataManager

local DECOR_STATUE_TAG = "DecorStatue"
local DECOR_FURNITURE_TAG = "DecorFurniture"
-- Statues use the same display sizing as world creatures (modelDisplaySize × modelScaleMultiplier), at 50%.
local STATUE_SIZE_FRACTION = 0.5
local STATUE_Y_OFFSET = 1.5
local FURNITURE_Y_OFFSET = 0.8

local eventsFolder = nil

local function findPlotModel(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return nil end
	local plotsFolder = Workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return nil end
	return plotsFolder:FindFirstChild("Plot" .. data.plotId)
		or plotsFolder:FindFirstChild("Part" .. data.plotId)
end

local function parseSlotKey(slotKey)
	if type(slotKey) ~= "string" then return nil, nil end
	local a, b = slotKey:match("^(%d+)_(%d+)$")
	return tonumber(a), tonumber(b)
end

local function findDecorPoint(plotModel, slotKey)
	local floorNum, slotIdx = parseSlotKey(slotKey)
	if not floorNum or not slotIdx then return nil end
	local floorFolder = plotModel:FindFirstChild("Floor" .. floorNum)
	if not floorFolder then return nil end
	local name = "DecorPoint" .. slotIdx
	for _, desc in ipairs(floorFolder:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == name then
			return desc
		end
	end
	return nil
end

local function clearDecorOnPoint(point)
	for _, child in ipairs(point:GetChildren()) do
		if CollectionService:HasTag(child, DECOR_STATUE_TAG) or CollectionService:HasTag(child, DECOR_FURNITURE_TAG) then
			child:Destroy()
		end
	end
end

local function spawnStatue(point, creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end
	local model = CreatureModelLoader.LoadTemplate(creatureId, info.displayName or creatureId)
	if not model then return nil end
	pcall(function()
		CreatureModelLoader.ApplyDisplayScaleFromCreatureData(model, creatureId, STATUE_SIZE_FRACTION)
	end)
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
	CollectionService:AddTag(model, DECOR_STATUE_TAG)
	model.Name = "DecorStatue_" .. creatureId
	model.Parent = point
	return model
end

local function spawnFurniture(point, furnitureId)
	local entry = FurnitureCatalog.GetById(furnitureId)
	if not entry then return nil end
	local modelsFolder = ReplicatedStorage:FindFirstChild("FurnitureModels")
	local template = modelsFolder and modelsFolder:FindFirstChild(entry.modelName)
	if not template then return nil end
	local clone = template:Clone()
	if clone:IsA("Model") then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		local target = point.CFrame * CFrame.new(0, FURNITURE_Y_OFFSET, 0)
		clone:PivotTo(target)
	elseif clone:IsA("BasePart") then
		clone.Anchored = true
		clone.CanCollide = false
		clone.CFrame = point.CFrame * CFrame.new(0, FURNITURE_Y_OFFSET, 0)
	end
	CollectionService:AddTag(clone, DECOR_FURNITURE_TAG)
	clone.Name = "DecorFurniture_" .. furnitureId
	clone.Parent = point
	return clone
end

local function notifyClient(player, msg, level)
	if not eventsFolder then return end
	local evt = eventsFolder:FindFirstChild("ShowNotification")
	if evt then evt:FireClient(player, msg, level or "info") end
end

local function fireDecorBonusUpdate(player)
	if not eventsFolder then return end
	local evt = eventsFolder:FindFirstChild("DecorStatueBonusSetUpdate")
	if not evt then return end
	local map = PlayerDataManager.GetDecorStatueBonusMap(player)
	local list = {}
	for id in pairs(map) do
		table.insert(list, id)
	end
	evt:FireClient(player, list)
end

local function applySlotVisual(player, slotKey, slotData)
	local plotModel = findPlotModel(player)
	if not plotModel or not slotData then return end
	local point = findDecorPoint(plotModel, slotKey)
	if not point then return end
	clearDecorOnPoint(point)
	if slotData.kind == "statue" and slotData.creatureId then
		spawnStatue(point, slotData.creatureId)
	elseif slotData.kind == "furniture" and slotData.furnitureId then
		spawnFurniture(point, slotData.furnitureId)
	end
end

function DecorSystem.PlaceAllDecor(player)
	local plotModel = findPlotModel(player)
	if not plotModel then return end
	local decorSlots = PlayerDataManager.GetDecorSlots(player)
	for slotKey, slotData in pairs(decorSlots) do
		if type(slotKey) == "string" and type(slotData) == "table" then
			local floorNum = parseSlotKey(slotKey)
			if floorNum and PlayerDataManager.OwnsFloor(player, floorNum) then
				applySlotVisual(player, slotKey, slotData)
			end
		end
	end
	fireDecorBonusUpdate(player)
end

function DecorSystem.ClearAllDecor(player)
	local plotModel = findPlotModel(player)
	if not plotModel then return end
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:match("^DecorPoint%d+$") then
			clearDecorOnPoint(desc)
		end
	end
end

function DecorSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")

	if not eventsFolder then
		warn("[DecorSystem] Events folder missing")
		return
	end

	local bonusEvt = eventsFolder:FindFirstChild("DecorStatueBonusSetUpdate")
	if not bonusEvt then
		bonusEvt = Instance.new("RemoteEvent")
		bonusEvt.Name = "DecorStatueBonusSetUpdate"
		bonusEvt.Parent = eventsFolder
	end

	local placeFurnish = eventsFolder:FindFirstChild("PlaceFurnish")
	if not placeFurnish then
		placeFurnish = Instance.new("RemoteEvent")
		placeFurnish.Name = "PlaceFurnish"
		placeFurnish.Parent = eventsFolder
	end
	placeFurnish.OnServerEvent:Connect(function(player, slotKey, kind, id)
		if type(slotKey) ~= "string" or type(kind) ~= "string" or type(id) ~= "string" then return end
		local ok, msg = PlayerDataManager.PlaceFurnish(player, slotKey, kind, id)
		if ok then
			local slotData = PlayerDataManager.GetDecorSlots(player)[slotKey]
			applySlotVisual(player, slotKey, slotData)
			notifyClient(player, kind == "statue" and "Statue placed!" or "Furniture placed!", "info")
			local coinsEvt = eventsFolder:FindFirstChild("CoinsUpdate")
			if coinsEvt then coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player)) end
			fireDecorBonusUpdate(player)
		else
			notifyClient(player, msg or "Failed", "error")
		end
	end)

	local removeFurnish = eventsFolder:FindFirstChild("RemoveFurnish")
	if not removeFurnish then
		removeFurnish = Instance.new("RemoteEvent")
		removeFurnish.Name = "RemoveFurnish"
		removeFurnish.Parent = eventsFolder
	end
	removeFurnish.OnServerEvent:Connect(function(player, slotKey)
		if type(slotKey) ~= "string" then return end
		local plotModel = findPlotModel(player)
		local point = plotModel and findDecorPoint(plotModel, slotKey)
		local ok, msg = PlayerDataManager.RemoveFurnish(player, slotKey)
		if ok then
			if point then clearDecorOnPoint(point) end
			notifyClient(player, "Removed", "info")
			fireDecorBonusUpdate(player)
		else
			notifyClient(player, msg or "Failed", "error")
		end
	end)

	local placeEvt = eventsFolder:FindFirstChild("PlaceDecor")
	if placeEvt then
		placeEvt.OnServerEvent:Connect(function(player, slotIndex, creatureId)
			if type(slotIndex) ~= "number" or type(creatureId) ~= "string" then return end
			local slotKey = "4_" .. tostring(math.floor(slotIndex))
			local ok, msg = PlayerDataManager.PlaceFurnish(player, slotKey, "statue", creatureId)
			if ok then
				local slotData = PlayerDataManager.GetDecorSlots(player)[slotKey]
				applySlotVisual(player, slotKey, slotData)
				notifyClient(player, "Statue placed!", "info")
				local coinsEvt = eventsFolder:FindFirstChild("CoinsUpdate")
				if coinsEvt then coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player)) end
				fireDecorBonusUpdate(player)
			else
				notifyClient(player, msg or "Failed to place statue", "error")
			end
		end)
	end

	local removeEvt = eventsFolder:FindFirstChild("RemoveDecor")
	if removeEvt then
		removeEvt.OnServerEvent:Connect(function(player, slotIndex)
			if type(slotIndex) ~= "number" then return end
			local slotKey = "4_" .. tostring(math.floor(slotIndex))
			local plotModel = findPlotModel(player)
			local point = plotModel and findDecorPoint(plotModel, slotKey)
			local ok, msg = PlayerDataManager.RemoveFurnish(player, slotKey)
			if ok then
				if point then clearDecorOnPoint(point) end
				notifyClient(player, "Statue removed", "info")
				fireDecorBonusUpdate(player)
			else
				notifyClient(player, msg or "Failed", "error")
			end
		end)
	end

	local getDecor = eventsFolder:FindFirstChild("GetDecorSlots")
	if not getDecor then
		getDecor = Instance.new("RemoteFunction")
		getDecor.Name = "GetDecorSlots"
		getDecor.Parent = eventsFolder
	end
	getDecor.OnServerInvoke = function(player)
		return PlayerDataManager.GetDecorSlots(player)
	end

	Players.PlayerAdded:Connect(function(plr)
		task.defer(function()
			task.wait(2)
			if plr.Parent and PlayerDataManager.GetData(plr) then
				local slots = PlayerDataManager.GetDecorSlots(plr)
				local has = false
				for _ in pairs(slots) do has = true break end
				if has then
					pcall(function() DecorSystem.PlaceAllDecor(plr) end)
				else
					fireDecorBonusUpdate(plr)
				end
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		pcall(function() DecorSystem.PlaceAllDecor(player) end)
	end

	print("[DecorSystem] Initialized (multi-floor furnish + statue capture bonus sync)")
end

return DecorSystem
