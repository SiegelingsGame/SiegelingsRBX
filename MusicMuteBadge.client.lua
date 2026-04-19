-- ═══════════════════════════════════════════════════════════════════════════════
-- Last updated: 2026-04-20 16:00
-- MusicMuteBadge.client.lua — Small top-edge control to mute gameplay music (SoundGroup).
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local TopRightBadgeTray = require(ReplicatedStorage.Modules:WaitForChild("TopRightBadgeTray"))
local musicCfg = GameConfig.GameplayMusic or {}

if musicCfg.Enabled == false then
	return
end

local GROUP_NAME = musicCfg.SoundGroupName or "Music"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local musicGroup = SoundService:FindFirstChild(GROUP_NAME)
if not musicGroup or not musicGroup:IsA("SoundGroup") then
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = GROUP_NAME
	musicGroup.Volume = 1
	musicGroup.Parent = SoundService
end

local muted = false
local volumeBeforeMute = musicGroup.Volume > 0 and musicGroup.Volume or 1

local container = Instance.new("Frame")
container.Name = "MusicMuteBadge"
container.AnchorPoint = Vector2.new(0, 0)
container.Size = UDim2.fromOffset(44, 44)
container.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
container.BackgroundTransparency = 0.12
container.BorderSizePixel = 0
container.LayoutOrder = TopRightBadgeTray.Order.MusicMute
container.Parent = TopRightBadgeTray.GetBadgeRow(player)

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = container

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(90, 95, 120)
stroke.Thickness = 1
stroke.Transparency = 0.35
stroke.Parent = container

local btn = Instance.new("TextButton")
btn.Name = "Toggle"
btn.Size = UDim2.fromScale(1, 1)
btn.BackgroundTransparency = 1
btn.Text = ""
btn.AutoButtonColor = false
btn.Parent = container

local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.BackgroundTransparency = 1
icon.Font = Enum.Font.GothamBold
icon.TextScaled = true
icon.TextColor3 = Color3.fromRGB(235, 238, 252)
icon.Parent = container


local function syncVisual()
	if muted then
		icon.Text = "🔇"
		container.BackgroundColor3 = Color3.fromRGB(38, 28, 28)
		stroke.Color = Color3.fromRGB(140, 90, 90)
	else
		icon.Text = "🔊"
		container.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
		stroke.Color = Color3.fromRGB(90, 95, 120)
	end
end

local function applyMute()
	if muted then
		volumeBeforeMute = musicGroup.Volume > 0.001 and musicGroup.Volume or volumeBeforeMute
		musicGroup.Volume = 0
	else
		musicGroup.Volume = volumeBeforeMute > 0 and volumeBeforeMute or 1
	end
	syncVisual()
end

syncVisual()

btn.MouseButton1Click:Connect(function()
	muted = not muted
	applyMute()
end)
