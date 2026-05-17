--[[
	CookKitchenAnimator — ReplicatedStorage.Modules
	Drives: creature pulse, elemental shard hover + spin, smoke rise,
	specimen cage orbit, NPC idle sway (Cook kitchen model).
]]

local RunService = game:GetService("RunService")

local M = {}

local active = {} -- [model] = true — avoid double Heartbeat if SSS + in-model script both run

--- @param model Model kitchen root (e.g. Cook_Kitchen_FINAL)
function M.start(model)
	if not model or not model:IsA("Model") or not model.Parent then
		return
	end
	if active[model] then
		return
	end
	active[model] = true

	local function find(name)
		return model:FindFirstChild(name, true)
	end

	local function restOf(part)
		return part and { cframe = part.CFrame, size = part.Size }
	end

	local creatures = { find("Cook_Creature_1"), find("Cook_Creature_2") }
	local creatureRest = { restOf(creatures[1]), restOf(creatures[2]) }
	local creaturePhase = { 0, 0.33 }

	local elements = {
		{ part = find("Cook_Element_Fire"), phase = 0, amp = 0.35, spinDir = -1 },
		{ part = find("Cook_Element_Water"), phase = 0.25, amp = 0.28, spinDir = 1 },
		{ part = find("Cook_Element_Earth"), phase = 0.50, amp = 0.38, spinDir = -1 },
		{ part = find("Cook_Element_Storm"), phase = 0.75, amp = 0.30, spinDir = 1 },
	}
	for _, e in ipairs(elements) do
		e.rest = e.part and e.part.CFrame
	end

	local smoke = find("Cook_SmokeWisp")
	local smokeRest = smoke and smoke.CFrame

	local specimens = { find("Cook_Specimen_1"), find("Cook_Specimen_2") }
	local specRest = { restOf(specimens[1]), restOf(specimens[2]) }

	local npcBody = find("Cook_NPC_Body")
	local npcHead = find("Cook_NPC_Head")
	local npcRestB = npcBody and npcBody.CFrame
	local npcRestH = npcHead and npcHead.CFrame

	local t0 = tick()
	local LOOP = 4.0

	print("[Cook_Anim] Running on: " .. model:GetFullName())

	RunService.Heartbeat:Connect(function()
		local now = tick() - t0
		local t = (now % LOOP) / LOOP

		for i, c in ipairs(creatures) do
			if c and creatureRest[i] then
				local ph = (t + creaturePhase[i]) % 1
				local pulse = 1 + 0.14 * math.sin(ph * math.pi * 2) + 0.05 * math.sin(ph * math.pi * 8)
				local squash = 1 - 0.07 * math.sin(ph * math.pi * 2)
				local wobbleX = 0.04 * math.sin(ph * math.pi * 4)
				local rest = creatureRest[i]
				c.Size = rest.size * Vector3.new(squash, squash, pulse)
				c.CFrame = rest.cframe + Vector3.new(wobbleX, 0, 0)
			end
		end

		for _, e in ipairs(elements) do
			if e.part and e.rest then
				local ph = (t + e.phase) % 1
				local zOff = e.amp * math.sin(ph * math.pi * 2)
				local spin = e.spinDir * ph * math.pi * 2
				e.part.CFrame = (e.rest + Vector3.new(0, 0, zOff)) * CFrame.Angles(0, spin, 0)
			end
		end

		if smoke and smokeRest then
			local driftZ = (now % 2.0) / 2.0 * 1.4
			local swayX = 0.28 * math.sin(t * math.pi * 2)
			smoke.CFrame = smokeRest + Vector3.new(swayX, 0, driftZ)
			local scaleZ = 1 + 0.2 * math.sin(t * math.pi * 2)
			smoke.Size = Vector3.new(smoke.Size.X, smoke.Size.Y, smoke.Size.Z * scaleZ)
		end

		for i, s in ipairs(specimens) do
			if s and specRest[i] then
				local ph = (t + (i - 1) * 0.5) % 1
				local ang = ph * math.pi * 2
				local r = 0.14
				s.CFrame = specRest[i].cframe
					+ Vector3.new(r * math.cos(ang), r * 0.3 * math.sin(ang * 2), r * math.sin(ang))
			end
		end

		if npcBody and npcRestB then
			local breathe = 0.04 * math.sin(t * math.pi * 2)
			npcBody.CFrame = npcRestB * CFrame.Angles(breathe * 0.3, 0, 0)
		end
		if npcHead and npcRestH then
			local nod = 0.025 * math.sin(t * math.pi * 4)
			npcHead.CFrame = npcRestH * CFrame.Angles(nod, 0.04 * math.sin(t * math.pi * 2), 0)
		end
	end)

	print("[Cook_Anim] All animations running. Loop: " .. LOOP .. "s")
end

return M
