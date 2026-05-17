--[[
	Starts cook kitchen motion from ServerScriptService.
	Requires: ReplicatedStorage.Modules.CookKitchenAnimator

	If you also use a Script inside the kitchen model, remove one — the animator
	refuses to attach twice to the same model instance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CookKitchenAnimator = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CookKitchenAnimator"))

local function findCookKitchenModel()
	local probe = Workspace:FindFirstChild("Cook_Hearth_Base", true)
		or Workspace:FindFirstChild("Cook_Wok", true)
	if probe then
		local m = probe.Parent
		while m and m.Parent ~= Workspace do
			if m:IsA("Model") then
				return m
			end
			m = m.Parent
		end
	end
	return nil
end

task.spawn(function()
	local model = findCookKitchenModel()
	if model and model:IsA("Model") then
		CookKitchenAnimator.start(model)
		return
	end
	local conn
	conn = Workspace.DescendantAdded:Connect(function(inst)
		if inst.Name == "Cook_Hearth_Base" or inst.Name == "Cook_Wok" then
			local m = findCookKitchenModel()
			if m and m:IsA("Model") then
				CookKitchenAnimator.start(m)
				if conn then
					conn:Disconnect()
				end
			end
		end
	end)
	for _ = 1, 60 do
		task.wait(1)
		local m = findCookKitchenModel()
		if m and m:IsA("Model") then
			CookKitchenAnimator.start(m)
			if conn then
				conn:Disconnect()
			end
			return
		end
	end
	warn("[CookKitchenAnimation] Cook kitchen model not found after 60s.")
end)
