--[[
	Last updated: 2026-04-23 21:35
	CreatureAnimation.lua - ReplicatedStorage.Modules (ModuleScript)
	Loads and plays creature animations from ReplicatedStorage.RBX_ANIMSAVES (fallback: ServerStorage).
	Animation types: Idle (default), Move, Attack, Special, Income, Faint (one-shot, freezes on final frame).
	Folder naming: # Model_DisplayName (e.g. # Model_Breezee)

	HYBRID ANIMATION SUPPORT (FIX #12):
	Supports two types of animation objects in the anim folder:
	  1. Animation (published) — Has rbxassetid:// ID. Used directly. Best for production.
	  2. KeyframeSequence (local) — Raw keyframe data saved by the Animation Editor.
	     Converted to a playable Animation at runtime via
	     KeyframeSequenceProvider:RegisterKeyframeSequence(). IDs are session-scoped
	     (regenerated each server start). Best for development/iteration.

	NESTED KFS SUPPORT (FIX #14):
	The Animation Editor may nest KeyframeSequences as CHILDREN of the Animation object
	(Animation → KeyframeSequence) rather than as siblings. resolveAnimObject now checks
	both child and sibling locations when an Animation has an invalid ID (rbxassetid://0).

	TO PUBLISH FOR PRODUCTION:
	  1. Open Animation Editor in Roblox Studio
	  2. Load the animation for the creature
	  3. Click "..." menu → "Save to Roblox" / "Export"
	  4. This creates an Animation instance with a permanent rbxassetid:// ID
	  5. Place it in the creature's anim folder in RBX_ANIMSAVES with the correct name
	     (Idle, Move, Attack, Special, or Income)dfd
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)

local CreatureAnimation = {}

local ANIM_SAVES = "RBX_ANIMSAVES"
local ANIM_TYPES = { "Attack", "Idle", "Income", "Move", "Special", "Faint", "Knocked", "Swimming" }
-- [model] = { animator, animFolder, tracks = { animType = AnimationTrack } }
local modelCache = {}
-- Models that failed setup (no rig or no anim folder) - avoid re-running Setup and log spam
local failedSetups = {}
-- ══════════════════════════════════════════════════════════════════════════════
-- KEYFRAME REGISTRATION CACHE (FIX #12)
-- KeyframeSequences from the Animation Editor are converted to playable Animation
-- instances at runtime via KeyframeSequenceProvider:RegisterKeyframeSequence().
-- Each KFS is registered once per server session; the resulting Animation is cached here.
-- Published Animation objects (with rbxassetid:// IDs) bypass this entirely.
-- ══════════════════════════════════════════════════════════════════════════════
local kfsCache = {} -- [KeyframeSequence instance] = Animation instance

local function getAnimFolder(model, creatureId)
	local animSaves = ReplicatedStorage:FindFirstChild(ANIM_SAVES) or ServerStorage:FindFirstChild(ANIM_SAVES)
	if not animSaves then return nil end

	local function tryFolder(name)
		return name and animSaves:FindFirstChild(name)
	end

	local info = CreatureData.GetById(creatureId)
	local displayName = info and (info.displayName or info.modelName or creatureId) or creatureId
	local templateName = model and model:GetAttribute("TemplateName")

	-- Try multiple naming conventions (Blender/plugin/Animation Editor varies)
	for _, name in ipairs({
		"# Model_" .. (displayName or ""),
		"# " .. (templateName or ""),
		"#Model_" .. (displayName or ""),
		"Model_" .. (displayName or ""),
		displayName .. "Model",
		"Model_" .. displayName,
		displayName or "",
		templateName or "",
	}) do
		if name and name ~= "" then
			local f = tryFolder(name)
			if f then return f end
		end
	end
	-- Fallback: case-insensitive match on Folder or Model (RBX_ANIMSAVES may use Model_Breezee as Model)
	local search = (displayName or ""):lower()
	for _, child in ipairs(animSaves:GetChildren()) do
		if (child:IsA("Folder") or child:IsA("Model")) and child.Name:lower():find(search, 1, true) then
			return child
		end
	end
	return nil
end

local function getAnimator(model)
	-- AnimationController rigs (Blender import): Animator lives under AnimationController
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("AnimationController") then
			local animator = desc:FindFirstChildOfClass("Animator")
			if animator then return animator end
		elseif desc:IsA("Animator") then
			return desc
		end
	end
	-- Humanoid rigs: need Animator (LoadAnimation is on Animator, not Humanoid)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator") or model:FindFirstChildOfClass("Animator")
		if animator then return animator end
		-- Create Animator if missing (Roblox R15/R6 chars have one; some imports don't)
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		return newAnimator
	end
	-- Fallback for Model-type rigs (TemplateType "Model") missing AnimationController
	-- Blender exports may have Motor6Ds but forget AnimationController
	if model:GetAttribute("TemplateType") == "Model" then
		local ac = Instance.new("AnimationController")
		local animator = Instance.new("Animator")
		animator.Parent = ac
		ac.Parent = model
		return animator
	end
	return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- RESOLVE ANIMATION OBJECT (FIX #12)
-- Handles both published Animation instances and local KeyframeSequence objects.
-- ══════════════════════════════════════════════════════════════════════════════

--- Check if an AnimationId is a real published asset (not empty, not "0", not placeholder).
-- FIX #13: The Animation Editor creates Animation objects with AnimationId = "rbxassetid://0"
-- when the animation hasn't been published. These fail at runtime with
-- "Failed to load animation with sanitized ID rbxassetid://0".
local function isValidAnimationId(id)
	if not id or id == "" then return false end
	-- Strip the "rbxassetid://" prefix and check if the numeric ID is real (> 0)
	local numStr = id:match("rbxassetid://(%d+)")
	if numStr then
		return tonumber(numStr) > 0
	end
	-- Accept other URL formats (http asset delivery, etc.) as potentially valid
	return #id > 0
end

--- Registers a KeyframeSequence via KeyframeSequenceProvider and returns a playable Animation.
-- Caches the result so each KFS is only registered once per server session.
-- @param kfs KeyframeSequence - the raw keyframe data from the Animation Editor
-- @param animType string - name for the Animation instance (e.g. "Idle")
-- @param folderPath string - for logging
-- @return Animation|nil
local function registerKeyframeSequence(kfs, animType, folderPath)
	if kfsCache[kfs] then
		return kfsCache[kfs]
	end

	local ok, animId = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
	end)

	if not ok or not animId or animId == "" then
		return nil
	end

	-- Create a runtime Animation instance pointing to the registered ID.
	-- NOT parented to the data model to avoid clutter; kfsCache keeps a strong ref.
	local anim = Instance.new("Animation")
	anim.Name = animType .. "_Registered"
	anim.AnimationId = animId

	kfsCache[kfs] = anim
	return anim
end

--- Resolves an animation object from the anim folder. Supports published Animation
--- instances (used directly), KeyframeSequences (registered at runtime), and
--- Animation objects with invalid IDs (falls back to sibling KeyframeSequence).
-- @param animFolder Folder|Model - the creature's animation folder in RBX_ANIMSAVES
-- @param animType string - "Idle", "Move", "Attack", "Special", "Income"
-- @return Animation|nil - a playable Animation instance, or nil if not found/failed
local function resolveAnimObject(animFolder, animType)
	local child = animFolder:FindFirstChild(animType)
	if not child then
		return nil
	end

	-- ── Path A: Published Animation with valid asset ID ──
	-- Standard production workflow: Animation Editor → "Save to Roblox" → rbxassetid://
	if child:IsA("Animation") then
		if isValidAnimationId(child.AnimationId) then
			return child
		end
		-- FIX #13: Animation has invalid/placeholder ID (e.g. "rbxassetid://0").
		-- The Animation Editor creates KeyframeSequences that may be stored as:
		--   1. Siblings of the Animation (same parent folder)
		--   2. Children of the Animation object itself (nested: Animation → KeyframeSequence)
		-- FIX #14: Also search children of the Animation, since the Animation Editor
		-- commonly nests the KFS inside the Animation object.
		-- FIX #15: Recursively search descendants — some exports nest Animation → Animation → KeyframeSequence.
		local function findInDescendants(obj)
			local kfs, pubAnim
			for _, desc in ipairs(obj:GetDescendants()) do
				if desc:IsA("KeyframeSequence") and not kfs then
					kfs = desc
				elseif desc:IsA("Animation") and isValidAnimationId(desc.AnimationId) and not pubAnim then
					pubAnim = desc
				end
			end
			return kfs, pubAnim
		end
		local kfs, pubAnim = findInDescendants(child)
		if kfs then
			return registerKeyframeSequence(kfs, animType, animFolder:GetFullName())
		end
		if pubAnim then
			return pubAnim
		end
		-- Search siblings for a KFS with the same name (alternate layout)
		for _, sibling in ipairs(animFolder:GetChildren()) do
			if sibling:IsA("KeyframeSequence") and sibling.Name == animType then
				return registerKeyframeSequence(sibling, animType, animFolder:GetFullName())
			end
		end
		-- No KFS found anywhere
		return nil
	end

	-- ── Path B: KeyframeSequence → register at runtime ──
	-- Development workflow: Animation Editor saves locally as KeyframeSequence.
	-- Use KeyframeSequenceProvider:RegisterKeyframeSequence() to get a temporary
	-- rbxassetid:// hash valid for this server session.
	if child:IsA("KeyframeSequence") then
		return registerKeyframeSequence(child, animType, animFolder:GetFullName())
	end

	-- ── Path C: Unknown type ──
	return nil
end

--- Setup animation system for a model. Call after LoadAndIntegrate.
-- Supports Humanoid rigs and AnimationController+Animator (Blender-imported) rigs.
-- @param model Model - the creature model
-- @param creatureId string - creature id for animation folder lookup
-- @param defaultAnim string - "Idle", "Income", etc. (default "Idle")
function CreatureAnimation.Setup(model, creatureId, defaultAnim)
	if not model or not creatureId then return end
	if failedSetups[model] then return end

	local animator = getAnimator(model)
	if not animator then
		failedSetups[model] = true
		return
	end

	local animFolder = getAnimFolder(model, creatureId)
	if not animFolder then
		failedSetups[model] = true
		return
	end

	modelCache[model] = { animator = animator, animFolder = animFolder, tracks = {}, creatureId = creatureId }

	-- ══════════════════════════════════════════════════════════════════════════════
	-- DIAGNOSTIC: Log all animations available in the folder at setup time.
	-- This helps verify which animation types (Idle, Move, Attack, Income, Special)
	-- actually exist and what form they're in (Animation vs KeyframeSequence).
	-- ══════════════════════════════════════════════════════════════════════════════
	local foundAnims = {}
	for _, animName in ipairs(ANIM_TYPES) do
		local child = animFolder:FindFirstChild(animName)
		if child then
			local childType = child.ClassName
			-- Check for nested KFS children (FIX #14 layout)
			local hasNestedKFS = false
			for _, sub in ipairs(child:GetChildren()) do
				if sub:IsA("KeyframeSequence") then hasNestedKFS = true; break end
			end
			if child:IsA("Animation") then
				local validId = isValidAnimationId(child.AnimationId)
				table.insert(foundAnims, animName .. "(" .. (validId and "published" or (hasNestedKFS and "nested-KFS" or "INVALID-no-KFS")) .. ")")
			elseif child:IsA("KeyframeSequence") then
				table.insert(foundAnims, animName .. "(KFS)")
			else
				table.insert(foundAnims, animName .. "(" .. childType .. "?)")
			end
		end
	end
	-- Always log missing anims so creators know what to add
	local missingAnims = {}
	for _, animName in ipairs(ANIM_TYPES) do
		if not animFolder:FindFirstChild(animName) then
			table.insert(missingAnims, animName)
		end
	end
	CreatureAnimation.PlayAnimation(model, defaultAnim or "Idle", creatureId)
end

--- Play an animation on a creature model.
-- @param model Model - the creature model
-- @param animType string - "Idle", "Move", "Attack", "Special", "Income"
-- @param creatureId string (optional) - for setup if not cached
-- @param options table (optional) - { speed = number } playback speed (default 1). Use for Attack to tie to creature speed stat.
function CreatureAnimation.PlayAnimation(model, animType, creatureId, options)
	if not model then return end
	if not table.find(ANIM_TYPES, animType) then return end

	local cache = modelCache[model]
	if not cache then
		if failedSetups[model] then return end
		CreatureAnimation.Setup(model, creatureId or model:GetAttribute("CreatureId"), animType)
		return
	end

	-- Same animation already playing
	if cache.currentAnim == animType then return end

	-- FIX #12: resolveAnimObject handles both published Animation objects AND
	-- local KeyframeSequence objects (registered at runtime via KSP).
	local animObj = resolveAnimObject(cache.animFolder, animType)
	if not animObj then
		return
	end

	local track = cache.tracks[animType]
	if not track then
		local loaded
		local ok, err = pcall(function()
			loaded = cache.animator:LoadAnimation(animObj)
		end)
		if not ok then
			return
		end
		if not loaded then
			return
		end
		track = loaded
		cache.tracks[animType] = track
	end
	if not track then return end

	if cache.currentTrack then
		cache.currentTrack:Stop(0.15)
	end
	cache.currentAnim = animType
	cache.currentTrack = track
	local playbackSpeed = (options and options.speed) or 1
	-- Idle, Move, Income, Attack, Swimming loop; Faint is one-shot
	track.Looped = (animType == "Idle" or animType == "Move" or animType == "Income" or animType == "Attack" or animType == "Swimming")
	-- Priority: Attack > Move > Swimming > Idle (Income = Idle)
	if animType == "Attack" then track.Priority = Enum.AnimationPriority.Action
	elseif animType == "Move" or animType == "Swimming" then track.Priority = Enum.AnimationPriority.Movement
	else track.Priority = Enum.AnimationPriority.Idle
	end
	track:Play(0.15, 1, playbackSpeed)

	-- Replicate to clients for multiplayer (animations must play on each client for replication)
	if RunService:IsServer() and model.Parent then
		local events = ReplicatedStorage:FindFirstChild("Events")
		local evt = events and events:FindFirstChild("PlayCreatureAnimation")
		if evt then
			evt:FireAllClients(model, animType, creatureId, options)
		end
	end
end

--- Stop and clear cached data when model is destroyed.
function CreatureAnimation.OnModelDestroyed(model)
	local cache = modelCache[model]
	if cache then
		if cache.currentTrack then cache.currentTrack:Stop(0) end
		modelCache[model] = nil
	end
	failedSetups[model] = nil
end

-- Clean up cache when model is removed
local function initCleanup()
	game.DescendantRemoving:Connect(function(desc)
		if desc:IsA("Model") and modelCache[desc] then
			CreatureAnimation.OnModelDestroyed(desc)
		end
	end)
end
task.defer(initCleanup)

return CreatureAnimation
