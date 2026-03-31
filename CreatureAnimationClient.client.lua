-- CreatureAnimationClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Listens for PlayCreatureAnimation from server and plays animations on replicated creature models.
-- Fixes animations not showing for other players in multiplayer (Server & Clients mode).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureAnimation = require(ReplicatedStorage.Modules.CreatureAnimation)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local evt = Events:WaitForChild("PlayCreatureAnimation", 5)
if not evt then return end

evt.OnClientEvent:Connect(function(model, animType, creatureId, options)
	if not model or not model.Parent then return end
	CreatureAnimation.PlayAnimation(model, animType, creatureId, options)
end)
