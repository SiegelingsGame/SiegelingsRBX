-- MobileWindowLayout.lua
-- Reusable helper for mobile-only fullscreen-style menu placement inside safe bounds.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileWindowLayout = {}

local function readUiMenuLayoutTweaks()
	local spawnOff, heightScale = 0, 1
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
	end)
	if ok and type(cfg) == "table" then
		if type(cfg.UIMenuSpawnOffsetYPx) == "number" then
			spawnOff = cfg.UIMenuSpawnOffsetYPx
		end
		if type(cfg.UIMenuWindowHeightScale) == "number" and cfg.UIMenuWindowHeightScale > 0 then
			heightScale = cfg.UIMenuWindowHeightScale
		end
	end
	return spawnOff, heightScale
end

local function readMobileFillConfig()
	local fillSafeArea = false
	local edgeInsetPx = 0
	local useCoinBarTop = true
	local reserveHubGap = true
	local ignoreLegacyHeightTweaks = true
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))
	end)
	if ok and type(cfg) == "table" then
		if cfg.MobileMenuFillDeviceSafeArea == true then
			fillSafeArea = true
		end
		if type(cfg.MobileMenuEdgeInsetPx) == "number" and cfg.MobileMenuEdgeInsetPx >= 0 then
			edgeInsetPx = cfg.MobileMenuEdgeInsetPx
		end
		if cfg.MobileMenuUseHUDCoinBarTop == false then
			useCoinBarTop = false
		end
		if cfg.MobileMenuReserveBottomHubGap == false then
			reserveHubGap = false
		end
		if cfg.MobileMenuIgnoreLegacyMenuHeightTweaksWhenFilling == false then
			ignoreLegacyHeightTweaks = false
		end
	end
	return fillSafeArea, edgeInsetPx, useCoinBarTop, reserveHubGap, ignoreLegacyHeightTweaks
end

local DEFAULTS = {
	-- Insets applied in addition to Roblox GUI insets (tight = max usable area).
	leftInset = 6,
	rightInset = 6,
	topInset = 0,
	bottomInset = 4,
	-- Extra gap above system/home bar when hub toolbar bound is unavailable.
	bottomMobileExtra = 4,
	-- Minimum usable panel size.
	minWidth = 280,
	minHeight = 220,
	-- Optional guard rails for very large tablets.
	maxWidthRatio = 1,
	maxHeightRatio = 1,
}

local MENU_GAP_ABOVE_HUB_PX = 4

local HUD_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function getViewport()
	local camera = Workspace.CurrentCamera
	return (camera and camera.ViewportSize) or Vector2.new(1280, 720)
end

local function getGuiInsets()
	local ok, topLeft, bottomRight = pcall(function()
		return GuiService:GetGuiInset()
	end)
	if not ok then
		return Vector2.new(0, 0), Vector2.new(0, 0)
	end
	return topLeft, bottomRight
end

local function getTickerTopBound()
	local player = Players.LocalPlayer
	if not player then return nil end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	local notificationGui = playerGui:FindFirstChild("NotificationGUI")
	if not notificationGui or not notificationGui:IsA("ScreenGui") then
		return nil
	end
	local tickerBar = notificationGui:FindFirstChild("TickerBar")
	if tickerBar and tickerBar:IsA("GuiObject") then
		return math.floor(tickerBar.AbsolutePosition.Y)
	end
	return nil
end

