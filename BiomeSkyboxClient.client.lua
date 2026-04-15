-- ══════════════════════════════════════════════════════════════════════════════
-- BiomeSkyboxClient.client.lua
-- Dynamically swaps the Lighting skybox based on which biome zone the player
-- is currently standing in. Supports:
--   • 4 outer biome baseplates (Desert, Electric, Water, Cave)
--   • Hub area + road surfaces (all use ArenaSky)
--   • 4 inner biome wedges between spoke-roads (Forest, Wind, Ice, Fire)
--   • Fallback to ArenaSky when no zone matches
--
-- Setup requirements:
--   1. Sky objects in ReplicatedStorage.SkyBox folder, named:
--      ArenaSky, BattleSky (hub/roads during workspace.ArenaBattleInProgress — optional but recommended),
--      DesertSky, ElectricSky, WaterSky,
--      ForestSky, WindSky, IceSky, FireSky
--   2. Outer baseplates in workspace.Terrain:
--      DesertBaseplate, ElectricBaseplate, OceanBaseplate, CaveBaseplate
--   3. Hub ground part at workspace.HubArea.HubGround
--   4. Road parts in workspace.Roads:
--      CaveRoad, ElectricRoad, DesertRoad, WetRoad
--      (arranged as spokes radiating from hub center)
--   5. This script placed in StarterPlayerScriptsdfs
--
-- Detection priority:
--   1. Outer baseplates (XZ bounding box + vertical buffer)
--   2. Hub ground / roads (XZ bounding box)
--   3. Inner wedge between two roads (angle from hub center)s
--   4. Fallback → ArenaSky
-- ══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local biomeCfg = GameConfig.BiomeSkybox or {}

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIGURATION.
-- ══════════════════════════════════════════════════════════════════════════════

--- Maximum studs above a baseplate/part that still counts as "over" it
local VERTICAL_BUFFER = 900

--- Roads and hub ground are thin/flat; players going "vertical" in interior
--- zones should NOT have their sky overridden by these ground parts.
--- Keep this small so sky selection is effectively based on XZ for interior
--- wedges, even while airborne.
local GROUND_VERTICAL_BUFFER = 100

--- How often to check position (seconds). 0 = every frame.
local CHECK_INTERVAL = 0.1

--- Default/fallback sky name (hub, roads, and anywhere unmatched)
local DEFAULT_SKY = "ArenaSky"

--- During workspace.ArenaBattleInProgress, hub/roads/default resolve to this sky (if present in SkyBox)
local BATTLE_SKY_NAME = (type(biomeCfg.BattleSkyName) == "string" and biomeCfg.BattleSkyName ~= "") and biomeCfg.BattleSkyName or "BattleSky"

--- Timeout (seconds) for WaitForChild calls during setup
local WAIT_TIMEOUT = 15

--- Maximum XZ distance (studs) from hub center that inner-wedge detection applies...
--- Beyond this radius the player is in an outer biome zone, not an inner wedge.
--- Set this to roughly the distance from hub center to the nearest outer baseplate edge.
local INNER_WEDGE_MAX_RADIUS = 1200

-- ══════════════════════════════════════════════════════════════════════════════
-- ZONE DEFINITIONS
-- ══════════════════════════════════════════════════════════════════════════════

--- Outer biomes: each has a single baseplate Part whose XZ footprint defines
--- the zone boundary.
--- @field path string[] — ancestor chain under workspace to reach the part
--- @field sky  string   — name of the Sky object in ReplicatedStorage.SkyBox
local OUTER_ZONES = {
	{ path = {"Terrain", "DesertBaseplate"},   sky = "DesertSky" },
	{ path = {"Terrain", "ElectricBaseplate"}, sky = "ElectricSky" },
	{ path = {"Terrain", "OceanBaseplate"},    sky = "WaterSky" },
	{ path = {"Terrain", "CaveBaseplate"},     sky = "CaveSky" },
}

