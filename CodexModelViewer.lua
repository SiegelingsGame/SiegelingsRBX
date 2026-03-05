--[[
	CodexModelViewer.lua - ReplicatedStorage.Modules.CodexModelViewer (ModuleScript)
	Reusable interactive 3D model viewer for Codex (and elsewhere).
	- Drag to orbit (Y axis; optional X)
	- Mouse wheel to zoom
	- Auto-rotate option
	- Safe mount/unmount from ReplicatedStorage.CreatureModels
	- LoadModelByAssetId(assetId) - load arbitrary models from catalog via InsertService
	- Placeholder when model missing (no errors)
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local InsertService = game:GetService("InsertService")

local CreatureData = nil
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getCreatureData()
	if not CreatureData then
		CreatureData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CreatureData"))
	end
	return CreatureData
end

local CodexModelViewer = {}
CodexModelViewer.__index = CodexModelViewer

-- Default config
local DEFAULTS = {
	autoRotate = false,
	zoomEnabled = true,
	rotateSpeed = 0.5,
	zoomSpeed = 0.1,
	minZoom = 0.5,
	maxZoom = 100,  -- allow large catalog models (e.g. InsertService.LoadAsset)
	autoRotateSpeed = 0.3,
	size = UDim2.new(1, 0, 1, 0),
}

-- Create a clone for viewport using LoadAndIntegrate so scaling matches world/companion
-- (LoadTemplate alone skips scaling; raw models can be 0.01 or 100 studs = invisible or huge)
local function cloneForViewport(creatureId)
	local data = getCreatureData():GetById(creatureId)
	if not data then return nil end
	local CreatureModelLoader = require(ReplicatedStorage.Modules:FindFirstChild("CreatureModelLoader"))
	local tempModel = Instance.new("Model")
	tempModel.Name = data.modelName or "ViewportClone"
	local body, core, ok = CreatureModelLoader.LoadAndIntegrate(tempModel, data.modelName, data.displayName, nil, {
		targetSize = 5,  -- nice size for codex viewport (matches typical creature display)
		creatureId = creatureId,
	})
	if not ok or not body then return nil end
	-- Strip scripts, anchor all parts for safe viewport display
	for _, desc in ipairs(tempModel:GetDescendants()) do
		if desc:IsA("Script") or desc:IsA("LocalScript") or desc:IsA("ModuleScript") then desc:Destroy() end
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end
	return tempModel
end

-- Center model at origin so camera orbit looks correct (works for Model or single BasePart)
local function centerModelAtOrigin(obj)
	local ok, cf, size = pcall(function()
		if obj:IsA("Model") then return obj:GetBoundingBox() end
		if obj:IsA("BasePart") then return obj.CFrame, obj.Size end
		return nil, nil
	end)
	if not ok or not cf then return end
	local center = cf.Position
	if obj:IsA("Model") then
		obj:PivotTo(CFrame.new(-center) * obj:GetPivot())
	elseif obj:IsA("BasePart") then
		obj.CFrame = CFrame.new(-center) * obj.CFrame
	end
end

local function getModelFitZoom(obj)
	local ok, cf, size = pcall(function()
		if obj:IsA("Model") then return obj:GetBoundingBox() end
		if obj:IsA("BasePart") then return obj.CFrame, obj.Size end
		return nil, nil
	end)
	if not ok or not size then return 2 end
	local maxDim = math.max(size.X, size.Y, size.Z)
	if maxDim < 0.01 then return 2 end
	return math.max(1.5, maxDim * 0.8)
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

	self._angleY = 0
	self._angleX = 0
	self._zoom = 2
	self._currentCreatureId = nil
	self._customAssetId = nil
	self._model = nil
	self._dragging = false
	self._lastInputPos = nil
	self._lastAutoRotateTime = nil
	self._heartbeatConn = nil

	local vf = Instance.new("ViewportFrame")
	vf.Name = "CodexViewer"
	vf.Size = options.size or DEFAULTS.size
	vf.BackgroundColor3 = Color3.fromRGB(30, 32, 45)
	vf.BorderSizePixel = 0
	vf.Parent = parent

	local cam = Instance.new("Camera")
	cam.CameraType = Enum.CameraType.Scriptable
	cam.Parent = vf
	vf.CurrentCamera = cam

	-- ViewportFrame lighting (uses built-in Ambient/LightColor/LightDirection only;
	-- DirectionalLight cannot be parented to ViewportFrame)
	vf.Ambient = Color3.fromRGB(100, 100, 120)
	vf.LightColor = Color3.new(1, 1, 1)
	vf.LightDirection = Vector3.new(-0.5, -0.7, -0.5).Unit

	self._viewport = vf
	self._camera = cam
	self:_updateCamera()

	-- Input: drag to rotate
	local function onInputBegan(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = true
			self._lastInputPos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end
	local function onInputChanged(input, gpe)
		if not self._dragging then return end
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
		if gpe then return end
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

	-- Auto-rotate (delta-time so speed is consistent across frame rates)
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

function CodexModelViewer:_updateCamera()
	local r = self._zoom
	local ay, ax = self._angleY, self._angleX
	local x = math.sin(ay) * math.cos(ax) * r
	local z = math.cos(ay) * math.cos(ax) * r
	local y = math.sin(ax) * r
	self._camera.CFrame = CFrame.new(x, y, z) * CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(0, 0, 0))
end

function CodexModelViewer:SetCreature(creatureId)
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	self._currentCreatureId = creatureId
	self._customAssetId = nil
	if not creatureId then return end

	local data = getCreatureData():GetById(creatureId)
	if not data then return end

	local clone = cloneForViewport(creatureId)
	if clone then
		clone.Parent = self._viewport
		pcall(centerModelAtOrigin, clone)
		self._model = clone
		self._zoom = math.clamp(getModelFitZoom(clone), self.minZoom, self.maxZoom)
		self:_updateCamera()
	else
		-- Placeholder: visible colored sphere when no mesh exists (large so it's not a tiny dot)
		local part = Instance.new("Part")
		part.Name = "Placeholder"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(2.5, 2.5, 2.5)
		part.Position = Vector3.new(0, 0, 0)
		part.Anchored = true
		part.CanCollide = false
		part.Color = data.primaryColor or Color3.fromRGB(100, 100, 100)
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = self._viewport
		self._model = part
		self._zoom = math.clamp(2.5, self.minZoom, self.maxZoom)
	end
	self:_updateCamera()
end

--- Load any model by Roblox asset ID (InsertService.LoadAsset).
--- Use for previewing catalog models in the Codex.
--- Returns true on success, false on failure.
function CodexModelViewer:LoadModelByAssetId(assetId)
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	self._currentCreatureId = nil
	self._customAssetId = assetId

	local id = tonumber(assetId and assetId:match("%d+"))
	if not id then return false end

	local success, model = pcall(InsertService.LoadAsset, InsertService, id)
	if not success or not model then return false end

	-- Clean and prepare model for viewport
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

	model.Parent = self._viewport
	pcall(function()
		if model:IsA("Model") then model:PivotTo(CFrame.new(0, 0, 0)) end
	end)
	centerModelAtOrigin(model)
	self._model = model

	local fitZoom = getModelFitZoom(model)
	-- Scale distance so model fits (getModelFitZoom ≈ maxDim*0.8; we want distance ≈ maxDim*1.2)
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

--- Capture a 2D snapshot of the front of the model (face +Z) as a static ImageLabel.
--- Use when ViewportFrame display fails - shows a static image instead.
--- Yields. Returns ImageLabel on success, nil on failure. Caller parents the ImageLabel.
--- Requires ViewportFrame.CaptureSnapshotAsync (Roblox 645+).
function CodexModelViewer:CaptureSnapshotAsync()
	local vf = self._viewport
	if not vf or not self._model then return nil end
	-- Face camera at front of model (angleY=0 looks down -Z, so model faces us)
	self._angleY = 0
	self._angleX = math.rad(10)
	self:_updateCamera()
	-- Wait for render
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
