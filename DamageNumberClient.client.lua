-- DamageNumberClient.client.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Shows damage numbers only for creatures the player is attacking (or companion) and arena/PvP.
-- Server fires ShowDamageNumber only to relevant player(s) to reduce open-world clutter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local showEvt = Events:FindFirstChild("ShowDamageNumber")
if not showEvt or not showEvt:IsA("RemoteEvent") then return end

local function showDamageNumber(pos, damage, color)
	local att = Instance.new("Part")
	att.Size = Vector3.new(0.1, 0.1, 0.1)
	att.Position = pos + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1))
	att.Anchored = true
	att.CanCollide = false
	att.Transparency = 1
	att.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 60, 0, 24)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = att
	bb.Parent = att

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "-" .. math.floor(damage)
	lbl.TextColor3 = color or Color3.fromRGB(255, 100, 60)
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextSize = 16
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = bb

	task.spawn(function()
		for i = 1, 15 do
			if not att.Parent then break end
			att.Position = att.Position + Vector3.new(0, 0.1, 0)
			lbl.TextTransparency = i / 15
			lbl.TextStrokeTransparency = 0.3 + (i / 15) * 0.7
			RunService.Heartbeat:Wait()
		end
		att:Destroy()
	end)
end

showEvt.OnClientEvent:Connect(function(pos, damage, color)
	if typeof(pos) == "Vector3" and type(damage) == "number" then
		showDamageNumber(pos, damage, color)
	end
end)
