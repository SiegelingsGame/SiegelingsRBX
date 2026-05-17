-- LeaderboardSystem.lua - ServerScriptService (ModuleScript)
-- Manages physical leaderboard billboards and serves leaderboard data to clients.
-- Physical boards: place Parts named LeaderboardIncome, LeaderboardBattle, LeaderboardMonsters in workspace.Arena.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataManager -- set during Init

local LeaderboardSystem = {}

local REFRESH_INTERVAL = 30
local MAX_ENTRIES = 10 -- physical arena boards
local REMOTE_MAX_ENTRIES = 3 -- full-screen UI: top 3 only

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
		title = "TOP SIEGELING COLLECTORS",
		titleColor = Color3.fromRGB(200, 120, 255),
		getStat = function(data) return #data.inventory end,
		formatValue = function(v) return tostring(v) .. " owned" end,
	},
}

local boardRefs = {} -- { [partName] = { part = Part } }

-- Gather sorted leaderboard data from all online playersbf
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

-- Rank display config
local RANK_COLORS = {
	Color3.fromRGB(255, 200, 50),  -- gold
	Color3.fromRGB(200, 200, 220), -- silver
	Color3.fromRGB(210, 145, 65),  -- bronze
}
local RANK_GLOW_COLORS = {
	Color3.fromRGB(255, 180, 0),
	Color3.fromRGB(160, 170, 200),
	Color3.fromRGB(180, 110, 30),
}
local RANK_LABELS = { "1ST", "2ND", "3RD" }
local RANK_CARD_BG = {
	Color3.fromRGB(40, 35, 18),  -- warm dark gold tint
	Color3.fromRGB(28, 30, 40),  -- cool dark silver tint
	Color3.fromRGB(35, 28, 18),  -- warm dark bronze tint
}

-- Fetch player headshot thumbnail (server-side)
local thumbnailCache = {}
local function getHeadshotUrl(userId)
	if thumbnailCache[userId] then return thumbnailCache[userId] end
	local ok, content, isReady = pcall(function()
		return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
	end)
	if ok and content then
		thumbnailCache[userId] = content
		return content
	end
	return nil
end

-- Helper: create a circular avatar ImageLabel inside a parent
local function createAvatarCircle(parent, size, posX, posY, userId, borderColor)
	-- Outer ring (glow border)
	local ring = Instance.new("Frame")
	ring.Size = UDim2.new(0, size + 6, 0, size + 6)
	ring.Position = UDim2.new(0, posX - 3, 0, posY - 3)
	ring.BackgroundColor3 = borderColor or Color3.fromRGB(255, 200, 50)
	ring.BackgroundTransparency = 0.3
	ring.BorderSizePixel = 0
	ring.Parent = parent
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)

	-- Inner circle background
	local circle = Instance.new("Frame")
	circle.Size = UDim2.new(0, size, 0, size)
	circle.Position = UDim2.new(0, 3, 0, 3)
	circle.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
	circle.BorderSizePixel = 0
	circle.Parent = ring
	Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)

	-- Avatar image
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.new(1, -4, 1, -4)
	img.Position = UDim2.new(0, 2, 0, 2)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Fit
	img.Parent = circle
	Instance.new("UICorner", img).CornerRadius = UDim.new(1, 0)

	if userId then
		local url = getHeadshotUrl(userId)
		if url then img.Image = url end
	end

	return ring
end

