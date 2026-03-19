-- TradeSystem.lua - ServerScriptService (ModuleScript)
-- Secure player-to-player trading. Server-authoritative session state to prevent dupes/exploits.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local FavoriteCreatureSystem = nil
pcall(function() FavoriteCreatureSystem = require(ServerScriptService.FavoriteCreatureSystem) end)

local TradeSystem = {}

-- Injected
local PlayerDataManager
local Remotes = {}

-- tradeId -> session
local sessions = {}
-- userId -> tradeId (1 active trade per player)
local activeByUser = {}

local function nowId(a, b)
	return tostring(a) .. "-" .. tostring(b) .. "-" .. tostring(math.floor(os.clock() * 1000))
end

local function getPlayerByUserId(userId)
	return Players:GetPlayerByUserId(userId)
end

local function invHasUid(plr, uid)
	local d = PlayerDataManager.GetData(plr)
	if not d or not d.inventory then return false end
	local su = tostring(uid or "")
	if su == "" then return false end
	for _, e in ipairs(d.inventory) do
		if e.uid and tostring(e.uid) == su then return true end
	end
	return false
end

local function countInventory(plr)
	local d = PlayerDataManager.GetData(plr)
	return (d and d.inventory and #d.inventory) or 0
end

local function toArray(setTbl)
	local arr = {}
	for uid, v in pairs(setTbl or {}) do
		if v then table.insert(arr, uid) end
	end
	table.sort(arr)
	return arr
end

-- Build display info (displayName, level) for each offered uid for one player
local function getOfferDetails(plr, uidList)
	if not plr or type(uidList) ~= "table" then return {} end
	local d = PlayerDataManager.GetData(plr)
	if not d or not d.inventory then return {} end
	local details = {}
	for _, uid in ipairs(uidList) do
		local su = tostring(uid or "")
		for _, e in ipairs(d.inventory) do
			if e.uid and tostring(e.uid) == su then
				local info = CreatureData.GetById(e.id)
				table.insert(details, {
					uid = uid,
					displayName = info and info.displayName or e.id,
					level = e.level or 1,
				})
				break
			end
		end
	end
	return details
end

local function broadcastState(sess)
	local offerA = toArray(sess.offers[sess.aId])
	local offerB = toArray(sess.offers[sess.bId])
	local aPlr = getPlayerByUserId(sess.aId)
	local bPlr = getPlayerByUserId(sess.bId)

	local state = {
		tradeId = sess.tradeId,
		aId = sess.aId,
		bId = sess.bId,
		status = sess.status,
		offers = {
			[tostring(sess.aId)] = offerA,
			[tostring(sess.bId)] = offerB,
		},
		offerDetails = {
			[tostring(sess.aId)] = getOfferDetails(aPlr, offerA),
			[tostring(sess.bId)] = getOfferDetails(bPlr, offerB),
		},
		accepted = {
			[tostring(sess.aId)] = sess.accepted[sess.aId] and true or false,
			[tostring(sess.bId)] = sess.accepted[sess.bId] and true or false,
		},
	}
	if aPlr and Remotes.TradeState then Remotes.TradeState:FireClient(aPlr, state) end
	if bPlr and Remotes.TradeState then Remotes.TradeState:FireClient(bPlr, state) end
end

local function endSession(sess, reason)
	sess.status = reason or "ended"
	broadcastState(sess)
	sessions[sess.tradeId] = nil
	activeByUser[sess.aId] = nil
	activeByUser[sess.bId] = nil
end

local function validateOffer(plr, offerArr)
	if type(offerArr) ~= "table" then return false, "Invalid offer" end
	local seen = {}
	for _, uid in ipairs(offerArr) do
		if type(uid) ~= "string" or uid == "" then return false, "Invalid creature" end
		if seen[uid] then return false, "Duplicate creature" end
		seen[uid] = true
		if not invHasUid(plr, uid) then return false, "Creature not owned" end
	end
	return true, nil, seen
end

local function completeTrade(sess)
	local aPlr = getPlayerByUserId(sess.aId)
	local bPlr = getPlayerByUserId(sess.bId)
	if not aPlr or not bPlr then
		endSession(sess, "player_left")
		return
	end

	local offerA = toArray(sess.offers[sess.aId])
	local offerB = toArray(sess.offers[sess.bId])

	-- Validate still owned
	local okA, msgA = validateOffer(aPlr, offerA)
	if not okA then endSession(sess, "invalid_offer") return end
	local okB, msgB = validateOffer(bPlr, offerB)
	if not okB then endSession(sess, "invalid_offer") return end

	-- Capacity check (remove offered, add received)
	local aCount = countInventory(aPlr)
	local bCount = countInventory(bPlr)
	local aAfter = aCount - #offerA + #offerB
	local bAfter = bCount - #offerB + #offerA
	if aAfter > (GameConfig.MaxInventorySize or 50) or bAfter > (GameConfig.MaxInventorySize or 50) then
		endSession(sess, "inventory_full")
		return
	end

	-- Do transfers
	for _, uid in ipairs(offerA) do
		PlayerDataManager.TransferCreature(aPlr, bPlr, uid, { source = "trade" })
	end
	for _, uid in ipairs(offerB) do
		PlayerDataManager.TransferCreature(bPlr, aPlr, uid, { source = "trade" })
	end
	if PlayerDataManager.NotifyAchievement then
		PlayerDataManager.NotifyAchievement("OnTradeCompleted", aPlr)
		PlayerDataManager.NotifyAchievement("OnTradeCompleted", bPlr)
	end

	-- Refresh favorite companion models for both players (so traded favorites appear without re-equipping)
	if FavoriteCreatureSystem then
		FavoriteCreatureSystem.DespawnCompanion(aPlr)
		FavoriteCreatureSystem.DespawnCompanion(bPlr)
		-- Spawn immediately so companions update right after trade
		if aPlr.Parent then FavoriteCreatureSystem.SpawnCompanion(aPlr) end
		if bPlr.Parent then FavoriteCreatureSystem.SpawnCompanion(bPlr) end
	end

	sess.status = "completed"
	broadcastState(sess)
	endSession(sess, "completed")
end

function TradeSystem.Init(pdm, remotes)
	PlayerDataManager = pdm
	Remotes = remotes or {}

	-- Client -> server: request trade
	if Remotes.TradeRequest then
		Remotes.TradeRequest.OnServerEvent:Connect(function(player, targetUserId)
			targetUserId = tonumber(targetUserId)
			if not targetUserId then return end
			if targetUserId == player.UserId then return end
			local target = getPlayerByUserId(targetUserId)
			if not target then return end
			if activeByUser[player.UserId] or activeByUser[targetUserId] then return end

			local tradeId = nowId(player.UserId, targetUserId)
			local sess = {
				tradeId = tradeId,
				aId = player.UserId,
				bId = targetUserId,
				offers = {
					[player.UserId] = {},
					[targetUserId] = {},
				},
				accepted = {
					[player.UserId] = false,
					[targetUserId] = false,
				},
				status = "pending",
			}
			sessions[tradeId] = sess
			activeByUser[player.UserId] = tradeId
			activeByUser[targetUserId] = tradeId

			-- Notify target
			if Remotes.TradeInvite then
				Remotes.TradeInvite:FireClient(target, { tradeId = tradeId, fromUserId = player.UserId, fromName = player.Name })
			end
			-- Also tell requester we created it
			broadcastState(sess)
		end)
	end

	-- Client -> server: accept/decline invite
	if Remotes.TradeResponse then
		Remotes.TradeResponse.OnServerEvent:Connect(function(player, tradeId, accept)
			local sess = sessions[tradeId]
			if not sess then return end
			if player.UserId ~= sess.bId then return end
			if sess.status ~= "pending" then return end
			if not accept then
				endSession(sess, "declined")
				return
			end
			sess.status = "active"
			broadcastState(sess)
		end)
	end

	-- Client -> server: update offer (array of uids)
	if Remotes.TradeUpdateOffer then
		Remotes.TradeUpdateOffer.OnServerEvent:Connect(function(player, tradeId, offerArr)
			local sess = sessions[tradeId]
			if not sess or sess.status ~= "active" then return end
			if player.UserId ~= sess.aId and player.UserId ~= sess.bId then return end

			local ok, msg, setTbl = validateOffer(player, offerArr)
			if not ok then return end

			sess.offers[player.UserId] = setTbl
			-- any offer change resets accept flags
			sess.accepted[sess.aId] = false
			sess.accepted[sess.bId] = false
			broadcastState(sess)
		end)
	end

	-- Client -> server: accept trade
	if Remotes.TradeAccept then
		Remotes.TradeAccept.OnServerEvent:Connect(function(player, tradeId)
			local sess = sessions[tradeId]
			if not sess or sess.status ~= "active" then return end
			if player.UserId ~= sess.aId and player.UserId ~= sess.bId then return end
			sess.accepted[player.UserId] = true
			broadcastState(sess)
			if sess.accepted[sess.aId] and sess.accepted[sess.bId] then
				completeTrade(sess)
			end
		end)
	end

	-- Client -> server: cancel trade
	if Remotes.TradeCancel then
		Remotes.TradeCancel.OnServerEvent:Connect(function(player, tradeId)
			local sess = sessions[tradeId]
			if not sess then return end
			if player.UserId ~= sess.aId and player.UserId ~= sess.bId then return end
			endSession(sess, "cancelled")
		end)
	end

	-- Cleanup on leave
	Players.PlayerRemoving:Connect(function(plr)
		local tid = activeByUser[plr.UserId]
		if tid then
			local sess = sessions[tid]
			if sess then endSession(sess, "player_left") end
		end
	end)

	print("[TradeSystem] Initialized")
end

-- Public profile for profile popup: favorite, stats, battle team, isFriend
function TradeSystem.GetPublicProfile(requestingPlayer, targetUserId)
	targetUserId = tonumber(targetUserId)
	if not targetUserId then return nil end
	local target = getPlayerByUserId(targetUserId)
	if not target then return nil end
	local d = PlayerDataManager.GetData(target)
	if not d then return nil end

	-- Is target on requesting player's friends list?
	local isFriend = false
	if requestingPlayer then
		local reqData = PlayerDataManager.GetData(requestingPlayer)
		if reqData and reqData.friendsList then
			for _, fid in ipairs(reqData.friendsList) do
				if fid == targetUserId then isFriend = true break end
			end
		end
	end

	local favUid = d.favoriteUid
	local favEntry = nil
	local favCreatureId = nil
	if favUid and d.inventory then
		local favStr = tostring(favUid)
		for _, e in ipairs(d.inventory) do
			if e.uid and tostring(e.uid) == favStr then favEntry = e; favCreatureId = e.id break end
		end
	end
	local info = favCreatureId and CreatureData.GetById(favCreatureId) or nil
	local favorite = nil
	if favCreatureId and info then
		favorite = {
			id = favCreatureId,
			displayName = info.displayName or favCreatureId,
			rarity = info.rarity or "Common",
			primaryColor = info.primaryColor and { info.primaryColor.R, info.primaryColor.G, info.primaryColor.B } or { 0.5, 0.5, 0.5 },
			level = favEntry and (favEntry.level or 1) or 1,
			health = info.health,
			attack = info.attack,
			defense = info.defense,
			speed = info.speed,
		}
	end

	-- Battle team: ordered list of { slotIndex, creatureId, displayName }
	local battleTeam = {}
	if d.battleTeam and type(d.battleTeam) == "table" then
		local uidToEntry = {}
		for _, e in ipairs(d.inventory or {}) do
			if e.uid then uidToEntry[tostring(e.uid)] = e end
		end
		for slotStr, uid in pairs(d.battleTeam) do
			local slot = tonumber(slotStr)
			if slot and uid and uidToEntry[tostring(uid)] then
				local entry = uidToEntry[tostring(uid)]
				local c = CreatureData.GetById(entry.id)
				table.insert(battleTeam, {
					slotIndex = slot,
					creatureId = entry.id,
					displayName = c and c.displayName or entry.id,
				})
			end
		end
		table.sort(battleTeam, function(a, b) return a.slotIndex < b.slotIndex end)
	end

	-- Leaderboard-style stats
	local stats = d.stats or {}
	return {
		userId = targetUserId,
		name = target.Name,
		playerLevel = d.playerLevel or 1,
		isFriend = isFriend,
		stats = {
			arenaWins = stats.arenaWins or 0,
			arenaLosses = stats.arenaLosses or 0,
			arenaMaxStreak = stats.arenaMaxStreak or 0,
			totalCaptured = stats.totalCaptured or 0,
			totalIncome = stats.totalIncome or 0,
			totalRaids = stats.totalRaids or 0,
		},
		battleTeam = battleTeam,
		favorite = favorite,
	}
end

return TradeSystem

