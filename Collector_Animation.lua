--[[
	In-model entrypoint (paste as Script under the OUTER Collector_Platform model).
	Requires synced ModuleScript: ReplicatedStorage.Modules.CollectorPlatformAnimator

	Remove this Script if you use ServerScriptService.CollectorPlatformAnimation only (avoid duplicate runs).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules", 15)
local animatorMod = Modules and Modules:WaitForChild("CollectorPlatformAnimator", 15)
if not animatorMod then
	warn("[Collector_Animation] CollectorPlatformAnimator module missing — sync Rojo / add ModuleScript.")
	return
end

local CollectorPlatformAnimator = require(animatorMod)

task.defer(function()
	local model = script.Parent
	if model and model:IsA("Model") then
		CollectorPlatformAnimator.start(model)
	else
		warn("[Collector_Animation] Parent must be the outer Collector_Platform Model.")
	end
end)