-- Create or refresh the SurfaceGui on a board Part
-- Layout: title bar, 3 podium cards (2nd | 1st | 3rd) with avatars, runner-up 4th bar
local function refreshBoard(boardDef)
	local ref = boardRefs[boardDef.partName]
	if not ref or not ref.part or not ref.part.Parent then return end

	local part = ref.part

	-- Remove existing SurfaceGui
	local existing = part:FindFirstChild("LeaderboardSG")
	if existing then existing:Destroy() end

	local S = UI_SCALE
	local sg = Instance.new("SurfaceGui")
	sg.Name = "LeaderboardSG"
	sg.Face = Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 50 / S
	sg.Parent = part

	-- Background
	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, math.floor(8 * S))

	-- Subtle top accent line
	local accentLine = Instance.new("Frame")
	accentLine.Size = UDim2.new(1, -math.floor(20 * S), 0, math.floor(3 * S))
	accentLine.Position = UDim2.new(0, math.floor(10 * S), 0, 0)
	accentLine.BackgroundColor3 = boardDef.titleColor or Color3.fromRGB(255, 200, 50)
	accentLine.BackgroundTransparency = 0.3
	accentLine.BorderSizePixel = 0
	accentLine.Parent = bg

	-- Title bar
	local titleH = math.floor(38 * S)
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, titleH)
	titleBar.Position = UDim2.new(0, 0, 0, math.floor(3 * S))
	titleBar.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
	titleBar.BackgroundTransparency = 0.2
	titleBar.BorderSizePixel = 0
	titleBar.Parent = bg

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = boardDef.title
	titleLabel.TextColor3 = boardDef.titleColor or Color3.fromRGB(255, 200, 50)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = math.floor(20 * S)
	titleLabel.Parent = titleBar

	-- Gather data
	local entries = gatherLeaderboardData(boardDef.getStat)

	-- === PODIUM SECTION ===
	-- Layout order on board: 2nd (left) | 1st (center, taller) | 3rd (right)
	local podiumTop = titleH + math.floor(10 * S)
	local cardW = math.floor(90 * S)
	local cardGap = math.floor(8 * S)
	local totalCardsW = cardW * 3 + cardGap * 2
	-- We'll position using proportions of the parent width for centering

	-- Card heights: 1st is tallest, 2nd/3rd shorter (podium effect)
	local cardH1 = math.floor(180 * S)
	local cardH2 = math.floor(160 * S)
	local cardH3 = math.floor(155 * S)
	local cardHeights = { cardH1, cardH2, cardH3 }

	-- Display order on screen: [2nd] [1st] [3rd] for podium feel
	local displayOrder = { 2, 1, 3 }
	local avatarSize1 = math.floor(58 * S)
	local avatarSize23 = math.floor(48 * S)
	local avatarSizes = { avatarSize1, avatarSize23, avatarSize23 }

	for col = 1, 3 do
		local rank = displayOrder[col]
		local entry = entries[rank]
		local cardH = cardHeights[rank]
		local rankColor = RANK_COLORS[rank]
		local glowColor = RANK_GLOW_COLORS[rank]
		local cardBg = RANK_CARD_BG[rank]
		local avatarSz = avatarSizes[rank]

		-- Vertical offset: 1st starts higher (podium step effect)
		local yOffset = podiumTop
		if rank == 2 then yOffset = podiumTop + math.floor(20 * S) end
		if rank == 3 then yOffset = podiumTop + math.floor(25 * S) end

		-- Horizontal position: evenly spaced 3 columns
		local xFrac = (col - 1) / 3
		local xPad = math.floor(6 * S)

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1 / 3, -xPad * 2, 0, cardH)
		card.Position = UDim2.new(xFrac, xPad, 0, yOffset)
		card.BackgroundColor3 = cardBg
		card.BorderSizePixel = 0
		card.Parent = bg
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, math.floor(8 * S))

		-- Card glow border
		local cardStroke = Instance.new("UIStroke")
		cardStroke.Color = glowColor
		cardStroke.Thickness = rank == 1 and math.floor(2 * S) or math.floor(1.5 * S)
		cardStroke.Transparency = rank == 1 and 0.2 or 0.45
		cardStroke.Parent = card

		-- Rank badge
		local badgeH = math.floor(22 * S)
		local badge = Instance.new("TextLabel")
		badge.Size = UDim2.new(1, 0, 0, badgeH)
		badge.Position = UDim2.new(0, 0, 0, math.floor(6 * S))
		badge.BackgroundTransparency = 1
		badge.Text = RANK_LABELS[rank] or ("#" .. rank)
		badge.TextColor3 = rankColor
		badge.Font = Enum.Font.GothamBlack
		badge.TextSize = rank == 1 and math.floor(18 * S) or math.floor(14 * S)
		badge.Parent = card

		-- Avatar (centered in card)
		local avatarX = math.floor((cardW - avatarSz) / 2)  -- approximate centering
		-- Use 0.5 scale positioning for true center
		local avatarFrame = Instance.new("Frame")
		avatarFrame.Size = UDim2.new(0, avatarSz + 6, 0, avatarSz + 6)
		avatarFrame.Position = UDim2.new(0.5, -math.floor((avatarSz + 6) / 2), 0, badgeH + math.floor(10 * S))
		avatarFrame.BackgroundColor3 = glowColor
		avatarFrame.BackgroundTransparency = 0.25
		avatarFrame.BorderSizePixel = 0
		avatarFrame.Parent = card
		Instance.new("UICorner", avatarFrame).CornerRadius = UDim.new(1, 0)

		local avatarInner = Instance.new("Frame")
		avatarInner.Size = UDim2.new(0, avatarSz, 0, avatarSz)
		avatarInner.Position = UDim2.new(0, 3, 0, 3)
		avatarInner.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
		avatarInner.BorderSizePixel = 0
		avatarInner.Parent = avatarFrame
		Instance.new("UICorner", avatarInner).CornerRadius = UDim.new(1, 0)

		local avatarImg = Instance.new("ImageLabel")
		avatarImg.Size = UDim2.new(1, -4, 1, -4)
		avatarImg.Position = UDim2.new(0, 2, 0, 2)
		avatarImg.BackgroundTransparency = 1
		avatarImg.ScaleType = Enum.ScaleType.Fit
		avatarImg.Parent = avatarInner
		Instance.new("UICorner", avatarImg).CornerRadius = UDim.new(1, 0)

		if entry and entry.userId then
			local url = getHeadshotUrl(entry.userId)
			if url then avatarImg.Image = url end
		end

		-- Player name
		local nameY = badgeH + math.floor(10 * S) + avatarSz + math.floor(12 * S)
		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -math.floor(6 * S), 0, math.floor(16 * S))
		nameLbl.Position = UDim2.new(0, math.floor(3 * S), 0, nameY)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = entry and entry.name or "---"
		nameLbl.TextColor3 = Color3.fromRGB(230, 232, 240)
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = rank == 1 and math.floor(13 * S) or math.floor(11 * S)
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.Parent = card

		-- Stat value
		local valY = nameY + math.floor(18 * S)
		local valLbl = Instance.new("TextLabel")
		valLbl.Size = UDim2.new(1, -math.floor(6 * S), 0, math.floor(16 * S))
		valLbl.Position = UDim2.new(0, math.floor(3 * S), 0, valY)
		valLbl.BackgroundTransparency = 1
		valLbl.Text = entry and boardDef.formatValue(entry.value, entry.data) or ""
		valLbl.TextColor3 = Color3.fromRGB(100, 220, 160)
		valLbl.Font = Enum.Font.GothamMedium
		valLbl.TextSize = math.floor(11 * S)
		valLbl.TextTruncate = Enum.TextTruncate.AtEnd
		valLbl.Parent = card
	end

	-- === 4TH PLACE RUNNER-UP BAR ===
	local entry4 = entries[4]
	local runnerY = podiumTop + cardH1 + math.floor(14 * S)

	-- Divider line
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -math.floor(20 * S), 0, math.floor(1 * S))
	divider.Position = UDim2.new(0, math.floor(10 * S), 0, runnerY)
	divider.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.Parent = bg

	-- "RUNNER-UP" label
	local runnerLabelH = math.floor(16 * S)
	local runnerLabel = Instance.new("TextLabel")
	runnerLabel.Size = UDim2.new(1, 0, 0, runnerLabelH)
	runnerLabel.Position = UDim2.new(0, 0, 0, runnerY + math.floor(3 * S))
	runnerLabel.BackgroundTransparency = 1
	runnerLabel.Text = "RUNNER-UP"
	runnerLabel.TextColor3 = Color3.fromRGB(100, 105, 130)
	runnerLabel.Font = Enum.Font.GothamBold
	runnerLabel.TextSize = math.floor(9 * S)
	runnerLabel.Parent = bg

	-- Runner-up row
	local rowY = runnerY + runnerLabelH + math.floor(6 * S)
	local rowH = math.floor(36 * S)

	local row4 = Instance.new("Frame")
	row4.Size = UDim2.new(1, -math.floor(16 * S), 0, rowH)
	row4.Position = UDim2.new(0, math.floor(8 * S), 0, rowY)
	row4.BackgroundColor3 = Color3.fromRGB(22, 24, 36)
	row4.BorderSizePixel = 0
	row4.Parent = bg
	Instance.new("UICorner", row4).CornerRadius = UDim.new(0, math.floor(6 * S))

	local row4Stroke = Instance.new("UIStroke")
	row4Stroke.Color = Color3.fromRGB(60, 65, 85)
	row4Stroke.Thickness = math.floor(1 * S)
	row4Stroke.Transparency = 0.6
	row4Stroke.Parent = row4

	-- #4 rank label
	local rank4Lbl = Instance.new("TextLabel")
	rank4Lbl.Size = UDim2.new(0, math.floor(28 * S), 1, 0)
	rank4Lbl.Position = UDim2.new(0, math.floor(4 * S), 0, 0)
	rank4Lbl.BackgroundTransparency = 1
	rank4Lbl.Text = "#4"
	rank4Lbl.TextColor3 = Color3.fromRGB(140, 145, 165)
	rank4Lbl.Font = Enum.Font.GothamBold
	rank4Lbl.TextSize = math.floor(13 * S)
	rank4Lbl.Parent = row4

	-- Small avatar for 4th
	local miniAvatarSz = math.floor(26 * S)
	local miniAvatarX = math.floor(32 * S)
	local miniAvatarY = math.floor((rowH - miniAvatarSz) / 2)

	local miniFrame = Instance.new("Frame")
	miniFrame.Size = UDim2.new(0, miniAvatarSz, 0, miniAvatarSz)
	miniFrame.Position = UDim2.new(0, miniAvatarX, 0, miniAvatarY)
	miniFrame.BackgroundColor3 = Color3.fromRGB(35, 37, 50)
	miniFrame.BorderSizePixel = 0
	miniFrame.Parent = row4
	Instance.new("UICorner", miniFrame).CornerRadius = UDim.new(1, 0)

	local miniImg = Instance.new("ImageLabel")
	miniImg.Size = UDim2.new(1, -2, 1, -2)
	miniImg.Position = UDim2.new(0, 1, 0, 1)
	miniImg.BackgroundTransparency = 1
	miniImg.ScaleType = Enum.ScaleType.Fit
	miniImg.Parent = miniFrame
	Instance.new("UICorner", miniImg).CornerRadius = UDim.new(1, 0)

	if entry4 and entry4.userId then
		local url = getHeadshotUrl(entry4.userId)
		if url then miniImg.Image = url end
	end

	-- 4th name
	local name4Lbl = Instance.new("TextLabel")
	name4Lbl.Size = UDim2.new(0.4, -math.floor(62 * S), 1, 0)
	name4Lbl.Position = UDim2.new(0, miniAvatarX + miniAvatarSz + math.floor(6 * S), 0, 0)
	name4Lbl.BackgroundTransparency = 1
	name4Lbl.Text = entry4 and entry4.name or "---"
	name4Lbl.TextColor3 = Color3.fromRGB(200, 202, 215)
	name4Lbl.Font = Enum.Font.GothamMedium
	name4Lbl.TextSize = math.floor(11 * S)
	name4Lbl.TextXAlignment = Enum.TextXAlignment.Left
	name4Lbl.TextTruncate = Enum.TextTruncate.AtEnd
	name4Lbl.Parent = row4

	-- 4th value
	local val4Lbl = Instance.new("TextLabel")
	val4Lbl.Size = UDim2.new(0.45, -math.floor(8 * S), 1, 0)
	val4Lbl.Position = UDim2.new(0.55, 0, 0, 0)
	val4Lbl.BackgroundTransparency = 1
	val4Lbl.Text = entry4 and boardDef.formatValue(entry4.value, entry4.data) or ""
	val4Lbl.TextColor3 = Color3.fromRGB(100, 220, 160)
	val4Lbl.Font = Enum.Font.GothamMedium
	val4Lbl.TextSize = math.floor(11 * S)
	val4Lbl.TextXAlignment = Enum.TextXAlignment.Right
	val4Lbl.Parent = row4
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
		for i = 1, math.min(REMOTE_MAX_ENTRIES, #entries) do
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

	for i = 1, math.min(REMOTE_MAX_ENTRIES, #entries) do
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
