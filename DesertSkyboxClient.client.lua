-- ══════════════════════════════════════════════════════════════════════════════
-- DesertSkyboxClient.client.lua
-- Swaps the skybox to "DesertSky" when the player is directly above or
-- touching the DesertBaseplate part. Restores the default skybox when they
-- leave that region.
--
-- Setup requirements:
--   1. A Part in workspace called "DesertBaseplate"
--   2. A Sky object in Lighting (or ReplicatedStorage) called "DesertSky"
--      with your desert skybox textures configured
--   3. Place this script in StarterPlayerScripts
--
-- How it works:
--   Every frame, checks if the player's HumanoidRootPart XZ position is
--   within the DesertBaseplate's bounding box. If so, swaps in DesertSky.
--   When they leave, restores the original sky.
-- ══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ══════════════════════════════════════════════════════════════════════════════

-- Vertical buffer above the baseplate that still counts as "over" it (studs)
local VERTICAL_BUFFER = 500

-- How often to check position (seconds). 0 = every frame via Heartbeat.
local CHECK_INTERVAL = 0.1

-- ══════════════════════════════════════════════════════════════════════════════
-- REFERENCES
-- ══════════════════════════════════════════════════════════════════════════════

-- Find the DesertBaseplate in workspace
local desertBaseplate = workspace:WaitForChild("DesertBaseplate", 10)
if not desertBaseplate then
	warn("[DesertSkybox] Could not find workspace.DesertBaseplate — skybox swap disabled")
	return
end

-- Find the DesertSky object. Check Lighting, then ReplicatedStorage.Skybox folder,
-- then ReplicatedStorage root.
local skyboxFolder = ReplicatedStorage:FindFirstChild("Skybox")
local desertSky = Lighting:FindFirstChild("DesertSky")
	or (skyboxFolder and skyboxFolder:FindFirstChild("DesertSky"))
	or ReplicatedStorage:FindFirstChild("DesertSky")
if not desertSky then
	warn("[DesertSkybox] Could not find DesertSky object — skybox swap disabled")
	return
end

-- Clone it so we can freely parent/unparent without losing it
desertSky = desertSky:Clone()
desertSky.Name = "DesertSky_Active"

-- ══════════════════════════════════════════════════════════════════════════════
-- SAVE THE DEFAULT SKY
-- ══════════════════════════════════════════════════════════════════════════════

-- Capture whatever Sky is currently in Lighting as the "default"
local defaultSky = Lighting:FindFirstChildOfClass("Sky")

-- ══════════════════════════════════════════════════════════════════════════════
-- POSITION CHECK
-- ══════════════════════════════════════════════════════════════════════════════

--- Returns true if the given world position is within the XZ bounding box
--- of the DesertBaseplate and above (or on) its top surface.
--- @param position Vector3 — the player's world position
--- @return boolean
local function isOverDesertBaseplate(position)
	local cf = desertBaseplate.CFrame
	local size = desertBaseplate.Size

	-- Transform player position into the baseplate's local space
	-- This correctly handles rotated baseplates
	local localPos = cf:PointToObjectSpace(position)

	local halfX = size.X / 2
	local halfZ = size.Z / 2
	local halfY = size.Y / 2

	-- Check XZ bounds (within the footprint of the baseplate)
	if math.abs(localPos.X) > halfX then return false end
	if math.abs(localPos.Z) > halfZ then return false end

	-- Check Y: player must be above the bottom of the baseplate,
	-- and within VERTICAL_BUFFER studs above the top surface
	if localPos.Y < -halfY then return false end
	if localPos.Y > halfY + VERTICAL_BUFFER then return false end

	return true
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SKYBOX SWAP LOGIC
-- ══════════════════════════════════════════════════════════════════════════════

local isInDesert = false

local function setDesertSkybox(enabled)
	if enabled == isInDesert then return end
	isInDesert = enabled

	if enabled then
		-- Remove the default sky and parent in the desert sky
		if defaultSky and defaultSky.Parent == Lighting then
			defaultSky.Parent = nil
		end
		desertSky.Parent = Lighting
	else
		-- Remove desert sky and restore default
		desertSky.Parent = nil
		if defaultSky then
			defaultSky.Parent = Lighting
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- MAIN LOOP
-- ══════════════════════════════════════════════════════════════════════════════

local timeSinceLastCheck = 0

RunService.Heartbeat:Connect(function(dt)
	timeSinceLastCheck += dt
	if timeSinceLastCheck < CHECK_INTERVAL then return end
	timeSinceLastCheck = 0

	local character = localPlayer.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	setDesertSkybox(isOverDesertBaseplate(rootPart.Position))
end)
