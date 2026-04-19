--[[
	NpcSpawnMarkers.lua — ReplicatedStorage/Modules
	Optional hub NPC placement: find the first workspace BasePart with a given name
	(BrokerSpawn, CookSpawn, SiegeSpawn, CuratorSpawn, etc.).

	ResolvePlacementRelativeToHubSpawn: express marker position & facing relative to
	workspace.HubArea.SpawnLocation so NPC offsets stay tied to the default hub spawn
	when the hub model settles or moves at runtime.

	HideSpawnMarkers: once the server starts, hub slot helper parts become fully invisible
	(Roblox Transparency = 1); positions remain valid for NPC placement math.
]]
-- Last updated: 2026-04-18 22:35

local Workspace = game:GetService("Workspace")

local NpcSpawnMarkers = {}

local HIDDEN_MARKER_NAMES = {
	BrokerSpawn = true,
	CookSpawn = true,
	SiegeSpawn = true,
	CuratorSpawn = true,
}

function NpcSpawnMarkers.FindNamedPart(markerName)
	if type(markerName) ~= "string" or markerName == "" then
		return nil
	end
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == markerName and desc:IsA("BasePart") then
			return desc
		end
	end
	return nil
end

function NpcSpawnMarkers.GetDefaultHubSpawn()
	local hub = Workspace:FindFirstChild("HubArea")
	local spawn = hub and hub:FindFirstChild("SpawnLocation")
	if spawn and spawn:IsA("BasePart") then
		return spawn
	end
	return nil
end

--- @return table|nil { spawnPart, marker, worldPosition, flatLookWorld }
function NpcSpawnMarkers.ResolvePlacementRelativeToHubSpawn(markerName)
	local spawnPart = NpcSpawnMarkers.GetDefaultHubSpawn()
	if not spawnPart then
		return nil
	end
	local marker = NpcSpawnMarkers.FindNamedPart(markerName)
	if not marker then
		return nil
	end
	local localPos = spawnPart.CFrame:PointToObjectSpace(marker.Position)
	local worldPosition = spawnPart.CFrame:PointToWorldSpace(localPos)

	local localLook = spawnPart.CFrame:VectorToObjectSpace(marker.CFrame.LookVector)
	local horizontalLocal = Vector3.new(localLook.X, 0, localLook.Z)
	local horizontalWorld = spawnPart.CFrame:VectorToWorldSpace(horizontalLocal)
	if horizontalWorld.Magnitude < 1e-4 then
		local lv = spawnPart.CFrame.LookVector
		horizontalWorld = Vector3.new(lv.X, 0, lv.Z)
	end
	if horizontalWorld.Magnitude < 1e-4 then
		horizontalWorld = Vector3.new(0, 0, -1)
	end

	return {
		spawnPart = spawnPart,
		marker = marker,
		worldPosition = worldPosition,
		flatLookWorld = horizontalWorld.Unit,
	}
end

--- Hub NPC slot helpers: fully transparent in-game (Roblox 0–1 scale; 1 = 100%).
function NpcSpawnMarkers.HideSpawnMarkers()
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("BasePart") and HIDDEN_MARKER_NAMES[desc.Name] then
			desc.Transparency = 1
		elseif desc:IsA("Model") and HIDDEN_MARKER_NAMES[desc.Name] then
			for _, p in ipairs(desc:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency = 1
				end
			end
		end
	end
end

return NpcSpawnMarkers