--- Hub ground parts that use the default arena skybox.
--- Each entry is an ancestor path under workspace
local HUB_PARTS = {
	{"HubArea", "HubGround"},
}

--- Road part names (children of workspace.Roads). All roads → ArenaSky.
--- Also used to compute spoke angles for inner-wedge detection.
local ROAD_NAMES = { "CaveRoad", "ElectricRoad", "DesertRoad", "WetRoad" }

--- Inner biome wedges between two adjacent roads (clockwise sweep order).
--- Road angles (from debug logs):
---   ElectricRoad ≈ -180°  (West / -X)
---   CaveRoad     ≈  -90°  (North / -Z)sd
---   WetRoad      ≈    0°  (East / +X)
---   DesertRoad   ≈   90°  (South / +Z)
--- Clockwise order: Electric → Cave → Wet → Desert → Electric
--- @field from string — name of the starting road spoke
--- @field to   string — name of the ending road spoke (clockwise)
--- @field sky  string — Sky object name for this wedge
local INNER_WEDGES = {
	{ from = "ElectricRoad", to = "CaveRoad",     sky = "EarthSky" },  -- NW: between Electric(-180°) and Cave(-90°)
	{ from = "CaveRoad",     to = "WetRoad",      sky = "FireSky" },   -- NE: between Cave(-90°) and Wet(0°)
	{ from = "WetRoad",      to = "DesertRoad",   sky = "IceSky" },    -- SE: between Wet(0°) and Desert(90°)
	{ from = "DesertRoad",   to = "ElectricRoad", sky = "WindSky" },   -- SW: between Desert(90°) and Electric(180°)
}

-- ══════════════════════════════════════════════════════════════════════════════
-- SKYBOX LOADING
-- Load all Sky objects from ReplicatedStorage.Skybox into a lookup table.
-- Each sky is cloned so we can freely parent/unparent without losing originals.
-- ══════════════════════════════════════════════════════════════════════════════

local skyboxFolder = ReplicatedStorage:WaitForChild("SkyBox", WAIT_TIMEOUT)
if not skyboxFolder then
	warn("[BiomeSkybox] Could not find ReplicatedStorage.Skybox folder — skybox system disabled")
	return
end

--- Lookup table: skyName → cloned Sky instance (parented to nil until active)
local skyCache = {}

for _, child in ipairs(skyboxFolder:GetChildren()) do
	if child:IsA("Sky") then
		local clone = child:Clone()
		clone.Name = child.Name .. "_Active"
		skyCache[child.Name] = clone
	end
end

-- Verify we have the default sky at minimum
if not skyCache[DEFAULT_SKY] then
	warn("[BiomeSkybox] Missing '" .. DEFAULT_SKY .. "' in Skybox folder — skybox system disabled")
	return
end

if not skyCache[BATTLE_SKY_NAME] then
	warn("[BiomeSkybox] Missing '" .. BATTLE_SKY_NAME .. "' in Skybox folder — arena battles will keep " .. DEFAULT_SKY .. " visuals until you add it")
end

-- ══════════════════════════════════════════════════════════════════════════════
-- CAPTURE & REMOVE THE INITIAL LIGHTING SKY
-- We take ownership of Lighting's sky slot; the initial sky is replaced by2
-- our managed ArenaSky on startup.
-- ══════════════════════════════════════════════════════════════════════════════

-- Remove whatever sky is currently in Lighting so we start clean
local initialSky = Lighting:FindFirstChildOfClass("Sky")
if initialSky then
	initialSky.Parent = nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- PART RESOLUTION
-- Safely find workspace parts, warn if missing but continue gracefully.
-- ══════════════════════════════════════════════════════════════════════════════

--- Walk a path of child names starting from workspace.dffd
--- @param pathParts string[] — e.g. {"Terrain", "DesertBaseplate"}
--- @return BasePart|nil
local function resolveWorkspacePart(pathParts)
	local current = workspace
	for _, name in ipairs(pathParts) do
		current = current:WaitForChild(name, WAIT_TIMEOUT)
		if not current then
			return nil
		end
	end
	return current
