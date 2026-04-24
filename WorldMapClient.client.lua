-- WorldMapClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- World map image with live player position. Open via HUD [M] Map (HUDToggleMenu → WorldMapGUI).
-- Last updated: 2026-04-23 22:37

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local WM = GameConfig.WorldMap
if not WM or WM.Enabled ~= true then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local C = {
	bg = Color3.fromRGB(14, 16, 24),
	accent = Color3.fromRGB(120, 200, 255),
	gold = Color3.fromRGB(232, 175, 72),
	white = Color3.new(1, 1, 1),
	muted = Color3.fromRGB(140, 145, 160),
	base = Color3.fromRGB(120, 200, 255),
}

local function resolvePath(root, pathParts)
	local inst = root
	for _, name in ipairs(pathParts or {}) do
		inst = inst and inst:FindFirstChild(name)
	end
	return inst
end

local function expandPartXZ(minX, maxX, minZ, maxZ, part)
	if not part or not part:IsA("BasePart") then
		return minX, maxX, minZ, maxZ
	end
	local e = part.Size * 0.5
	local p = part.Position
	return math.min(minX, p.X - e.X),
		math.max(maxX, p.X + e.X),
		math.min(minZ, p.Z - e.Z),
		math.max(maxZ, p.Z + e.Z)
end

local function computeWorldXZBounds()
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local biome = GameConfig.BiomeZone
	if WM.UseAutoBounds and biome then
		for _, def in ipairs(biome.OuterZones or {}) do
			local part = resolvePath(workspace, def.path or {})
			minX, maxX, minZ, maxZ = expandPartXZ(minX, maxX, minZ, maxZ, part)
		end
		for _, pathParts in ipairs(biome.HubParts or {}) do
			local part = resolvePath(workspace, pathParts)
			minX, maxX, minZ, maxZ = expandPartXZ(minX, maxX, minZ, maxZ, part)
		end
	end
	if minX == math.huge or maxX <= minX or maxZ <= minZ then
		return {
			minX = WM.MinWorldXZ.X,
			maxX = WM.MaxWorldXZ.X,
			minZ = WM.MinWorldXZ.Y,
			maxZ = WM.MaxWorldXZ.Y,
		}
	end
	local pad = math.clamp(tonumber(WM.AutoBoundsPadFraction) or 0.08, 0, 0.25)
	local w = maxX - minX
	local d = maxZ - minZ
	minX -= w * pad
	maxX += w * pad
	minZ -= d * pad
	maxZ += d * pad
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
end

local function rotateUV(tx, tz)
	local rot = tonumber(WM.RotationDegrees) or 0
	rot = ((math.floor(rot / 90 + 0.5) * 90) % 360 + 360) % 360
	if rot == 0 then
		return tx, tz
	end
	-- rotate around center (0.5, 0.5) in 90-degree steps
	local x = tx - 0.5
	local y = tz - 0.5
	if rot == 90 then
		x, y = y, -x
	elseif rot == 180 then
		x, y = -x, -y
	elseif rot == 270 then
		x, y = -y, x
	end
	return x + 0.5, y + 0.5
end

local function findBasePlotsFolderClient()
	local w = workspace
	local f = w:FindFirstChild("BasePlots") or w:FindFirstChild("Plots")
	if f then return f end
	for _, segName in ipairs({ "World", "Map", "Game", "Lobby", "Hub", "Main", "Terrain" }) do
		local seg = w:FindFirstChild(segName)
		if seg then
			f = seg:FindFirstChild("BasePlots") or seg:FindFirstChild("Plots")
			if f then return f end
		end
	end
	return nil
end

local function findMyPlot()
	local plotsFolder = findBasePlotsFolderClient()
	if not plotsFolder then return nil end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			return plot
		end
	end
	-- Fallback: server sometimes only stamps OwnerUserId on the creature orbs
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		for _, desc in ipairs(plot:GetDescendants()) do
			if desc:IsA("Model") then
				local ownerId = desc:GetAttribute("OwnerUserId")
				if ownerId == player.UserId then
					return plot
				end
			end
		end
	end
	return nil
end

