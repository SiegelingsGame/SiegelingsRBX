--[[
  HauntedHouseBaseGenerator.lua
  =============================
  Builds a full haunted-house base plot in code. Compatible with BasePlacementSystem.
  Run from Studio (Command Bar or a one-time Script) or from a server script.

  Usage:
    local Generator = require(path.to.HauntedHouseBaseGenerator)
    Generator.BuildPlot(plotId, position)   -- builds in Workspace.BasePlots
    -- or --
    Generator.BuildPlot(plotId, position, parentFolder)  -- custom parent

  Requires: Workspace. BasePlots folder is created if missing.
]]

local Workspace = game:GetService("Workspace")

-- Optional: use Instructions for validation or docs (same folder or ReplicatedStorage.Modules)
local Instructions
do
	local ok, mod = pcall(function()
		return require(script.Parent:FindFirstChild("BaseBuildInstructions_HauntedHouse") or script.Parent.BaseBuildInstructions_HauntedHouse)
	end)
	if ok and mod then Instructions = mod end
end

local Generator = {}

-- Layout constants (match GameConfig: PlotSize 50, spacing 8)
local PLOT_SIZE = 50
local FLOOR_HEIGHT = 12
local POINT_PAD_SIZE = Vector3.new(4, 1, 4)
local WALL_HEIGHT = 10

-- Haunted house theme
local COLORS = {
	Floor = Color3.fromRGB(45, 42, 55),
	Wall = Color3.fromRGB(35, 32, 45),
	Trim = Color3.fromRGB(80, 40, 100),
	Point = Color3.fromRGB(50, 45, 60),
	Stairs = Color3.fromRGB(55, 50, 65),
	Sign = Color3.fromRGB(30, 28, 38),
}
local MATERIALS = {
	Floor = Enum.Material.Slate,
	Wall = Enum.Material.Brick,
	Trim = Enum.Material.Wood,
	Point = Enum.Material.Concrete,
	Stairs = Enum.Material.Wood,
	Sign = Enum.Material.Wood,
}

local function createPart(name, size, cframe, parent, options)
	options = options or {}
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = options.CanCollide ~= false
	p.Material = options.Material or Enum.Material.Concrete
	p.Color = options.Color or Color3.fromRGB(80, 80, 80)
	p.Parent = parent
	if options.Transparency then p.Transparency = options.Transparency end
	if options.IsGlass then p:SetAttribute("IsGlass", true) end
	return p
end

local function createFolder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

--- Build one floor's platform (one big part) and optional walls
local function buildFloorPlatform(plot, floorName, yLevel, options)
	options = options or {}
	local floorFolder = plot:FindFirstChild(floorName)
	if not floorFolder then return end

	local w, d = PLOT_SIZE - 4, PLOT_SIZE - 4
	local floorPart = createPart(floorName .. "_Base", Vector3.new(w, 2, d),
		CFrame.new(0, yLevel, 0), floorFolder,
		{ Material = MATERIALS.Floor, Color = COLORS.Floor })
	floorPart.Name = "FloorBase"

	-- Short walls around the platform (haunted house perimeter)
	local h = WALL_HEIGHT
	local halfW, halfD = w/2, d/2
	-- Front wall ( -Z )
	createPart("WallFront", Vector3.new(w + 2, h, 2), CFrame.new(0, yLevel + 1 + h/2, -halfD - 1), floorFolder, { Material = MATERIALS.Wall, Color = COLORS.Wall })
	-- Back wall ( +Z )
	createPart("WallBack", Vector3.new(w + 2, h, 2), CFrame.new(0, yLevel + 1 + h/2, halfD + 1), floorFolder, { Material = MATERIALS.Wall, Color = COLORS.Wall })
	-- Left ( -X )
	createPart("WallLeft", Vector3.new(2, h, d + 2), CFrame.new(-halfW - 1, yLevel + 1 + h/2, 0), floorFolder, { Material = MATERIALS.Wall, Color = COLORS.Wall })
	-- Right ( +X )
	createPart("WallRight", Vector3.new(2, h, d + 2), CFrame.new(halfW + 1, yLevel + 1 + h/2, 0), floorFolder, { Material = MATERIALS.Wall, Color = COLORS.Wall })
end

--- Create a single point part (DefensePoint/IncomePoint/BattlePoint)
local function addPoint(floorFolder, pointName, position, inSubfolder)
	local container = floorFolder
	if inSubfolder then
		container = floorFolder:FindFirstChild(inSubfolder) or createFolder(inSubfolder, floorFolder)
	end
	return createPart(pointName, POINT_PAD_SIZE,
		CFrame.new(position) + CFrame.Angles(0, 0, 0), container,
		{ Material = MATERIALS.Point, Color = COLORS.Point })
end

--- Stairs from yFrom to yTo, inside floorFolder
local function addStairs(floorFolder, yFrom, yTo, side)
	local stepCount = 8
	local dy = (yTo - yFrom) / stepCount
	local stepW, stepD = 6, 4
	local x = side == "Left" and -PLOT_SIZE/4 or PLOT_SIZE/4
	local z = -PLOT_SIZE/4
	for i = 1, stepCount do
		local y = yFrom + (i - 0.5) * dy
		createPart("Stair" .. i, Vector3.new(stepW, dy + 0.5, stepD), CFrame.new(x, y, z), floorFolder, { Material = MATERIALS.Stairs, Color = COLORS.Stairs })
	end
	-- Railing (decorative)
	createPart("StairsRailing", Vector3.new(0.5, (yTo - yFrom) + 1, stepD + 1), CFrame.new(x + stepW/2 + 0.5, (yFrom + yTo)/2, z), floorFolder, { Material = MATERIALS.Trim, Color = COLORS.Trim })
