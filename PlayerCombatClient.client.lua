-- PlayerCombatClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Target-based combat: Player and companion only attack when a target is selected from the target menu.
-- F toggles ranged / melee mode. Click on fainted creature = capture (handled by CaptureClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)

-- Wait for Events (don't exit early so weapon toggle and attack loop can run once ready)
local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then
	warn("[PlayerCombatClient] Events not found - retrying periodically")
	while not Events do
		task.wait(1)
		Events = ReplicatedStorage:FindFirstChild("Events")
	end
end

local playerAttack = Events:WaitForChild("PlayerAttack", 10)
if not playerAttack then
	warn("[PlayerCombatClient] PlayerAttack remote not found - retrying periodically")
	while not playerAttack do
		task.wait(1)
		playerAttack = Events:FindFirstChild("PlayerAttack")
	end
end
local playerAttackFX = Events:FindFirstChild("PlayerAttackFX")

-- Wait for character
if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
	player.CharacterAdded:Wait()
	player.Character:WaitForChild("HumanoidRootPart", 10)
end

-- Shared target store: CaptureClient sets this when player selects target; we only attack when it has a value
local targetStore = playerGui:FindFirstChild("CurrentCombatTargetId")
if not targetStore or not targetStore:IsA("StringValue") then
	targetStore = Instance.new("StringValue")
	targetStore.Name = "CurrentCombatTargetId"
	targetStore.Value = ""
	targetStore.Parent = playerGui
end

-- -- STATE --
local combatMode = "ranged" -- "ranged" or "melee"
local lastAutoAttack = 0
local lastOutOfRangeToast = 0  -- throttle "Target out of range" feedback
local WORLD_TAG = "WorldCreature"

-- -- HUD --
local sg = Instance.new("ScreenGui")
sg.Name = "CombatHUD"
sg.ResetOnSpawn = false
sg.DisplayOrder = 5
sg.Parent = playerGui

-- Target indicator (tracker) showing which creature auto-attack is targeting; +10% size
local targetIndicator = Instance.new("Frame")
targetIndicator.Size = UDim2.new(0, 200, 0, 20)
targetIndicator.Position = UDim2.new(0.5, -100, 1, -700)
targetIndicator.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
targetIndicator.BackgroundTransparency = 0.3
targetIndicator.BorderSizePixel = 0
targetIndicator.Visible = false
targetIndicator.Parent = sg
Instance.new("UICorner", targetIndicator).CornerRadius = UDim.new(0, 6)
local trackerScale = Instance.new("UIScale")
trackerScale.Scale = 1.1  -- +10% tracker size (all devices)
trackerScale.Parent = targetIndicator
-- On mobile: move down and scale 65% (was 50%; +30% larger); tracker scale 1.1 applied above
if UserInputService.TouchEnabled then
	targetIndicator.Position = UDim2.new(0.5, -100, 1, -180)
	local targetUIScale = Instance.new("UIScale")
	targetUIScale.Scale = 0.65  -- 0.5 * 1.30 for 30% larger on mobile
	targetUIScale.Parent = targetIndicator
end

local targetLbl = Instance.new("TextLabel")
targetLbl.Size = UDim2.new(1, 0, 1, 0)
targetLbl.BackgroundTransparency = 1
targetLbl.Text = ""
targetLbl.TextColor3 = Color3.fromRGB(255, 200, 50)
targetLbl.Font = Enum.Font.GothamMedium
targetLbl.TextSize = 10
targetLbl.Parent = targetIndicator

-- Mobile / HUD weapon toggle (shared with F key)
local weaponToggleEvt = playerGui:FindFirstChild("ToggleWeaponMode")
if not weaponToggleEvt or not weaponToggleEvt:IsA("BindableEvent") then
	weaponToggleEvt = Instance.new("BindableEvent")
	weaponToggleEvt.Name = "ToggleWeaponMode"
	weaponToggleEvt.Parent = playerGui
end

local function toggleWeaponMode()
	combatMode = combatMode == "ranged" and "melee" or "ranged"
	Notify.Toast(
		combatMode == "ranged" and "Switched to RANGED" or "Switched to MELEE",
		combatMode == "ranged" and Color3.fromRGB(60, 160, 255) or Color3.fromRGB(255, 100, 60),
		1.5
	)
	-- Notify [F] button to update label (Ranged/Melee)
	local evt = playerGui:FindFirstChild("WeaponModeChanged")
	if evt and evt:IsA("BindableEvent") then evt:Fire(combatMode) end
end

weaponToggleEvt.Event:Connect(function()
	toggleWeaponMode()
end)

-- WeaponModeChanged: fires (combatMode) so [F] button can update its label (Ranged/Melee)
local weaponModeEvt = playerGui:FindFirstChild("WeaponModeChanged")
if not weaponModeEvt or not weaponModeEvt:IsA("BindableEvent") then
	weaponModeEvt = Instance.new("BindableEvent")
	weaponModeEvt.Name = "WeaponModeChanged"
	weaponModeEvt.Parent = playerGui
end
weaponModeEvt:Fire(combatMode)

-- -- F KEY: toggle mode --
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F then
		toggleWeaponMode()
	end
end)

