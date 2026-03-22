-- GymJumbotronClient.client.lua - StarterPlayerScripts (LocalScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Live Jumbotron Viewport System for Base Gym (Floor 4) Battles
--
-- Converts the 4 existing Leaderboard screen parts inside each plot's
-- Floor4/BaseGym into live battle camera feeds — like a stadium jumbotron.
-- Spectators outside the base can watch the gym battle in real time even
-- if they are not physically present in the arena.
--
-- Screen assignments (using existing part names — NOT renamed):
--   LeaderboardBattle  → Overhead tactical camera (vertical, looking down)
--   LeaderboardIncome  → Side panoramic camera (both teams, ~10° elevation)
--   LeaderboardLevels  → Siegeknight #1 live follow camera (owner — front-facing)
--   LeaderboardMonster → Siegeknight #2 live follow camera (challenger — front-facing)
--
-- Architecture:
--   - Pure client-side — each client builds its own local ViewportFrames
--   - Watches "GymBattleInProgress" attribute on plots (set by GymBattleSystem)
--   - Reads "GymOwnerUserId" / "GymChallengerUserId" attributes for player feeds
--   - Clones battle creatures from workspace into ViewportFrames
--   - Syncs clone transforms every frame to match live battle state
--   - Distance-gated: only active when local player is within ACTIVATION_RANGE
--   - Auto-cleans up when battle ends or player moves away
--
-- FIX #21 Jumbotron system:
--   ViewportFrames can't render the live world directly, so we clone the
--   server-spawned battle creatures into isolated 3D viewports and sync
--   their transforms each frame. Player follow cameras clone the character
--   model. Each viewport has its own Camera, lighting, and arena floor.
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

-- ═══════════════════════════════════════════════════════════════════════════════
-- Feature toggle: controlled by GameConfig.GymJumbotronEnabled
-- When false the entire script exits immediately — zero overhead.
-- ═══════════════════════════════════════════════════════════════════════════════
if not GameConfig.GymJumbotronEnabled then
	-- Feature disabled — skip all setup, no connections, no memory
	return
end

local player = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════════════════
-- Configuration
-- ═══════════════════════════════════════════════════════════════════════════════

-- Distance (studs) from plot center within which jumbotrons activate for this client
local ACTIVATION_RANGE = 250

-- How long to wait after GymBattleInProgress goes true before scanning for creatures
-- (server spawns creatures after a 2s countdown)
local CREATURE_SCAN_DELAY = 3.5

-- Position sync throttle: sync every N render frames (1 = every frame, 2 = every other)
local SYNC_EVERY_N_FRAMES = 2

-- Creature re-scan interval (seconds) — picks up newly spawned or destroyed creatures
local RESCAN_INTERVAL = 1.0

-- Camera settings
local OVERHEAD_HEIGHT     = 55    -- studs above arena center
local OVERHEAD_FOV        = 50    -- wide FOV to capture the whole arena
local SIDE_DISTANCE       = 45    -- studs to the side of the arena
local SIDE_HEIGHT         = 8     -- studs above arena center
local SIDE_TILT_DEG       = 10    -- degrees from horizontal (slight downward look)
local SIDE_FOV            = 45    -- moderate FOV for cinematic side view
local PLAYER_CAM_DISTANCE = 14    -- studs in front of the player character
local PLAYER_CAM_HEIGHT   = 2     -- studs above the player's head
local PLAYER_CAM_FOV      = 55    -- standard FOV for player close-up
local PLAYER_CAM_LERP     = 0.12  -- smoothing factor for follow camera (0-1, lower = smoother)

-- Viewport lighting
local VIEWPORT_AMBIENT     = Color3.fromRGB(140, 140, 160)
local VIEWPORT_LIGHT_COLOR = Color3.fromRGB(255, 255, 245)
local VIEWPORT_LIGHT_DIR   = Vector3.new(-0.5, -1, -0.5)
local VIEWPORT_BG_COLOR    = Color3.fromRGB(10, 10, 18)

-- Arena floor (simple platform cloned into each viewport)
local FLOOR_COLOR    = Color3.fromRGB(25, 28, 38)
local FLOOR_MATERIAL = Enum.Material.SmoothPlastic
local FLOOR_SIZE     = Vector3.new(80, 1, 80) -- wide enough to cover the arena

-- Overlay UI colors
local LIVE_DOT_COLOR    = Color3.fromRGB(255, 40, 40)
local LABEL_TEXT_COLOR  = Color3.fromRGB(220, 220, 230)
local LABEL_BG_COLOR    = Color3.fromRGB(0, 0, 0)
local LABEL_BG_ALPHA    = 0.5

-- ═══════════════════════════════════════════════════════════════════════════════
-- Screen definitions — maps each physical part to its camera role
-- ═══════════════════════════════════════════════════════════════════════════════
local SCREEN_DEFS = {
	{
		partName   = "LeaderboardBattle",
		label      = "OVERHEAD CAM",
		cameraType = "overhead",
	},
	{
		partName   = "LeaderboardIncome",
		label      = "SIDE VIEW",
		cameraType = "side",
	},
	{
		partName   = "LeaderboardLevels",
		label      = "DEFENDER CAM",
		cameraType = "playerFollow",
		followRole = "owner",
	},
	{
		partName   = "LeaderboardMonster",
		label      = "CHALLENGER CAM",
		cameraType = "playerFollow",
		followRole = "challenger",
	},
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════════════

-- plotName → session table
local activeSessions = {}

-- Frame counter for throttled sync
local frameCounter = 0

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Safely clone a model for ViewportFrame display
-- Strips scripts, BillboardGuis, Humanoid animations — keeps visual parts only.
-- All BaseParts anchored to prevent physics simulation inside viewport.
--
-- @param model  Model — the original model from workspace
-- @return Model — the cleaned clone (NOT yet parented)
-- ═══════════════════════════════════════════════════════════════════════════════
local function cloneForViewport(model)
	local clone = model:Clone()

	-- Strip non-visual descendants
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript")
			or desc:IsA("BillboardGui") or desc:IsA("ProximityPrompt")
			or desc:IsA("ClickDetector") or desc:IsA("BodyMover")
			or desc:IsA("BodyPosition") or desc:IsA("BodyGyro")
			or desc:IsA("BodyVelocity") or desc:IsA("BodyForce")
			or desc:IsA("Sound") then
			pcall(function() desc:Destroy() end)
		end
	end

	-- Anchor everything so viewport physics don't interfere
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	return clone
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Clone a player character for ViewportFrame display
-- Anchors all parts, strips scripts and non-visual elements.
--
-- @param character Model — the player's character model
-- @return Model|nil — cleaned clone, or nil if character invalid
-- ═══════════════════════════════════════════════════════════════════════════════
local function cloneCharacterForViewport(character)
	if not character or not character.Parent then return nil end

	local ok, clone = pcall(function() return character:Clone() end)
	if not ok or not clone then return nil end

	-- Strip non-visual stuff but keep Humanoid for rendering body parts
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript")
			or desc:IsA("BillboardGui") or desc:IsA("ProximityPrompt")
			or desc:IsA("Sound") or desc:IsA("ForceField")
			or desc:IsA("BodyMover") or desc:IsA("BodyPosition")
			or desc:IsA("BodyGyro") then
			pcall(function() desc:Destroy() end)
		end
	end

	-- Anchor all parts
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	return clone
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Create a simple arena floor platform for a viewport
-- Positioned at the given center, wide enough to cover the battle area.
--
-- @param centerPos Vector3 — center of the arena in world coords
-- @return Part — the floor part (NOT yet parented)
-- ═══════════════════════════════════════════════════════════════════════════════
local function createArenaFloor(centerPos)
	local floor = Instance.new("Part")
	floor.Name = "JumbotronFloor"
	floor.Anchored = true
	floor.CanCollide = false
	floor.Size = FLOOR_SIZE
	floor.Color = FLOOR_COLOR
	floor.Material = FLOOR_MATERIAL
	floor.Position = Vector3.new(centerPos.X, centerPos.Y - 1, centerPos.Z)
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	return floor
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Create the SurfaceGui + ViewportFrame + Camera + overlay on a screen part
-- Returns a "screen" table with all references needed for updates.
--
-- @param screenPart BasePart — the physical Leaderboard part
-- @param def        table    — SCREEN_DEFS entry (cameraType, label, etc.)
-- @param arenaCenter Vector3 — center of the gym arena
-- @param arenaRight  Vector3 — unit vector pointing "right" of the arena (for side cam)
-- @return table — screen session data
-- ═══════════════════════════════════════════════════════════════════════════════
local function createViewportScreen(screenPart, def, arenaCenter, arenaRight)
	-- Remove any existing SurfaceGui on this part (leaderboard overlays etc.)
	for _, child in ipairs(screenPart:GetChildren()) do
		if child:IsA("SurfaceGui") then
			child:Destroy()
		end
	end

	-- ── SurfaceGui ──────────────────────────────────────────────────────────
	local sg = Instance.new("SurfaceGui")
	sg.Name = "JumbotronSG"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.AlwaysOnTop = false
	sg.MaxDistance = 200
	sg.Parent = screenPart

	-- ── ViewportFrame ───────────────────────────────────────────────────────
	local vf = Instance.new("ViewportFrame")
	vf.Name = "BattleViewport"
	vf.Size = UDim2.new(1, 0, 1, 0)
	vf.BackgroundColor3 = VIEWPORT_BG_COLOR
	vf.BorderSizePixel = 0
	vf.Ambient = VIEWPORT_AMBIENT
	vf.LightColor = VIEWPORT_LIGHT_COLOR
	vf.LightDirection = VIEWPORT_LIGHT_DIR
	vf.Parent = sg

	-- ── Camera ──────────────────────────────────────────────────────────────
	local cam = Instance.new("Camera")
	cam.Name = "JumbotronCam"
	cam.Parent = vf
	vf.CurrentCamera = cam

	-- Set initial camera CFrame + FOV based on type
	if def.cameraType == "overhead" then
		-- Straight down (vertical tactical view)
		cam.CFrame = CFrame.new(
			arenaCenter + Vector3.new(0, OVERHEAD_HEIGHT, 0),
			arenaCenter
		)
		cam.FieldOfView = OVERHEAD_FOV

	elseif def.cameraType == "side" then
		-- Side view: elevated, looking across the arena at ~10° from horizontal
		local sideOffset = arenaRight * SIDE_DISTANCE + Vector3.new(0, SIDE_HEIGHT, 0)
		local camPos = arenaCenter + sideOffset
		-- 10° tilt: look slightly below center
		local tiltDown = math.tan(math.rad(SIDE_TILT_DEG)) * SIDE_DISTANCE
		local lookTarget = arenaCenter + Vector3.new(0, -tiltDown * 0.1, 0)
		cam.CFrame = CFrame.new(camPos, lookTarget)
		cam.FieldOfView = SIDE_FOV

	elseif def.cameraType == "playerFollow" then
		-- Will be updated each frame; start looking at arena center
		cam.CFrame = CFrame.new(arenaCenter + Vector3.new(0, 5, PLAYER_CAM_DISTANCE), arenaCenter)
		cam.FieldOfView = PLAYER_CAM_FOV
	end

	-- ── Overlay: "LIVE" indicator (red dot + text, top-left) ────────────────
	local liveFrame = Instance.new("Frame")
	liveFrame.Name = "LiveIndicator"
	liveFrame.Size = UDim2.new(0, 120, 0, 36)
	liveFrame.Position = UDim2.new(0, 8, 0, 8)
	liveFrame.BackgroundColor3 = LABEL_BG_COLOR
	liveFrame.BackgroundTransparency = LABEL_BG_ALPHA
	liveFrame.BorderSizePixel = 0
	liveFrame.Parent = sg
	Instance.new("UICorner", liveFrame).CornerRadius = UDim.new(0, 6)

	-- Red dot
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.new(0, 12, 0, 12)
	dot.Position = UDim2.new(0, 8, 0.5, -6)
	dot.BackgroundColor3 = LIVE_DOT_COLOR
	dot.BorderSizePixel = 0
	dot.Parent = liveFrame
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

	local liveLabel = Instance.new("TextLabel")
	liveLabel.Name = "LiveText"
	liveLabel.Size = UDim2.new(1, -28, 1, 0)
	liveLabel.Position = UDim2.new(0, 26, 0, 0)
	liveLabel.BackgroundTransparency = 1
	liveLabel.Text = "LIVE"
	liveLabel.TextColor3 = LIVE_DOT_COLOR
	liveLabel.Font = Enum.Font.GothamBlack
	liveLabel.TextSize = 18
	liveLabel.TextXAlignment = Enum.TextXAlignment.Left
	liveLabel.Parent = liveFrame

	-- Pulse the red dot for that broadcast feel
	task.spawn(function()
		while dot and dot.Parent do
			local tween1 = TweenService:Create(dot, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {BackgroundTransparency = 0.6})
			tween1:Play(); tween1.Completed:Wait()
			if not dot.Parent then break end
			local tween2 = TweenService:Create(dot, TweenInfo.new(0.6, Enum.EasingStyle.Sine), {BackgroundTransparency = 0})
			tween2:Play(); tween2.Completed:Wait()
		end
	end)

	-- ── Overlay: Camera label (bottom-left) ─────────────────────────────────
	local labelFrame = Instance.new("Frame")
	labelFrame.Name = "CamLabel"
	labelFrame.Size = UDim2.new(0, 200, 0, 32)
	labelFrame.Position = UDim2.new(0, 8, 1, -40)
	labelFrame.BackgroundColor3 = LABEL_BG_COLOR
	labelFrame.BackgroundTransparency = LABEL_BG_ALPHA
	labelFrame.BorderSizePixel = 0
	labelFrame.Parent = sg
	Instance.new("UICorner", labelFrame).CornerRadius = UDim.new(0, 6)

	local camLabel = Instance.new("TextLabel")
	camLabel.Size = UDim2.new(1, -12, 1, 0)
	camLabel.Position = UDim2.new(0, 6, 0, 0)
	camLabel.BackgroundTransparency = 1
	camLabel.Text = def.label
	camLabel.TextColor3 = LABEL_TEXT_COLOR
	camLabel.Font = Enum.Font.GothamBold
	camLabel.TextSize = 16
	camLabel.TextXAlignment = Enum.TextXAlignment.Left
	camLabel.Parent = labelFrame

	-- ── Arena floor inside the viewport ─────────────────────────────────────
	local arenaFloor = createArenaFloor(arenaCenter)
	arenaFloor.Parent = vf

	-- Build the screen table
	local screen = {
		part           = screenPart,
		surfaceGui     = sg,
		viewportFrame  = vf,
		camera         = cam,
		cameraType     = def.cameraType,
		followRole     = def.followRole,
		arenaCenter    = arenaCenter,
		arenaRight     = arenaRight,
		arenaFloor     = arenaFloor,
		creatureClones = {},    -- { real = Model, clone = Model }[]
		playerClone    = nil,   -- cloned character for playerFollow screens
		playerUserId   = nil,   -- which player this follow cam tracks
		lastCamCFrame  = cam.CFrame, -- for smooth lerp on player follow
	}

	return screen
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Find all gym battle creature models inside a BaseGym folder
-- Uses CollectionService tags or falls back to searching RedTeam/BlueTeam children.
--
-- @param baseGym Folder — the BaseGym folder
-- @param plotName string — e.g. "Plot1" (for tag-based lookup)
-- @return Model[] — array of creature models currently in the arena
-- ═══════════════════════════════════════════════════════════════════════════════
local function getArenaCreatures(baseGym, plotName)
	local creatures = {}
	local tag = "GymBattleCreature_" .. plotName

	-- Try tag-based lookup first (fastest, most reliable)
	local tagged = CollectionService:GetTagged(tag)
	if #tagged > 0 then
		for _, obj in ipairs(tagged) do
			if obj:IsA("Model") and obj.Parent and obj:IsDescendantOf(baseGym) then
				table.insert(creatures, obj)
			end
		end
		return creatures
	end

	-- Fallback: search RedTeam + BlueTeam children
	for _, teamName in ipairs({"RedTeam", "BlueTeam"}) do
		local folder = baseGym:FindFirstChild(teamName)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("Model") and child.Name:match("^GymArena_") then
					table.insert(creatures, child)
				end
			end
		end
	end

	return creatures
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Sync all creature clone transforms to match real-world originals
-- Updates Position, Size, Transparency, and Color of each BasePart.
-- Removes clones whose originals have been destroyed (fainted creatures).
--
-- @param screen table — the screen session data
-- ═══════════════════════════════════════════════════════════════════════════════
local function syncCreatureClones(screen)
	for i = #screen.creatureClones, 1, -1 do
		local pair = screen.creatureClones[i]

		-- If the original was destroyed (creature fainted), destroy clone
		if not pair.real or not pair.real.Parent then
			if pair.clone and pair.clone.Parent then
				pair.clone:Destroy()
			end
			table.remove(screen.creatureClones, i)
		else
			-- Sync each BasePart in the clone to match the real model
			for _, realPart in ipairs(pair.real:GetDescendants()) do
				if realPart:IsA("BasePart") then
					-- Find matching part in clone by name (search recursively)
					local clonePart = pair.clone:FindFirstChild(realPart.Name, true)
					if clonePart and clonePart:IsA("BasePart") then
						clonePart.CFrame = realPart.CFrame
						clonePart.Size = realPart.Size
						clonePart.Transparency = realPart.Transparency
						clonePart.Color = realPart.Color
					end
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Sync a player character clone to match the real character
-- Updates HumanoidRootPart CFrame and all body part transforms.
--
-- @param screen table — the screen session data
-- @param realCharacter Model|nil — the real player character
-- ═══════════════════════════════════════════════════════════════════════════════
local function syncPlayerClone(screen, realCharacter)
	if not screen.playerClone then return end
	if not realCharacter or not realCharacter.Parent then return end

	local realRoot = realCharacter:FindFirstChild("HumanoidRootPart")
	if not realRoot then return end

	-- Sync all body parts
	for _, realPart in ipairs(realCharacter:GetDescendants()) do
		if realPart:IsA("BasePart") then
			local clonePart = screen.playerClone:FindFirstChild(realPart.Name, true)
			if clonePart and clonePart:IsA("BasePart") then
				clonePart.CFrame = realPart.CFrame
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Update the camera CFrame for a player-follow screen
-- Camera stays in front of the tracked player, facing them head-on.
-- Uses lerp for smooth, cinematic movement.
--
-- @param screen table — the screen session data
-- ═══════════════════════════════════════════════════════════════════════════════
local function updatePlayerFollowCamera(screen)
	local targetPlayer = nil
	if screen.playerUserId then
		targetPlayer = Players:GetPlayerByUserId(screen.playerUserId)
	end

	if not targetPlayer or not targetPlayer.Character then return end
	local character = targetPlayer.Character
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Position camera in front of the player, facing them
	local playerPos = rootPart.Position
	local playerLook = rootPart.CFrame.LookVector
	local camPos = playerPos + playerLook * PLAYER_CAM_DISTANCE + Vector3.new(0, PLAYER_CAM_HEIGHT, 0)
	local targetCFrame = CFrame.new(camPos, playerPos + Vector3.new(0, 1, 0))

	-- Smooth lerp for cinematic feel
	screen.lastCamCFrame = screen.lastCamCFrame:Lerp(targetCFrame, PLAYER_CAM_LERP)
	screen.camera.CFrame = screen.lastCamCFrame
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Scan for new creatures and add clones to a screen's viewport
-- Called periodically to pick up newly spawned creatures or re-sync after
-- creatures are destroyed (death visual complete → model removed).
--
-- @param screen   table  — the screen session data
-- @param baseGym  Folder — the BaseGym folder
-- @param plotName string — e.g. "Plot1"
-- ═══════════════════════════════════════════════════════════════════════════════
local function rescanCreatures(screen, baseGym, plotName)
	local realCreatures = getArenaCreatures(baseGym, plotName)

	-- Build set of already-cloned originals
	local clonedSet = {}
	for _, pair in ipairs(screen.creatureClones) do
		if pair.real then clonedSet[pair.real] = true end
	end

	-- Clone any new creatures
	for _, realModel in ipairs(realCreatures) do
		if not clonedSet[realModel] then
			local ok, clone = pcall(cloneForViewport, realModel)
			if ok and clone then
				clone.Parent = screen.viewportFrame
				table.insert(screen.creatureClones, { real = realModel, clone = clone })
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Set up or refresh the player character clone for a follow-camera screen
--
-- @param screen    table  — the screen session data
-- @param plotModel Model  — the plot model (has GymOwnerUserId/GymChallengerUserId)
-- ═══════════════════════════════════════════════════════════════════════════════
local function setupPlayerClone(screen, plotModel)
	if screen.cameraType ~= "playerFollow" then return end

	-- Determine which player to track
	local userId = nil
	if screen.followRole == "owner" then
		userId = plotModel:GetAttribute("GymOwnerUserId")
	elseif screen.followRole == "challenger" then
		userId = plotModel:GetAttribute("GymChallengerUserId")
	end

	-- Skip if already tracking the right player
	if screen.playerUserId == userId and screen.playerClone and screen.playerClone.Parent then
		return
	end

	-- Clean up old clone
	if screen.playerClone then
		pcall(function() screen.playerClone:Destroy() end)
		screen.playerClone = nil
	end

	screen.playerUserId = userId
	if not userId then return end

	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer or not targetPlayer.Character then return end

	local clone = cloneCharacterForViewport(targetPlayer.Character)
	if clone then
		clone.Parent = screen.viewportFrame
		screen.playerClone = clone
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- setupJumbotron(plotModel)
-- Called when GymBattleInProgress becomes true on a plot.
-- Creates all 4 viewport screens and starts the tracking session.
--
-- @param plotModel Model — the Plot model containing Floor4/BaseGym
-- ═══════════════════════════════════════════════════════════════════════════════
local function setupJumbotron(plotModel)
	local plotName = plotModel.Name
	if activeSessions[plotName] then return end -- already active

	local floor4 = plotModel:FindFirstChild("Floor4")
	if not floor4 then return end
	local baseGym = floor4:FindFirstChild("BaseGym")
	if not baseGym then return end

	-- Find arena center from GymCenter part
	local gymCenter = baseGym:FindFirstChild("GymCenter")
	if not gymCenter or not gymCenter:IsA("BasePart") then
		warn("[Jumbotron] No GymCenter found in " .. plotName .. "/Floor4/BaseGym")
		return
	end
	local arenaCenter = gymCenter.Position

	-- Compute arena "right" direction (perpendicular to the line between teams)
	-- Use the vector from BlueTeam center to RedTeam center as "forward"
	local blueFolder = baseGym:FindFirstChild("BlueTeam")
	local redFolder = baseGym:FindFirstChild("RedTeam")
	local arenaForward = Vector3.new(0, 0, 1) -- default
	if blueFolder and redFolder then
		-- Get average position of each team's battle points
		local function avgPos(folder)
			local sum, count = Vector3.zero, 0
			for _, c in ipairs(folder:GetChildren()) do
				if c:IsA("BasePart") then sum = sum + c.Position; count = count + 1 end
			end
			return count > 0 and (sum / count) or arenaCenter
		end
		local blueCenter = avgPos(blueFolder)
		local redCenter = avgPos(redFolder)
		local diff = (redCenter - blueCenter)
		if diff.Magnitude > 1 then
			arenaForward = Vector3.new(diff.X, 0, diff.Z).Unit
		end
	end
	-- "Right" is perpendicular to forward on the XZ plane
	local arenaRight = Vector3.new(-arenaForward.Z, 0, arenaForward.X)

	-- ── Create the 4 screens ────────────────────────────────────────────────
	local screens = {}
	local missingParts = {}

	for _, def in ipairs(SCREEN_DEFS) do
		local part = baseGym:FindFirstChild(def.partName)
		if part and part:IsA("BasePart") then
			local screen = createViewportScreen(part, def, arenaCenter, arenaRight)
			table.insert(screens, screen)
		else
			table.insert(missingParts, def.partName)
		end
	end

	if #missingParts > 0 then
		warn("[Jumbotron] Missing screen parts in " .. plotName .. ": " .. table.concat(missingParts, ", "))
	end

	if #screens == 0 then
		warn("[Jumbotron] No screen parts found in " .. plotName .. "/Floor4/BaseGym — skipping")
		return
	end

	-- ── Build session ───────────────────────────────────────────────────────
	local session = {
		plotModel    = plotModel,
		plotName     = plotName,
		baseGym      = baseGym,
		arenaCenter  = arenaCenter,
		screens      = screens,
		running      = true,
		lastRescan   = 0,
	}

	activeSessions[plotName] = session

	-- ── Initial creature scan (delayed to allow server spawning) ────────────
	task.spawn(function()
		task.wait(CREATURE_SCAN_DELAY)
		if not session.running then return end

		for _, screen in ipairs(session.screens) do
			rescanCreatures(screen, baseGym, plotName)
			setupPlayerClone(screen, plotModel)
		end
	end)

	print("[Jumbotron] Activated on " .. plotName .. " (" .. #screens .. " screens)")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- teardownJumbotron(plotName)
-- Called when GymBattleInProgress becomes nil/false or player leaves range.
-- Destroys all viewports and cleans up session state.
--
-- @param plotName string — e.g. "Plot1"
-- ═══════════════════════════════════════════════════════════════════════════════
local function teardownJumbotron(plotName)
	local session = activeSessions[plotName]
	if not session then return end

	session.running = false

	for _, screen in ipairs(session.screens) do
		-- Destroy all creature clones
		for _, pair in ipairs(screen.creatureClones) do
			if pair.clone and pair.clone.Parent then
				pair.clone:Destroy()
			end
		end
		screen.creatureClones = {}

		-- Destroy player clone
		if screen.playerClone then
			pcall(function() screen.playerClone:Destroy() end)
			screen.playerClone = nil
		end

		-- Destroy the SurfaceGui (removes viewport + camera + overlays)
		if screen.surfaceGui and screen.surfaceGui.Parent then
			screen.surfaceGui:Destroy()
		end
	end

	activeSessions[plotName] = nil
	print("[Jumbotron] Deactivated on " .. plotName)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Check if local player is within range of a plot
-- ═══════════════════════════════════════════════════════════════════════════════
local function isPlayerInRange(plotModel)
	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	local plotCenter = plotModel:FindFirstChild("PlotCenter", true)
	local refPos = plotCenter and plotCenter.Position or plotModel:GetPivot().Position
	return (root.Position - refPos).Magnitude <= ACTIVATION_RANGE
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Frame update: sync clones, update cameras, manage distance gating
-- Runs every RenderStepped frame (throttled by SYNC_EVERY_N_FRAMES).
-- ═══════════════════════════════════════════════════════════════════════════════
local function onRenderStepped()
	frameCounter = frameCounter + 1
	local doSync = (frameCounter % SYNC_EVERY_N_FRAMES) == 0

	for plotName, session in pairs(activeSessions) do
		if not session.running then continue end

		-- Periodic creature rescan
		local now = os.clock()
		if now - session.lastRescan >= RESCAN_INTERVAL then
			session.lastRescan = now
			for _, screen in ipairs(session.screens) do
				rescanCreatures(screen, session.baseGym, plotName)
				-- Refresh player clone if character respawned
				if screen.cameraType == "playerFollow" then
					setupPlayerClone(screen, session.plotModel)
				end
			end
		end

		-- Sync transforms (throttled)
		if doSync then
			for _, screen in ipairs(session.screens) do
				syncCreatureClones(screen)

				-- Sync player clone and camera for follow screens
				if screen.cameraType == "playerFollow" and screen.playerUserId then
					local targetPlayer = Players:GetPlayerByUserId(screen.playerUserId)
					if targetPlayer and targetPlayer.Character then
						syncPlayerClone(screen, targetPlayer.Character)
						updatePlayerFollowCamera(screen)
					end
				end
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- watchPlot(plotModel)
-- Watches a single plot for GymBattleInProgress attribute changes.
-- Activates jumbotron when battle starts, tears down when it ends.
--
-- @param plotModel Model — the Plot model
-- ═══════════════════════════════════════════════════════════════════════════════
local function watchPlot(plotModel)
	-- Check if battle is already in progress (late join / reconnect)
	if plotModel:GetAttribute("GymBattleInProgress") then
		-- Only activate if close enough
		task.spawn(function()
			task.wait(1) -- small delay for character to load
			if isPlayerInRange(plotModel) then
				setupJumbotron(plotModel)
			end
		end)
	end

	-- Watch for attribute changes
	plotModel:GetAttributeChangedSignal("GymBattleInProgress"):Connect(function()
		local inProgress = plotModel:GetAttribute("GymBattleInProgress")
		if inProgress then
			-- Battle started — check range before activating
			if isPlayerInRange(plotModel) then
				setupJumbotron(plotModel)
			end
		else
			-- Battle ended — tear down
			teardownJumbotron(plotModel.Name)
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Distance check loop: periodically enable/disable jumbotrons based on range
-- Activates when player walks near an active battle; deactivates when they leave.
-- ═══════════════════════════════════════════════════════════════════════════════
local function distanceCheckLoop()
	while true do
		task.wait(2)

		local plotsFolder = Workspace:FindFirstChild("BasePlots")
		if not plotsFolder then continue end

		for _, plotModel in ipairs(plotsFolder:GetChildren()) do
			local inProgress = plotModel:GetAttribute("GymBattleInProgress")
			local sessionActive = activeSessions[plotModel.Name] ~= nil
			local inRange = isPlayerInRange(plotModel)

			if inProgress and not sessionActive and inRange then
				-- Player walked into range of an active battle
				setupJumbotron(plotModel)
			elseif sessionActive and not inRange then
				-- Player walked out of range
				teardownJumbotron(plotModel.Name)
			elseif sessionActive and not inProgress then
				-- Battle ended while we had a session
				teardownJumbotron(plotModel.Name)
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Initialization
-- ═══════════════════════════════════════════════════════════════════════════════
local function init()
	-- Wait for BasePlots to exist
	local plotsFolder = Workspace:WaitForChild("BasePlots", 30)
	if not plotsFolder then
		warn("[Jumbotron] BasePlots folder not found — jumbotron system disabled")
		return
	end

	-- Watch all existing plots
	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		if plotModel:IsA("Model") then
			watchPlot(plotModel)
		end
	end

	-- Watch for new plots added at runtime (e.g., late-loaded bases)
	plotsFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.wait(0.5)
			watchPlot(child)
		end
	end)

	-- Connect frame update
	RunService.RenderStepped:Connect(onRenderStepped)

	-- Start distance check loop
	task.spawn(distanceCheckLoop)

	print("[Jumbotron] GymJumbotronClient initialized — watching BasePlots for gym battles")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Cleanup: tear down all sessions when player leaves
-- ═══════════════════════════════════════════════════════════════════════════════
Players.PlayerRemoving:Connect(function(removingPlayer)
	if removingPlayer == player then
		for plotName in pairs(activeSessions) do
			teardownJumbotron(plotName)
		end
	end
end)

-- Start
init()