local function getPlotCenterWorldPosition(plot)
	if not plot then return nil end
	local raw = plot:FindFirstChild("PlotCenter", true)
	if not raw then
		if plot:IsA("Model") then
			return plot:GetPivot().Position
		end
		return nil
	end
	if raw:IsA("BasePart") then
		return raw.Position
	end
	if raw:IsA("Model") then
		if raw.PrimaryPart then
			return raw.PrimaryPart.Position
		end
		local bp = raw:FindFirstChildWhichIsA("BasePart", true)
		return bp and bp.Position or nil
	end
	return nil
end

local function det3(a11, a12, a13, a21, a22, a23, a31, a32, a33)
	return a11 * (a22 * a33 - a23 * a32) - a12 * (a21 * a33 - a23 * a31) + a13 * (a21 * a32 - a22 * a31)
end

local function solveAffineFrom3(worldA, uvA, worldB, uvB, worldC, uvC)
	-- Solve:
	-- u = a*x + b*z + e
	-- v = c*x + d*z + f
	local x1, z1 = worldA.X, worldA.Y
	local x2, z2 = worldB.X, worldB.Y
	local x3, z3 = worldC.X, worldC.Y
	local u1, v1 = uvA.X, uvA.Y
	local u2, v2 = uvB.X, uvB.Y
	local u3, v3 = uvC.X, uvC.Y

	local D = det3(x1, z1, 1, x2, z2, 1, x3, z3, 1)
	if math.abs(D) < 1e-6 then
		return nil
	end

	local Da = det3(u1, z1, 1, u2, z2, 1, u3, z3, 1)
	local Db = det3(x1, u1, 1, x2, u2, 1, x3, u3, 1)
	local De = det3(x1, z1, u1, x2, z2, u2, x3, z3, u3)

	local Dc = det3(v1, z1, 1, v2, z2, 1, v3, z3, 1)
	local Dd = det3(x1, v1, 1, x2, v2, 1, x3, v3, 1)
	local Df = det3(x1, z1, v1, x2, z2, v2, x3, z3, v3)

	return {
		a = Da / D, b = Db / D, e = De / D,
		c = Dc / D, d = Dd / D, f = Df / D,
	}
end

local function getCalibration()
	local cal = WM.Calibration
	if type(cal) ~= "table" then return nil end
	if type(cal.A) ~= "table" or type(cal.B) ~= "table" or type(cal.C) ~= "table" then return nil end

	local function asV2(t)
		if typeof(t) == "Vector2" then return t end
		if type(t) ~= "table" then return nil end
		local x = tonumber(t.X or t.x or t[1])
		local y = tonumber(t.Y or t.y or t[2])
		if not x or not y then return nil end
		return Vector2.new(x, y)
	end

	local A_world = asV2(cal.A.world)
	local A_uv = asV2(cal.A.uv)
	local B_world = asV2(cal.B.world)
	local B_uv = asV2(cal.B.uv)
	local C_world = asV2(cal.C.world)
	local C_uv = asV2(cal.C.uv)
	if not (A_world and A_uv and B_world and B_uv and C_world and C_uv) then return nil end

	return solveAffineFrom3(A_world, A_uv, B_world, B_uv, C_world, C_uv)
end

local function worldXZToUV_fallback(worldPos, bounds)
	local spanX = math.max(1e-3, bounds.maxX - bounds.minX)
	local spanZ = math.max(1e-3, bounds.maxZ - bounds.minZ)
	local tx = (worldPos.X - bounds.minX) / spanX
	local tz = (worldPos.Z - bounds.minZ) / spanZ
	tx = math.clamp(tx, 0, 1)
	tz = math.clamp(tz, 0, 1)
	if WM.FlipWorldZOnMap then
		tz = 1 - tz
	end
	tx, tz = rotateUV(tx, tz)
	return math.clamp(tx, 0, 1), math.clamp(tz, 0, 1)
end

local function worldXZToUV(worldPos, bounds, affine)
	if affine then
		local u = affine.a * worldPos.X + affine.b * worldPos.Z + affine.e
		local v = affine.c * worldPos.X + affine.d * worldPos.Z + affine.f
		return math.clamp(u, 0, 1), math.clamp(v, 0, 1)
	end
	return worldXZToUV_fallback(worldPos, bounds)
end