end

-- Resolve outer-zone parts
--- @type {part: BasePart, sky: string}[]
local outerZones = {}
for _, def in ipairs(OUTER_ZONES) do
	local part = resolveWorkspacePart(def.path)
	if part then
		table.insert(outerZones, { part = part, sky = def.sky })
	else
		warn("[BiomeSkybox] Missing outer zone part: workspace." .. table.concat(def.path, "."))
	end
end

-- Resolve hub parts
--- @type BasePart[]
local hubParts = {}
for _, pathParts in ipairs(HUB_PARTS) do
	local part = resolveWorkspacePart(pathParts)
	if part then
		table.insert(hubParts, part)
	else
		warn("[BiomeSkybox] Missing hub part: workspace." .. table.concat(pathParts, "."))
	end
end

-- Resolve road parts
--- @type {[string]: BasePart}  — roadName → Part
local roadParts = {}
--- @type BasePart[]  — flat list for bounding-box checks
local roadPartList = {}
local roadsFolder = workspace:WaitForChild("Roads", WAIT_TIMEOUT)
if roadsFolder then
	for _, name in ipairs(ROAD_NAMES) do
		local part = roadsFolder:WaitForChild(name, WAIT_TIMEOUT)
		if part then
			roadParts[name] = part
			table.insert(roadPartList, part)
		else
			warn("[BiomeSkybox] Missing road part: workspace.Roads." .. name)
		end
	end
else
	warn("[BiomeSkybox] Missing workspace.Roads folder — road/wedge detection disabled")
end

-- ══════════════════════════════════════════════════════════════════════════════
-- PRECOMPUTE ROAD SPOKE ANGLES (for inner-wedge detection)
-- Each road's angle is measured from the hub center on the XZ plane.
-- ══════════════════════════════════════════════════════════════════════════════

--- Hub center position (XZ) used as origin for angle calculations
local hubCenter = Vector3.new(0, 0, 0)
if #hubParts > 0 then
	hubCenter = hubParts[1].Position
end

--- Precomputed angle (radians) for each road, measured from hubCenter..
--- @type {[string]: number}
local roadAngles = {}
for name, part in pairs(roadParts) do
	local dx = part.Position.X - hubCenter.X
	local dz = part.Position.Z - hubCenter.Z
	roadAngles[name] = math.atan2(dz, dx)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- GEOMETRY HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

--- Check if a world position is within a Part's XZ footprint and within
--- VERTICAL_BUFFER studs above its top surface.
--- Works correctly with rotated parts by transforming to local space.
--- @param position Vector3 — player world position
--- @param part     BasePart
--- @return boolean
local function isOverPart(position, part, verticalBuffer)
	verticalBuffer = verticalBuffer or GROUND_VERTICAL_BUFFER
	local cf = part.CFrame
	local size = part.Size
	local localPos = cf:PointToObjectSpace(position)

	local halfX = size.X / 2
	local halfZ = size.Z / 2
	local halfY = size.Y / 2

	-- XZ bounds
	if math.abs(localPos.X) > halfX then return false end
	if math.abs(localPos.Z) > halfZ then return false end

	-- Y bounds: above bottom, within vertical buffer above top
	if localPos.Y < -halfY then return false end
	if localPos.Y > halfY + verticalBuffer then return false end

	return true
end

--- Check if a world position is within a Part's XZ footprint, ignoring height.
--- Used to ensure outer baseplates always take priority over inner wedges even
--- when the player is far above the baseplate (beyond VERTICAL_BUFFER).
--- FIX: Prevents inner wedge skybox from showing when the player is above an
--- outer baseplate but beyond its vertical buffer.
--- @param position Vector3 — player world position
--- @param part     BasePart
--- @return boolean
local function isOverPartXZ(position, part)
	local cf = part.CFrame
	local size = part.Size
	local localPos = cf:PointToObjectSpace(position)

	local halfX = size.X / 2
	local halfZ = size.Z / 2

	-- XZ bounds only — no height check
	if math.abs(localPos.X) > halfX then return false end
	if math.abs(localPos.Z) > halfZ then return false end

	return true