end

--- Build all point layouts for the three floors (positions in plot space, Y relative to each floor)
local function addAllPoints(plot, y1, y2, y3)
	local half = PLOT_SIZE/2 - 6
	-- Floor1: Defense 1-6 around perimeter, Income 1-6 in center
	local floor1 = plot:FindFirstChild("Floor1")
	local def1 = createFolder("DefensePoints", floor1)
	local inc1 = createFolder("IncomePoints", floor1)
	-- Defense 1-6: corners and mid-sides
	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6) - math.pi/2
		local r = half - 2
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		addPoint(floor1, "DefensePoint" .. i, Vector3.new(x, y1 + 1, z), "DefensePoints")
	end
	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6)
		local r = 8
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		addPoint(floor1, "IncomePoint" .. i, Vector3.new(x, y1 + 1, z), "IncomePoints")
	end

	-- Floor2: Defense 7-12, Income 7-12, Battle 1-9
	local floor2 = plot:FindFirstChild("Floor2")
	local def2 = createFolder("DefensePoints", floor2)
	local inc2 = createFolder("IncomePoints", floor2)
	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6) - math.pi/2
		local r = half - 2
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		addPoint(floor2, "DefensePoint" .. (6 + i), Vector3.new(x, y2 + 1, z), "DefensePoints")
	end
	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6)
		local r = 8
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		addPoint(floor2, "IncomePoint" .. (6 + i), Vector3.new(x, y2 + 1, z), "IncomePoints")
	end
	-- Battle 1-9 in 3x3 grid (ballroom)
	local battleTeam = createFolder("BattleTeam", floor2)
	local spacing = 10
	for row = 0, 2 do
		for col = 0, 2 do
			local idx = row * 3 + col + 1
			local x = (col - 1) * spacing
			local z = (row - 1) * spacing
			addPoint(floor2, "BattlePoint" .. idx, Vector3.new(x, y2 + 1, z), "BattleTeam")
		end
	end

	-- Floor3: Defense 13-18, Income 13-18
	local floor3 = plot:FindFirstChild("Floor3")
	local def3 = createFolder("DefensePoints", floor3)
	local inc3 = createFolder("IncomePoints", floor3)
	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6) - math.pi/2
		local r = half - 2
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		addPoint(floor3, "DefensePoint" .. (12 + i), Vector3.new(x, y3 + 1, z), "DefensePoints")
	end
	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6)
		local r = 8
		local x, z = math.cos(angle) * r, math.sin(angle) * r
		addPoint(floor3, "IncomePoint" .. (12 + i), Vector3.new(x, y3 + 1, z), "IncomePoints")
	end
end

--- Build PlotCenter and SignPart
local function addPlotCenterAndSign(plot, y1)
	createPart("PlotCenter", Vector3.new(2, 1, 2), CFrame.new(0, y1 + 0.5, 0), plot, { Material = MATERIALS.Floor, Color = COLORS.Trim, CanCollide = false })
	createPart("SignPart", Vector3.new(8, 6, 0.5), CFrame.new(0, y1 + 4, -PLOT_SIZE/2 - 4), plot, { Material = MATERIALS.Sign, Color = COLORS.Sign })
end

--- Add a few haunted-house props (optional)
local function addProps(plot, y1)
	local floor1 = plot:FindFirstChild("Floor1")
	if not floor1 then return end
	-- Lanterns at corners
	for _, offset in ipairs({ Vector3.new(PLOT_SIZE/4, y1 + 2, -PLOT_SIZE/4), Vector3.new(-PLOT_SIZE/4, y1 + 2, -PLOT_SIZE/4) }) do
		local lamp = createPart("Lantern", Vector3.new(1.5, 3, 1.5), CFrame.new(offset), floor1, { Material = Enum.Material.Metal, Color = Color3.fromRGB(60, 50, 40) })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 60)
		light.Range = 12
		light.Brightness = 0.5
		light.Parent = lamp
	end
end

--- Main build: create the full plot model and all descendants
function Generator.BuildPlot(plotId, position, parentFolder)
	position = position or Vector3.new(0, 0, 0)
	parentFolder = parentFolder or Workspace:FindFirstChild("BasePlots")
	if not parentFolder then
		parentFolder = Instance.new("Folder")
		parentFolder.Name = "BasePlots"
		parentFolder.Parent = Workspace
	end

	local plotName = "Plot" .. tostring(plotId)
	local existing = parentFolder:FindFirstChild(plotName)
	if existing then existing:Destroy() end

	local plot = Instance.new("Model")
	plot.Name = plotName
	plot.Parent = parentFolder

	-- Build in model space at origin; move to world position at the end with PivotTo
	local y1 = 0
	local y2 = FLOOR_HEIGHT
	local y3 = 2 * FLOOR_HEIGHT

	-- Floor containers (Folders so they can be shown/hidden)
	createFolder("Floor1", plot)
	createFolder("Floor2", plot)
	createFolder("Floor3", plot)

	buildFloorPlatform(plot, "Floor1", y1)
	buildFloorPlatform(plot, "Floor2", y2)
	buildFloorPlatform(plot, "Floor3", y3)

	addStairs(plot:FindFirstChild("Floor2"), y1, y2, "Left")
	addStairs(plot:FindFirstChild("Floor3"), y2, y3, "Right")

	addAllPoints(plot, y1, y2, y3)
	addPlotCenterAndSign(plot, y1)
	addProps(plot, y1)

	-- Move entire plot to world position
	plot:PivotTo(CFrame.new(position))

	return plot
end

--- Convenience: build default Plot1 at origin (for testing in Studio)
function Generator.BuildDefault()
	return Generator.BuildPlot(1, Vector3.new(0, 0, 0))
end

return Generator
