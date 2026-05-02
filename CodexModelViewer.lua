--[[
	CodexModelViewer.lua - ReplicatedStorage.Modules.CodexModelViewer (ModuleScript)
	Reusable interactive 3D model viewer for Codex and Inventory.
	- Drag to orbit (Y axis; optional X)
	- Mouse wheel to zoom
	- Auto-rotate option
	- Element-themed lighting, background, and floor
	- Creature animation support for viewport models (Idle by default; optional Income, etc.)
	- Safe mount/unmount from ReplicatedStorage.CreatureModels
	- LoadModelByAssetId(assetId) - load arbitrary models from catalog via InsertService
	- Placeholder when model missing (no errors)
]]

-- Last updated: 2026-04-22 22:45

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local InsertService = game:GetService("InsertService")

local CreatureData = nil
local CreatureAnimation = nil
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getCreatureData()
	if not CreatureData then
		CreatureData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CreatureData"))
	end
	return CreatureData
end

local function getCreatureAnimation()
	if CreatureAnimation == nil then
		local mod = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("CreatureAnimation")
		if mod then
			local ok, m = pcall(require, mod)
			CreatureAnimation = ok and m or false
		else
			CreatureAnimation = false
		end
	end
	return CreatureAnimation or nil
end

local CodexModelViewer = {}
CodexModelViewer.__index = CodexModelViewer

local DEFAULTS = {
	autoRotate = false,
	zoomEnabled = true,
	rotateSpeed = 0.5,
	zoomSpeed = 0.1,
	minZoom = 0.5,
	maxZoom = 100,
	autoRotateSpeed = 0.3,
	size = UDim2.new(1, 0, 1, 0),
	showFloor = true,
	themedLighting = true,
	playIdleAnimation = false,
	-- When playIdleAnimation: first animation to play ("Idle", "Income", …)
	defaultAnimType = "Idle",
	interactable = true,
	-- "full" (normal render) or "silhouette" (dark hidden-shape render).
	renderMode = "full",
	-- Multiplier applied to auto fit distance after model load (< 1 = camera closer / larger on screen).
	fillZoomScale = 1,
	-- If set (e.g. UDim.new(1, 0) for a circle on a square host), applies UICorner on the
	-- ViewportFrame. Parent Frame clipping does not mask 3D viewport output; this does.
	viewportCornerRadius = nil,
}
local START_ANGLE_Y = math.pi * 1.5 -- rotate start 90deg so model faces camera
local START_ANGLE_X = math.rad(12)

