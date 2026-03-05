-- HUDButtonBar.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Bottom-center clickable button bar for all menus. Uses scale-based layout and viewport text scaling.
-- Clicking a button fires a BindableEvent that the corresponding menu script listens to.
-- Keyboard shortcuts still work independently in each menu script.
-- FIX: PlayerGui is cleared on respawn; we restore the bar and HUDToggleMenu on CharacterAdded.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local toggleEvent
local sg

-- Create or reuse shared BindableEvent for menu toggling (so menu scripts can connect before we run)
local function ensureToggleEvent()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if evt and evt:IsA("BindableEvent") then
		toggleEvent = evt
		return evt
	end
	toggleEvent = Instance.new("BindableEvent")
	toggleEvent.Name = "HUDToggleMenu"
	toggleEvent.Parent = playerGui
	return toggleEvent
end

local function buildHUDButtonBar()
	-- Remove old bar if it exists (e.g. from previous run before respawn)
	local old = playerGui:FindFirstChild("HUDButtonBar")
	if old then old:Destroy() end

	ensureToggleEvent()

	-- Screen GUI
	sg = Instance.new("ScreenGui")
	sg.Name = "HUDButtonBar"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 40
	sg.Parent = playerGui

	--[[ TEXT SCALING (viewport-based, same approach as LaunchScreen)
     getTextScale() returns a multiplier from CurrentCamera.ViewportSize vs reference resolution.
     TEXT_SIZE_MULTIPLIER boosts result for readability; tune if text is too small/large. ]]
local TEXT_REFERENCE_WIDTH = 1920
local TEXT_REFERENCE_HEIGHT = 1080
local TEXT_SCALE_CLAMP_MIN = 0.6
local TEXT_SCALE_CLAMP_MAX = 1.5
local TEXT_SIZE_MULTIPLIER = 1.85

local function getTextScale()
	local camera = workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(TEXT_REFERENCE_WIDTH, TEXT_REFERENCE_HEIGHT)
	local raw = math.min(viewport.X / TEXT_REFERENCE_WIDTH, viewport.Y / TEXT_REFERENCE_HEIGHT)
	return math.clamp(raw, TEXT_SCALE_CLAMP_MIN, TEXT_SCALE_CLAMP_MAX) * TEXT_SIZE_MULTIPLIER
end

local textScale = getTextScale()

-- Button definitions (module-level so InputBegan can reference after restore)
local buttonDefs = {
	{ label = "[K] Codex",      key = "K", menuName = "CodexGuide",     color = Color3.fromRGB(180, 140, 255), desc = "Guide, Lore, creatures" },
	{ label = "[Q] Inventory",  key = "Q", menuName = "InventoryUI",    color = Color3.fromRGB(60, 160, 255), desc = "Manage creatures" },
	{ label = "[R] Eggs",       key = "R", menuName = "EggShopGUI",     color = Color3.fromRGB(255, 200, 50), desc = "Buy & hatch eggs" },
	{ label = "[G] Buffs",      key = "G", menuName = "BuffShopGUI",    color = Color3.fromRGB(80, 220, 120), desc = "Buy power-ups" },
	{ label = "[C] Cosmetics",  key = "C", menuName = "CosmeticShopGUI", color = Color3.fromRGB(200, 120, 255), desc = "Trails & auras" },
	{ label = "[V] Friends",    key = "V", menuName = "FriendsListGUI", color = Color3.fromRGB(255, 130, 80), desc = "Base access list" },
	{ label = "[X] Leaders",    key = "X", menuName = "LeaderboardGUI", color = Color3.fromRGB(100, 220, 160), desc = "Leaderboards" },
	{ label = "[P] Profile",    key = "P", menuName = "ProfileGUI",     color = Color3.fromRGB(200, 180, 255), desc = "Player profile" },
	{ label = "[Z] Rebirth",    key = "Z", menuName = "RebirthUI",      color = Color3.fromRGB(255, 180, 80),  desc = "Pilot rebirth - reset for permanent bonuses" },
	{ label = "[H] Recall", key = "H", menuName = "GoHome",  color = Color3.fromRGB(255, 220, 100), desc = "Channel 5s to return to base (interrupt on damage)" },
}

