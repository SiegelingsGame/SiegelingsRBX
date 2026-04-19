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

-- Last updated: 2026-04-18 23:25

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

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
	JungleHut = {
		Wall   = { Color = Color3.fromRGB(72, 92, 54),   Material = Enum.Material.Wood },
		Floor  = { Color = Color3.fromRGB(58, 78, 46),   Material = Enum.Material.LeafyGrass },
		Trim   = { Color = Color3.fromRGB(96, 72, 42),   Material = Enum.Material.Wood },
		Point  = { Color = Color3.fromRGB(52, 68, 44),   Material = Enum.Material.Ground },
		Stairs = { Color = Color3.fromRGB(84, 64, 38),   Material = Enum.Material.Wood },
		Sign   = { Color = Color3.fromRGB(110, 130, 72), Material = Enum.Material.Wood },
		Door   = { Color = Color3.fromRGB(68, 52, 34),   Material = Enum.Material.Wood },
		Window = { Color = Color3.fromRGB(85, 105, 70),  Material = Enum.Material.Glass },
		GymBlueTeam = Color3.fromRGB(70, 160, 220),
		GymRedTeam  = Color3.fromRGB(220, 95, 55),
	},
	IceFortress = {
		Wall   = { Color = Color3.fromRGB(178, 215, 235), Material = Enum.Material.Ice },
		Floor  = { Color = Color3.fromRGB(210, 232, 245), Material = Enum.Material.Snow },
		Trim   = { Color = Color3.fromRGB(140, 175, 205), Material = Enum.Material.Glacier },
		Point  = { Color = Color3.fromRGB(155, 195, 220), Material = Enum.Material.Ice },
		Stairs = { Color = Color3.fromRGB(188, 218, 238), Material = Enum.Material.Ice },
		Sign   = { Color = Color3.fromRGB(165, 205, 228), Material = Enum.Material.SmoothPlastic },
		Door   = { Color = Color3.fromRGB(120, 155, 188), Material = Enum.Material.Ice },
		Window = { Color = Color3.fromRGB(195, 225, 242), Material = Enum.Material.Glass },
		GymBlueTeam = Color3.fromRGB(55, 110, 210),
		GymRedTeam  = Color3.fromRGB(230, 75, 85),
	},
	VolcanicCavern = {
		Wall   = { Color = Color3.fromRGB(42, 34, 38),    Material = Enum.Material.Basalt },
		Floor  = { Color = Color3.fromRGB(48, 28, 22),    Material = Enum.Material.CrackedLava },
		Trim   = { Color = Color3.fromRGB(255, 95, 38),    Material = Enum.Material.Neon },
		Point  = { Color = Color3.fromRGB(55, 42, 44),    Material = Enum.Material.Slate },
		Stairs = { Color = Color3.fromRGB(62, 48, 46),    Material = Enum.Material.Rock },
		Sign   = { Color = Color3.fromRGB(75, 58, 52),    Material = Enum.Material.Basalt },
		Door   = { Color = Color3.fromRGB(38, 28, 26),    Material = Enum.Material.Slate },
		Window = { Color = Color3.fromRGB(255, 130, 55), Material = Enum.Material.Neon },
		GymBlueTeam = Color3.fromRGB(65, 145, 240),
		GymRedTeam  = Color3.fromRGB(255, 215, 60),
	},
	FloatingPalace = {
		Wall   = { Color = Color3.fromRGB(235, 242, 252), Material = Enum.Material.Marble },
		Floor  = { Color = Color3.fromRGB(248, 250, 255), Material = Enum.Material.CeramicTiles },
		Trim   = { Color = Color3.fromRGB(218, 198, 140), Material = Enum.Material.SmoothPlastic },
		Point  = { Color = Color3.fromRGB(225, 232, 248), Material = Enum.Material.Marble },
		Stairs = { Color = Color3.fromRGB(238, 242, 252), Material = Enum.Material.Marble },
		Sign   = { Color = Color3.fromRGB(210, 225, 245), Material = Enum.Material.Limestone },
		Door   = { Color = Color3.fromRGB(230, 208, 155), Material = Enum.Material.Marble },
		Window = { Color = Color3.fromRGB(190, 215, 245), Material = Enum.Material.Glass },
		GymBlueTeam = Color3.fromRGB(85, 125, 235),
		GymRedTeam  = Color3.fromRGB(235, 105, 115),
	},
	-- Plain color themes (same code path as full themes; no exterior shell)
	-- Each includes GymBlueTeam/GymRedTeam colors that never match the main color
	exterior_red    = { Wall = {Color = Color3.fromRGB(200, 60, 60)}, Floor = {Color = Color3.fromRGB(200, 60, 60)}, Trim = {Color = Color3.fromRGB(200, 60, 60)}, Point = {Color = Color3.fromRGB(200, 60, 60)}, Stairs = {Color = Color3.fromRGB(200, 60, 60)}, Sign = {Color = Color3.fromRGB(200, 60, 60)}, Door = {Color = Color3.fromRGB(200, 60, 60)}, Window = {Color = Color3.fromRGB(200, 60, 60)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(60, 200, 100) },
	exterior_blue   = { Wall = {Color = Color3.fromRGB(60, 100, 200)}, Floor = {Color = Color3.fromRGB(60, 100, 200)}, Trim = {Color = Color3.fromRGB(60, 100, 200)}, Point = {Color = Color3.fromRGB(60, 100, 200)}, Stairs = {Color = Color3.fromRGB(60, 100, 200)}, Sign = {Color = Color3.fromRGB(60, 100, 200)}, Door = {Color = Color3.fromRGB(60, 100, 200)}, Window = {Color = Color3.fromRGB(60, 100, 200)}, GymBlueTeam = Color3.fromRGB(220, 180, 50), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_green  = { Wall = {Color = Color3.fromRGB(60, 180, 80)}, Floor = {Color = Color3.fromRGB(60, 180, 80)}, Trim = {Color = Color3.fromRGB(60, 180, 80)}, Point = {Color = Color3.fromRGB(60, 180, 80)}, Stairs = {Color = Color3.fromRGB(60, 180, 80)}, Sign = {Color = Color3.fromRGB(60, 180, 80)}, Door = {Color = Color3.fromRGB(60, 180, 80)}, Window = {Color = Color3.fromRGB(60, 180, 80)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_yellow = { Wall = {Color = Color3.fromRGB(220, 200, 60)}, Floor = {Color = Color3.fromRGB(220, 200, 60)}, Trim = {Color = Color3.fromRGB(220, 200, 60)}, Point = {Color = Color3.fromRGB(220, 200, 60)}, Stairs = {Color = Color3.fromRGB(220, 200, 60)}, Sign = {Color = Color3.fromRGB(220, 200, 60)}, Door = {Color = Color3.fromRGB(220, 200, 60)}, Window = {Color = Color3.fromRGB(220, 200, 60)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_purple = { Wall = {Color = Color3.fromRGB(140, 80, 200)}, Floor = {Color = Color3.fromRGB(140, 80, 200)}, Trim = {Color = Color3.fromRGB(140, 80, 200)}, Point = {Color = Color3.fromRGB(140, 80, 200)}, Stairs = {Color = Color3.fromRGB(140, 80, 200)}, Sign = {Color = Color3.fromRGB(140, 80, 200)}, Door = {Color = Color3.fromRGB(140, 80, 200)}, Window = {Color = Color3.fromRGB(140, 80, 200)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_orange = { Wall = {Color = Color3.fromRGB(230, 140, 50)}, Floor = {Color = Color3.fromRGB(230, 140, 50)}, Trim = {Color = Color3.fromRGB(230, 140, 50)}, Point = {Color = Color3.fromRGB(230, 140, 50)}, Stairs = {Color = Color3.fromRGB(230, 140, 50)}, Sign = {Color = Color3.fromRGB(230, 140, 50)}, Door = {Color = Color3.fromRGB(230, 140, 50)}, Window = {Color = Color3.fromRGB(230, 140, 50)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_white  = { Wall = {Color = Color3.fromRGB(248, 248, 250)}, Floor = {Color = Color3.fromRGB(248, 248, 250)}, Trim = {Color = Color3.fromRGB(248, 248, 250)}, Point = {Color = Color3.fromRGB(248, 248, 250)}, Stairs = {Color = Color3.fromRGB(248, 248, 250)}, Sign = {Color = Color3.fromRGB(248, 248, 250)}, Door = {Color = Color3.fromRGB(248, 248, 250)}, Window = {Color = Color3.fromRGB(248, 248, 250)}, GymBlueTeam = Color3.fromRGB(60, 140, 220), GymRedTeam = Color3.fromRGB(200, 60, 60) },
	exterior_black  = { Wall = {Color = Color3.fromRGB(28, 28, 32)}, Floor = {Color = Color3.fromRGB(28, 28, 32)}, Trim = {Color = Color3.fromRGB(28, 28, 32)}, Point = {Color = Color3.fromRGB(28, 28, 32)}, Stairs = {Color = Color3.fromRGB(28, 28, 32)}, Sign = {Color = Color3.fromRGB(28, 28, 32)}, Door = {Color = Color3.fromRGB(28, 28, 32)}, Window = {Color = Color3.fromRGB(28, 28, 32)}, GymBlueTeam = Color3.fromRGB(90, 170, 255), GymRedTeam = Color3.fromRGB(255, 85, 85) },
}

--- Premium full themes override part materials; exterior_* paint themes = color only (keeps DiamondPlate in Studio).
local PREMIUM_FULL_THEME_IDS = {
	HauntedHouse = true,
	RetroArcade = true,
	JungleHut = true,
	IceFortress = true,
	VolcanicCavern = true,
	FloatingPalace = true,
}
local function isPremiumFullTheme(themeId)
	return themeId ~= nil and PREMIUM_FULL_THEME_IDS[themeId] == true
end

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
				end
			end
		end
	end
end

local DEFAULT_GREY = Color3.fromRGB(120, 120, 125)
-- No exterior theme: grass tint on foundations; materials stay as authored (e.g. DiamondPlate).
local DEFAULT_GRASS_COLOR = Color3.fromRGB(88, 142, 72)

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

-- Siegelings on income/defense/battle slots are Models under the plot (see BasePlacementSystem.spawnBaseOrb).
-- Their meshes often contain names like "Floor" / "Wall" / "Point" that match structural filters; never tint them.
local BASE_SLOT_CREATURE_TAGS = {
	BaseDefenseCreature = true,
	BaseIncomeCreature = true,
	BaseBattleCreature = true,
}

local function isDescendantOfBaseSlotCreature(part)
	local p = part
	while p and p ~= game do
		if p:IsA("Model") then
			for _, tag in ipairs(CollectionService:GetTags(p)) do
				if BASE_SLOT_CREATURE_TAGS[tag] then
					return true
				end
			end
		end
		p = p.Parent
	end
	return false
end

-- Floor1/Carpet1 (or CArpet1) and Floor2/Carpet2: tinted via ApplyBaseColorToPlot (income vs defense shop colors).
local CARPET_FOLDER_NAMES = { Carpet1 = true, CArpet1 = true, Carpet2 = true, CArpet2 = true }
local function isUnderBaseCarpetFolder(part)
	local p = part and part.Parent
	while p do
		if CARPET_FOLDER_NAMES[p.Name] then
			return true
		end
		p = p.Parent
	end
	return false
end

--- Parts that should never use exterior / base-color cosmetics (keep asset colors).
local function shouldSkipCosmeticRecolor(part)
	if not part or not part:IsA("BasePart") then return false end
	if isUnderBaseCarpetFolder(part) then return true end
	if isLeaderboardCosmeticPart(part) then return true end
	if isDescendantOfBaseSlotCreature(part) then return true end
	local n = part.Name
	local nl = string.lower(n)
	if nl:find("teleport") or nl:find("teleporter") then return true end
	if nl:match("tele$") then return true end -- e.g. ElectricTele, CaveTele
	if nl:find("battlepointwall", 1, true) then return true end
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

--- Check if part should get base color (plot center, ramps, stairs, floors; not glass or special machines).
--- Floor decks: e.g. Folder "Floor2" → Part "Floor2" (same as theme isFloorPart; case-insensitive "floor" match).
local function shouldApplyBaseColor(part)
	if isGlassPart(part) then return false end
	if shouldSkipCosmeticRecolor(part) then return false end
	local n = part.Name
	local nl = string.lower(n)
	if nl == "plotcenter" then return true end
	if nl:find("ramp", 1, true) then return true end
	if nl:find("stair", 1, true) then return true end
	if nl:find("floor", 1, true) then return true end
	return false
end

-- Stored Enum.Material.Value from before any cosmetic changed this part (restore on unequip).
local ATTR_ORIGIN_MAT = "BaseCosmeticOriginMaterial"

local function materialFromStoredValue(val)
	if type(val) ~= "number" then return nil end
	for _, e in ipairs(Enum.Material:GetEnumItems()) do
		if e.Value == val then
			return e
		end
	end
	return nil
end

local function restoreOriginMaterial(desc)
	local v = desc:GetAttribute(ATTR_ORIGIN_MAT)
	local mat = materialFromStoredValue(v)
	if mat then
		desc.Material = mat
	end
end

-- Forward declaration — assigned after shouldApplyBaseSlotPadColor / carpet helpers exist.
local ensureCosmeticOriginSnapshots

local function applyDefaultToFilteredParts(plotModel, filterFn)
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and not isGlassPart(desc) then
			if shouldSkipCosmeticRecolor(desc) then continue end
			if filterFn and not filterFn(desc) then continue end
			desc.Color = DEFAULT_GREY
			desc.Transparency = 0
			restoreOriginMaterial(desc)
		end
	end
end

--- Reset parts to default grey when unequipping. onlyBaseColorParts = true resets foundations only.
local function applyDefaultToPlot(plotModel, onlyBaseColorParts)
	applyDefaultToFilteredParts(plotModel, onlyBaseColorParts and shouldApplyBaseColor or nil)
end

--- Apply theme as skin: recolor non-glass parts and add ExteriorShell (door + window frames). Does not delete plot.
--- For color-only themes (BaseExteriorItems with .color): apply color to base foundations only, no shell.
function BaseExteriorSystem.ApplyThemeToPlot(plotModel, themeId)
	if not plotModel or not plotModel.Parent then return false end

	if ensureCosmeticOriginSnapshots then
		ensureCosmeticOriginSnapshots(plotModel)
	end

	-- Remove previous exterior shell
	local oldShell = plotModel:FindFirstChild("ExteriorShell")
	if oldShell then oldShell:Destroy() end

	if not themeId or themeId == "" then
		-- Default plot: grass tint on foundations; grey trim elsewhere.
		-- Materials: restore Studio/default snapshot (premium themes overwrite Material).
		for _, desc in ipairs(plotModel:GetDescendants()) do
			if desc:IsA("BasePart") and not isGlassPart(desc) and not shouldSkipCosmeticRecolor(desc) then
				if shouldApplyBaseColor(desc) then
					desc.Color = DEFAULT_GRASS_COLOR
				else
					desc.Color = DEFAULT_GREY
				end
				desc.Transparency = 0
				restoreOriginMaterial(desc)
			end
		end
		applyGymTeamColors(plotModel, DEFAULT_GYM_BLUE, DEFAULT_GYM_RED)
		return true
	end

	local palette = THEME_PALETTES[themeId]
	if not palette then return false end

	-- 1) Recolor plot parts. Materials only change for premium full themes (see PREMIUM_FULL_THEME_IDS).
	local isPlainColor = themeId:match("^exterior_")
	local premiumFull = isPremiumFullTheme(themeId)
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and not isGlassPart(desc) and not shouldSkipCosmeticRecolor(desc) then
			if isPlainColor and not shouldApplyBaseColor(desc) then
				continue
			end
			local style = getThemeStyle(desc.Name, palette)
			if style and style.Color then desc.Color = style.Color end
			if premiumFull and style and style.Material then
				desc.Material = style.Material
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

--- Base Plots palette: tint IncomePoint* / DefensePoint* pads, Carpet1/Carpet2, and ramp parts (income vs defense by floor).
--- Pass nil to reset pads to default grey; carpet parts keep their Studio colors (not overwritten).

local function shouldApplyBaseSlotPadColor(part)
	if isGlassPart(part) then return false end
	if shouldSkipCosmeticRecolor(part) then return false end
	local n = part.Name
	if string.sub(n, 1, 11) == "IncomePoint" then return true end
	if string.sub(n, 1, 12) == "DefensePoint" then return true end
	return false
end

--- Capture Enum.Material.Value once per part so unequipping themes/base tints can restore authored materials.
ensureCosmeticOriginSnapshots = function(plotModel)
	if not plotModel then return end
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and not isGlassPart(desc) then
			local touchesTheme = not shouldSkipCosmeticRecolor(desc)
			local touchesPads = shouldApplyBaseSlotPadColor(desc)
			local touchesCarpet = isUnderBaseCarpetFolder(desc)
			if touchesTheme or touchesPads or touchesCarpet then
				if desc:GetAttribute(ATTR_ORIGIN_MAT) == nil then
					desc:SetAttribute(ATTR_ORIGIN_MAT, desc.Material.Value)
				end
			end
		end
	end
end

--- Clear stored origin materials (e.g. after plot reset / recycling) so the next owner re-snapshots from template.
function BaseExteriorSystem.ClearCosmeticOriginSnapshots(plotModel)
	if not plotModel then return end
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc:SetAttribute(ATTR_ORIGIN_MAT, nil)
		end
	end
end

local function deriveDefensePadColor(main)
	return Color3.new(
		math.clamp(main.R * 0.82, 0, 1),
		math.clamp(main.G * 0.82, 0, 1),
		math.clamp(main.B * 0.82, 0, 1)
	)
end

--- Floor1/Carpet1 → income shop color; Floor2/Carpet2 → defense shop color (BaseColorItems).
local function applyCarpetFolderTints(plotModel, incomeCol, defenseCol)
	if not plotModel then return end
	local f1 = plotModel:FindFirstChild("Floor1")
	if f1 then
		local folder = f1:FindFirstChild("Carpet1") or f1:FindFirstChild("CArpet1")
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BasePart") and not isGlassPart(d) then
					d.Color = incomeCol
				end
			end
		end
	end
	local f2 = plotModel:FindFirstChild("Floor2")
	if f2 then
		local folder = f2:FindFirstChild("Carpet2") or f2:FindFirstChild("CArpet2")
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				if d:IsA("BasePart") and not isGlassPart(d) then
					d.Color = defenseCol
				end
			end
		end
	end
end

--- Ramp parts (name contains "ramp"): Floor2 → defense pad color; Floor1 or elsewhere → income (matches Carpet1 / IncomePoint).
local function applyRampPadTints(plotModel, incomeCol, defenseCol)
	if not plotModel or not incomeCol or not defenseCol then return end
	local f2 = plotModel:FindFirstChild("Floor2")
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and not isGlassPart(desc) and not shouldSkipCosmeticRecolor(desc) then
			local nl = string.lower(desc.Name)
			if nl:find("ramp", 1, true) then
				if f2 and desc:IsDescendantOf(f2) then
					desc.Color = defenseCol
				else
					desc.Color = incomeCol
				end
			end
		end
	end
end

function BaseExteriorSystem.ApplyBaseColorToPlot(plotModel, colorId)
	if not plotModel or not plotModel.Parent then return false end

	if ensureCosmeticOriginSnapshots then
		ensureCosmeticOriginSnapshots(plotModel)
	end

	if not colorId or colorId == "" then
		applyDefaultToFilteredParts(plotModel, shouldApplyBaseSlotPadColor)
		-- Carpet* folders: keep authored starter colors unless a Base Plots palette is equipped.
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

	local incomeCol = config.color
	local defenseCol = config.defensePointColor or deriveDefensePadColor(incomeCol)

	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("BasePart") and shouldApplyBaseSlotPadColor(desc) then
			local n = desc.Name
			if string.sub(n, 1, 11) == "IncomePoint" then
				desc.Color = incomeCol
			elseif string.sub(n, 1, 12) == "DefensePoint" then
				desc.Color = defenseCol
			end
		end
	end
	applyCarpetFolderTints(plotModel, incomeCol, defenseCol)
	applyRampPadTints(plotModel, incomeCol, defenseCol)
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
