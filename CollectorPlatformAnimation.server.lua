--[[
	Starts collector hub motion from ServerScriptService.
	Requires: ReplicatedStorage.Modules.CollectorPlatformAnimator
	Uses outer Collector_Platform when nested duplicate names exist.

	If you also use a Script inside Collector_Platform, remove one — the animator
	refuses to attach twice to the same model instance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CollectorPlatformAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CollectorPlatformAnimator"))

--- Prefer outer wrapper: Model "Collector_Platform" whose direct child is also "Collector_Platform" (your hierarchy).
local function findCollectorModel()
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == "Collector_Platform" then
			local inner = d:FindFirstChild("Collector_Platform")
			if inner and inner:IsA("Model") then
				return d
			end
		end
	end
	local probe = Workspace:FindFirstChild("Collector_Disk_Gold", true)
		or Workspace:FindFirstChild("Collector_Floor_Wood", true)
	if probe then
		local m = probe.Parent
		while m and m.Parent ~= Workspace do
			if m:IsA("Model") then
				return m
			end
			m = m.Parent
		end
	end
	return Workspace:FindFirstChild("Collector_Platform", true)
end

task.spawn(function()
	local model = findCollectorModel()
	if model and model:IsA("Model") then
		CollectorPlatformAnimator.start(model)
		return
	end
	local conn
	conn = Workspace.DescendantAdded:Connect(function(inst)
		if
			inst.Name == "Collector_Platform"
			or inst.Name == "Collector_Disk_Gold"
			or inst.Name == "Collector_Floor_Wood"
		then
			local m = findCollectorModel()
			if m and m:IsA("Model") then
				CollectorPlatformAnimator.start(m)
				if conn then
					conn:Disconnect()
				end
			end
		end
	end)
	for _ = 1, 60 do
		task.wait(1)
		local m = findCollectorModel()
		if m and m:IsA("Model") then
			CollectorPlatformAnimator.start(m)
			if conn then
				conn:Disconnect()
			end
			return
		end
	end
	warn("[CollectorPlatformAnimation] Collector_Platform not found after 60s.")
end)
