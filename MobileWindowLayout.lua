-- MobileWindowLayout.lua
-- Reusable helper for mobile-only fullscreen-style menu placement inside safe bounds.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MobileWindowLayout = {}

local DEFAULTS = {
	-- Insets applied in addition to Roblox GUI insets.
	leftInset = 16,
	rightInset = 16,
	topInset = 12,
	bottomInset = 16,
	-- Additional mobile breathing room to avoid bottom controls.
	bottomMobileExtra = 16,
	-- Minimum usable panel size.
	minWidth = 280,
	minHeight = 220,
	-- Optional guard rails for very large tablets.
	maxWidthRatio = 0.98,
	maxHeightRatio = 1,
}

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
		leftInset = config.leftInset or DEFAULTS.leftInset,
		rightInset = config.rightInset or DEFAULTS.rightInset,
		topInset = config.topInset or DEFAULTS.topInset,
		bottomInset = config.bottomInset or DEFAULTS.bottomInset,
		bottomMobileExtra = config.bottomMobileExtra or DEFAULTS.bottomMobileExtra,
	}

	local vp = getViewport()
	local insetTL, insetBR = getGuiInsets()
	local left = insetTL.X + cfg.leftInset
	local right = vp.X - insetBR.X - cfg.rightInset
	local top = insetTL.Y + cfg.topInset
	local tickerTop = getTickerTopBound()
	if tickerTop then
		-- Keep mobile windows aligned to the same top bound as the ticker area.
		top = tickerTop
	end
	local bottom = vp.Y - insetBR.Y - cfg.bottomInset - cfg.bottomMobileExtra

	-- Clamp for narrow devices so we always return a valid region.
	if bottom <= top + DEFAULTS.minHeight then
		bottom = vp.Y - insetBR.Y - cfg.bottomInset
	end
	if right <= left + DEFAULTS.minWidth then
		right = vp.X - insetBR.X - cfg.rightInset
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
			if toolbar:GetAttribute("MobileHUDVisible") == false then
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

return MobileWindowLayout
