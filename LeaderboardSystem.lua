-- LeaderboardSystem.lua - ServerScriptService (ModuleScript)
-- Manages physical leaderboard billboards and serves leaderboard data to clients.
-- Physical boards: place Parts named LeaderboardIncome, LeaderboardBattle, LeaderboardMonsters in workspace.Arena.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager -- set during Init

local LeaderboardSystem = {}

local REFRESH_INTERVAL = 30
local MAX_ENTRIES = 10

-- Scale factor for physical board text (increase to make text larger and more readable)
-- Lower PixelsPerStud = larger display; higher TextSize = bigger text
local UI_SCALE = 2

-- PvP wins/losses per server (in-memory only, resets when server restarts)
local pvpSessionStats = {}  -- [userId] = { wins = number, losses = number }

-- Board definitions
local BOARD_DEFS = {
	{
		partName = "LeaderboardIncome",
		title = "TOP INCOME EARNERS",
		titleColor = Color3.fromRGB(100, 220, 160),
		getStat = function(data) return data.stats.totalIncome or 0 end,
		formatValue = function(v) return tostring(v) .. " coins" end,
	},
	{
		partName = "LeaderboardBattle",
		title = "TOP BATTLE VICTORS",
		titleColor = Color3.fromRGB(255, 100, 60),
		getStat = function(data) return data.stats.arenaWins or 0 end,
		formatValue = function(v, data)
			local streak = data.stats.arenaMaxStreak or 0
			if streak > 0 then
				return tostring(v) .. " W | " .. streak .. " best"
			end
			return tostring(v) .. " W"
		end,
	},
	{
		partName = "LeaderboardMonsters",
		title = "TOP SIEGLING COLLECTORS",
		titleColor = Color3.fromRGB(200, 120, 255),
		getStat = function(data) return #data.inventory end,
		formatValue = function(v) return tostring(v) .. " owned" end,
	},
}

local boardRefs = {} -- { [partName] = { part = Part } }

-- Gather sorted leaderboard data from all online playersb
local function gatherLeaderboardData(statGetter)
	local entries = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local data = PlayerDataManager.GetData(player)
		if data then
			table.insert(entries, {
				name = player.Name,
				userId = player.UserId,
				value = statGetter(data),
				data = data,
			})
		end
	end
	table.sort(entries, function(a, b) return a.value > b.value end)
	return entries
end

