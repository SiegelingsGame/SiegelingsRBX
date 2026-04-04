--[[
  BaseExteriorSystem.lua - ServerScriptService (ModuleScript)
  ===========================================================
  Backend for updating the exterior of a player's base.
  Uses Floor 3 as the reference: its size = outer (farther) bound,
  Floor 3 wall height = highest wall point, with space above for toppers/decoration.
  Designed to work with a UI agent (remotes + clear API).

  Bounds (from Floor3):
    - fartherBoundXZ: half-extent in X/Z (Floor 3 platform/walls)
    - wallHeightFloor3: height of Floor 3 walls
    - topOfWallsY: highest wall point (model space)
    - decorationSpaceAbove: studs reserved for toppers/decoration
    - decorationTopY: top of decoration zone (model space)

  UI AGENT API (call from client or UI scripts):
    local Events = ReplicatedStorage:WaitForChild("Events")
    -- Get bounds for current player's plot (decorationSpaceAbove optional, default 8)
    local bounds = Events.GetExteriorBounds:InvokeServer(decorationSpaceAbove)
    -- bounds.success, bounds.halfSizeX, bounds.halfSizeZ, bounds.topOfWallsY, bounds.decorationTopY, bounds.worldCFrame, etc.
    -- Get build instructions (contract + theme) for a theme name
    local instructions = Events.GetBuildInstructions:InvokeServer("HauntedHouse")
    -- Refresh exterior / decoration zone (e.g. after base structure change)
    Events.RefreshExterior:FireServer()
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GameConfig = nil
pcall(function() GameConfig = require(ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("GameConfig", 5)) end)

local BaseExteriorSystem = {}

local PlayerDataManager = nil
local eventsFolder = nil
local InstructionsModule = nil
local GeneratorModule = nil

-- Default decoration space above highest wall (studs)
local DEFAULT_DECORATION_SPACE = 8

-- Optional: load Instructions and Generator (same folder or ReplicatedStorage.Modules)
do
	local SSS = game:GetService("ServerScriptService")
	local parent = SSS:FindFirstChild("BaseExteriorSystem") and SSS or SSS.Parent
	pcall(function()
		InstructionsModule = require(parent:FindFirstChild("BaseBuildInstructions_HauntedHouse") or SSS:FindFirstChild("BaseBuildInstructions_HauntedHouse"))
	end)
	pcall(function()
		GeneratorModule = require(parent:FindFirstChild("HauntedHouseBaseGenerator") or SSS:FindFirstChild("HauntedHouseBaseGenerator"))
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BOUNDS FROM FLOOR 3
-- ═══════════════════════════════════════════════════════════════════════════
-- Uses Floor 3 size as farther bound, Floor 3 wall height as highest wall,
-- plus space above for toppers/decoration.

--- Get the Floor3 folder from a plot model.
local function getFloor3(plotModel)
	if not plotModel then return nil end
	return plotModel:FindFirstChild("Floor3")
end

--- Compute axis-aligned bounds of a folder's BaseParts in model space (plot's pivot = origin).
local function getFolderAABB(folder, plotModel)
	local modelPivot = plotModel and plotModel:GetPivot() or CFrame.new()
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("BasePart") then
			local cf = modelPivot:PointToObjectSpace(desc.Position)
			local s = desc.Size
			local rx, ry, rz = s.X/2, s.Y/2, s.Z/2
			lo = Vector3.new(math.min(lo.X, cf.X - rx), math.min(lo.Y, cf.Y - ry), math.min(lo.Z, cf.Z - rz))
			hi = Vector3.new(math.max(hi.X, cf.X + rx), math.max(hi.Y, cf.Y + ry), math.max(hi.Z, cf.Z + rz))
		end
	end
	if lo.X == math.huge then return nil, nil end
	return lo, hi
end

--- Get wall height from Floor3 by finding Wall* parts and taking max Y extent.
local function getFloor3WallHeight(floor3, plotModel)
	local modelPivot = plotModel and plotModel:GetPivot() or CFrame.new()
	local maxTop = -math.huge
	for _, desc in ipairs(floor3:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:match("^Wall") then
			local cf = modelPivot:PointToObjectSpace(desc.Position)
			local top = cf.Y + desc.Size.Y/2
			if top > maxTop then maxTop = top end
		end
	end
	if maxTop == -math.huge then return nil, nil end
	-- Floor level from FloorBase
	local floorBase = floor3:FindFirstChild("FloorBase") or floor3:FindFirstChild("Floor3_Base")
	local floorY = 0
	if floorBase then
		floorY = (modelPivot:PointToObjectSpace(floorBase.Position)).Y
	end
	local wallHeight = maxTop - floorY
	return wallHeight, maxTop
end

--- Compute exterior bounds from Floor3. Returns table for UI agent.
-- @param plotModel Model - the plot (e.g. Plot1 under BasePlots)
-- @param decorationSpaceAbove number|nil - studs above top of walls for toppers (default DEFAULT_DECORATION_SPACE)
-- @return table|nil { halfSizeX, halfSizeZ, sizeX, sizeZ, wallHeightFloor3, topOfWallsY, decorationSpaceAbove, decorationTopY, floor3CenterY, worldCFrame, success }
function BaseExteriorSystem.GetExteriorBounds(plotModel, decorationSpaceAbove)
	decorationSpaceAbove = decorationSpaceAbove or DEFAULT_DECORATION_SPACE
	local plotPivot = plotModel and plotModel:GetPivot() or CFrame.new()
	local floor3 = getFloor3(plotModel)
	if not floor3 then
		-- No Floor3: use whole-plot bounds (any structure works)
		local bounds = BaseExteriorSystem.GetPlotBoundsFromModel(plotModel)
		if not bounds then
			return { success = false, error = "Plot has no parts", worldCFrame = plotPivot }
		end
		return {
			success = true,
			halfSizeX = bounds.halfSizeX, halfSizeZ = bounds.halfSizeZ,
			sizeX = bounds.sizeX, sizeZ = bounds.sizeZ,
			wallHeightFloor3 = bounds.wallHeight,
			topOfWallsY = bounds.topY,
			decorationSpaceAbove = decorationSpaceAbove,
			decorationTopY = bounds.topY + decorationSpaceAbove,
			floor3CenterY = bounds.floorY + bounds.wallHeight / 2,
			worldCFrame = bounds.worldCFrame,
			plotName = plotModel.Name,
		}
	end

	local plotPivot = plotModel:GetPivot()
	local lo, hi = getFolderAABB(floor3, plotModel)
	if not lo or not hi then
		return {
			success = false,
			error = "Floor3 has no BaseParts",
			worldCFrame = plotPivot,
		}
	end

	local wallHeight, topOfWallsY = getFloor3WallHeight(floor3, plotModel)
	if not wallHeight then
		topOfWallsY = hi.Y
		wallHeight = hi.Y - lo.Y
	end

	local halfSizeX = (hi.X - lo.X) / 2
	local halfSizeZ = (hi.Z - lo.Z) / 2
	local sizeX, sizeZ = hi.X - lo.X, hi.Z - lo.Z
	local floor3CenterY = (lo.Y + hi.Y) / 2
	local decorationTopY = topOfWallsY + decorationSpaceAbove

	return {
		success = true,
		halfSizeX = halfSizeX,
		halfSizeZ = halfSizeZ,
		sizeX = sizeX,
		sizeZ = sizeZ,
		fartherBoundXZ = math.max(halfSizeX, halfSizeZ),
		wallHeightFloor3 = wallHeight,
		topOfWallsY = topOfWallsY,
		decorationSpaceAbove = decorationSpaceAbove,
		decorationTopY = decorationTopY,
		floor3CenterY = floor3CenterY,
		worldCFrame = plotPivot,
		plotName = plotModel.Name,
	}
end

--- Get or create a DecorationZone folder in the plot for UI agent to place toppers.
-- Puts an invisible anchored part at decoration height as a reference (optional).
function BaseExteriorSystem.GetOrCreateDecorationZone(plotModel, decorationSpaceAbove)
	local bounds = BaseExteriorSystem.GetExteriorBounds(plotModel, decorationSpaceAbove)
	if not bounds or not bounds.success then return nil, bounds end

	local exteriorFolder = plotModel:FindFirstChild("Exterior")
	if not exteriorFolder then
		exteriorFolder = Instance.new("Folder")
		exteriorFolder.Name = "Exterior"
		exteriorFolder.Parent = plotModel
	end

	local zoneFolder = exteriorFolder:FindFirstChild("DecorationZone")
	if not zoneFolder then
		zoneFolder = Instance.new("Folder")
		zoneFolder.Name = "DecorationZone"
		zoneFolder.Parent = exteriorFolder
	end

	-- Optional: marker part at center of decoration zone (for UI to position toppers)
	local marker = zoneFolder:FindFirstChild("DecorationTopMarker")
	if not marker then
		marker = Instance.new("Part")
		marker.Name = "DecorationTopMarker"
		marker.Size = Vector3.new(1, 0.5, 1)
		marker.Transparency = 1
		marker.CanCollide = false
		marker.Anchored = true
		marker.Parent = zoneFolder
	end
	local worldTop = bounds.worldCFrame * Vector3.new(0, bounds.decorationTopY, 0)
	marker.Position = worldTop
	marker:SetAttribute("DecorationTopY", bounds.decorationTopY)
	marker:SetAttribute("TopOfWallsY", bounds.topOfWallsY)
	marker:SetAttribute("HalfSizeX", bounds.halfSizeX)
	marker:SetAttribute("HalfSizeZ", bounds.halfSizeZ)

	return zoneFolder, bounds
end

--- Refresh exterior: recompute bounds and update Exterior/DecorationZone. Call after base structure changes.
function BaseExteriorSystem.RefreshExterior(plotModel, options)
	options = options or {}
	local bounds = BaseExteriorSystem.GetExteriorBounds(plotModel, options.decorationSpaceAbove)
	if not bounds or not bounds.success then return bounds end
	BaseExteriorSystem.GetOrCreateDecorationZone(plotModel, options.decorationSpaceAbove)
	return bounds
end

--- Return build instructions for a theme (for UI agent to read contract + theme spec).
function BaseExteriorSystem.GetBuildInstructions(themeName)
	themeName = themeName or "HauntedHouse"
	if InstructionsModule then
		return InstructionsModule
	end
	-- Fallback minimal contract for UI
	return {
		StructureContract = {
			Floors = { "Floor1", "Floor2", "Floor3" },
			PlotRequiredChildren = { "PlotCenter", "SignPart" },
		},
		Theme = themeName,
		ThemeBrief = "Use Floor3 size as exterior bound; Floor3 wall height as highest wall; space above for toppers.",
	}
end

--- Get plot model for a player (by plotId from PlayerDataManager).
function BaseExteriorSystem.GetPlotForPlayer(player)
	if not PlayerDataManager then return nil end
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return nil end
	local plotsFolder = Workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return nil end
	return plotsFolder:FindFirstChild("Plot" .. data.plotId) or plotsFolder:FindFirstChild("Part" .. data.plotId)
end

--- Get exterior bounds for the current player's plot (for UI agent).
function BaseExteriorSystem.GetExteriorBoundsForPlayer(player, decorationSpaceAbove)
	local plot = BaseExteriorSystem.GetPlotForPlayer(player)
	if not plot then return { success = false, error = "No plot" } end
	return BaseExteriorSystem.GetExteriorBounds(plot, decorationSpaceAbove)
end

--- Optional: build a full plot using HauntedHouseBaseGenerator (for testing or initial placement).
function BaseExteriorSystem.BuildPlot(plotId, position, parentFolder)
	if GeneratorModule and GeneratorModule.BuildPlot then
		return GeneratorModule.BuildPlot(plotId, position, parentFolder)
	end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- THEME SKIN: recolor existing parts (except glass) + add exterior shell (door, windows)
-- Does NOT delete or replace the plot; works on whatever structure the player has.
-- ═══════════════════════════════════════════════════════════════════════════

local THEME_PALETTES = {
	HauntedHouse = {
		Wall   = { Color = Color3.fromRGB(35, 32, 45),  Material = Enum.Material.Brick },
		Floor  = { Color = Color3.fromRGB(45, 42, 55),  Material = Enum.Material.Slate },
		Trim   = { Color = Color3.fromRGB(80, 40, 100), Material = Enum.Material.Wood },
		Point  = { Color = Color3.fromRGB(50, 45, 60),  Material = Enum.Material.Concrete },
		Stairs = { Color = Color3.fromRGB(55, 50, 65), Material = Enum.Material.Wood },
		Sign   = { Color = Color3.fromRGB(30, 28, 38), Material = Enum.Material.Wood },
		Door   = { Color = Color3.fromRGB(40, 35, 25), Material = Enum.Material.Wood },
		Window = { Color = Color3.fromRGB(25, 22, 35), Material = Enum.Material.Concrete },
		-- Floor 4 gym battle team colors (must contrast with dark purple theme)
		GymBlueTeam = Color3.fromRGB(60, 140, 220),
		GymRedTeam  = Color3.fromRGB(200, 60, 60),
	},
	RetroArcade = {
		Wall   = { Color = Color3.fromRGB(20, 10, 40),  Material = Enum.Material.Neon },
		Floor  = { Color = Color3.fromRGB(25, 15, 45),  Material = Enum.Material.SmoothPlastic },
		Trim   = { Color = Color3.fromRGB(255, 50, 150), Material = Enum.Material.Neon },
		Point  = { Color = Color3.fromRGB(50, 255, 200), Material = Enum.Material.Neon },
		Stairs = { Color = Color3.fromRGB(80, 30, 100), Material = Enum.Material.Neon },
		Sign   = { Color = Color3.fromRGB(15, 5, 35), Material = Enum.Material.SmoothPlastic },
		Door   = { Color = Color3.fromRGB(255, 100, 50), Material = Enum.Material.Neon },
		Window = { Color = Color3.fromRGB(50, 200, 255), Material = Enum.Material.Neon },
		-- Floor 4 gym battle team colors (must contrast with neon teal/pink theme)
		GymBlueTeam = Color3.fromRGB(80, 80, 255),
		GymRedTeam  = Color3.fromRGB(255, 60, 60),
	},
	-- Plain color themes (same code path as full themes; no exterior shell)
	-- Each includes GymBlueTeam/GymRedTeam colors that never match the main color
	exterior_red    = { Wall = {Color = Color3.fromRGB(200, 60, 60)}, Floor = {Color = Color3.fromRGB(200, 60, 60)}, Trim = {Color = Color3.fromRGB(200, 60, 60)}, Point = {Color = Color3.fromRGB(200, 60, 60)}, Stairs = {Color = Color3.fromRGB(200, 60, 60)}, Sign = {Color = Color3.fromRGB(200, 60, 60)}, Door = {Color = Color3.fromRGB(200, 60, 60)}, Window = {Color = Color3.fromRGB(200, 60, 60)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(60, 200, 100) },
	exterior_blue   = { Wall = {Color = Color3.fromRGB(60, 100, 200)}, Floor = {Color = Color3.fromRGB(60, 100, 200)}, Trim = {Color = Color3.fromRGB(60, 100, 200)}, Point = {Color = Color3.fromRGB(60, 100, 200)}, Stairs = {Color = Color3.fromRGB(60, 100, 200)}, Sign = {Color = Color3.fromRGB(60, 100, 200)}, Door = {Color = Color3.fromRGB(60, 100, 200)}, Window = {Color = Color3.fromRGB(60, 100, 200)}, GymBlueTeam = Color3.fromRGB(220, 180, 50), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_green  = { Wall = {Color = Color3.fromRGB(60, 180, 80)}, Floor = {Color = Color3.fromRGB(60, 180, 80)}, Trim = {Color = Color3.fromRGB(60, 180, 80)}, Point = {Color = Color3.fromRGB(60, 180, 80)}, Stairs = {Color = Color3.fromRGB(60, 180, 80)}, Sign = {Color = Color3.fromRGB(60, 180, 80)}, Door = {Color = Color3.fromRGB(60, 180, 80)}, Window = {Color = Color3.fromRGB(60, 180, 80)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_yellow = { Wall = {Color = Color3.fromRGB(220, 200, 60)}, Floor = {Color = Color3.fromRGB(220, 200, 60)}, Trim = {Color = Color3.fromRGB(220, 200, 60)}, Point = {Color = Color3.fromRGB(220, 200, 60)}, Stairs = {Color = Color3.fromRGB(220, 200, 60)}, Sign = {Color = Color3.fromRGB(220, 200, 60)}, Door = {Color = Color3.fromRGB(220, 200, 60)}, Window = {Color = Color3.fromRGB(220, 200, 60)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_purple = { Wall = {Color = Color3.fromRGB(140, 80, 200)}, Floor = {Color = Color3.fromRGB(140, 80, 200)}, Trim = {Color = Color3.fromRGB(140, 80, 200)}, Point = {Color = Color3.fromRGB(140, 80, 200)}, Stairs = {Color = Color3.fromRGB(140, 80, 200)}, Sign = {Color = Color3.fromRGB(140, 80, 200)}, Door = {Color = Color3.fromRGB(140, 80, 200)}, Window = {Color = Color3.fromRGB(140, 80, 200)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_orange = { Wall = {Color = Color3.fromRGB(230, 140, 50)}, Floor = {Color = Color3.fromRGB(230, 140, 50)}, Trim = {Color = Color3.fromRGB(230, 140, 50)}, Point = {Color = Color3.fromRGB(230, 140, 50)}, Stairs = {Color = Color3.fromRGB(230, 140, 50)}, Sign = {Color = Color3.fromRGB(230, 140, 50)}, Door = {Color = Color3.fromRGB(230, 140, 50)}, Window = {Color = Color3.fromRGB(230, 140, 50)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
}

-- ═══════════════════════════════════════════════════════════════════════════
-- DEFAULT GYM TEAM COLORS (used when no theme is equipped or theme has no overrides)
-- These are also used by ApplyBaseColorToPlot to override the base color on gym points.
-- ═══════════════════════════════════════════════════════════════════════════
local DEFAULT_GYM_BLUE = Color3.fromRGB(60, 140, 220)
local DEFAULT_GYM_RED  = Color3.fromRGB(200, 60, 60)

-- ═══════════════════════════════════════════════════════════════════════════
-- applyGymTeamColors(plotModel, blueColor, redColor)
-- Re-colors BattlePoints inside Floor4/BaseGym/BlueTeam and RedTeam so each
-- team is visually distinct and never matches the main theme color.
-- Called after the main theme/base-color pass.
-- @param plotModel Model — the plot
-- @param blueColor Color3 — color for BlueTeam BattlePoints
-- @param redColor  Color3 — color for RedTeam BattlePoints
-- ═══════════════════════════════════════════════════════════════════════════
local function applyGymTeamColors(plotModel, blueColor, redColor)
	local floor4 = plotModel:FindFirstChild("Floor4")
	if not floor4 then return end
	local gym = floor4:FindFirstChild("BaseGym")
	if not gym then return end

	local teamColors = {
		BlueTeam = blueColor or DEFAULT_GYM_BLUE,
		RedTeam  = redColor or DEFAULT_GYM_RED,
	}
	for teamName, color in pairs(teamColors) do
		local teamFolder = gym:FindFirstChild(teamName)
		if teamFolder then
			for _, desc in ipairs(teamFolder:GetDescendants()) do
				if desc:IsA("BasePart") and desc.Name:match("^BattlePoint") then
					desc.Color = color
					desc.Material = Enum.Material.SmoothPlastic
				end
			end
		end
	end
end

local DEFAULT_GREY = Color3.fromRGB(120, 120, 125)
local DEFAULT_MATERIAL = Enum.Material.Concrete

local function isGlassPart(part)
	if part.Transparency >= 0.9 then return true end
	if part.Material == Enum.Material.Glass then return true end
	if part:GetAttribute("IsGlass") then return true end
	return false
end

--- Get AABB of entire plot from all BaseParts (works with any structure, no Floor3 required).
function BaseExteriorSystem.GetPlotBoundsFromModel(plotModel)
	if not plotModel then return nil end
	local pivot = plotModel:GetPivot()
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			local cf = pivot:PointToObjectSpace(desc.CFrame.Position)
			local s = desc.Size
			local rx, ry, rz = s.X/2, s.Y/2, s.Z/2
			lo = Vector3.new(math.min(lo.X, cf.X - rx), math.min(lo.Y, cf.Y - ry), math.min(lo.Z, cf.Z - rz))
			hi = Vector3.new(math.max(hi.X, cf.X + rx), math.max(hi.Y, cf.Y + ry), math.max(hi.Z, cf.Z + rz))
		end
	end
	if lo.X == math.huge then return nil end
	local sizeX, sizeZ = hi.X - lo.X, hi.Z - lo.Z
	local wallHeight = hi.Y - lo.Y
	return {
		lo = lo, hi = hi,
		center = (lo + hi) / 2,
		halfSizeX = sizeX / 2, halfSizeZ = sizeZ / 2,
		sizeX = sizeX, sizeZ = sizeZ,
		wallHeight = wallHeight,
		floorY = lo.Y, topY = hi.Y,
		worldCFrame = pivot,
	}
end

-- Explicit wall/floor/stair part names (user's base structure: BackWall, FrontWall, Floor2, etc.)
local WALL_NAMES = { BackWall = true, FrontWall = true, LeftWall = true, RightWall = true, BackWall2 = true, FrontWall2 = true, LeftWall2 = true, RightWall2 = true, BattlePointWall = true }
local function isWallPart(name)
	if WALL_NAMES[name] then return true end
	return name and name:lower():find("wall")
end
local function isFloorPart(name)
	if not name then return false end
	local n = name:lower()
	return n:find("floor") or n == "floorbase"
end
local function isStairPart(name)
	return name and name:lower():find("stair")
end

--- Gym / arena leaderboard screen parts (LeaderboardBattle, LeaderboardIncome, …) and anything parented under them.
--- Never recolor with base color or exterior theme — keeps screen/UI appearance stable.
local function isLeaderboardCosmeticPart(part)
	if not part or not part:IsA("BasePart") then return false end
	local lower = string.lower(part.Name)
	if #lower >= 11 and lower:sub(1, 11) == "leaderboard" then return true end
	local p = part.Parent
	while p do
		if p:IsA("BasePart") then
			local pl = string.lower(p.Name)
			if #pl >= 11 and pl:sub(1, 11) == "leaderboard" then return true end
		end
		p = p.Parent
	end
	return false
end

--- Parts that should never use exterior / base-color cosmetics (keep asset colors).
local function shouldSkipCosmeticRecolor(part)
	if not part or not part:IsA("BasePart") then return false end
	if isLeaderboardCosmeticPart(part) then return true end
	local n = part.Name
	local nl = string.lower(n)
	if nl:find("teleport") or nl:find("teleporter") then return true end
	if nl:match("tele$") then return true end -- e.g. ElectricTele, CaveTele
	if n == "MCombiner" or n == "Combiner" or n == "MRecycler" or n == "Recycler" then return true end
	local anc = part.Parent
	while anc do
		local an = string.lower(anc.Name)
		if anc.Name == "TeleportParts" or an:find("teleport") then return true end
		anc = anc.Parent
	end
	return false
end

local function getThemeStyle(partName, palette)
	if not partName or not palette then return palette.Trim or palette.Wall end
	local n = partName
	if isWallPart(n) then return palette.Wall end
	if isFloorPart(n) then return palette.Floor end
	if isStairPart(n) then return palette.Stairs end
	if n:match("Point") or n:match("Defense") or n:match("Income") or n:match("Battle") then return palette.Point end
	if n:match("Sign") then return palette.Sign end
	return palette.Trim or palette.Wall
end

local function createShellPart(name, size, cframe, parent, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = true
	p.Material = material or Enum.Material.Concrete
	p.Color = color or Color3.fromRGB(60, 60, 60)
	p.Parent = parent
	return p
end

--- Check if part should get base color (walls, stairs, floors, points — not glass, teleporters, combiner, recycler).
--- Floor decks: e.g. Folder "Floor2" → Part "Floor2" (same as theme isFloorPart; case-insensitive "floor" match).
local function shouldApplyBaseColor(part)
	if isGlassPart(part) then return false end
	if shouldSkipCosmeticRecolor(part) then return false end
	local n = part.Name
	local nl = string.lower(n)
	if nl:find("wall", 1, true) then return true end
	if nl:find("stair", 1, true) then return true end
	if nl:find("floor", 1, true) then return true end
	if n:match("^DefensePoint") then return true end
	if n:match("^IncomePoint") then return true end
	if n:match("^BattlePoint") then return true end
	return false
end

--- Reset parts to default grey when unequipping. onlyBaseColorParts = true resets walls/stairs/points only (not teleporter/combiner/recycler).
local function applyDefaultToPlot(plotModel, onlyBaseColorParts)
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and not isGlassPart(desc) then
			if shouldSkipCosmeticRecolor(desc) then continue end
			if onlyBaseColorParts and not shouldApplyBaseColor(desc) then continue end
			desc.Color = DEFAULT_GREY
			desc.Material = DEFAULT_MATERIAL
			desc.Transparency = 0
		end
	end
end

--- Apply theme as skin: recolor non-glass parts and add ExteriorShell (door + window frames). Does not delete plot.
--- For color-only themes (BaseExteriorItems with .color): apply color to walls & stairs only, no shell.
function BaseExteriorSystem.ApplyThemeToPlot(plotModel, themeId)
	if not plotModel or not plotModel.Parent then return false end

	-- Remove previous exterior shell
	local oldShell = plotModel:FindFirstChild("ExteriorShell")
	if oldShell then oldShell:Destroy() end

	if not themeId or themeId == "" then
		applyDefaultToPlot(plotModel, false)
		-- FIX: Always apply distinct gym team colors even on default theme
		applyGymTeamColors(plotModel, DEFAULT_GYM_BLUE, DEFAULT_GYM_RED)
		return true
	end

	local palette = THEME_PALETTES[themeId]
	if not palette then return false end

	-- 1) Recolor all non-glass BaseParts in the plot
	-- For color-only themes (exterior_red etc), set SmoothPlastic so color is visible (Material was overriding)
	local isPlainColor = themeId:match("^exterior_")
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and not isGlassPart(desc) and not shouldSkipCosmeticRecolor(desc) then
			local style = getThemeStyle(desc.Name, palette)
			if style and style.Color then desc.Color = style.Color end
			if style and style.Material then
				desc.Material = style.Material
			elseif isPlainColor and style and style.Color then
				-- Color-only themes: use SmoothPlastic so the color is clearly visible
				desc.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	-- FIX: Override Floor 4 gym BattlePoints with distinct team colors (never match main theme)
	applyGymTeamColors(plotModel, palette.GymBlueTeam, palette.GymRedTeam)

	-- 2) Build exterior shell (door + windows) - skip for plain color themes (exterior_red, etc.)
	if isPlainColor then return true end

	-- 3) Build exterior shell (door + windows) in plot model space
	local bounds = BaseExteriorSystem.GetPlotBoundsFromModel(plotModel)
	if not bounds then return true end

	local pivot = plotModel:GetPivot()
	local shell = Instance.new("Folder")
	shell.Name = "ExteriorShell"
	shell.Parent = plotModel

	local lo, hi = bounds.lo, bounds.hi
	local floorY = bounds.floorY
	local topY = bounds.topY
	local midY = (floorY + topY) / 2
	local midX = (lo.X + hi.X) / 2
	local midZ = (lo.Z + hi.Z) / 2

	-- Door on front face (min Z): center of front wall
	local doorW, doorH, doorD = 5, 7, 0.5
	local doorZ = lo.Z - doorD/2 - 0.2
	local doorCf = CFrame.new(midX, floorY + doorH/2 + 0.5, doorZ)
	local doorPart = createShellPart("ExteriorDoor", Vector3.new(doorW, doorH, doorD), doorCf, shell,
		palette.Door and palette.Door.Color or Color3.fromRGB(40, 35, 25),
		palette.Door and palette.Door.Material or Enum.Material.Wood)
	doorPart.CFrame = pivot:ToWorldSpace(doorCf)

	-- Window frames: left wall (min X), right (max X), back (max Z)
	local windowH = 4
	local windowW = 5
	local windowD = 0.4
	local winStyle = palette.Window or palette.Trim

	local function addWindow(x, z, name)
		local cf = CFrame.new(x, midY, z)
		local p = createShellPart(name, Vector3.new(windowW, windowH, windowD), cf, shell,
			winStyle.Color, winStyle.Material)
		p.CFrame = pivot:ToWorldSpace(cf)
	end

	local inset = 0.2
	addWindow(lo.X - windowD/2 - inset, midZ - bounds.halfSizeZ * 0.4, "ExteriorWindowL1")
	addWindow(lo.X - windowD/2 - inset, midZ + bounds.halfSizeZ * 0.4, "ExteriorWindowL2")
	addWindow(hi.X + windowD/2 + inset, midZ - bounds.halfSizeZ * 0.4, "ExteriorWindowR1")
	addWindow(hi.X + windowD/2 + inset, midZ + bounds.halfSizeZ * 0.4, "ExteriorWindowR2")
	if bounds.sizeZ >= 18 then
		addWindow(midX - bounds.halfSizeX * 0.4, hi.Z + windowD/2 + inset, "ExteriorWindowB1")
		addWindow(midX + bounds.halfSizeX * 0.4, hi.Z + windowD/2 + inset, "ExteriorWindowB2")
	end

	return true
end

--- Apply base color to walls, stairs, points. Does not affect glass, teleporters, combiner, or recycler.
--- Pass nil to reset those parts to default grey.
--- FIX: Floor 4 gym BattlePoints always get distinct team colors that never match the base color.

-- Per-base-color gym team overrides (blue/red that contrast with the base color)
local BASE_COLOR_GYM_TEAMS = {
	base_red    = { blue = Color3.fromRGB(60, 140, 220), red = Color3.fromRGB(60, 200, 100) },
	base_blue   = { blue = Color3.fromRGB(220, 180, 50), red = Color3.fromRGB(200, 60, 60) },
	base_green  = { blue = Color3.fromRGB(60, 140, 220), red = Color3.fromRGB(200, 60, 60) },
	base_yellow = { blue = Color3.fromRGB(60, 140, 220), red = Color3.fromRGB(200, 60, 60) },
	base_purple = { blue = Color3.fromRGB(60, 140, 220), red = Color3.fromRGB(200, 60, 60) },
	base_orange = { blue = Color3.fromRGB(60, 140, 220), red = Color3.fromRGB(200, 60, 60) },
}

function BaseExteriorSystem.ApplyBaseColorToPlot(plotModel, colorId)
	if not plotModel or not plotModel.Parent then return false end
	if not colorId or colorId == "" then
		applyDefaultToPlot(plotModel, true)
		applyGymTeamColors(plotModel, DEFAULT_GYM_BLUE, DEFAULT_GYM_RED)
		return true
	end

	local config = nil
	for _, item in ipairs(GameConfig and GameConfig.BaseColorItems or {}) do
		if item.id == colorId and item.color then
			config = item
			break
		end
	end
	if not config then return false end

	local color = config.color
	-- Use SmoothPlastic so the color is visible; some materials (e.g. Brick/Himmelblau) can obscure Color
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and shouldApplyBaseColor(desc) then
			desc.Color = color
			desc.Material = Enum.Material.SmoothPlastic
		end
	end

	-- FIX: Override Floor 4 gym BattlePoints with distinct team colors (never match base color)
	local gymOverride = BASE_COLOR_GYM_TEAMS[colorId]
	if gymOverride then
		applyGymTeamColors(plotModel, gymOverride.blue, gymOverride.red)
	else
		applyGymTeamColors(plotModel, DEFAULT_GYM_BLUE, DEFAULT_GYM_RED)
	end
	return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INIT & REMOTES FOR UI AGENT
-- ═══════════════════════════════════════════════════════════════════════════

function BaseExteriorSystem.Init(playerDataManager)
	PlayerDataManager = playerDataManager
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then return end

	-- Use remotes created by MainServer (Events.GetExteriorBounds, GetBuildInstructions, RefreshExterior)
	local getExteriorBounds = eventsFolder:FindFirstChild("GetExteriorBounds")
	local getBuildInstructions = eventsFolder:FindFirstChild("GetBuildInstructions")
	local refreshExterior = eventsFolder:FindFirstChild("RefreshExterior")
	if not getExteriorBounds or not getBuildInstructions or not refreshExterior then
		warn("[BaseExteriorSystem] Remotes GetExteriorBounds, GetBuildInstructions, or RefreshExterior missing in Events. Add makeFunc/makeEvent in MainServer.")
		return
	end

	getExteriorBounds.OnServerInvoke = function(plr, decorationSpaceAbove)
		return BaseExteriorSystem.GetExteriorBoundsForPlayer(plr, decorationSpaceAbove)
	end

	getBuildInstructions.OnServerInvoke = function(plr, themeName)
		return BaseExteriorSystem.GetBuildInstructions(themeName)
	end

	refreshExterior.OnServerEvent:Connect(function(plr)
		local plot = BaseExteriorSystem.GetPlotForPlayer(plr)
		if plot then
			BaseExteriorSystem.RefreshExterior(plot)
		end
	end)

	print("[BaseExteriorSystem] Initialized (bounds from Floor3, decoration zone, UI agent remotes)")
end

return BaseExteriorSystem