end

--- Normalize an angle to the range (-π, π].
--- @param a number — angle in radians
--- @return number
local function normalizeAngle(a)
	a = a % (2 * math.pi)
	if a > math.pi then
		a = a - 2 * math.pi
	end
	return a
end

--- Check if angle `a` falls within the clockwise sweep from `fromAngle` to
--- `toAngle`. "Clockwise" here means increasing angle on the XZ plane
--- (atan2 convention).
--- @param a         number — test angle (radians)
--- @param fromAngle number — start of sector (radians)
--- @param toAngle   number — end of sector (radians)
--- @return boolean
local function isAngleBetween(a, fromAngle, toAngle)
	-- Normalize everything relative to fromAngle so the sector starts at 0
	local sweep = normalizeAngle(toAngle - fromAngle)
	local test  = normalizeAngle(a - fromAngle)

	-- Handle the two cases: sector doesn't wrap vs. wraps around ±π
	if sweep > 0 then
		-- Normal case: sector spans [0, sweep]
		return test >= 0 and test <= sweep
	else
		-- Wrapped case: sector spans [0, sweep+2π] effectively
		-- i.e. test is NOT in the excluded range (sweep, 0)
		return test >= 0 or test <= sweep
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- ZONE DETECTION
-- Determines which sky name should be active for the given player position.
-- ══════════════════════════════════════════════════════════════════════════════

--- Raw biome sky (no arena-battle override).
--- Priority: outer baseplates → hub → roads → inner wedge → fallback.
--- @param position Vector3 — player world position
--- @return string — name of the Sky object to display
local function getSkyRawForPosition(position)
	-- Priority 1: Outer biome baseplates
	for _, zone in ipairs(outerZones) do
		if isOverPart(position, zone.part, VERTICAL_BUFFER) then
			return zone.sky
		end
	end

	-- Priority 2: Hub ground
	for _, part in ipairs(hubParts) do
		if isOverPart(position, part, GROUND_VERTICAL_BUFFER) then
			return DEFAULT_SKY
		end
	end

	-- Priority 3: Roads (all → ArenaSky)
	for _, part in ipairs(roadPartList) do
		if isOverPart(position, part, GROUND_VERTICAL_BUFFER) then
			return DEFAULT_SKY
		end
	end

	-- Priority 3.5: XZ-only outer baseplate check (no height limit)
	-- FIX: If the player is anywhere above an outer baseplate's XZ footprint
	-- (even far above it, beyond VERTICAL_BUFFER), use the outer sky.
	-- This prevents inner wedge radial detection from overriding the outer
	-- baseplate skybox when the inner wedge radius extends into outer territory.
	for _, zone in ipairs(outerZones) do
		if isOverPartXZ(position, zone.part) then
			return zone.sky
		end
	end

	-- Priority 4: Inner biome wedge (angle-based)
	-- Only attempt if we have hub center, road angles, AND the player is within
	-- INNER_WEDGE_MAX_RADIUS of hub center. Beyond that radius, the player is
	-- in an outer biome zone and should NOT match an inner wedge.
	if hubCenter and next(roadAngles) then
		local dx = position.X - hubCenter.X
		local dz = position.Z - hubCenter.Z
		local distFromHub = math.sqrt(dx * dx + dz * dz)

		if distFromHub <= INNER_WEDGE_MAX_RADIUS then
			local playerAngle = math.atan2(dz, dx)

			for _, wedge in ipairs(INNER_WEDGES) do
				local fromAngle = roadAngles[wedge.from]
				local toAngle   = roadAngles[wedge.to]
				if fromAngle and toAngle then
					if isAngleBetween(playerAngle, fromAngle, toAngle) then
						return wedge.sky
					end
				end
			end
		end
	end

	-- Priority 5: Fallback
	return DEFAULT_SKY
