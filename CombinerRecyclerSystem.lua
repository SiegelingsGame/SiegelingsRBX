-- CombinerRecyclerSystem.lua - ServerScriptService (ModuleScript)
-- MCombiner: interact to open combine UI (3 same creature + same variant → 1 next variant).
-- MRecycler: interact to open recycler UI (N duplicates → 1 creature 1 rarity tier higher).
-- Adds ProximityPrompts to MCombiner and MRecycler parts in each plot; handles RecycleDuplicates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = nil
pcall(function() GameConfig = require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("GameConfig", 5)) end)

local CombinerRecyclerSystem = {}

local PlayerDataManager = nil
local eventsFolder = nil

-- Accept exact or short names so place can use "MCombiner"/"Combiner" and "MRecycler"/"Recycler"
local COMBINER_NAMES = { ["MCombiner"] = true, ["Combiner"] = true }
local RECYCLER_NAMES = { ["MRecycler"] = true, ["Recycler"] = true }
local COMBINER_RECYCLER_FLOOR = 3  -- MCombiner and MRecycler live in Floor3 folder; only accessible when player owns Floor 3

local PROMPT_ACTION_COMBINER = "Combine"
local PROMPT_ACTION_RECYCLER = "Recycle"
local PROMPT_OBJECT_COMBINER = "Combiner"
local PROMPT_OBJECT_RECYCLER = "Recycler"
local PROMPT_DISTANCE = 14

local function getEvent(name)
	return eventsFolder and eventsFolder:FindFirstChild(name)
end

-- Walk up ancestors to find which FloorX folder a part lives in. Returns floor number (1,2,3) or nil.
local function getFloorForPart(part)
	local current = part.Parent
	while current and current ~= game do
		local floorNum = current.Name:match("^Floor(%d+)$")
		if floorNum then return tonumber(floorNum) end
		current = current.Parent
	end
	return nil
end

-- Call from BasePlacementSystem.PlaceCreatures with ownedFloors so only Floor 3 prompts are set when player owns Floor 3.
-- If GameConfig.CombinerRecyclerPromptAllPlots is true, prompts are added regardless of ownedFloors (for testing).
function CombinerRecyclerSystem.SetupPlotPrompts(plotModel, ownedFloors)
	if not plotModel then
		warn("[CombinerRecycler] SetupPlotPrompts: plotModel is nil")
		return
	end
	if not eventsFolder then
		warn("[CombinerRecycler] SetupPlotPrompts: Events folder not found in ReplicatedStorage (Init may have failed)")
		return
	end

	ownedFloors = ownedFloors or {1}
	local ownedSet = {}
	for _, f in ipairs(ownedFloors) do ownedSet[f] = true end
	local forceAllPlots = GameConfig and GameConfig.CombinerRecyclerPromptAllPlots == true
	if not ownedSet[COMBINER_RECYCLER_FLOOR] and not forceAllPlots then
		print("[CombinerRecycler] SetupPlotPrompts skipped for " .. plotModel.Name .. " (player does not own Floor 3; buy Floor 3 or set GameConfig.CombinerRecyclerPromptAllPlots = true for testing)")
		return
	end

	local openCombiner = getEvent("OpenCombiner")
	local openRecycler = getEvent("OpenRecycler")
	if not openCombiner or not openRecycler then
		warn("[CombinerRecycler] OpenCombiner or OpenRecycler remote missing in ReplicatedStorage.Events")
		return
	end

	local nCombiner, nRecycler = 0, 0
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if not desc:IsA("BasePart") then continue end
		local floor = getFloorForPart(desc)
		if floor ~= COMBINER_RECYCLER_FLOOR then continue end  -- only parts inside Floor3 folder
		if COMBINER_NAMES[desc.Name] then
			local prompt = desc:FindFirstChildOfClass("ProximityPrompt")
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "CombinerPrompt"
				prompt.ActionText = PROMPT_ACTION_COMBINER
				prompt.ObjectText = PROMPT_OBJECT_COMBINER
				prompt.MaxActivationDistance = PROMPT_DISTANCE
				prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.Enabled = true
				prompt.Parent = desc
			else
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.Enabled = true
				prompt.MaxActivationDistance = PROMPT_DISTANCE
			end
			if not desc:GetAttribute("CombinerBound") then
				desc:SetAttribute("CombinerBound", true)
				prompt.Triggered:Connect(function(plr)
					print("[CombinerRecycler] Combiner E pressed by " .. tostring(plr and plr.Name or "?"))
					if openCombiner then openCombiner:FireClient(plr) end
				end)
			end
			nCombiner = nCombiner + 1
		elseif RECYCLER_NAMES[desc.Name] then
			local prompt = desc:FindFirstChildOfClass("ProximityPrompt")
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "RecyclerPrompt"
				prompt.ActionText = PROMPT_ACTION_RECYCLER
				prompt.ObjectText = PROMPT_OBJECT_RECYCLER
				prompt.MaxActivationDistance = PROMPT_DISTANCE
				prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.Enabled = true
				prompt.Parent = desc
			else
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.Enabled = true
				prompt.MaxActivationDistance = PROMPT_DISTANCE
			end
			if not desc:GetAttribute("RecyclerBound") then
				desc:SetAttribute("RecyclerBound", true)
				prompt.Triggered:Connect(function(plr)
					print("[CombinerRecycler] Recycler E pressed by " .. tostring(plr and plr.Name or "?"))
					if openRecycler then openRecycler:FireClient(plr) end
				end)
			end
			nRecycler = nRecycler + 1
		end
	end
	if nCombiner > 0 or nRecycler > 0 then
		print("[CombinerRecycler] SetupPlotPrompts " .. plotModel.Name .. ": added " .. nCombiner .. " Combiner, " .. nRecycler .. " Recycler E-prompts")
	else
		warn("[CombinerRecycler] No MCombiner/MRecycler parts found in Floor3 of " .. plotModel.Name .. " (check part names and that they are inside a folder named exactly 'Floor3')")
	end
