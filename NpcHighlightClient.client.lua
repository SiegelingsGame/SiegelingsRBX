-- NpcHighlightClient.client.lua - StarterPlayer.StarterPlayerScripts
-- Keeps prompt-based NPC highlights hidden until the local player is nearby.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local HIGHLIGHT_DISTANCE = 50
local UPDATE_INTERVAL = 0.1

local EXCLUDED_TAGS = {
	BaseIncomeCreature = true,
	BaseDefenseCreature = true,
	BaseBattleCreature = true,
}

local trackedHighlights = {}

local function resolveHighlightDistance(highlight, root)
	local value = highlight and highlight:GetAttribute("NpcHighlightDistance")
	if type(value) == "number" and value > 0 then
		return value
	end

	local current = root
	while current and current ~= Workspace do
		value = current:GetAttribute("NpcHighlightDistance")
		if type(value) == "number" and value > 0 then
			return value
		end
		current = current.Parent
	end

	return HIGHLIGHT_DISTANCE
end

local function hasExcludedTag(instance)
	local current = instance
	while current and current ~= Workspace do
		for tagName in pairs(EXCLUDED_TAGS) do
			if CollectionService:HasTag(current, tagName) then
				return true
			end
		end
		current = current.Parent
	end
	return false
end

local function findPromptRootForHighlight(highlight)
	local current = highlight and highlight.Parent
	local fallbackPart = nil
	while current and current ~= Workspace do
		if current:IsA("Model") then
			if current:FindFirstChildWhichIsA("ProximityPrompt", true) then
				return current
			end
		elseif current:IsA("BasePart") then
			fallbackPart = fallbackPart or current
			if current:FindFirstChildWhichIsA("ProximityPrompt", true) then
				return current
			end
		end
		current = current.Parent
	end
	return fallbackPart
end

local function getRootPart(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart
			or instance:FindFirstChild("HumanoidRootPart", true)
			or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function isNpcHighlight(highlight)
	if not highlight or not highlight:IsA("Highlight") then
		return false, nil
	end
	if not highlight:IsDescendantOf(Workspace) then
		return false, nil
	end

	local root = findPromptRootForHighlight(highlight)
	if not root or hasExcludedTag(root) then
		return false, nil
	end

	local prompt = root:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return false, nil
	end

	return true, root
end

local function setHighlightVisible(highlight, visible)
	if highlight and highlight.Parent and highlight.Enabled ~= visible then
		highlight.Enabled = visible
	end
end

local function refreshHighlightRegistration(highlight)
	local isNpc, root = isNpcHighlight(highlight)
	if isNpc then
		trackedHighlights[highlight] = {
			root = root,
			distance = resolveHighlightDistance(highlight, root),
		}
		setHighlightVisible(highlight, false)
	else
		trackedHighlights[highlight] = nil
	end
end

local function getCharacterRoot()
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

-- Initial scan: GetDescendants() is one large allocation; spread iteration + highlight work across frames.
local HIGHLIGHT_BATCH = 60
local DESCENDANT_YIELD_EVERY = 2500
task.defer(function()
	local all = Workspace:GetDescendants()
	local hlSinceYield = 0
	local steps = 0
	for _, desc in ipairs(all) do
		steps += 1
		if steps >= DESCENDANT_YIELD_EVERY then
			steps = 0
			task.wait()
		end
		if desc:IsA("Highlight") then
			refreshHighlightRegistration(desc)
			hlSinceYield += 1
			if hlSinceYield >= HIGHLIGHT_BATCH then
				hlSinceYield = 0
				task.wait()
			end
		end
	end
end)

Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Highlight") then
		refreshHighlightRegistration(desc)
	elseif desc:IsA("ProximityPrompt") then
		-- One bounded scan under the owning model (was: GetDescendants on every ancestor — O(n²) path work).
		local model = desc:FindFirstAncestorOfClass("Model")
		if model then
			for _, child in ipairs(model:GetDescendants()) do
				if child:IsA("Highlight") then
					refreshHighlightRegistration(child)
				end
			end
		else
			local depth = 0
			local current = desc.Parent
			while current and current ~= Workspace and depth < 12 do
				for _, child in ipairs(current:GetChildren()) do
					if child:IsA("Highlight") then
						refreshHighlightRegistration(child)
					end
				end
				current = current.Parent
				depth += 1
			end
		end
	end
end)

Workspace.DescendantRemoving:Connect(function(desc)
	if desc:IsA("Highlight") then
		trackedHighlights[desc] = nil
	end
end)

local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	if elapsed < UPDATE_INTERVAL then
		return
	end
	elapsed = 0

	local playerRoot = getCharacterRoot()

	for highlight, tracked in pairs(trackedHighlights) do
		if not highlight or not highlight.Parent then
			trackedHighlights[highlight] = nil
			continue
		end

		local root = tracked and tracked.root
		local prompt = root and root.Parent and root:FindFirstChildWhichIsA("ProximityPrompt", true)
		local rootPart = getRootPart(root)
		if not prompt or not rootPart then
			trackedHighlights[highlight] = nil
			setHighlightVisible(highlight, false)
			continue
		end

		local shouldShow = false
		if playerRoot then
			local distance = (tracked and tracked.distance) or HIGHLIGHT_DISTANCE
			shouldShow = (playerRoot.Position - rootPart.Position).Magnitude <= distance
		end
		setHighlightVisible(highlight, shouldShow)
	end
end)
