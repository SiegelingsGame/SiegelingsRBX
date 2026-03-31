--[[
	EvolutionEffects.lua - ServerScriptService (ModuleScript)
	Visually appealing particle effects for creature evolution and devolution.
	Call PlayEvolutionEffect(pos) or PlayDevolutionEffect(pos) at the point where
	the transformation occurs (world position).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local EvolutionEffects = {}

-- Common sparkle texture used in capture/vortex effects
local PARTICLE_TEXTURE = "rbxassetid://5860841663"

local DURATION = 2.2

local function createEffectPart(position)
	local part = Instance.new("Part")
	part.Name = "EvolutionEffect"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = Workspace
	return part
end

local function addEmitter(parent, config)
	local att = Instance.new("Attachment")
	att.Parent = parent
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = config.texture or PARTICLE_TEXTURE
	pe.Color = config.color
	pe.Transparency = config.transparency
	pe.Size = config.size
	pe.Lifetime = config.lifetime
	pe.Rate = config.rate
	pe.Speed = config.speed
	pe.SpreadAngle = config.spreadAngle or Vector2.new(180, 180)
	pe.Acceleration = config.acceleration or Vector3.zero
	pe.LightEmission = config.lightEmission or 0.8
	pe.LightInfluence = config.lightInfluence or 0
	if config.rotSpeed then pe.RotSpeed = config.rotSpeed end
	pe.Parent = att
	return pe
end

-- Evolution: bright, ascending, energetic — golden/amber/magenta burst
function EvolutionEffects.PlayEvolutionEffect(position)
	local part = createEffectPart(position)

	-- Glow light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 220, 120)
	light.Brightness = 3
	light.Range = 12
	light.Parent = part

	-- Primary burst: golden sparkles rising
	addEmitter(part, {
		color = ColorSequence.new(
			Color3.fromRGB(255, 250, 180),
			Color3.fromRGB(255, 200, 80),
			Color3.fromRGB(255, 150, 50)
		),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.5, 0.5),
			NumberSequenceKeypoint.new(1, 1)
		}),
		size = NumberSequence.new(0.4, 1.2, 0.1),
		lifetime = NumberRange.new(0.6, 1.2),
		rate = 60,
		speed = NumberRange.new(8, 18),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, 12, 0),
		lightEmission = 0.9,
		rotSpeed = NumberRange.new(-60, 60),
	})

	-- Secondary ring: magenta/purple accent expanding outward
	addEmitter(part, {
		color = ColorSequence.new(
			Color3.fromRGB(255, 150, 255),
			Color3.fromRGB(200, 80, 220)
		),
		transparency = NumberSequence.new(0.4, 1),
		size = NumberSequence.new(0.6, 1.8),
		lifetime = NumberRange.new(0.5, 1),
		rate = 40,
		speed = NumberRange.new(4, 10),
		spreadAngle = Vector2.new(90, 90),
		acceleration = Vector3.new(0, 6, 0),
		lightEmission = 0.7,
	})

	-- Fade light over duration
	task.spawn(function()
		local start = tick()
		while tick() - start < DURATION do
			local t = (tick() - start) / DURATION
			if light.Parent then
				light.Brightness = 3 * (1 - t)
			end
			RunService.Heartbeat:Wait()
		end
		part:Destroy()
	end)
end

-- Devolution: calmer, descending — cool blue/purple/silver
function EvolutionEffects.PlayDevolutionEffect(position)
	local part = createEffectPart(position)

	-- Cool glow light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 180, 255)
	light.Brightness = 2.5
	light.Range = 10
	light.Parent = part

	-- Primary: soft blue/purple particles drifting down
	addEmitter(part, {
		color = ColorSequence.new(
			Color3.fromRGB(180, 200, 255),
			Color3.fromRGB(120, 160, 240),
			Color3.fromRGB(100, 120, 200)
		),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.6, 0.6),
			NumberSequenceKeypoint.new(1, 1)
		}),
		size = NumberSequence.new(0.3, 1, 0.2),
		lifetime = NumberRange.new(0.8, 1.4),
		rate = 45,
		speed = NumberRange.new(3, 9),
		spreadAngle = Vector2.new(180, 180),
		acceleration = Vector3.new(0, -8, 0),
		lightEmission = 0.6,
		rotSpeed = NumberRange.new(-30, 30),
	})

	-- Secondary: silver/white wisps inward
	addEmitter(part, {
		color = ColorSequence.new(
			Color3.fromRGB(200, 210, 255),
			Color3.fromRGB(160, 180, 220)
		),
		transparency = NumberSequence.new(0.5, 1),
		size = NumberSequence.new(0.4, 1.2),
		lifetime = NumberRange.new(0.6, 1.1),
		rate = 30,
		speed = NumberRange.new(2, 6),
		spreadAngle = Vector2.new(360, 360),
		acceleration = Vector3.new(0, -4, 0),
		lightEmission = 0.5,
	})

	-- Fade light over duration
	task.spawn(function()
		local start = tick()
		while tick() - start < DURATION do
			local t = (tick() - start) / DURATION
			if light.Parent then
				light.Brightness = 2.5 * (1 - t)
			end
			RunService.Heartbeat:Wait()
		end
		part:Destroy()
	end)
end

return EvolutionEffects