end

function CombinerRecyclerSystem.Init(playerDataManager)
	PlayerDataManager = playerDataManager
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then return end

	local recycleEvent = getEvent("RecycleDuplicates")
	local recycleResult = getEvent("RecycleResult")
	if recycleEvent and recycleResult then
		recycleEvent.OnServerEvent:Connect(function(player, uids)
			print("[CombinerRecycler] RecycleDuplicates received from " .. tostring(player and player.Name or "?") .. " uids=" .. (type(uids) == "table" and #uids or "nil") .. " raw=" .. tostring(uids))
			if not player or not PlayerDataManager.GetData(player) then
				warn("[CombinerRecycler] RecycleDuplicates: no player or no data")
				return
			end
			if type(uids) ~= "table" then
				print("[CombinerRecycler] RecycleDuplicates: invalid uids type")
				recycleResult:FireClient(player, false, "Invalid selection")
				return
			end
			local newUid, err = PlayerDataManager.RecycleDuplicates(player, uids)
			print("[CombinerRecycler] RecycleDuplicates result newUid=" .. tostring(newUid) .. " err=" .. tostring(err))
			if newUid then
				recycleResult:FireClient(player, true, newUid)
			else
				recycleResult:FireClient(player, false, err or "Recycle failed")
			end
		end)
	end

	-- Ensure prompts appear: either on all plots (testing) or only on plots where owner has Floor 3
	task.defer(function()
		task.wait(4)
		local plotsFolder = workspace:FindFirstChild("BasePlots")
		if not plotsFolder then return end
		local forceAll = GameConfig and GameConfig.CombinerRecyclerPromptAllPlots == true
		if forceAll then
			for _, plotModel in ipairs(plotsFolder:GetChildren()) do
				if plotModel:IsA("Model") or plotModel:IsA("Folder") then
					CombinerRecyclerSystem.SetupPlotPrompts(plotModel, {1, 2, 3})
				end
			end
			print("[CombinerRecycler] Applied E-prompts to ALL plots (CombinerRecyclerPromptAllPlots = true)")
		elseif PlayerDataManager then
			for _, plr in ipairs(Players:GetPlayers()) do
				local d = PlayerDataManager.GetData(plr)
				if d and d.plotId and d.plotId ~= 0 and d.ownedFloors then
					local owns3 = false
					for _, f in ipairs(d.ownedFloors) do if f == 3 then owns3 = true; break end end
					if owns3 then
						local plotModel = plotsFolder:FindFirstChild("Plot" .. d.plotId) or plotsFolder:FindFirstChild("Part" .. d.plotId)
						if plotModel then
							CombinerRecyclerSystem.SetupPlotPrompts(plotModel, d.ownedFloors)
						end
					end
				end
			end
		end
	end)

	Players.PlayerAdded:Connect(function(plr)
		task.defer(function()
			task.wait(5)
			local plotsFolder = workspace:FindFirstChild("BasePlots")
			if not plotsFolder then return end
			if GameConfig and GameConfig.CombinerRecyclerPromptAllPlots == true then
				for _, plotModel in ipairs(plotsFolder:GetChildren()) do
					if plotModel:IsA("Model") or plotModel:IsA("Folder") then
						CombinerRecyclerSystem.SetupPlotPrompts(plotModel, {1, 2, 3})
					end
				end
			else
				local d = PlayerDataManager and PlayerDataManager.GetData(plr)
				if not d or not d.plotId or d.plotId == 0 or not d.ownedFloors then return end
				local owns3 = false
				for _, f in ipairs(d.ownedFloors) do if f == 3 then owns3 = true; break end end
				if not owns3 then return end
				local plotModel = plotsFolder:FindFirstChild("Plot" .. d.plotId) or plotsFolder:FindFirstChild("Part" .. d.plotId)
				if plotModel then
					CombinerRecyclerSystem.SetupPlotPrompts(plotModel, d.ownedFloors)
				end
			end
		end)
	end)

	print("[CombinerRecyclerSystem] Initialized (MCombiner / MRecycler prompts via SetupPlotPrompts)")
end

return CombinerRecyclerSystem