-- Create or refresh the SurfaceGui on a board Part
local function refreshBoard(boardDef)
	local ref = boardRefs[boardDef.partName]
	if not ref or not ref.part or not ref.part.Parent then return end

	local part = ref.part

	-- Remove existing SurfaceGui
	local existing = part:FindFirstChild("LeaderboardSG")
	if existing then existing:Destroy() end

	local sg = Instance.new("SurfaceGui")
	sg.Name = "LeaderboardSG"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50 / UI_SCALE
	sg.Parent = part

	-- Background
	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	bg.BorderSizePixel = 0
	bg.Parent = sg

	local rowH = math.floor(26 * UI_SCALE)
	local titleH = math.floor(40 * UI_SCALE)

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, titleH)
	title.BackgroundColor3 = Color3.fromRGB(28, 30, 45)
	title.BorderSizePixel = 0
	title.Text = boardDef.title
	title.TextColor3 = boardDef.titleColor or Color3.fromRGB(255, 200, 50)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = math.floor(22 * UI_SCALE)
	title.Parent = bg
	Instance.new("UICorner", title).CornerRadius = UDim.new(0, 6)

	-- Gather data
	local entries = gatherLeaderboardData(boardDef.getStat)

	-- Rows
	local rowSpacing = math.floor(28 * UI_SCALE)
	for i = 1, MAX_ENTRIES do
		local entry = entries[i]
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -10, 0, rowH)
		row.Position = UDim2.new(0, 5, 0, titleH + 4 + (i - 1) * rowSpacing)
		row.BackgroundColor3 = i % 2 == 0
			and Color3.fromRGB(22, 24, 35)
			or Color3.fromRGB(18, 20, 30)
		row.BorderSizePixel = 0
		row.Parent = bg
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

		-- Rank color
		local rankColor = i == 1 and Color3.fromRGB(255, 200, 50)
			or i == 2 and Color3.fromRGB(200, 200, 210)
			or i == 3 and Color3.fromRGB(200, 140, 60)
			or Color3.fromRGB(140, 145, 160)

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(0, math.floor(30 * UI_SCALE), 1, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = "#" .. i
		rankLabel.TextColor3 = rankColor
		rankLabel.Font = Enum.Font.GothamBold
		rankLabel.TextSize = math.floor(14 * UI_SCALE)
		rankLabel.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.45, -math.floor(35 * UI_SCALE), 1, 0)
		nameLabel.Position = UDim2.new(0, math.floor(35 * UI_SCALE), 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = entry and entry.name or "---"
		nameLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.TextSize = math.floor(13 * UI_SCALE)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0.5, -10, 1, 0)
		valueLabel.Position = UDim2.new(0.5, 0, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = entry and boardDef.formatValue(entry.value, entry.data) or ""
		valueLabel.TextColor3 = Color3.fromRGB(100, 220, 160)
		valueLabel.Font = Enum.Font.GothamMedium
		valueLabel.TextSize = math.floor(12 * UI_SCALE)
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Parent = row
	end
end

-- Build PvP leaderboard: all online players, with session stats for those who have played
local function gatherPvPLeaderboardData()
	local entries = {}
	-- Include all online players (names show even with 0/0)
	for _, plr in ipairs(Players:GetPlayers()) do
		local stats = pvpSessionStats[plr.UserId]
		local wins = stats and stats.wins or 0
		local losses = stats and stats.losses or 0
		table.insert(entries, {
			name = plr.Name,
			userId = plr.UserId,
			value = wins,
			losses = losses,
		})
	end
	-- Sort by wins desc, then by losses asc (fewer losses = better)
	table.sort(entries, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.losses < b.losses
	end)
	return entries
end

-- Serve leaderboard data to clients
local function onGetLeaderboardData(player, category)
	if category == "pvp" then
		local entries = gatherPvPLeaderboardData()
		local result = {}
		for i = 1, math.min(MAX_ENTRIES, #entries) do
			local e = entries[i]
			table.insert(result, {
				rank = i,
				name = e.name,
				userId = e.userId,
				value = e.value,
				losses = e.losses or 0,
			})
		end
		local playerRank, playerValue, playerLosses = nil, nil, nil
		for i, e in ipairs(entries) do
			if e.userId == player.UserId then
				playerRank = i
				playerValue = e.value
				playerLosses = e.losses or 0
				break
			end
		end
		return {
			entries = result,
			playerRank = playerRank,
			playerValue = playerValue,
			playerLosses = playerLosses,
		}
	end

	local boardDef
	if category == "income" then boardDef = BOARD_DEFS[1]
	elseif category == "battle" then boardDef = BOARD_DEFS[2]
	elseif category == "monsters" then boardDef = BOARD_DEFS[3]
	else return {} end

	local entries = gatherLeaderboardData(boardDef.getStat)
	local result = {}

	for i = 1, math.min(MAX_ENTRIES, #entries) do
		local e = entries[i]
		table.insert(result, {
			rank = i,
			name = e.name,
			userId = e.userId,
			value = e.value,
			maxStreak = e.data.stats.arenaMaxStreak or 0,
		})
	end

	-- Find requesting player's rank
	local playerRank, playerValue = nil, nil
	for i, e in ipairs(entries) do
		if e.userId == player.UserId then
			playerRank = i
			playerValue = e.value
			break
		end
	end

	return {
		entries = result,
		playerRank = playerRank,
		playerValue = playerValue,
	}
end

-- Record a PvP battle result (called by PvPBattleSystem when a battle ends)
function LeaderboardSystem.RecordPvPResult(winnerPlayer, loserPlayer)
	if winnerPlayer and winnerPlayer.Parent then
		local uid = winnerPlayer.UserId
		if not pvpSessionStats[uid] then pvpSessionStats[uid] = { wins = 0, losses = 0 } end
		pvpSessionStats[uid].wins = (pvpSessionStats[uid].wins or 0) + 1
	end
	if loserPlayer and loserPlayer.Parent then
		local uid = loserPlayer.UserId
		if not pvpSessionStats[uid] then pvpSessionStats[uid] = { wins = 0, losses = 0 } end
		pvpSessionStats[uid].losses = (pvpSessionStats[uid].losses or 0) + 1
	end
end

function LeaderboardSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr

	-- Find physical board parts in workspace.Arena
	local arena = workspace:FindFirstChild("Arena")
	for _, def in ipairs(BOARD_DEFS) do
		local part = arena and arena:FindFirstChild(def.partName)
		if part and part:IsA("BasePart") then
			boardRefs[def.partName] = { part = part }
			print("[Leaderboard] Found board: " .. def.partName)
		else
			warn("[Leaderboard] Board part not found: " .. def.partName .. " (place a Part with this name in workspace.Arena)")
		end
	end

	-- Wire RemoteFunction
	local events = ReplicatedStorage:WaitForChild("Events", 10)
	if events then
		local getLeaderboard = events:FindFirstChild("GetLeaderboardData")
		if getLeaderboard then
			getLeaderboard.OnServerInvoke = onGetLeaderboardData
		end
	end

	-- Refresh loop for physical boards
	task.spawn(function()
		while true do
			for _, def in ipairs(BOARD_DEFS) do
				pcall(refreshBoard, def)
			end
			task.wait(REFRESH_INTERVAL)
		end
	end)

	print("[LeaderboardSystem] Initialized (" .. REFRESH_INTERVAL .. "s refresh, " .. MAX_ENTRIES .. " entries)")
end

return LeaderboardSystem