local sg = Instance.new("ScreenGui")
sg.Name = "WorldMapGUI"
sg.ResetOnSpawn = false
sg.Enabled = true
sg.DisplayOrder = 96
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.ZIndex = 1
backdrop.Visible = false
backdrop.Parent = sg

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(400, 320)
panel.BackgroundColor3 = C.bg
panel.BackgroundTransparency = 0.02
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Visible = false
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", panel).Color = C.accent

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -80, 0, 36)
title.Position = UDim2.new(0, 14, 0, 6)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = C.white
title.Text = "World map"
title.ZIndex = 3
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.Size = UDim2.fromOffset(32, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 45)
closeBtn.BackgroundTransparency = 0.2
closeBtn.Text = "✕"
closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.AutoButtonColor = false
closeBtn.ZIndex = 3
closeBtn.Parent = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

local mapFrame = Instance.new("Frame")
mapFrame.Name = "MapFrame"
mapFrame.AnchorPoint = Vector2.new(0.5, 0)
mapFrame.Position = UDim2.new(0.5, 0, 0, 44)
mapFrame.Size = UDim2.new(0.92, 0, 1, -92)
mapFrame.BackgroundColor3 = Color3.fromRGB(8, 10, 16)
mapFrame.BorderSizePixel = 0
mapFrame.ZIndex = 2
mapFrame.ClipsDescendants = true
mapFrame.Parent = panel
Instance.new("UICorner", mapFrame).CornerRadius = UDim.new(0, 10)

local mapImage = Instance.new("ImageLabel")
mapImage.Name = "MapImage"
mapImage.Size = UDim2.fromScale(1, 1)
mapImage.BackgroundTransparency = 1
mapImage.ScaleType = Enum.ScaleType.Fit
mapImage.ZIndex = 2
mapImage.Parent = mapFrame

local placeholder = Instance.new("TextLabel")
placeholder.Name = "Placeholder"
placeholder.Size = UDim2.new(1, -20, 1, -20)
placeholder.Position = UDim2.new(0, 10, 0, 10)
placeholder.BackgroundTransparency = 1
placeholder.Font = Enum.Font.GothamMedium
placeholder.TextSize = 13
placeholder.TextColor3 = C.muted
placeholder.TextWrapped = true
placeholder.TextYAlignment = Enum.TextYAlignment.Center
placeholder.Text = "Upload your world map image to Roblox, then set GameConfig.WorldMap.ImageAssetId to rbxassetid://… in GameConfigData."
placeholder.Visible = true
placeholder.ZIndex = 3
placeholder.Parent = mapFrame

local marker = Instance.new("Frame")
marker.Name = "YouAreHere"
marker.AnchorPoint = Vector2.new(0.5, 0.5)
marker.Size = UDim2.fromOffset(14, 14)
marker.BackgroundColor3 = C.gold
marker.BorderSizePixel = 0
marker.ZIndex = 10
marker.Parent = mapFrame
Instance.new("UICorner", marker).CornerRadius = UDim.new(1, 0)
local mStroke = Instance.new("UIStroke", marker)
mStroke.Color = Color3.new(1, 1, 1)
mStroke.Thickness = 2

local baseMarker = Instance.new("Frame")
baseMarker.Name = "BaseMarker"
baseMarker.AnchorPoint = Vector2.new(0.5, 0.5)
baseMarker.Size = UDim2.fromOffset(12, 12)
baseMarker.BackgroundColor3 = C.base
baseMarker.BorderSizePixel = 0
baseMarker.ZIndex = 9
baseMarker.Visible = false
baseMarker.Parent = mapFrame
Instance.new("UICorner", baseMarker).CornerRadius = UDim.new(0, 4)
local bStroke = Instance.new("UIStroke", baseMarker)
bStroke.Color = Color3.new(0, 0, 0)
bStroke.Transparency = 0.35
bStroke.Thickness = 2

