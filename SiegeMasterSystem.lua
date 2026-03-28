-- SiegeMasterSystem.lua - ServerScriptService (ModuleScript)
-- Spawns "Siege Master" in/near arena and opens siege provisions shop UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local SiegeMasterSystem = {}

local siegeMasterNPC
local eventsFolder

local function getConfig()
	return GameConfig.SiegeMaster or {}
end

local function isEnabled()
	if GameConfig.SiegeMasterEnabled == false then
		return false
	end
	return true
end

local function resolveArenaAnchor()
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then
		return nil
	end
	local center = arena:FindFirstChild("ArenaCenter", true)
	if center and center:IsA("BasePart") then
		return center.Position
	end
	local blueTeam = arena:FindFirstChild("BlueTeam", true)
	if blueTeam then
		local bp = blueTeam:FindFirstChild("BattlePoint1", true)
		if bp and bp:IsA("BasePart") then
			return bp.Position
		end
	end
	return nil
end

local function buildSpawnCFrame()
	local cfg = getConfig()
	local arenaOffset = cfg.OffsetFromArenaCenterStuds or Vector3.new(-22, 0, -8)
	local fallbackOffset = cfg.FallbackOffsetFromSpawnStuds or Vector3.new(-12, 0, -24)

	local baseXZ
	local arenaPos = resolveArenaAnchor()
	if arenaPos then
		baseXZ = arenaPos + Vector3.new(arenaOffset.X, 0, arenaOffset.Z)
	else
		local hub = Workspace:FindFirstChild("HubArea")
		local spawnRef = hub and hub:FindFirstChild("SpawnLocation")
		if not spawnRef or not spawnRef:IsA("BasePart") then
			return nil
		end
		baseXZ = spawnRef.Position + Vector3.new(fallbackOffset.X, 0, fallbackOffset.Z)
	end

	local rayOrigin = Vector3.new(baseXZ.X, baseXZ.Y + 70, baseXZ.Z)
	local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -260, 0))
	local groundY = rayResult and rayResult.Position.Y or baseXZ.Y
	local pos = Vector3.new(baseXZ.X, groundY + 2.5, baseXZ.Z)

	local baseCF = CFrame.new(pos)
	local extraRot = cfg.ExtraRotationDegrees
	if type(extraRot) == "table" then
		local pitch = tonumber(extraRot.pitch) or 0
		local yaw = tonumber(extraRot.yaw) or 0
		local roll = tonumber(extraRot.roll) or 0
		if pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
			baseCF = baseCF * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
		end
	end
	return baseCF
end

local function createSiegeMaster()
	if siegeMasterNPC and siegeMasterNPC.Parent then
		return siegeMasterNPC
	end

	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "SiegeMasterNPC" and (desc:IsA("Model") or desc:IsA("BasePart")) then
			siegeMasterNPC = desc
			break
		end
	end

	if not siegeMasterNPC then
		local spawnCF = buildSpawnCFrame()
		if not spawnCF then
			warn("[SiegeMaster] Could not resolve arena spawn position")
			return nil
		end

		local template = ReplicatedStorage:FindFirstChild("SiegeMasterNPC")
		if template and (template:IsA("Model") or template:IsA("BasePart")) then
			local npc = template:Clone()
			npc.Name = "SiegeMasterNPC"
			npc.Parent = Workspace
			if npc:IsA("Model") then
				if not npc.PrimaryPart then
					npc.PrimaryPart = npc:FindFirstChildWhichIsA("BasePart", true)
				end
				if npc.PrimaryPart then
					npc:PivotTo(spawnCF)
				end
			else
				npc.CFrame = spawnCF * CFrame.new(0, npc.Size.Y * 0.5, 0)
			end
			siegeMasterNPC = npc
		else
			local p = Instance.new("Part")
			p.Name = "SiegeMasterNPC"
			p.Size = Vector3.new(3, 5, 3)
			p.Anchored = true
			p.CanCollide = true
			p.Material = Enum.Material.Slate
			p.Color = Color3.fromRGB(175, 182, 192)
			p.CFrame = spawnCF * CFrame.new(0, p.Size.Y * 0.5, 0)
			p.Parent = Workspace
			siegeMasterNPC = p
		end
	end

	if siegeMasterNPC:IsA("Model") then
		local pp = siegeMasterNPC.PrimaryPart or siegeMasterNPC:FindFirstChildWhichIsA("BasePart", true)
		if pp and not siegeMasterNPC.PrimaryPart then
			siegeMasterNPC.PrimaryPart = pp
		end
		for _, d in ipairs(siegeMasterNPC:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	else
		siegeMasterNPC.Anchored = true
	end

	local adornee = (siegeMasterNPC:IsA("Model") and siegeMasterNPC.PrimaryPart) or siegeMasterNPC
	if adornee and not siegeMasterNPC:FindFirstChild("SiegeMasterTag", true) then
		local bb = Instance.new("BillboardGui")
		bb.Name = "SiegeMasterTag"
		bb.Adornee = adornee
		bb.Size = UDim2.new(0, 260, 0, 66)
		bb.StudsOffset = Vector3.new(0, 4.4, 0)
		bb.MaxDistance = 80
		bb.Parent = siegeMasterNPC

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0.5, 0)
		title.BackgroundTransparency = 1
		title.Text = "Siege Master"
		title.TextColor3 = Color3.fromRGB(225, 232, 242)
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.Parent = bb

		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.Size = UDim2.new(1, 0, 0.42, 0)
		sub.Position = UDim2.new(0, 0, 0.54, 0)
		sub.BackgroundTransparency = 1
		sub.Text = "XP & Siege Provisions"
		sub.TextColor3 = Color3.fromRGB(165, 175, 190)
		sub.Font = Enum.Font.GothamMedium
		sub.TextScaled = true
		sub.Parent = bb
	end

	local promptParent = (siegeMasterNPC:IsA("Model") and siegeMasterNPC.PrimaryPart) or siegeMasterNPC
	if promptParent and not siegeMasterNPC:FindFirstChild("SiegeMasterPrompt", true) then
		local cfg = getConfig()
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "SiegeMasterPrompt"
		prompt.ObjectText = "Siege Master"
		prompt.ActionText = "Open Shop"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = tonumber(cfg.PromptRange) or 12
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = promptParent
	end

	if not siegeMasterNPC:FindFirstChildWhichIsA("Highlight") then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(132, 142, 158)
		highlight.FillTransparency = 0.6
		highlight.OutlineColor = Color3.fromRGB(220, 230, 245)
		highlight.OutlineTransparency = 0.1
		highlight.Parent = siegeMasterNPC
	end

	return siegeMasterNPC
end

local function wirePrompt()
	local npc = siegeMasterNPC
	if not npc or not eventsFolder then
		return
	end
	local prompt = npc:FindFirstChild("SiegeMasterPrompt", true)
	local openEvt = eventsFolder:FindFirstChild("OpenSiegeMasterShop")
	if not prompt or not openEvt then
		return
	end

	prompt.Triggered:Connect(function(player)
		openEvt:FireClient(player)
	end)
end

function SiegeMasterSystem.GetNPC()
	return siegeMasterNPC
end

function SiegeMasterSystem.Init()
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not isEnabled() then
		print("[SiegeMaster] Disabled via GameConfig.SiegeMasterEnabled")
		return
	end

	local npc = createSiegeMaster()
	if not npc then
		return
	end
	wirePrompt()
	print("[SiegeMaster] Initialized")
end

return SiegeMasterSystem