-- Element → { bg, ambient, lightColor, lightDir, floorColor, floorAccent }
local ELEMENT_THEMES = {
	Fire      = { bg = Color3.fromRGB(45, 18, 12),  ambient = Color3.fromRGB(140, 60, 30),   light = Color3.fromRGB(255, 160, 80),  dir = Vector3.new(-0.4, -0.8, -0.3), floor = Color3.fromRGB(60, 25, 15),  accent = Color3.fromRGB(255, 80, 20) },
	Ice       = { bg = Color3.fromRGB(14, 24, 42),  ambient = Color3.fromRGB(80, 120, 180),  light = Color3.fromRGB(180, 220, 255), dir = Vector3.new(-0.3, -0.7, -0.5), floor = Color3.fromRGB(20, 35, 55),  accent = Color3.fromRGB(100, 180, 255) },
	Water     = { bg = Color3.fromRGB(10, 22, 38),  ambient = Color3.fromRGB(40, 100, 160),  light = Color3.fromRGB(120, 200, 255), dir = Vector3.new(-0.2, -0.6, -0.6), floor = Color3.fromRGB(15, 30, 50),  accent = Color3.fromRGB(60, 160, 230) },
	Earth     = { bg = Color3.fromRGB(28, 24, 16),  ambient = Color3.fromRGB(120, 100, 60),  light = Color3.fromRGB(220, 200, 140), dir = Vector3.new(-0.5, -0.7, -0.4), floor = Color3.fromRGB(40, 35, 22),  accent = Color3.fromRGB(160, 140, 80) },
	Wind      = { bg = Color3.fromRGB(20, 30, 28),  ambient = Color3.fromRGB(100, 160, 140), light = Color3.fromRGB(200, 255, 220), dir = Vector3.new(-0.6, -0.5, -0.4), floor = Color3.fromRGB(25, 38, 34),  accent = Color3.fromRGB(120, 220, 180) },
	Lightning = { bg = Color3.fromRGB(22, 18, 36),  ambient = Color3.fromRGB(100, 80, 180),  light = Color3.fromRGB(200, 180, 255), dir = Vector3.new(-0.3, -0.8, -0.3), floor = Color3.fromRGB(28, 22, 45),  accent = Color3.fromRGB(180, 120, 255) },
	Shadow    = { bg = Color3.fromRGB(12, 10, 18),  ambient = Color3.fromRGB(60, 40, 80),    light = Color3.fromRGB(140, 100, 180), dir = Vector3.new(-0.4, -0.6, -0.5), floor = Color3.fromRGB(18, 14, 24),  accent = Color3.fromRGB(120, 60, 160) },
	Light     = { bg = Color3.fromRGB(38, 36, 28),  ambient = Color3.fromRGB(180, 170, 120), light = Color3.fromRGB(255, 245, 200), dir = Vector3.new(-0.5, -0.7, -0.4), floor = Color3.fromRGB(45, 42, 32),  accent = Color3.fromRGB(255, 230, 140) },
	Psychic   = { bg = Color3.fromRGB(30, 14, 30),  ambient = Color3.fromRGB(140, 60, 140),  light = Color3.fromRGB(240, 140, 240), dir = Vector3.new(-0.3, -0.7, -0.5), floor = Color3.fromRGB(38, 18, 38),  accent = Color3.fromRGB(200, 80, 200) },
}
local DEFAULT_THEME = { bg = Color3.fromRGB(30, 32, 45), ambient = Color3.fromRGB(100, 100, 120), light = Color3.new(1, 1, 1), dir = Vector3.new(-0.5, -0.7, -0.5), floor = Color3.fromRGB(35, 38, 50), accent = Color3.fromRGB(80, 100, 140) }

