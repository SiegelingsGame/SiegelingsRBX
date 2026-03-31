--[[
	CreatureModelLoader.lua - ReplicatedStorage.Modules (ModuleScript)
	Loads creature models from ReplicatedStorage.CreatureModels.
	Prioritizes Model type (BreezeeModel, Model_Breezee) over legacy mesh (Breezee).
	Blender-imported rigs: Humanoid, AnimationController, nested bones under Meshy_Mesh.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)

local CreatureModelLoader = {}

local MODELS_FOLDER = "CreatureModels"

--- Names to try when locating a template (Model type first, then legacy mesh)
-- Convention: CreatureNameModel or Model_CreatureName for rigged/skeletal models
local function getTemplateNames(modelName, displayName)
	local names, seen = {}, {}
	local function add(n)
		if n and n ~= "" and not seen[n] then seen[n] = true; table.insert(names, n) end
	end
	if modelName then
		-- Model type first (BreezeeModel, Model_Breezee)
		add(modelName .. "Model")
		add("Model_" .. modelName)
		-- Legacy mesh fallback
		add(modelName)
	end
	if displayName and displayName ~= modelName then
		add(displayName .. "Model")
		add("Model_" .. displayName)
		add(displayName)
	end
	return names
end

--- Finds the part to use for position/adornee. Handles both legacy mesh and Blender-imported rigs.
-- Blender FBX import: Humanoid + HumanoidRootPart, or root bone; PrimaryPart often set by importer.
function CreatureModelLoader.GetBodyPart(model)
	if not model then return nil end
	-- Humanoid rigs (Blender character import): HumanoidRootPart is the root
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	-- Direct Body (legacy mesh)
	local body = model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then return body end
	-- Nested Body (rigged model with Body inside Meshy_Mesh etc.)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "Body" and d:IsA("BasePart") then return d end
	end
	-- PrimaryPart (importer often sets this for rig root)
	if model.PrimaryPart then return model.PrimaryPart end
	-- Fallbacks
	return model:FindFirstChildWhichIsA("MeshPart", true) or model:FindFirstChildWhichIsA("BasePart", true)
end

--- Loads a creature template. Tries Model type first, then legacy mesh.
-- Returns: clone (Model or BasePart), matchedName (string), or nil, nil if not found.
function CreatureModelLoader.LoadTemplate(modelName, displayName, timeout)
	timeout = timeout or 2
	local modelsFolder = game:GetService("ReplicatedStorage"):FindFirstChild(MODELS_FOLDER)
		or game:GetService("ReplicatedStorage"):WaitForChild(MODELS_FOLDER, timeout)
	if not modelsFolder then return nil, nil end

	for _, name in ipairs(getTemplateNames(modelName, displayName)) do
		local template = modelsFolder:FindFirstChild(name) or modelsFolder:WaitForChild(name, 0.5)
		if template then return template:Clone(), name end
	end
	return nil, nil
end

--- Integrates a template into a creature model. Returns body, core (or nil), and whether a custom model was used.
function CreatureModelLoader.IntegrateTemplate(creatureModel, template, position)
	local body, core
	if template:IsA("Model") then
		for _, child in ipairs(template:GetChildren()) do
			child.Parent = creatureModel
		end
		body = CreatureModelLoader.GetBodyPart(creatureModel)
		body = body or template.PrimaryPart or creatureModel:FindFirstChildWhichIsA("BasePart", true)
		template:Destroy()
	elseif template:IsA("BasePart") or template:IsA("MeshPart") then
		template.Name = "Body"
		template.Parent = creatureModel
		body = template
	end

	if body then
		-- Keep HumanoidRootPart name for fgHumanoid compatibility (Blender-imported rigs)
		if body.Name ~= "HumanoidRootPart" then body.Name = "Body" end
		body.Anchored = true
		body.CanCollide = true  -- monsters collide with walls; prevents clipping through terrain
		body.CastShadow = true
		if position then body.Position = position end
		creatureModel.PrimaryPart = body
	end
	-- Disable Humanoid physics so rig doesn't fall/tip (we move it manually)
	local humanoid = creatureModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end
	-- Ensure Model-type (rigged) temsplates have AnsimationController+Animator for scripted animations
	if template:IsA("Model") then
		local hasAnim = false
		for _, d in ipairs(creatureModel:GetDescendants()) do
			if d:IsA("AnimationController") or d:IsA("Animator") then
				hasAnim = true
				break
			end
		end
		if not hasAnim then
			local ac = Instance.new("AnimationController")
			local animator = Instance.new("Animator")
			animator.Parent = ac
			ac.Parent = creatureModel
		end
	end
	core = creatureModel:FindFirstChild("Core")
	return body, core
end

--- Returns true if any template exists for the creature (Model type or legacy mesh).
function CreatureModelLoader.HasTemplate(modelName, displayName)
	local modelsFolder = game:GetService("ReplicatedStorage"):FindFirstChild(MODELS_FOLDER)
	if not modelsFolder then return false end
	for _, name in ipairs(getTemplateNames(modelName, displayName)) do
		if modelsFolder:FindFirstChild(name) then return true end
	end
	return false
end

--- Scale to match target size. Models use ScaleTo; MeshPart/legacy scale body Size.
-- options.targetSize = desired max dimension. options.creatureId = for per-creature overrides.
-- CreatureData: modelDisplaySize (override targetSize), modelScaleMultiplier (fine-tune: 1.5 = 50% larger).
local function applyModelTransform(creatureModel, body, isModelType, options)
	local targetSize = options and options.targetSize and options.targetSize > 0 and options.targetSize or nil
	local scaleMultiplier = 1
	if options and options.creatureId then
		local info = CreatureData.GetById(options.creatureId)
		if info then
			if info.modelDisplaySize and info.modelDisplaySize > 0 then
				targetSize = info.modelDisplaySize
			end
			if info.modelScaleMultiplier and info.modelScaleMultiplier > 0 then
				scaleMultiplier = info.modelScaleMultiplier
			end
		end
	end
	if not targetSize then return end

	if isModelType then
		-- Rigged Model: try body part first (consistent for same-rig evolutions), then GetBoundingBox
		local maxDim = nil
		if body and body:IsA("BasePart") then
			local sz = body.Size
			maxDim = math.max(sz.X, sz.Y, sz.Z)
		end
		if not maxDim or maxDim < 0.001 then
			local ok, _, bboxSize = pcall(function() return creatureModel:GetBoundingBox() end)
			if ok and bboxSize then
				maxDim = math.max(bboxSize.X, bboxSize.Y, bboxSize.Z)
			end
		end
		if maxDim and maxDim > 0.001 then
			creatureModel:ScaleTo((targetSize / maxDim) * scaleMultiplier)
		end
	else
		-- Legacy mesh: scale the body part directly
		if body and body:IsA("BasePart") then
			local sz = body.Size
			local maxDim = math.max(sz.X, sz.Y, sz.Z)
			if maxDim > 0.001 then
				body.Size = sz * (targetSize / maxDim) * scaleMultiplier
			end
		end
	end
end

--- Load template and integrate. Returns body, core, success (true if custom model loaded).
-- options: { targetSize = number, creatureId = string } — scale to targetSize; creatureId for per-creature modelDisplaySize
function CreatureModelLoader.LoadAndIntegrate(creatureModel, modelName, displayName, position, options)
	local template, matchedName = CreatureModelLoader.LoadTemplate(modelName, displayName)
	if not template then
		return nil, nil, false
	end
	local isModelType = template:IsA("Model")
	local ok, body, core = pcall(CreatureModelLoader.IntegrateTemplate, creatureModel, template, position)
	if not ok then
		return nil, nil, false
	end
	if body and creatureModel then
		creatureModel:SetAttribute("TemplateName", matchedName)
		creatureModel:SetAttribute("TemplateType", isModelType and "Model" or "Mesh")
		pcall(applyModelTransform, creatureModel, body, isModelType, options or {})
	end
	return body, core, body ~= nil
end

--- Returns StudsOffset.Y so a billboard sits at the top of the model's bounding box (avoids name being blocked by body).
--- adornee: the part the BillboardGui adorns (usually body). Falls back to model.PrimaryPart or Body.
--- Returns number (studs), minimum 2, default 4.5 if GetBoundingBox fails.
function CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, adornee)
	local a = adornee or (model.PrimaryPart or model:FindFirstChild("Body") or model:FindFirstChild("HumanoidRootPart"))
	if not a or not a:IsA("BasePart") then return 4.5 end
	local adorneeY = a.Position.Y
	local ok, bboxCf, bboxSize = pcall(function() return model:GetBoundingBox() end)
	if ok and bboxCf and bboxSize and bboxSize.Y > 0 and bboxSize.Y < 100 then
		local topY = bboxCf.Position.Y + bboxSize.Y * 0.5
		return math.max(2, topY - adorneeY + 0.5)
	end
	return 4.5
end

return CreatureModelLoader