--- Top Y of HUD coin strip (HUDClient: CoinLabel's parent frame). Menus align here when present.
local function getCoinBarTopBound()
	local player = Players.LocalPlayer
	if not player then return nil end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	local hud = playerGui:FindFirstChild("HUD")
	if not hud or not hud:IsA("ScreenGui") then
		return nil
	end
	local coinLabel = hud:FindFirstChild("CoinLabel", true)
	if coinLabel and coinLabel:IsA("GuiObject") then
		local bar = coinLabel.Parent
		if bar and bar:IsA("GuiObject") then
			return math.floor(bar.AbsolutePosition.Y)
		end
	end
	return nil
end

local function getHUDToolbar()
	local player = Players.LocalPlayer
	if not player then return nil end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	local hudGui = playerGui:FindFirstChild("HUDButtonBar")
	if not hudGui or not hudGui:IsA("ScreenGui") then return nil end
	local toolbar = hudGui:FindFirstChild("Toolbar")
	if toolbar and toolbar:IsA("GuiObject") then
		return toolbar
	end
	return nil
end

--- Exclusive bottom Y for full-screen menus: sit just above the hub button bar (same math when bar is visible).
local function getMenuBottomExclusiveY()
	local toolbar = getHUDToolbar()
	if not toolbar then return nil end
	local vp = getViewport()
	local _, insetBR = getGuiInsets()
	local barH = toolbar.AbsoluteSize.Y
	if not barH or barH < 8 then return nil end
	local lift = tonumber(toolbar:GetAttribute("BottomLiftPx")) or 0
	local bottomEdgeY = vp.Y - insetBR.Y
	local topOfToolbar = bottomEdgeY - barH - lift
	return math.floor(topOfToolbar - MENU_GAP_ABOVE_HUB_PX)
end

function MobileWindowLayout.IsMobile()
	-- Touch + no keyboard is the strictest signal for phones/tablets.
	-- Keep viewport fallback for simulators and edge devices.
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return true
	end
	if UserInputService.TouchEnabled and not UserInputService.GamepadEnabled then
		return true
	end

	local vp = getViewport()
	return vp.X <= 900 or vp.Y <= 700
end

function MobileWindowLayout.GetBounds(config)
	config = config or {}
	local cfg = {
		leftInset = config.leftInset ~= nil and config.leftInset or DEFAULTS.leftInset,
		rightInset = config.rightInset ~= nil and config.rightInset or DEFAULTS.rightInset,
		topInset = config.topInset ~= nil and config.topInset or DEFAULTS.topInset,
		bottomInset = config.bottomInset ~= nil and config.bottomInset or DEFAULTS.bottomInset,
		bottomMobileExtra = config.bottomMobileExtra ~= nil and config.bottomMobileExtra or DEFAULTS.bottomMobileExtra,
		-- Optional vertical shift (negative = move up). Applied after insets/ticker bound.
		shiftYScale = config.shiftYScale or 0,
		shiftYOffset = config.shiftYOffset or 0,
	}

	local forceMaximal = config.useMaximalSafeRect == true
	local fillSafeArea, edgeInsetPx, useCoinBarTop, reserveHubGap, ignoreLegacyHeightTweaks =
		readMobileFillConfig()
	if config.reserveBottomHubGap ~= nil then
		reserveHubGap = config.reserveBottomHubGap
	end
	if forceMaximal then
		useCoinBarTop = false
		ignoreLegacyHeightTweaks = true
	end
	-- Full safe-area layout on touch devices when GameConfig enables it, or when a caller
	-- requests useMaximalSafeRect (e.g. compact desktop window using the same menu chrome).
	local mobileFillEffect = (MobileWindowLayout.IsMobile() and fillSafeArea) or forceMaximal
	if mobileFillEffect then
		if config.leftInset == nil then
			cfg.leftInset = edgeInsetPx
		end
		if config.rightInset == nil then
			cfg.rightInset = edgeInsetPx
		end
		if config.topInset == nil then
			cfg.topInset = edgeInsetPx
		end
		if config.bottomInset == nil then
			cfg.bottomInset = edgeInsetPx
		end
	end

	local vp = getViewport()
	local insetTL, insetBR = getGuiInsets()
	-- Use full viewport height (ignore status / home-indicator padding from GetGuiInset on Y only).
	if config.extendViewportVertically == true then
		insetTL = Vector2.new(insetTL.X, 0)
		insetBR = Vector2.new(insetBR.X, 0)
	end
	local left = insetTL.X + cfg.leftInset
	local right = vp.X - insetBR.X - cfg.rightInset
	-- Prefer HUD coin bar top (matches main HUD); else notification ticker; else safe top + inset.
	local top = insetTL.Y + cfg.topInset
	if not (mobileFillEffect and not useCoinBarTop) then
		local coinTop = getCoinBarTopBound()
		if coinTop then
			top = coinTop
		else
			local tickerTop = getTickerTopBound()
			if tickerTop then
				top = math.min(top, tickerTop)
			end
		end
	end
	-- Fill to just above hub bar when we can measure it; else safe bottom minus padding.
	local bottom = vp.Y - insetBR.Y - cfg.bottomInset - cfg.bottomMobileExtra
	local menuBottomExclusive = getMenuBottomExclusiveY()
	if reserveHubGap and menuBottomExclusive and menuBottomExclusive > top + DEFAULTS.minHeight then
		bottom = menuBottomExclusive
	end

	-- Optional vertical shift (keeps window height stable by shifting top+bottom equally).
	local shiftY = (cfg.shiftYScale * vp.Y) + cfg.shiftYOffset
	if shiftY ~= 0 then
		top = top + shiftY
		bottom = bottom + shiftY
	end

	-- Clamp into the usable screen region (respect Roblox GUI insets).
	local minTop = insetTL.Y
	local maxBottom = vp.Y - insetBR.Y
	if top < minTop then
		local d = minTop - top
		top = top + d
		bottom = bottom + d
	end
	if bottom > maxBottom then
		local d = bottom - maxBottom
		top = top - d
		bottom = bottom - d
	end
	-- Pulling bottom down can push top above the safe region upward past minTop; fix before height math.
	if top < minTop then
		local d = minTop - top
		top = top + d
		bottom = bottom + d
	end

	-- Clamp for narrow devices so we always return a valid region.
	if bottom <= top + DEFAULTS.minHeight then
		bottom = vp.Y - insetBR.Y - cfg.bottomInset
	end
	if right <= left + DEFAULTS.minWidth then
		right = vp.X - insetBR.X - cfg.rightInset
	end

	-- GameConfig: vertical spawn offset + window height scale (all menus using GetBounds / ApplyWindow)
	local spawnOff, heightScale = readUiMenuLayoutTweaks()
	if mobileFillEffect and ignoreLegacyHeightTweaks then
		spawnOff = 0
		heightScale = 1
	end
	local h = bottom - top
	h = math.max(DEFAULTS.minHeight, math.floor(h * heightScale + 0.5))
	bottom = top + h
	top = top + spawnOff
	bottom = bottom + spawnOff
	if top < minTop then
		local d = minTop - top
		top = top + d
		bottom = bottom + d
	end
	if bottom > maxBottom then
		local d = bottom - maxBottom
		top = top - d
		bottom = bottom - d
	end
	if bottom <= top + DEFAULTS.minHeight then
		bottom = math.min(maxBottom, top + DEFAULTS.minHeight)
	end
	if top < minTop then
		top = minTop
	end
	if bottom > maxBottom then
		bottom = maxBottom
	end
	if bottom < top + DEFAULTS.minHeight then
		bottom = math.min(maxBottom, top + DEFAULTS.minHeight)
	end

	return {
		left = left,
		right = right,
		top = top,
		bottom = bottom,
		width = math.max(DEFAULTS.minWidth, right - left),
		height = math.max(DEFAULTS.minHeight, bottom - top),
		viewport = vp,
	}
end

-- ── NPC / shop / cooking menus (parity with InventoryUI fullscreen bounds) ──
local NPC_MENU_BREAKPOINT_X = 620
local NPC_MENU_BREAKPOINT_Y = 500

function MobileWindowLayout.NpcMenuUsesFullscreenBounds(designW, designH)
	designW = designW or 640
	designH = designH or 620
	if MobileWindowLayout.IsMobile() then
		return true
	end
	local cam = Workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(designW, designH)
	if vp.X < NPC_MENU_BREAKPOINT_X or vp.Y < NPC_MENU_BREAKPOINT_Y then
		return true
	end
	return vp.X < designW or vp.Y < designH
end

function MobileWindowLayout.GetNpcFullscreenBoundsConfig(designW, designH, merge)
	designW = designW or 640
	designH = designH or 620
	merge = merge or {}
	local cam = Workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(designW, designH)
	local compactViewport = vp.X < designW or vp.Y < designH
	local isMobileLike = MobileWindowLayout.IsMobile()
		or vp.X < NPC_MENU_BREAKPOINT_X
		or vp.Y < NPC_MENU_BREAKPOINT_Y
	local cfg = {
		extendViewportVertically = true,
		reserveBottomHubGap = false,
		bottomMobileExtra = 0,
		topInset = 0,
		bottomInset = 0,
		mobileDraggable = false,
	}
	for k, v in pairs(merge) do
		cfg[k] = v
	end
	if compactViewport and not isMobileLike then
		cfg.useMaximalSafeRect = true
	end
	return cfg
end

function MobileWindowLayout.SyncNpcMenuScreenGui(screenGui, designW, designH)
	if not screenGui then
		return
	end
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(designW, designH) then
		screenGui.IgnoreGuiInset = true
	else
		screenGui.IgnoreGuiInset = false
	end
end

function MobileWindowLayout.ApplyWindow(frame, config)
	if not frame then return nil end
	config = config or {}
	local bounds = MobileWindowLayout.GetBounds(config)

	local width = bounds.width
	local height = bounds.height
	width = math.min(width, math.floor(bounds.viewport.X * (config.maxWidthRatio or DEFAULTS.maxWidthRatio)))
	height = math.min(height, math.floor(bounds.viewport.Y * (config.maxHeightRatio or DEFAULTS.maxHeightRatio)))

	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.fromOffset(math.floor(bounds.left), math.floor(bounds.top))
	frame.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
	if frame:IsA("Frame") then
		frame.Draggable = (config.mobileDraggable == nil) and true or config.mobileDraggable
	end

	return bounds
end

function MobileWindowLayout.RestoreDesktopWindow(frame, config)
	if not frame then return end
	config = config or {}
	if frame:IsA("Frame") then
		frame.Draggable = config.draggable == nil and true or config.draggable
	end
end

function MobileWindowLayout.BindViewportUpdate(callback)
	if type(callback) ~= "function" then
		return function() end
	end

	local connections = {}
	local currentCameraConn

	local function bindCamera(camera)
		if currentCameraConn then
			currentCameraConn:Disconnect()
			currentCameraConn = nil
		end
		if not camera then return end
		currentCameraConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(callback)
	end

	local camera = Workspace.CurrentCamera
	bindCamera(camera)
	table.insert(connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		bindCamera(Workspace.CurrentCamera)
		callback()
	end))

	table.insert(connections, UserInputService.LastInputTypeChanged:Connect(function()
		callback()
	end))

	return function()
		if currentCameraConn then
			currentCameraConn:Disconnect()
		end
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
	end