end

--- When a main arena battle is running, swap hub/road/default (ArenaSky) to the battle sky for all players.
local function resolveArenaBattleSky(baseSky)
	if workspace:GetAttribute("ArenaBattleInProgress") ~= true then
		return baseSky
	end
	if baseSky ~= DEFAULT_SKY then
		return baseSky
	end
	if skyCache[BATTLE_SKY_NAME] then
		return BATTLE_SKY_NAME
	end
	return baseSky
end

--- @param position Vector3
--- @return string — final sky name after arena-round override
local function getSkyForPosition(position)
	return resolveArenaBattleSky(getSkyRawForPosition(position))
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SKYBOX SWAP LOGIC — SMOOTH CROSSFADE
-- When the biome changes, both the old and new Sky objects live in Lighting
-- simultaneously. The old sky fades OUT (transparency → 1) while the new sky
-- fades IN (transparency → 0) over TRANSITION_DURATION seconds, creating a
-- seamless blend between biomes.
-- ══════════════════════════════════════════════════════════════════════════════

--- Duration in seconds for the crossfade transition between skyboxes
local TRANSITION_DURATION = 3

--- The six face properties on a Sky object that control image transparency
local SKY_FACE_PROPERTIES = {
	"SkyboxBk", "SkyboxDn", "SkyboxFt",
	"SkyboxLf", "SkyboxRt", "SkyboxUp",
}

--- Currently active sky name (nil = nothing set yet)
local currentSkyName = nil

--- Monotonically increasing ID to detect when a newer transition supersedes this one
local transitionId = 0

--- Set the transparency of all six face images on a Sky object.
--- @param sky Sky — the sky instance to modify
--- @param alpha number — 0 = fully visible, 1 = fully transparent
local function setSkyTransparency(sky, alpha)
	-- Clamp to [0, 1] for safety
	alpha = math.clamp(alpha, 0, 1)

	-- StarsMeshPart / CelestialBodiesShown don't have per-face transparency,
	-- but SkyboxBk..Up do NOT have a native transparency property either.
	-- Instead we overlay by setting the StarCount and SunAngularSize/MoonAngularSize
	-- to hide celestial bodies during the blend, and use a ColorCorrection trick.
	--
	-- FIX: Roblox Sky objects don't have per-face transparency. The correct
	-- approach is to tween all six face ASSET strings would flicker. Instead we
	-- use a pair of ColorCorrectionEffect objects — one tints the outgoing sky
	-- to match the incoming sky. But the simplest and most reliable approach is:
	-- We actually CAN NOT fade Sky face images natively.
	--
	-- REVISED APPROACH: We keep both skies in Lighting. Roblox renders the LAST
	-- Sky added. So we parent the new sky after the old one, then after a delay
	-- remove the old one. For a smooth visual blend we use a ColorCorrectionEffect
	-- that briefly fades to a neutral tint and back.

	-- This function is now used for the ColorCorrection-based fade (see below).
end

