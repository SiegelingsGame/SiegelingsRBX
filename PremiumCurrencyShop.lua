-- PremiumCurrencyShop.lua - ServerScriptService (ModuleScript)
-- Last updated: 2026-04-23 19:35
-- SCoins packs: buy with Diamonds (gems). Robux → Gems handled in EggShopSystem ProcessReceipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PremiumCurrencyShop = {}

local PlayerDataManager

function PremiumCurrencyShop.Init(pdm, eventsFolder)
	PlayerDataManager = pdm
	if not eventsFolder then
		return
	end

	local buyScoinsPack = eventsFolder:FindFirstChild("BuyScoinsPack")
	if not buyScoinsPack then
		warn("[PremiumCurrencyShop] BuyScoinsPack remote missing")
		return
	end

	local function getScoinsPackById(packId)
		if type(packId) ~= "string" then
			return nil
		end
		for _, p in ipairs(GameConfig.ScoinsGemPacks or {}) do
			if p.id == packId then
				return p
			end
		end
		return nil
	end

	buyScoinsPack.OnServerInvoke = function(player, packId)
		local pack = getScoinsPackById(packId)
		if not pack then
			return false, "Invalid pack"
		end
		local gemCost = tonumber(pack.gemCost) or 0
		local grant = tonumber(pack.scoins) or 0
		if gemCost <= 0 or grant <= 0 then
			return false, "Pack unavailable"
		end
		if not PlayerDataManager.SpendGems(player, gemCost) then
			return false, "Not enough diamonds! Need " .. gemCost
		end
		PlayerDataManager.AddScoins(player, grant)

		local gemsEvt = eventsFolder:FindFirstChild("GemsUpdate")
		if gemsEvt then
			gemsEvt:FireClient(player, PlayerDataManager.GetGems(player))
		end
		local scEvt = eventsFolder:FindFirstChild("SCoinsUpdate")
		if scEvt then
			scEvt:FireClient(player, PlayerDataManager.GetScoins(player))
		end

		task.spawn(function()
			pcall(function()
				if PlayerDataManager.RequestSave then
					PlayerDataManager.RequestSave(player)
				else
					PlayerDataManager.SavePlayer(player)
				end
			end)
		end)

		print("[PremiumCurrencyShop] " .. player.Name .. " bought SCoins pack " .. tostring(pack.id))
		return true, "Received " .. grant .. " SCoins!"
	end

	print("[PremiumCurrencyShop] Initialized")
end

return PremiumCurrencyShop