-- -- TARGET-BASED ATTACK LOOP (only attack when target selected from target menu) --
task.spawn(function()
	while true do
		task.wait(0.1) -- check 10 times per second

		if not playerAttack then continue end

		local targetId = (targetStore and targetStore.Value) or ""
		if targetId == "" then
			targetIndicator.Visible = false
			continue
		end

		local character = player.Character
		if not character then continue end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0
			or humanoid:GetState() == Enum.HumanoidStateType.Dead then
			targetIndicator.Visible = false
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		local now = tick()
		local cd = combatMode == "ranged" and GameConfig.PlayerRangedCooldown or GameConfig.PlayerMeleeCooldown
		if now - lastAutoAttack < cd then continue end

		-- Check if any GUI panel is open (don't attack while managing inventory etc.)
		local guiNames = {"InventoryUI", "ShopHubGUI", "EggShopGUI", "BuffShopGUI", "CosmeticShopGUI", "FriendsListGUI"}
		local menuOpen = false
		for _, gn in ipairs(guiNames) do
			local gui = playerGui:FindFirstChild(gn)
			if gui then
				for _, ch in ipairs(gui:GetChildren()) do
					if ch:IsA("Frame") and ch.Visible and ch.BackgroundTransparency < 0.5 then
						menuOpen = true
						break
					end
				end
			end
			if menuOpen then break end
		end
		if menuOpen then
			targetIndicator.Visible = false
			continue
		end

		-- Find target model by UniqueId (validate it still exists and is in range)
		local nearest = nil
		for _, model in ipairs(CollectionService:GetTagged(WORLD_TAG)) do
			if model.Parent and not model:GetAttribute("Fainted") then
				local uid = model:GetAttribute("UniqueId") or model:GetAttribute("UID")
				if uid and (tostring(uid) == targetId) then
					local body = model.PrimaryPart or model:FindFirstChild("Body")
					if body then
						local range = combatMode == "ranged" and GameConfig.PlayerRangedRange or GameConfig.PlayerMeleeRadius
						if (root.Position - body.Position).Magnitude <= range then
							nearest = model
							break
						end
					end
					break
				end
			end
		end

		if nearest then
			lastAutoAttack = now
			local targetBody = nearest.PrimaryPart or nearest:FindFirstChild("Body")

			-- Show target indicator
			local cid = nearest:GetAttribute("CreatureId")
			local info = cid and CreatureData.GetById(cid)
			targetLbl.Text = "Attacking: " .. (info and info.displayName or "creature")
			targetIndicator.Visible = true
			lastOutOfRangeToast = 0 -- reset so next out-of-range shows toast again

			if combatMode == "ranged" then
				local origin = root.Position + Vector3.new(0, 2, 0)
				local direction = targetBody and (targetBody.Position - origin).Unit or nil

				if direction and direction.Magnitude > 0.1 then
					playerAttack:FireServer("ranged", origin, direction, targetId)
				end
			else
				-- Server expects (attackType, origin, direction, targetUniqueId); for melee pass nil as direction so targetId is 5th arg
				playerAttack:FireServer("melee", root.Position, nil, targetId)
			end
		else
			targetIndicator.Visible = false
			-- Feedback when target selected but out of range (throttled to avoid spam)
			if now - lastOutOfRangeToast >= 2.5 then
				lastOutOfRangeToast = now
				Notify.Toast("Target out of range! Get closer.", Color3.fromRGB(255, 120, 80), 2)
			end
		end
	end
end)

-- -- ATTACK VISUAL EFFECTS (from server) --

local function rangedFX(fromPos, toPos, hit)
	task.spawn(function()
		local bolt = Instance.new("Part")
		bolt.Size = Vector3.new(1, 1, 1)
		bolt.Shape = Enum.PartType.Ball
		bolt.Color = Color3.fromRGB(60, 180, 255)
		bolt.Material = Enum.Material.Neon
		bolt.Anchored = true; bolt.CanCollide = false; bolt.CastShadow = false
		bolt.Position = fromPos; bolt.Parent = workspace

		local trail = Instance.new("Part")
		trail.Size = Vector3.new(0.4, 0.4, 0.4)
		trail.Shape = Enum.PartType.Ball
		trail.Color = Color3.fromRGB(120, 200, 255)
		trail.Material = Enum.Material.Neon
		trail.Transparency = 0.5
		trail.Anchored = true; trail.CanCollide = false; trail.CastShadow = false
		trail.Parent = workspace

		local dist = (toPos - fromPos).Magnitude
		local dur = math.min(dist / GameConfig.PlayerRangedSpeed, 0.5)
		local s = tick()
		while tick() - s < dur do
			local t = (tick() - s) / dur
			bolt.Position = fromPos:Lerp(toPos, t)
			trail.Position = fromPos:Lerp(toPos, math.max(0, t - 0.08))
			RunService.RenderStepped:Wait()
		end

		if hit then
			bolt.Color = Color3.fromRGB(255, 200, 60)
			bolt.Size = Vector3.new(2.5, 2.5, 2.5)
			bolt.Transparency = 0.3
			task.wait(0.1)
		end

		bolt:Destroy()
		trail:Destroy()
	end)
end

local function meleeFX(origin, hit)
	task.spawn(function()
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.3, 1, 1)
		ring.Color = hit and Color3.fromRGB(255, 120, 60) or Color3.fromRGB(200, 200, 220)
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.3
		ring.Anchored = true; ring.CanCollide = false; ring.CastShadow = false
		ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace

		local targetSize = Vector3.new(0.3, GameConfig.PlayerMeleeRadius * 2, GameConfig.PlayerMeleeRadius * 2)
		TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = targetSize, Transparency = 1
		}):Play()
		task.wait(0.4)
		ring:Destroy()
	end)
end

if playerAttackFX then
	playerAttackFX.OnClientEvent:Connect(function(attackerUserId, origin, endPos, mode, didHit)
		if mode == "ranged" and endPos then
			rangedFX(origin, endPos, didHit)
		elseif mode == "melee" then
			meleeFX(origin, didHit)
		end
	end)
end
--Testing?




