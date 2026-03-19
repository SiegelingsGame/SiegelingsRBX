-- KnightBaseClient.client.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- FIX #35: Knight Base Rental — Client HUD
-- Shows a deployment timer when the player rents a knight base in a biome,
-- displays countdown warnings, and handles shield-blocked notifications.
--
-- Events listened:
--   KnightBaseRented   (biomeName: string, duration: number)
--   KnightBaseReturned ()
--   KnightBaseTimer    (remainingSeconds: number)
--   KnightBaseWarning  (remainingSeconds: number | "shield_blocked")
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Notify = require(ReplicatedStorage.Modules:WaitForChild("NotificationManager"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Wait for Events folder and RemoteEvents
-- ═══════════════════════════════════════════════════════════════════════════════
local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then
	warn("[KnightBaseClient] Events folder not found, aborting")
	return
end

local rentedEvt   = Events:WaitForChild("KnightBaseRented", 10)
local returnedEvt = Events:WaitForChild("KnightBaseReturned", 10)
local timerEvt    = Events:WaitForChild("KnightBaseTimer", 10)
local warningEvt  = Events:WaitForChild("KnightBaseWarning", 10)

-- ═══════════════════════════════════════════════════════════════════════════════
-- Constants
-- ═══════════════════════════════════════════════════════════════════════════════
local FRAME_WIDTH  = 220
local FRAME_HEIGHT = 38
local BG_COLOR     = Color3.fromRGB(20, 20, 30)
local BG_TRANS     = 0.25
local BORDER_COLOR = Color3.fromRGB(180, 140, 50)  -- gold accent
local TEXT_COLOR   = Color3.fromRGB(255, 220, 120)  -- warm gold text
local WARN_COLOR_30 = Color3.fromRGB(255, 180, 60)  -- orange warning
local WARN_COLOR_10 = Color3.fromRGB(255, 60, 60)   -- red urgent

-- ═══════════════════════════════════════════════════════════════════════════════
-- Build the deployment HUD (hidden by default)
-- ═══════════════════════════════════════════════════════════════════════════════
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KnightBaseHUD"
screenGui.DisplayOrder = 55
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Main frame: centered near top of screen
local frame = Instance.new("Frame")
frame.Name = "DeployFrame"
frame.Size = UDim2.new(0, FRAME_WIDTH, 0, FRAME_HEIGHT)
frame.Position = UDim2.new(0.5, -FRAME_WIDTH / 2, 0, 52)  -- below top bar
frame.AnchorPoint = Vector2.new(0, 0)
frame.BackgroundColor3 = BG_COLOR
frame.BackgroundTransparency = BG_TRANS
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = screenGui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

-- Gold border stroke
local stroke = Instance.new("UIStroke")
stroke.Color = BORDER_COLOR
stroke.Thickness = 1.5
stroke.Transparency = 0.3
stroke.Parent = frame

-- Sword icon + biome label + timer
local label = Instance.new("TextLabel")
label.Name = "DeployLabel"
label.Size = UDim2.new(1, -16, 1, 0)
label.Position = UDim2.new(0, 8, 0, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 15
label.TextColor3 = TEXT_COLOR
label.TextXAlignment = Enum.TextXAlignment.Center
label.TextYAlignment = Enum.TextYAlignment.Center
label.Text = ""
label.Parent = frame

-- ═══════════════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════════════
local isActive = false
local currentBiome = ""
local currentRemaining = 0

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: format seconds as M:SS
-- @param seconds number
-- @return string  e.g. "4:32"
-- ═══════════════════════════════════════════════════════════════════════════════
local function formatTime(seconds)
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return m .. ":" .. string.format("%02d", s)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: update the label text and color based on remaining time
-- ═══════════════════════════════════════════════════════════════════════════════
local function updateDisplay()
	if not isActive then return end
	local timeStr = formatTime(currentRemaining)

	-- Color shifts as time runs low
	local textColor = TEXT_COLOR
	if currentRemaining <= 10 then
		textColor = WARN_COLOR_10
	elseif currentRemaining <= 30 then
		textColor = WARN_COLOR_30
	end

	label.Text = "⚔️  " .. currentBiome .. "  —  " .. timeStr
	label.TextColor3 = textColor
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fade in/out animations
-- ═══════════════════════════════════════════════════════════════════════════════
local function fadeIn()
	frame.Visible = true
	frame.BackgroundTransparency = 1
	label.TextTransparency = 1
	stroke.Transparency = 1
	TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = BG_TRANS,
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.4), { Transparency = 0.3 }):Play()
end

local function fadeOut()
	TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
	task.delay(0.35, function()
		if not isActive then
			frame.Visible = false
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Event Handlers
-- ═══════════════════════════════════════════════════════════════════════════════

-- KnightBaseRented: server tells us we just rented a knight base
-- @param biomeName string  e.g. "Desert"
-- @param duration  number  total seconds (e.g. 300)
if rentedEvt then
	rentedEvt.OnClientEvent:Connect(function(biomeName, duration)
		isActive = true
		currentBiome = biomeName or "Biome"
		currentRemaining = duration or 300
		updateDisplay()
		fadeIn()
		print("[KnightBaseClient] Rental started: " .. currentBiome .. " (" .. duration .. "s)")
	end)
end

-- KnightBaseReturned: rental ended, base returned home
if returnedEvt then
	returnedEvt.OnClientEvent:Connect(function()
		isActive = false
		currentBiome = ""
		currentRemaining = 0
		fadeOut()
		print("[KnightBaseClient] Rental ended, base returned home")
	end)
end

-- KnightBaseTimer: countdown tick every second
-- @param remaining number  seconds left
if timerEvt then
	timerEvt.OnClientEvent:Connect(function(remaining)
		if not isActive then return end
		currentRemaining = remaining
		updateDisplay()
	end)
end

-- KnightBaseWarning: countdown threshold warnings + shield blocked message
-- @param payload number|string  seconds remaining (30, 10) or "shield_blocked"
if warningEvt then
	warningEvt.OnClientEvent:Connect(function(payload)
		if payload == "shield_blocked" then
			-- Shield denial during knight base rental
			Notify.Toast(
				"Your base shield is recharging from the teleport",
				Color3.fromRGB(255, 140, 50),  -- orange
				4
			)
			return
		end

		-- Numeric countdown warning (30s, 10s)
		local remaining = tonumber(payload)
		if not remaining then return end

		if remaining <= 10 then
			Notify.Toast(
				"BASE RETURNING IN " .. remaining .. " SECONDS!",
				WARN_COLOR_10,
				3
			)
		elseif remaining <= 30 then
			Notify.Toast(
				"Base returning home in " .. remaining .. " seconds!",
				WARN_COLOR_30,
				4
			)
		end
	end)
end

print("[KnightBaseClient] Initialized — listening for knight base events")