-- BAR LAYOUT (scale-based, design reference 1920x1080)
-- Container sits at bottom-center; BAR_HEIGHT_SCALE = bar height (reduced to give more space for target UI above)
local BAR_WIDTH_SCALE = 0.7
local BAR_HEIGHT_SCALE = 32/1080
-- Scale entire bar/buttons up or down (e.g. 1.3 = 30% larger)
local BUTTON_BAR_SCALE = 1.35
-- Raise bar off bottom: increase BAR_BOTTOM_OFFSET_SCALE (e.g. 0.07–0.1)
local BAR_BOTTOM_OFFSET_SCALE = 0.1
-- Spread buttons apart: increase BAR_BUTTON_PADDING_SCALE (e.g. 0.015–0.025)
local BAR_BUTTON_PADDING_SCALE = 0.02
	local btnWScale = (1 - (#buttonDefs - 1) * BAR_BUTTON_PADDING_SCALE) / #buttonDefs

	local container = Instance.new("Frame")
container.AnchorPoint = Vector2.new(0.5, 1)
container.Size = UDim2.new(BAR_WIDTH_SCALE * BUTTON_BAR_SCALE, 0, BAR_HEIGHT_SCALE * BUTTON_BAR_SCALE, 0)
container.Position = UDim2.new(0.5, 0, 1, -BAR_BOTTOM_OFFSET_SCALE)
container.BackgroundTransparency = 1
container.Parent = sg

-- Horizontal list so button widths and gaps scale with container
local list = Instance.new("UIListLayout")
list.Parent = container
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Padding = UDim.new(BAR_BUTTON_PADDING_SCALE, 0)
list.SortOrder = Enum.SortOrder.LayoutOrder

-- Tooltip (scale-based size; position is set in pixels above the hovered button)
local TOOLTIP_GAP_PX = 6
local tipLabel = Instance.new("TextLabel")
tipLabel.Size = UDim2.new(200/1920, 0, 22/1080, 0)
tipLabel.AnchorPoint = Vector2.new(0.5, 1)
tipLabel.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
tipLabel.BackgroundTransparency = 0.1
tipLabel.BorderSizePixel = 0
tipLabel.Visible = false
tipLabel.Font = Enum.Font.GothamMedium
tipLabel.TextSize = math.max(10, math.floor(10 * textScale))
tipLabel.TextColor3 = Color3.fromRGB(180, 185, 200)
tipLabel.Parent = sg
Instance.new("UICorner", tipLabel).CornerRadius = UDim.new(0, 6)

-- Build buttons (each button: scale width from btnWScale, full height of container)
	for i, def in ipairs(buttonDefs) do
	local btn = Instance.new("TextButton")
	btn.LayoutOrder = i
	btn.Size = UDim2.new(btnWScale, 0, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = def.label
	btn.TextColor3 = def.color
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = math.max(10, math.floor(11 * textScale))
	btn.AutoButtonColor = false
	btn.Parent = container
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = def.color
	stroke.Thickness = 1
	stroke.Transparency = 0.6

	-- Hover: show tooltip directly above this button (pixel position so it stays above the right button)
	btn.MouseEnter:Connect(function()
		stroke.Transparency = 0
		btn.BackgroundTransparency = 0.05
		tipLabel.Text = def.desc .. " (" .. def.key .. ")"
		tipLabel.TextColor3 = def.color
		tipLabel.Visible = true
		-- Position tooltip above this button (defer so AbsoluteSize/Position are up to date)
		task.defer(function()
			local btnPos, btnSize = btn.AbsolutePosition, btn.AbsoluteSize
			local tipSize = tipLabel.AbsoluteSize
			local centerX = btnPos.X + btnSize.X / 2
			local tipX = centerX - tipSize.X / 2
			local tipY = btnPos.Y - TOOLTIP_GAP_PX - tipSize.Y
			tipLabel.Position = UDim2.new(0, tipX, 0, tipY)
		end)
	end)

	btn.MouseLeave:Connect(function()
		stroke.Transparency = 0.6
		btn.BackgroundTransparency = 0.15
		tipLabel.Visible = false
	end)

	-- Click: fire toggle event for the corresponding menu
	btn.MouseButton1Click:Connect(function()
		-- Visual flash
		btn.BackgroundColor3 = def.color
		btn.TextColor3 = Color3.new(0, 0, 0)
		task.delay(0.12, function()
			btn.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
			btn.TextColor3 = def.color
		end)

		-- Fire the toggle event (special case: GoHome fires remote directly)
		if def.menuName == "GoHome" then
			local events = ReplicatedStorage:FindFirstChild("Events")
			local goHomeEvt = events and events:FindFirstChild("GoHome")
			if goHomeEvt then goHomeEvt:FireServer() end
		else
			toggleEvent:Fire(def.menuName)
		end
	end)
	end

	-- Combat hint (top center; recreated on restore so it survives respawn)
	local HINT_WIDTH_SCALE = 420/1920
	local HINT_HEIGHT_SCALE = 26/1080
	local HINT_TOP_OFFSET_SCALE = 6/1080
	local hintFrame = Instance.new("Frame")
	hintFrame.AnchorPoint = Vector2.new(0.5, 0)
	hintFrame.Size = UDim2.new(HINT_WIDTH_SCALE, 0, HINT_HEIGHT_SCALE, 0)
	hintFrame.Position = UDim2.new(0.5, 0, 0, HINT_TOP_OFFSET_SCALE)
	hintFrame.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	hintFrame.BackgroundTransparency = 0.3
	hintFrame.BorderSizePixel = 0
	hintFrame.Parent = sg
	Instance.new("UICorner", hintFrame).CornerRadius = UDim.new(0, 8)
	local hintLbl = Instance.new("TextLabel")
	hintLbl.Size = UDim2.new(1, 0, 1, 0)
	hintLbl.BackgroundTransparency = 1
	hintLbl.Text = "Select target to attack | [F] Ranged/Melee | [E] Target nearest"
	hintLbl.TextColor3 = Color3.fromRGB(140, 150, 180)
	hintLbl.Font = Enum.Font.GothamMedium
	hintLbl.TextSize = math.max(10, math.floor(10 * textScale))
	hintLbl.Parent = hintFrame
	task.delay(15, function()
		if hintFrame and hintFrame.Parent then
			TweenService:Create(hintFrame, TweenInfo.new(2), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(hintLbl, TweenInfo.new(2), { TextTransparency = 1 }):Play()
			task.delay(2.1, function() if hintFrame then hintFrame.Visible = false end end)
		end
	end)
end

-- P, H, X, Q, K: use ContextActionService to capture before Roblox core (these keys can be consumed otherwise)
local function onHUDKeyCapture(actionName, state, input)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
	ensureToggleEvent()
	if input.KeyCode == Enum.KeyCode.Q and toggleEvent then
		toggleEvent:Fire("InventoryUI")
		return Enum.ContextActionResult.Sink
	end
	if input.KeyCode == Enum.KeyCode.K and toggleEvent then
		toggleEvent:Fire("CodexGuide")
		return Enum.ContextActionResult.Sink
	end
	if input.KeyCode == Enum.KeyCode.P and toggleEvent then
		toggleEvent:Fire("ProfileGUI")
		return Enum.ContextActionResult.Sink
	end
	if input.KeyCode == Enum.KeyCode.H then
		local events = ReplicatedStorage:FindFirstChild("Events")
		local goHomeEvt = events and events:FindFirstChild("GoHome")
		if goHomeEvt then goHomeEvt:FireServer() end
		return Enum.ContextActionResult.Sink
	end
	if input.KeyCode == Enum.KeyCode.X and toggleEvent then
		toggleEvent:Fire("LeaderboardGUI")
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end
ContextActionService:BindAction("HUD_PHX", onHUDKeyCapture, false, Enum.KeyCode.Q, Enum.KeyCode.K, Enum.KeyCode.P, Enum.KeyCode.H, Enum.KeyCode.X)

-- Keyboard shortcuts for all HUD menus (runs once; toggleEvent persists across respawn)
local keyToEnum = {
	Q = Enum.KeyCode.Q, W = Enum.KeyCode.W, E = Enum.KeyCode.E, R = Enum.KeyCode.R,
	T = Enum.KeyCode.T, Y = Enum.KeyCode.Y, U = Enum.KeyCode.U, I = Enum.KeyCode.I,
	O = Enum.KeyCode.O, P = Enum.KeyCode.P, A = Enum.KeyCode.A, S = Enum.KeyCode.S,
	D = Enum.KeyCode.D, F = Enum.KeyCode.F, G = Enum.KeyCode.G, H = Enum.KeyCode.H,
	J = Enum.KeyCode.J, K = Enum.KeyCode.K, L = Enum.KeyCode.L, Z = Enum.KeyCode.Z,
	X = Enum.KeyCode.X, C = Enum.KeyCode.C, V = Enum.KeyCode.V, B = Enum.KeyCode.B,
	N = Enum.KeyCode.N, M = Enum.KeyCode.M,
}
-- Keys handled by ContextActionService above (so we don't fire toggle twice)
local keysHandledByCAS = { Q = true, K = true, P = true, H = true, X = true }
UserInputService.InputBegan:Connect(function(input, gp)
	-- Skip if typing in chat/TextBox; ignore gp (can block keys incorrectly in some Roblox contexts)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard or not input.KeyCode then return end
	for _, def in ipairs(buttonDefs) do
		if keysHandledByCAS[def.key] then continue end
		local keyEnum = keyToEnum[def.key]
		if keyEnum and input.KeyCode == keyEnum then
			-- #region agent log
			pcall(function()
				local hs = game:GetService("HttpService")
				hs:PostAsync("http://127.0.0.1:7242/ingest/29779be3-c77e-4205-a6a3-76f7b6b6f8e7", hs:JSONEncode({
					location = "HUDButtonBar.lua:keyMatch", message = "HUD key matched",
					data = { key = def.key, menuName = def.menuName, buttonCount = #buttonDefs },
					timestamp = math.floor(tick() * 1000), hypothesisId = "H2"
				}))
			end)
			-- #endregion
			if toggleEvent then
				if def.menuName == "GoHome" then
					local events = ReplicatedStorage:FindFirstChild("Events")
					local goHomeEvt = events and events:FindFirstChild("GoHome")
					if goHomeEvt then goHomeEvt:FireServer() end
				else
					toggleEvent:Fire(def.menuName)
				end
			end
			break
		end
	end
end)

-- Initial build
buildHUDButtonBar()

-- Restore on respawn (PlayerGui is cleared on death; recreate bar and HUDToggleMenu)
player.CharacterAdded:Connect(function()
	task.wait(0.15)
	buildHUDButtonBar()
end)