local baseLabel = Instance.new("TextLabel")
baseLabel.Name = "BaseLabel"
baseLabel.AnchorPoint = Vector2.new(0, 0.5)
baseLabel.Position = UDim2.new(0, 10, 0.5, 0)
baseLabel.Size = UDim2.fromOffset(80, 18)
baseLabel.BackgroundTransparency = 1
baseLabel.Font = Enum.Font.GothamBold
baseLabel.TextSize = 11
baseLabel.TextColor3 = C.white
baseLabel.TextStrokeTransparency = 0.6
baseLabel.TextXAlignment = Enum.TextXAlignment.Left
baseLabel.Text = "BASE"
baseLabel.ZIndex = 10
baseLabel.Visible = false
baseLabel.Parent = baseMarker

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -10)
hint.Size = UDim2.new(1, -24, 0, 22)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 11
hint.TextColor3 = C.muted
hint.Text = "[M] or HUD · Esc or ✕ to close"
hint.ZIndex = 3
hint.Parent = panel

local calHelp = Instance.new("TextLabel")
calHelp.Name = "CalHelp"
calHelp.AnchorPoint = Vector2.new(0.5, 0)
calHelp.Position = UDim2.new(0.5, 0, 0, 36)
calHelp.Size = UDim2.new(1, -24, 0, 18)
calHelp.BackgroundTransparency = 1
calHelp.Font = Enum.Font.GothamMedium
calHelp.TextSize = 11
calHelp.TextColor3 = C.muted
calHelp.Text = ""
calHelp.ZIndex = 4
calHelp.Visible = false
calHelp.Parent = panel

local function normalizeMapImageId(id)
	if type(id) ~= "string" then
		return nil
	end
	id = string.match(id, "^%s*(.-)%s*$") or id
	if id == "" then
		return nil
	end
	if string.match(id, "^rbxassetid://") then
		return id
	end
	if string.match(id, "^%d+$") then
		return "rbxassetid://" .. id
	end
	return nil
end

local function applyImage()
	local nid = normalizeMapImageId(WM.ImageAssetId)
	if nid then
		mapImage.Image = nid
		placeholder.Visible = false
	else
		mapImage.Image = ""
		placeholder.Visible = true
	end
end
applyImage()

local rsConn = nil
local openBounds = nil
local baseRetryAt = 0
local affine = nil
local calibrating = false
local calStep = 1
local calAnchors = { nil, nil, nil } -- { world=Vector2(x,z), uv=Vector2(u,v) }

local function printCalibrationBlock()
	local labels = { "A", "B", "C" }
	for i = 1, 3 do
		if not calAnchors[i] then return end
	end
	local function fmt(n)
		return string.format("%.6f", n)
	end
	local function fmtWorld(v2)
		return ("Vector2.new(%s, %s)"):format(fmt(v2.X), fmt(v2.Y))
	end
	local function fmtUV(v2)
		return ("Vector2.new(%s, %s)"):format(fmt(v2.X), fmt(v2.Y))
	end

	print("[WorldMapCalibration] Paste this into GameConfigData.lua under GameConfig.WorldMap.Calibration = { ... }")
	print("Calibration = {")
	for i = 1, 3 do
		local a = calAnchors[i]
		print(("  %s = { world = %s, uv = %s },"):format(labels[i], fmtWorld(a.world), fmtUV(a.uv)))
	end
	print("},")
end

local function updateCalHelp()
	if not calibrating then
		calHelp.Visible = false
		hint.Text = "[M] or HUD · Esc or ✕ to close"
		return
	end
	calHelp.Visible = true
	local stepName = ({ "A", "B", "C" })[calStep] or "?"
	calHelp.Text = ("CALIBRATE: Stand on landmark %s, then click it on the map. (Click = set %s)"):format(stepName, stepName)
	hint.Text = "[C] Exit calibrate · Esc/✕ close · After C, copy Output snippet"
end