local function cloneForViewport(creatureId, skipAnchor)
	local data = getCreatureData().GetById(creatureId)
	if not data then return nil, "missing_creature_data" end
	local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")
	local loaderScript = modulesFolder and modulesFolder:FindFirstChild("CreatureModelLoader")
	if not loaderScript then
		return nil, "missing_creature_model_loader_module"
	end
	local CreatureModelLoader = require(loaderScript)
	local tempModel = Instance.new("Model")
	tempModel.Name = data.modelName or "ViewportClone"
	local body, core, ok = CreatureModelLoader.LoadAndIntegrate(tempModel, data.modelName, data.displayName, nil, {
		targetSize = 5,
		creatureId = creatureId,
	})
	if not ok or not body then
		tempModel:Destroy()
		return nil, "template_not_found_or_body_missing"
	end
	for _, desc in ipairs(tempModel:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then desc:Destroy() end
		if desc:IsA("BasePart") then
			if not skipAnchor then desc.Anchored = true end
			desc.CanCollide = false
		end
	end
	return tempModel, nil
end

local function centerModelAtOrigin(obj)
	local ok, cf, size = pcall(function()
		if obj:IsA("Model") then return obj:GetBoundingBox() end
		if obj:IsA("BasePart") then return obj.CFrame, obj.Size end
		return nil, nil
	end)
	if not ok or not cf then return Vector3.new(0, 0, 0), Vector3.new(4, 4, 4) end
	local center = cf.Position
	if obj:IsA("Model") then
		obj:PivotTo(CFrame.new(-center) * obj:GetPivot())
	elseif obj:IsA("BasePart") then
		obj.CFrame = CFrame.new(-center) * obj.CFrame
	end
	return center, size
end

local function getModelFitZoom(obj)
	local ok, cf, size = pcall(function()
		if obj:IsA("Model") then return obj:GetBoundingBox() end
		if obj:IsA("BasePart") then return obj.CFrame, obj.Size end
		return nil, nil
	end)
	if not ok or not size then return 5 end
	local maxDim = math.max(size.X, size.Y, size.Z)
	if maxDim < 0.01 then return 5 end
	return math.max(3, maxDim * 1.4)
end

local function getModelBoundsSize(obj)
	local ok, cf, size = pcall(function()
		if obj:IsA("Model") then return obj:GetBoundingBox() end
		if obj:IsA("BasePart") then return obj.CFrame, obj.Size end
		return nil, nil
	end)
	if not ok or not size then return Vector3.new(4, 4, 4) end
	return size
end

local function createFloor(world, theme, modelSize, placementYOffset)
	placementYOffset = placementYOffset or 0
	local floorRadius = math.max(modelSize.X, modelSize.Z) * 0.8 + 2
	local floor = Instance.new("Part")
	floor.Name = "ViewerFloor"
	floor.Shape = Enum.PartType.Cylinder
	floor.Size = Vector3.new(0.15, floorRadius * 2, floorRadius * 2)
	-- Match base placement feel: distance from model center to floor is
	-- (modelSize.Y / 2) plus any per-creature modelPlacementYOffset that lifts
	-- defense/income creatures off their point. Since the viewer recenters the
	-- model at origin, we push the floor downward by that combined offset.
	local floorY = -modelSize.Y * 0.5 - placementYOffset - 0.08
	floor.CFrame = CFrame.new(0, floorY, 0) * CFrame.Angles(0, 0, math.rad(90))
	floor.Anchored = true
	floor.CanCollide = false
	floor.Color = theme.floor
	floor.Material = Enum.Material.SmoothPlastic
	floor.TopSurface = Enum.SurfaceType.Smooth
	floor.BottomSurface = Enum.SurfaceType.Smooth
	floor.Parent = world

	local ring = Instance.new("Part")
	ring.Name = "FloorRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.05, (floorRadius + 0.3) * 2, (floorRadius + 0.3) * 2)
	ring.CFrame = floor.CFrame
	ring.Anchored = true
	ring.CanCollide = false
	ring.Color = theme.accent
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.5
	ring.Parent = world

	return floor, ring
end

function CodexModelViewer.new(parent, options)
	options = options or {}
	local self = setmetatable({}, CodexModelViewer)
	self.autoRotate = options.autoRotate == nil and DEFAULTS.autoRotate or options.autoRotate
	self.zoomEnabled = options.zoomEnabled == nil and DEFAULTS.zoomEnabled or options.zoomEnabled
	self.rotateSpeed = options.rotateSpeed or DEFAULTS.rotateSpeed
	self.zoomSpeed = options.zoomSpeed or DEFAULTS.zoomSpeed
	self.minZoom = options.minZoom or DEFAULTS.minZoom
	self.maxZoom = options.maxZoom or DEFAULTS.maxZoom
	self.autoRotateSpeed = options.autoRotateSpeed or DEFAULTS.autoRotateSpeed
	self.showFloor = options.showFloor == nil and DEFAULTS.showFloor or options.showFloor
	self.themedLighting = options.themedLighting == nil and DEFAULTS.themedLighting or options.themedLighting
	self.playIdleAnimation = options.playIdleAnimation == nil and DEFAULTS.playIdleAnimation or options.playIdleAnimation
	self.interactable = options.interactable == nil and DEFAULTS.interactable or options.interactable
	self.renderMode = options.renderMode or DEFAULTS.renderMode
	self._fillZoomScale = options.fillZoomScale == nil and DEFAULTS.fillZoomScale or options.fillZoomScale

	self._angleY = START_ANGLE_Y
	self._angleX = START_ANGLE_X
	self._zoom = 5
	self._currentCreatureId = nil
	self._customAssetId = nil
	self._model = nil
	self._floor = nil
	self._floorRing = nil
	self._dragging = false
	self._lastInputPos = nil
	self._lastAutoRotateTime = nil
	self._heartbeatConn = nil

	local vf = Instance.new("ViewportFrame")
	vf.Name = "CodexViewer"
	vf.Size = options.size or DEFAULTS.size
	vf.BackgroundColor3 = Color3.fromRGB(30, 32, 45)
	vf.BorderSizePixel = 0
	vf.BackgroundTransparency = 0
	vf.Parent = parent
	local cornerR = options.viewportCornerRadius
	if cornerR == nil then cornerR = DEFAULTS.viewportCornerRadius end
	if cornerR ~= nil then
		vf.ClipsDescendants = true
		local cr = Instance.new("UICorner", vf)
		cr.CornerRadius = cornerR
	end

	local cam = Instance.new("Camera")
	cam.CameraType = Enum.CameraType.Scriptable
	cam.Parent = vf
	vf.CurrentCamera = cam
	local world = Instance.new("WorldModel")
	world.Name = "ViewerWorld"
	world.Parent = vf

	vf.Ambient = Color3.fromRGB(100, 100, 120)
	vf.LightColor = Color3.new(1, 1, 1)
	vf.LightDirection = Vector3.new(-0.5, -0.7, -0.5).Unit

	self._viewport = vf
	self._camera = cam
	self._world = world
	self:_updateCamera()

	local function onInputBegan(input, gpe)
		if not self.interactable or gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = true
			self._lastInputPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end
	local function onInputChanged(input, gpe)
		if not self.interactable or not self._dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			local delta = pos - self._lastInputPos
			self._lastInputPos = pos
			self._angleY = self._angleY - delta.X * self.rotateSpeed * 0.01
			self._angleX = self._angleX - delta.Y * self.rotateSpeed * 0.01
			self._angleX = math.clamp(self._angleX, -math.rad(80), math.rad(80))
			self:_updateCamera()
		end
	end
	local function onInputEnded(input, gpe)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = false
		end
	end
	local function onWheel(input, gpe)
		if not self.interactable or gpe then return end
		if not self.zoomEnabled then return end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local delta = input.Position.Z
			self._zoom = math.clamp(self._zoom - delta * self.zoomSpeed, self.minZoom, self.maxZoom)
			self:_updateCamera()
		end
	end

	vf.InputBegan:Connect(onInputBegan)
	vf.InputChanged:Connect(onInputChanged)
	vf.InputEnded:Connect(onInputEnded)
	vf.InputChanged:Connect(onWheel)
	vf.Active = self.interactable

	local function startAutoRotate()
		if self._heartbeatConn then return end
		self._lastAutoRotateTime = tick()
		self._heartbeatConn = RunService.Heartbeat:Connect(function()
			if not self._dragging and self.autoRotate then
				local now = tick()
				self._angleY = self._angleY + self.autoRotateSpeed * (now - (self._lastAutoRotateTime or now))
				self._lastAutoRotateTime = now
				self:_updateCamera()
			end
		end)
	end
	local function stopAutoRotate()
		if self._heartbeatConn then
			self._heartbeatConn:Disconnect()
			self._heartbeatConn = nil
		end
	end
	self._startAutoRotate = startAutoRotate
	self._stopAutoRotate = stopAutoRotate
	if self.autoRotate then startAutoRotate() end

	self.Destroy = function()
		stopAutoRotate()
		self:SetCreature(nil)
		vf:Destroy()
	end

	return self
end

function CodexModelViewer:_applyRenderModeToModel()
	if not self._model then return end
	if self.renderMode ~= "silhouette" then return end
	for _, desc in ipairs(self._model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Color = Color3.fromRGB(42, 47, 60)
			desc.Material = Enum.Material.SmoothPlastic
			desc.Transparency = math.max(desc.Transparency, 0)
			if desc:IsA("MeshPart") then
				desc.TextureID = ""
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		elseif desc:IsA("SpecialMesh") then
			desc.TextureId = ""
		end
	end
end

function CodexModelViewer:SetRenderMode(mode)
	if mode == "silhouette" then
		self.renderMode = "silhouette"
	else
		self.renderMode = "full"
	end
	-- Re-apply on current model only for silhouette; full is naturally restored on SetCreature reload.
	if self._model and self.renderMode == "silhouette" then
		self:_applyRenderModeToModel()
	end
end

function CodexModelViewer:_updateCamera()
	local r = self._zoom
	local ay, ax = self._angleY, self._angleX
	local x = math.sin(ay) * math.cos(ax) * r
	local z = math.cos(ay) * math.cos(ax) * r
	local y = math.sin(ax) * r
	local pos = Vector3.new(x, y, z)
	self._camera.CFrame = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
end

function CodexModelViewer:_applyTheme(element)
	if not self.themedLighting then return end
	local theme = ELEMENT_THEMES[element] or DEFAULT_THEME
	local vf = self._viewport
	vf.BackgroundColor3 = theme.bg
	vf.Ambient = theme.ambient
	vf.LightColor = theme.light
	vf.LightDirection = theme.dir.Unit
	return theme
end

function CodexModelViewer:_clearFloor()
	if self._floor then self._floor:Destroy(); self._floor = nil end
	if self._floorRing then self._floorRing:Destroy(); self._floorRing = nil end
end

function CodexModelViewer:_tryPlayIdle(creatureId)
	if not self.playIdleAnimation then return end
	local anim = getCreatureAnimation()
	if not anim or not self._model then return end
	local animType = self.defaultAnimType or "Idle"
	pcall(function()
		if anim.PlayAnimation then
			anim.PlayAnimation(self._model, animType, creatureId)
		else
			anim.Setup(self._model, creatureId, animType)
		end
	end)
end

-- Explicit animation control for external UIs (e.g. Inventory details).
-- stateName: "Idle", "Move" (walking), "Income", "Attack", "Special" (CreatureAnimation.PlayAnimation).
function CodexModelViewer:PlayAnimationState(stateName)
	local anim = getCreatureAnimation()
	if not anim or not self._model or not self._currentCreatureId then return end
	if type(stateName) ~= "string" or stateName == "" then return end
	local animType = (stateName == "Walking") and "Move" or stateName
	pcall(function()
		if anim.PlayAnimation then
			anim.PlayAnimation(self._model, animType, self._currentCreatureId)
		else
			anim.Setup(self._model, self._currentCreatureId, animType)
		end
	end)
end

function CodexModelViewer:SetCreature(creatureId)
	-- Always fully reset viewport state before loading next creature.
	-- This prevents stale models/background from carrying over between selections.
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	self:_clearFloor()
	if self._world then
		for _, child in ipairs(self._world:GetChildren()) do
			child:Destroy()
		end
	end
	self._currentCreatureId = creatureId
	self._customAssetId = nil
	self._zoom = 5
	self._angleY = START_ANGLE_Y
	self._angleX = START_ANGLE_X
	if self.themedLighting then
		self:_applyTheme(nil) -- reset background/light to default theme before next model
	end
	self:_updateCamera()
	if not creatureId then return end

	local data = getCreatureData().GetById(creatureId)
	if not data then return end

	local theme = self:_applyTheme(data.element) or DEFAULT_THEME

	local clone, cloneErr = cloneForViewport(creatureId, self.playIdleAnimation)
	if clone then
		if not clone.PrimaryPart then
			clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart", true)
		end
		clone.Parent = self._world or self._viewport
		local _, modelSize = centerModelAtOrigin(clone)
		-- Match income/favorite orientation: apply same stand-up + yaw as base placement,
		-- then +90° Y (180° from prior setting) so Siegelings face the viewport camera.
		local cd = getCreatureData()
		if cd and cd.GetModelRotationOffset and clone:IsA("Model") then
			local rotOffset = cd.GetModelRotationOffset(creatureId, "companion", false) or CFrame.identity
			local faceForward = CFrame.Angles(0, math.rad(90), 0)
			clone:PivotTo(clone:GetPivot() * rotOffset * faceForward)
		end
		self._model = clone
		self._zoom = math.clamp(getModelFitZoom(clone) * (self._fillZoomScale or 1), self.minZoom, self.maxZoom)

		if self.showFloor then
			local sz = getModelBoundsSize(clone)
			-- Use same vertical feel as base income/defense placement by applying
			-- the per-creature modelPlacementYOffset here too.
			local placementYOffset = 0
			local cd = getCreatureData()
			if cd and cd.GetModelPlacementYOffset and data then
				placementYOffset = cd.GetModelPlacementYOffset(data) or 0
			end
			self._floor, self._floorRing = createFloor(self._world or self._viewport, theme, sz, placementYOffset)
		end

		self:_updateCamera()
		self:_applyRenderModeToModel()
		if self.renderMode ~= "silhouette" then
			self:_tryPlayIdle(creatureId)
		end
	else
		local part = Instance.new("Part")
		part.Name = "Placeholder"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(4, 4, 4)
		part.Position = Vector3.new(0, 0, 0)
		part.Anchored = true
		part.CanCollide = false
		part.Color = data.primaryColor or Color3.fromRGB(100, 100, 100)
		part.Material = Enum.Material.Neon
		part.Parent = self._world or self._viewport
		self._model = part

		if self.showFloor then
			self._floor, self._floorRing = createFloor(self._world or self._viewport, theme, Vector3.new(4, 4, 4), 0)
		end

		self._zoom = math.clamp(6 * (self._fillZoomScale or 1), self.minZoom, self.maxZoom)
	end
	self:_applyRenderModeToModel()
	self:_updateCamera()
end

function CodexModelViewer:LoadModelByAssetId(assetId)
	-- Hard reset viewer state before loading arbitrary catalog model.
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	self:_clearFloor()
	if self._world then
		for _, child in ipairs(self._world:GetChildren()) do
			child:Destroy()
		end
	end
	self._currentCreatureId = nil
	self._customAssetId = assetId
	self._zoom = 5
	self._angleY = START_ANGLE_Y
	self._angleX = START_ANGLE_X
	if self.themedLighting then
		self:_applyTheme(nil)
	end
	self:_updateCamera()

	local id = tonumber(assetId and assetId:match("%d+"))
	if not id then return false end

	local success, model = pcall(InsertService.LoadAsset, InsertService, id)
	if not success or not model then return false end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CastShadow = false
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		end
	end
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanCollide = false
		model.CastShadow = false
	end

	model.Parent = self._world or self._viewport
	pcall(function()
		if model:IsA("Model") then model:PivotTo(CFrame.new(0, 0, 0)) end
	end)
	centerModelAtOrigin(model)
	self._model = model

	local fitZoom = getModelFitZoom(model)
	self._zoom = math.clamp(math.max(fitZoom * 1.5, 5), self.minZoom, self.maxZoom)
	self:_updateCamera()
	return true
end

function CodexModelViewer:SetAutoRotate(on)
	self.autoRotate = on
	if on then self._startAutoRotate() else self._stopAutoRotate() end
end

function CodexModelViewer:GetViewportFrame()
	return self._viewport
end

function CodexModelViewer:CaptureSnapshotAsync()
	local vf = self._viewport
	if not vf or not self._model then return nil end
	self._angleY = 0
	self._angleX = math.rad(10)
	self:_updateCamera()
	task.wait()
	task.wait()
	local ok, contentId = pcall(function()
		return vf:CaptureSnapshotAsync()
	end)
	if not ok or not contentId or contentId == "" then return nil end
	local img = Instance.new("ImageLabel")
	img.Name = "CodexSnapshot"
	img.Size = UDim2.new(1, 0, 1, 0)
	img.BackgroundTransparency = 1
	img.Image = contentId
	img.ScaleType = Enum.ScaleType.Fit
	return img
end

return CodexModelViewer