end

function MobileWindowLayout.SetHUDBarVisible(visible)
	if not MobileWindowLayout.IsMobile() then return end
	local toolbar = getHUDToolbar()
	if not toolbar then return end

	local shownXScale = toolbar:GetAttribute("ShownXScale")
	local shownXOffset = toolbar:GetAttribute("ShownXOffset")
	local shownYScale = toolbar:GetAttribute("ShownYScale")
	local shownYOffset = toolbar:GetAttribute("ShownYOffset")
	if shownXScale == nil then
		toolbar:SetAttribute("ShownXScale", toolbar.Position.X.Scale)
		toolbar:SetAttribute("ShownXOffset", toolbar.Position.X.Offset)
		toolbar:SetAttribute("ShownYScale", toolbar.Position.Y.Scale)
		toolbar:SetAttribute("ShownYOffset", toolbar.Position.Y.Offset)
		shownXScale = toolbar.Position.X.Scale
		shownXOffset = toolbar.Position.X.Offset
		shownYScale = toolbar.Position.Y.Scale
		shownYOffset = toolbar.Position.Y.Offset
	end

	local shownPos = UDim2.new(shownXScale, shownXOffset, shownYScale, shownYOffset)
	local hiddenPos = UDim2.new(shownXScale, shownXOffset, 1, 88)
	toolbar:SetAttribute("MobileHUDVisible", visible and true or false)

	if visible then
		toolbar.Visible = true
		if toolbar.Position ~= shownPos then
			TweenService:Create(toolbar, HUD_TWEEN_INFO, { Position = shownPos }):Play()
		end
	else
		toolbar.Visible = true
		local tw = TweenService:Create(toolbar, HUD_TWEEN_INFO, { Position = hiddenPos })
		tw:Play()
		tw.Completed:Connect(function()
			-- Only hide if toolbar still exists and was not shown by a racing NotifyMenuClosed
			if toolbar.Parent and toolbar:GetAttribute("MobileHUDVisible") == false then
				toolbar.Visible = false
			end
		end)
	end
