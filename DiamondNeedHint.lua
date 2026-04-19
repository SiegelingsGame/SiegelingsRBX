-- DiamondNeedHint.lua — ReplicatedStorage.Modules
-- Last updated: 2026-04-18 21:00
-- Shared client helper: popup when a gem/diamond purchase fails for insufficient balance.

local DiamondNeedHint = {}

local function isInsufficientDiamondMessage(msg)
	if type(msg) ~= "string" then
		return false
	end
	local lower = string.lower(msg)
	if not string.find(lower, "not enough", 1, true) then
		return false
	end
	return string.find(lower, "diamond", 1, true) ~= nil
		or string.find(lower, "gem", 1, true) ~= nil
end

--- Call after a failed purchase when using diamonds/gems as currency.
function DiamondNeedHint.OnInsufficientDiamonds(success, serverMsg, NotifyModule)
	if success then
		return
	end
	if not NotifyModule or not NotifyModule.RewardPopup then
		return
	end
	if not isInsufficientDiamondMessage(serverMsg) then
		return
	end
	local accent = Color3.fromRGB(180, 120, 255)
	NotifyModule.RewardPopup("Need more Diamonds?", accent, {
		{ text = "Earn Diamonds from Achievements (rewards menu).", color = Color3.fromRGB(200, 205, 220), textSize = 14 },
		{ text = "Complete Eleminion quests — each path grants gem rewards.", color = Color3.fromRGB(200, 205, 220), textSize = 14 },
		{ text = "Or open Shop → Gems to buy Diamonds with Robux.", color = Color3.fromRGB(220, 200, 120), textSize = 14 },
	}, 9)
end

return DiamondNeedHint