local function setOpen(open)
	panel.Visible = open
	backdrop.Visible = open
	if open then
		openBounds = computeWorldXZBounds()
		baseRetryAt = 0
		affine = getCalibration()
		calibrating = false
		calStep = 1
		calAnchors = { nil, nil, nil }
		updateCalHelp()
		MobileWindowLayout.NotifyMenuOpened()
		if rsConn then
			rsConn:Disconnect()
		end
		rsConn = RunService.RenderStepped:Connect(function()
			local ch = player.Character
			local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart"))
			if not root then
				return
			end

			local b = openBounds
			local spanX = math.max(1e-3, b.maxX - b.minX)
			local spanZ = math.max(1e-3, b.maxZ - b.minZ)

			-- Base marker: resolve occasionally (plot replication can lag behind character spawn)
			if not baseMarker.Visible and tick() >= baseRetryAt then
				baseRetryAt = tick() + 0.75
				local plot = findMyPlot()
				local basePos = plot and getPlotCenterWorldPosition(plot)
				if basePos then
					local bx, bz = worldXZToUV(basePos, b, affine)
					baseMarker.Position = UDim2.new(bx, 0, bz, 0)
					baseMarker.Visible = true
					baseLabel.Visible = true
				end
			end

			local tx, tz = worldXZToUV(root.Position, b, affine)
			marker.Position = UDim2.new(tx, 0, tz, 0)
		end)
	else
		openBounds = nil
		affine = nil
		calibrating = false
		updateCalHelp()
		baseMarker.Visible = false
		baseLabel.Visible = false
		if rsConn then
			rsConn:Disconnect()
			rsConn = nil
		end
		MobileWindowLayout.NotifyMenuClosed()
	end
end

local function layoutPanel()
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	local fill = math.clamp(tonumber(WM.PanelFill) or 0.88, 0.4, 0.98)
	local short = math.min(vp.X, vp.Y) * fill
	local ar = math.max(0.5, tonumber(WM.MapAspectRatio) or 1.65)
	local mapW = short * 0.92
	local mapH = mapW / ar
	mapFrame.Size = UDim2.new(0.92, 0, 0, math.floor(mapH))
	panel.Size = UDim2.fromOffset(math.floor(short), math.floor(44 + mapH + 48))
end

layoutPanel()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layoutPanel)
end
MobileWindowLayout.BindViewportUpdate(layoutPanel)

local function toggle()
	setOpen(not panel.Visible)
end

closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)
backdrop.MouseButton1Click:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not panel.Visible then
		return
	end
	if input.KeyCode == Enum.KeyCode.C and WM.CalibrationEnabled == true then
		calibrating = not calibrating
		calStep = 1
		calAnchors = { nil, nil, nil }
		updateCalHelp()
		if not calibrating then
			-- when exiting, attempt to print if all points captured
			printCalibrationBlock()
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		setOpen(false)
	end
end)

mapFrame.InputBegan:Connect(function(input)
	if not panel.Visible or not calibrating then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local ch = player.Character
	local root = ch and (ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChildWhichIsA("BasePart"))
	if not root then
		return
	end
	local absPos = mapImage.AbsolutePosition
	local absSize = mapImage.AbsoluteSize
	if absSize.X <= 1 or absSize.Y <= 1 then
		return
	end
	local mousePos = UserInputService:GetMouseLocation()
	local u = (mousePos.X - absPos.X) / absSize.X
	local v = (mousePos.Y - absPos.Y) / absSize.Y
	u = math.clamp(u, 0, 1)
	v = math.clamp(v, 0, 1)

	calAnchors[calStep] = {
		world = Vector2.new(root.Position.X, root.Position.Z),
		uv = Vector2.new(u, v),
	}
	print(("[WorldMapCalibration] Set %s: world=(%.3f, %.3f) uv=(%.4f, %.4f)"):format(
		({ "A", "B", "C" })[calStep] or "?", root.Position.X, root.Position.Z, u, v
	))

	if calStep < 3 then
		calStep += 1
		updateCalHelp()
	else
		-- Done: print block + immediately apply for this session
		printCalibrationBlock()
		local a = calAnchors[1]
		local b = calAnchors[2]
		local c = calAnchors[3]
		local solved = solveAffineFrom3(a.world, a.uv, b.world, b.uv, c.world, c.uv)
		if solved then
			affine = solved
			print("[WorldMapCalibration] Applied solved calibration for this session. Paste into config to persist.")
		else
			print("[WorldMapCalibration] Could not solve (anchors collinear). Pick 3 points not in a straight line.")
		end
		calibrating = false
		updateCalHelp()
	end
end)

local function getHUDToggle()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = playerGui
	end
	return evt
end

local function onHUDToggle(menuName)
	if menuName == "WorldMapGUI" then
		layoutPanel()
		toggle()
	end
end

getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then
		child.Event:Connect(onHUDToggle)
	end
end)

print("[WorldMapClient] Loaded — set WorldMap.ImageAssetId after uploading map art; [M] to open")