end

function MobileWindowLayout.NotifyMenuOpened()
	MobileWindowLayout.SetHUDBarVisible(false)
end

function MobileWindowLayout.NotifyMenuClosed()
	MobileWindowLayout.SetHUDBarVisible(true)
end

--- Menu window titles on phone/tablet: center text with symmetric horizontal gutters so labels
--- are not drawn under Roblox CoreGui (top-left). On desktop, restores the given layout.
--- desktop: optional { Position, Size, TextXAlignment } (defaults captured from `label` if omitted).
--- mobileLeftGutter / mobileRightGutter: pixels reserved for system UI and close buttons (defaults 44 / 50).
--- Returns apply() — call whenever layout is reapplied (e.g. from BindViewportUpdate alongside ApplyWindow).
function MobileWindowLayout.MenuHeaderTitleLayout(label, desktop)
	if not label or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return function() end
	end
	desktop = desktop or {}
	local save = {
		Position = desktop.Position ~= nil and desktop.Position or label.Position,
		Size = desktop.Size ~= nil and desktop.Size or label.Size,
		TextXAlignment = desktop.TextXAlignment ~= nil and desktop.TextXAlignment or label.TextXAlignment,
	}
	local lg = desktop.mobileLeftGutter
	if lg == nil then
		lg = 44
	end
	local rg = desktop.mobileRightGutter
	if rg == nil then
		rg = 50
	end

	local function apply()
		if not label.Parent then
			return
		end
		if MobileWindowLayout.IsMobile() then
			label.TextXAlignment = Enum.TextXAlignment.Center
			label.Position = UDim2.new(0, lg, save.Position.Y.Scale, save.Position.Y.Offset)
			label.Size = UDim2.new(1, -(lg + rg), save.Size.Y.Scale, save.Size.Y.Offset)
		else
			label.TextXAlignment = save.TextXAlignment
			label.Position = save.Position
			label.Size = save.Size
		end
	end

	apply()
	return apply
end

return MobileWindowLayout