--- Swap the Lighting sky to the given sky name with a smooth crossfade.
--- No-op if already displaying that sky.
--- @param skyName string — key into skyCache (e.g. "DesertSky")
local function setSky(skyName)
	if skyName == currentSkyName then return end

	-- Resolve the target sky object
	local newSky = skyCache[skyName]
	if not newSky then
		warn("[BiomeSkybox] Sky '" .. skyName .. "' not found in cache, using " .. DEFAULT_SKY)
		skyName = DEFAULT_SKY
		newSky = skyCache[DEFAULT_SKY]
		if not newSky then return end
	end

	-- If no current sky (first load), just parent immediately with no transition
	if not currentSkyName then
		newSky.Parent = Lighting
		currentSkyName = skyName
		-- Publish sky name so other systems (e.g. GameplayMusic) can react to biome changes
		localPlayer:SetAttribute("CurrentSkyName", skyName)
		return
	end

	-- Grab the old sky before we update the name
	local oldSkyName = currentSkyName
	local oldSky = skyCache[oldSkyName]
	currentSkyName = skyName
	-- Publish sky name so other systems (e.g. GameplayMusic) can react to biome changes
	localPlayer:SetAttribute("CurrentSkyName", skyName)

	-- Bump transition ID so any in-progress transition cancels itself
	transitionId += 1
	local myId = transitionId

	-- Spawn the crossfade coroutine so it doesn't block the heartbeat loop
	task.spawn(function()
		-- ── Phase 1: Create a temporary ColorCorrectionEffect for the fade ──
		-- We fade screen brightness down to a tint, swap the sky mid-fade,
		-- then fade back up. This creates a smooth dissolve illusion.
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "BiomeSkyTransition"
		cc.Brightness = 0
		cc.Contrast = 0
		cc.Saturation = 0
		cc.TintColor = Color3.new(1, 1, 1)
		cc.Parent = Lighting

		local halfDuration = TRANSITION_DURATION / 2
		local elapsed = 0

		-- ── Phase 1a: Fade OUT (darken / whiteout) ──────────────────────────
		-- Gradually reduce brightness to obscure the sky swap
		while elapsed < halfDuration do
			if transitionId ~= myId then
				-- A newer transition started — bail out and let it take overs
				cc:Destroy()
				return
			end
			local dt = task.wait()
			elapsed += dt
			local t = math.clamp(elapsed / halfDuration, 0, 1)
			-- Ease-in-out using smoothstep for a natural feel
			local smooth = t * t * (3 - 2 * t)
			cc.Brightness = -smooth * 0.2  -- darken to 60% black at midpoint
		end

		-- ── Phase 2: Swap the sky at the darkest point ──────────────────────
		if transitionId ~= myId then
			cc:Destroy()
			return
		end
		if oldSky and oldSky.Parent == Lighting then
			oldSky.Parent = nil
		end
		newSky.Parent = Lighting

		-- ── Phase 3: Fade back IN ───────────────────────────────────────────
		elapsed = 0
		while elapsed < halfDuration do
			if transitionId ~= myId then
				cc:Destroy()
				return
			end
			local dt = task.wait()
			elapsed += dt
			local t = math.clamp(elapsed / halfDuration, 0, 1)
			local smooth = t * t * (3 - 2 * t)
			cc.Brightness = -0.6 * (1 - smooth)  -- rise from -0.6 back to 0
		end

		-- ── Cleanup ─────────────────────────────────────────────────────────
		cc.Brightness = 0
		cc:Destroy()
	end)
end

-- Set initial sky to default (instant, no transition)
setSky(resolveArenaBattleSky(DEFAULT_SKY))

-- Re-evaluate immediately when a main arena battle starts or ends (all clients)
workspace:GetAttributeChangedSignal("ArenaBattleInProgress"):Connect(function()
	local character = localPlayer.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	setSky(getSkyForPosition(rootPart.Position))
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- MAIN LOOP
-- Runs on Heartbeat with a configurable check interval for performance.
-- ══════════════════════════════════════════════════════════════════════════════

task.spawn(function()
	local interval = math.max(0.05, CHECK_INTERVAL)
	local lastEvalPos = nil
	local lastEvalClock = 0
	local POSITION_EPSILON = 1.5
	local MAX_IDLE_SKIP = 0.5
	while true do
		task.wait(interval)
		local character = localPlayer.Character
		if not character then
			continue
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		local now = os.clock()
		local pos = rootPart.Position
		if lastEvalPos then
			local moved = (pos - lastEvalPos).Magnitude
			if moved < POSITION_EPSILON and (now - lastEvalClock) < MAX_IDLE_SKIP then
				continue
			end
		end
		lastEvalPos = pos
		lastEvalClock = now

		local skyName = getSkyForPosition(pos)

		setSky(skyName)
	end
end)
