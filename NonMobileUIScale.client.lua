-- NonMobileUIScale.client.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Scales up the entire UI by 25% on non-mobile devices only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileWindowLayout = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCALE = 1.25
local SCALE_NAME = "GlobalNonMobileScale"

local function shouldScale()
	return not MobileWindowLayout.IsMobile()
end

local function ensureScaled(screenGui)
	if not shouldScale() then
		return
	end
	if not screenGui or not screenGui:IsA("ScreenGui") then
		return
	end
	-- Opt-out flag per GUI if needed.
	if screenGui:GetAttribute("IgnoreNonMobileScale") == true then
		return
	end

	-- If some other system already inserted a scale, don't stack scales.
	local existing = screenGui:FindFirstChild(SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		existing.Scale = SCALE
		return
	end
	if screenGui:FindFirstChildOfClass("UIScale") then
		return
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Name = SCALE_NAME
	uiScale.Scale = SCALE
	uiScale.Parent = screenGui
end

-- Initial pass (defer a bit so other UIs can spawn first)
task.defer(function()
	for _, child in ipairs(playerGui:GetChildren()) do
		ensureScaled(child)
	end
end)

playerGui.ChildAdded:Connect(function(child)
	ensureScaled(child)
end)

print("[NonMobileUIScale] Loaded - non-mobile UI scale x" .. tostring(SCALE))
