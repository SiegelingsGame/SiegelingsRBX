-- ArenaRocClient.client.lua — StarterPlayerScripts
-- Roc hub mirrors FriendsListClient ProfilePopupGUI (same layout as walking up to a player).
-- NPC team rows come from GameConfig.ArenaRoc + CreatureData when remotes omit data (not player DB).
-- Last updated: 2026-04-23 19:00

-- Roc trade rules (only Siegelings are capturable/tradable, so the inventory strip only ever contains
-- Siegelings — mixed offers of any count are always valid):
--   * YOUR OFFER = 0          → THEIR OFFER empty.
--   * YOUR OFFER > 0          → THEIR OFFER = "• Cacty Lv.1".
--   * YOUR OFFER contains ≥10 Cactys (anywhere in the mix) → THEIR OFFER = "• CactyJackedty Lv.1".
-- Reward is always exactly 1 creature regardless of how many are offered.
local ROC_BUILD_STAMP = "ROC build 2026-04-23 19:00 (server accepts any inventory uid)"
print("[ArenaRocClient] " .. ROC_BUILD_STAMP)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules", 30)
local GameConfig = require(Modules:WaitForChild("GameConfig", 20))
local CreatureData = require(Modules:WaitForChild("CreatureData", 20))
local MobileWindowLayout = nil
pcall(function()
	MobileWindowLayout = require(Modules:WaitForChild("MobileWindowLayout", 10))
end)

local Notify = nil
do
	local n = Modules:FindFirstChild("NotificationManager")
	if n then
		local ok, r = pcall(require, n)
		if ok then
			Notify = r
		end
	end
end

local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(26, 30, 44),
	accent = Color3.fromRGB(200, 170, 90),
	muted = Color3.fromRGB(130, 138, 158),
	white = Color3.fromRGB(240, 242, 248),
	green = Color3.fromRGB(80, 220, 120),
	blue = Color3.fromRGB(60, 140, 255),
	red = Color3.fromRGB(255, 70, 60),
	-- Match FriendsListClient trade strip / InventoryUIManager favorite highlight
	favorite = Color3.fromRGB(255, 200, 50),
}

-- Match FriendsListClient `TradeGUI` inventory strip background
local TRADE_INV_STRIP_BG = Color3.fromRGB(18, 20, 30)
local TRADE_ROW_OFFER_BG = Color3.fromRGB(25, 45, 30)

local function clientIsSiegelingSpecies(creatureId)
	if type(creatureId) ~= "string" or creatureId == "" then
		return false
	end
	local id = string.lower(creatureId)
	if id == "pylook" then
		return true
	end
	if string.find(id, "siegeling", 1, true) ~= nil or string.find(id, "siegling", 1, true) ~= nil then
		return true
	end
	local info = CreatureData.GetById(creatureId)
	if not info then
		return false
	end
	local dn = string.lower(tostring(info.displayName or ""))
	return string.find(dn, "siegeling", 1, true) ~= nil
end

local function enrichTradeRow(row)
	if type(row) ~= "table" then
		return row
	end
	if row.isSiegeling == nil then
		row.isSiegeling = clientIsSiegelingSpecies(tostring(row.id or ""))
	end
	row.isFavorite = row.isFavorite == true
	return row
end

task.defer(function()
	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 120)
	if not eventsFolder then
		warn("[ArenaRoc] Events folder not found; Roc UI disabled")
		return
	end

	local function w(name, timeout)
		return eventsFolder:WaitForChild(name, timeout or 45)
	end

	local rocOpenHub = w("RocOpenHub")
	local rocHubRelease = w("RocHubRelease")
	local rocHubBattle = w("RocHubRequestBattle")
	local getTradeInvFn = w("GetRocTradeInventory")
	local submitFn = w("SubmitRocTrade")
	local requestNpcBattle = w("RequestRocNpcBattle", 20)

	if not rocOpenHub or not getTradeInvFn or not submitFn or not rocHubRelease or not rocHubBattle then
		warn("[ArenaRoc] Missing Roc remotes; hub disabled until server provides Events.")
		return
	end

	local hubGui
	local hubView
	local tradeView
	local tradeScroll -- inventory strip (FriendsList TradeGUI pattern)
	local tradeListLayout -- UIListLayout under tradeScroll
	local rocMyOfferScroll
	local rocTheirOfferScroll
	local rocMyOfferTitle
	local rocTheirOfferTitle
	local lastHubPayload
	local lastTradeInventory = {}
	local selected = {}
	local busy = false

	local function findTradeRow(uid)
		local su = tostring(uid or "")
		for _, x in ipairs(lastTradeInventory) do
			if tostring(x.uid) == su then
				return x
			end
		end
		return nil
	end

	local function countSelectedCacty()
		local n = 0
		for uid in pairs(selected) do
			local r = findTradeRow(uid)
			if r and string.lower(tostring(r.id or "")) == "cacty" then
				n += 1
			end
		end
		return n
	end

	local function refreshTradeScrollCanvasFromLayout()
		if not tradeScroll or not tradeScroll.Parent or not tradeListLayout then
			return
		end
		if tradeScroll.AutomaticCanvasSize ~= Enum.AutomaticSize.None then
			return
		end
		local h = tradeListLayout.AbsoluteContentSize.Y + 16
		tradeScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(h, 80))
	end

	local function toast(msg, color)
		if Notify and Notify.Toast then
			Notify.Toast(msg, color or C.white, 3.5)
		end
	end

	local function releaseHubLock()
		if rocHubRelease then
			rocHubRelease:FireServer()
		end
	end

	-- Tear down UI only. Do NOT RocHubRelease — opening the hub always calls this first; releasing here
	-- would clear the server hub lock immediately after ProximityPrompt granted it (trade/PvP then fail).
	local function destroyHubGui()
		selected = {}
		busy = false
		lastHubPayload = nil
		if hubGui then
			hubGui:Destroy()
			hubGui = nil
		end
		hubView = nil
		tradeView = nil
		tradeScroll = nil
		tradeListLayout = nil
		rocMyOfferScroll = nil
		rocTheirOfferScroll = nil
		rocMyOfferTitle = nil
		rocTheirOfferTitle = nil
		if MobileWindowLayout and MobileWindowLayout.NotifyMenuClosed then
			pcall(function()
				MobileWindowLayout.NotifyMenuClosed()
			end)
		end
	end

	local function closeAll()
		destroyHubGui()
		releaseHubLock()
	end

	-- FriendsListClient TradeGUI: "Your Offer" / "Their Offer" column text (no extra "random" copy).
	local function refreshRocOfferPanels()
		local nSel = 0
		for _ in pairs(selected) do
			nSel += 1
		end
		if rocMyOfferTitle then
			rocMyOfferTitle.Text = "YOUR OFFER (" .. tostring(nSel) .. ")"
		end

		if not rocMyOfferScroll or not rocTheirOfferScroll then
			return
		end

		for _, ch in ipairs(rocMyOfferScroll:GetChildren()) do
			if ch:IsA("TextLabel") then
				ch:Destroy()
			end
		end
		for _, ch in ipairs(rocTheirOfferScroll:GetChildren()) do
			if ch:IsA("TextLabel") then
				ch:Destroy()
			end
		end

		local function addOfferLine(parent, txt, clr)
			local l = Instance.new("TextLabel")
			l.Size = UDim2.new(1, -8, 0, 20)
			l.BackgroundTransparency = 1
			l.Text = txt
			l.TextColor3 = clr or C.white
			l.Font = Enum.Font.GothamMedium
			l.TextSize = 10
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.ZIndex = 27
			l.Parent = parent
		end

		-- Count Cactys inside the offer. We don't categorize further: every tradable creature is a
		-- Siegeling, so the only decision is whether the mix crosses the 10-Cacty CactyJackedty threshold.
		local nCacty = 0
		for uid in pairs(selected) do
			local r = findTradeRow(uid)
			if r then
				local cr = CreatureData.GetById(r.id)
				local nm = (cr and cr.displayName) or tostring(r.id)
				local line = "• " .. nm .. " Lv." .. tostring(r.level or 1)
				if r.isFavorite then
					line = line .. " ★"
				end
				addOfferLine(rocMyOfferScroll, line, r.isFavorite and C.favorite or C.white)

				if string.lower(tostring(r.id or "")) == "cacty" then
					nCacty += 1
				end
			end
		end
		if nSel == 0 then
			addOfferLine(rocMyOfferScroll, "Tap inventory above to add to your offer.", C.muted)
		end

		-- THEIR OFFER refreshes on the same click that drives YOUR OFFER:
		--   * nSel == 0            → empty (Roc pulls his offer back too)
		--   * nCacty >= 10         → CactyJackedty (check this first so 10+ never shows plain Cacty)
		--   * nSel > 0             → plain Cacty
		if nSel > 0 then
			if nCacty >= 10 then
				local jack = CreatureData.GetById("cactyjackedty")
				local jackNm = (jack and jack.displayName) or "CactyJackedty"
				addOfferLine(rocTheirOfferScroll, "• " .. jackNm .. " Lv.1", C.white)
			else
				addOfferLine(rocTheirOfferScroll, "• Cacty Lv.1", C.white)
			end
		end

		local function sizeOfferScroll(sf)
			local lay = sf:FindFirstChildOfClass("UIListLayout")
			if lay then
				pcall(function()
					lay:ApplyLayout()
				end)
				sf.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 6)
			end
		end
		sizeOfferScroll(rocMyOfferScroll)
		sizeOfferScroll(rocTheirOfferScroll)
	end

	local function clearTradeScroll()
		if not tradeScroll then
			return
		end
		for _, ch in ipairs(tradeScroll:GetChildren()) do
			if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
				ch:Destroy()
			end
		end
	end

	-- Unicode "✕" often renders blank on some devices/fonts; keep the hitbox obvious.
	local function styleRocCloseButton(btn, z)
		if not btn then
			return
		end
		btn.ZIndex = z or 100
		btn.AutoButtonColor = true
		btn.Text = "X"
		btn.TextSize = 14
		btn.Font = Enum.Font.GothamBold
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.BackgroundColor3 = Color3.fromRGB(200, 55, 50)
		btn.BackgroundTransparency = 0.15
		local s = btn:FindFirstChildOfClass("UIStroke")
		if not s then
			s = Instance.new("UIStroke")
			s.Parent = btn
		end
		s.Thickness = 1
		s.Color = Color3.fromRGB(255, 255, 255)
		s.Transparency = 0.35
	end

	-- FriendsListClient TradeGUI inventory strip layout: dark strip, compact rows, element orb + name (Lv.n) + ★ favorite.
	local function rebuildRocTradeInventoryUI(rows)
		clearTradeScroll()
		if not tradeScroll then
			return
		end

		lastTradeInventory = rows
		local layoutOrder = 0
		local function nextOrder()
			layoutOrder += 1
			return layoutOrder
		end

		local function addP2pStyleRow(row)
			local uid = tostring(row.uid or "")
			if uid == "" then
				return
			end

			local cr = CreatureData.GetById(row.id)
			local rowF = Instance.new("TextButton")
			rowF.Name = "TradeInvRow"
			rowF.Text = ""
			rowF.AutoButtonColor = false
			rowF.Size = UDim2.new(1, -6, 0, 28)
			rowF.BorderSizePixel = 0
			rowF.LayoutOrder = nextOrder()
			rowF.ZIndex = 26
			rowF.Parent = tradeScroll
			Instance.new("UICorner", rowF).CornerRadius = UDim.new(0, 6)

			local sel = selected[uid] == true
			rowF.BackgroundColor3 = sel and TRADE_ROW_OFFER_BG or C.card

			local orb = Instance.new("Frame")
			orb.Name = "Orb"
			orb.Size = UDim2.new(0, 18, 0, 18)
			orb.Position = UDim2.new(0, 6, 0.5, -9)
			orb.BackgroundColor3 = (cr and cr.primaryColor) or Color3.fromRGB(80, 80, 90)
			orb.BorderSizePixel = 0
			orb.ZIndex = 27
			orb.Parent = rowF
			Instance.new("UICorner", orb).CornerRadius = UDim.new(1, 0)

			local lvl = tonumber(row.level) or 1
			local disp = tostring(row.displayName or row.id or "?")
			local nameLbl = Instance.new("TextLabel")
			nameLbl.BackgroundTransparency = 1
			nameLbl.Size = UDim2.new(1, -32, 1, 0)
			nameLbl.Position = UDim2.new(0, 28, 0, 0)
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 11
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.TextColor3 = row.isFavorite and C.favorite or C.white
			nameLbl.Text = disp .. " (Lv." .. tostring(lvl) .. ")" .. (row.isFavorite and " ★" or "")
			nameLbl.ZIndex = 27
			nameLbl.Parent = rowF

			rowF.MouseButton1Click:Connect(function()
				-- Plain toggle. Only Siegelings reach this UI (non-Siegelings are uncapturable), so
				-- there is no category mutex — any mix up to the full inventory is allowed.
				if selected[uid] then
					selected[uid] = nil
				else
					selected[uid] = true
				end
				rebuildRocTradeInventoryUI(lastTradeInventory)
			end)
		end

		for _, row in ipairs(rows) do
			enrichTradeRow(row)
		end

		local sieg, cacty, other = {}, {}, {}
		for _, row in ipairs(rows) do
			local idl = string.lower(tostring(row.id or ""))
			if row.isSiegeling then
				table.insert(sieg, row)
			elseif idl == "cacty" then
				table.insert(cacty, row)
			else
				table.insert(other, row)
			end
		end

		local ordered = {}
		for _, row in ipairs(sieg) do
			table.insert(ordered, row)
		end
		for _, row in ipairs(other) do
			table.insert(ordered, row)
		end
		for _, row in ipairs(cacty) do
			table.insert(ordered, row)
		end

		for _, row in ipairs(ordered) do
			addP2pStyleRow(row)
		end

		if tradeListLayout then
			pcall(function()
				tradeListLayout:ApplyLayout()
			end)
		end
		task.defer(refreshTradeScrollCanvasFromLayout)
		refreshRocOfferPanels()
	end

	local function openTradePanel()
		if not tradeView or not hubView or not lastHubPayload then
			return
		end
		selected = {}
		refreshRocOfferPanels()
		local invOk, rowsOrErr = pcall(function()
			return getTradeInvFn:InvokeServer()
		end)
		if not invOk then
			warn("[ArenaRoc] GetRocTradeInventory failed: " .. tostring(rowsOrErr))
			toast("Could not reach trade server — try again.", Color3.fromRGB(255, 120, 100))
			return
		end
		local rows = rowsOrErr
		if type(rows) ~= "table" then
			rows = {}
		end
		clearTradeScroll()
		if #rows == 0 then
			local empty = Instance.new("TextLabel")
			empty.BackgroundTransparency = 1
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 11
			empty.TextColor3 = C.muted
			empty.TextWrapped = true
			empty.TextXAlignment = Enum.TextXAlignment.Left
			empty.Size = UDim2.new(1, -16, 0, 0)
			empty.AutomaticSize = Enum.AutomaticSize.Y
			empty.ZIndex = 26
			empty.Text = "No tradable creatures. Close and talk to Roc again."
			empty.Parent = tradeScroll
			refreshRocOfferPanels()
		else
			rebuildRocTradeInventoryUI(rows)
		end
		hubView.Visible = false
		tradeView.Visible = true
	end

	local function backToHub()
		selected = {}
		clearTradeScroll()
		if tradeView then
			tradeView.Visible = false
		end
		if hubView then
			hubView.Visible = true
		end
		refreshRocOfferPanels()
	end

	local function normalizeRocInventory(inv)
		local list = {}
		if type(inv) ~= "table" then
			return list
		end
		for _, row in ipairs(inv) do
			if type(row) == "table" and (row.displayName or row.id) then
				table.insert(list, row)
			end
		end
		if #list == 0 then
			for _, row in pairs(inv) do
				if type(row) == "table" and (row.displayName or row.id) then
					table.insert(list, row)
				end
			end
		end
		table.sort(list, function(a, b)
			return (tonumber(a.sortOrder) or 999) < (tonumber(b.sortOrder) or 999)
		end)
		return list
	end

	local function buildFallbackTeamRows()
		local out = {}
		local gc = GameConfig and GameConfig.ArenaRoc
		if not gc or not gc.DisplayTeam or not CreatureData then
			return out
		end
		local opLvl = tonumber(gc.OpponentLevel) or 25
		for i, s in ipairs(gc.DisplayTeam) do
			if type(s) == "table" then
				local id = s.creatureId or s.id
				if type(id) == "string" and id ~= "" then
					local cInf = CreatureData.GetById(id)
					local level = tonumber(s.level)
					if not level or level < 1 then
						if string.find(string.lower(id), "jacked", 1, true) then
							level = opLvl
						else
							level = 1
						end
					end
					local lineDetail
					if cInf then
						lineDetail = (cInf.element or "?")
							.. " "
							.. (cInf.class or "")
							.. "  ·  "
							.. tostring(cInf.rarity or "Common")
						if cInf.health and cInf.attack and cInf.defense and cInf.speed then
							lineDetail = lineDetail
								.. "  ·  HP"
								.. tostring(cInf.health)
								.. " / ATK"
								.. tostring(cInf.attack)
								.. " / DEF"
								.. tostring(cInf.defense)
								.. " / SPD"
								.. tostring(cInf.speed)
						end
					end
					table.insert(out, {
						sortOrder = tonumber(s.sortOrder) or i,
						id = id,
						displayName = s.displayName or (cInf and cInf.displayName) or id,
						level = level,
						note = tostring(s.note or ""),
						baseIncome = s.baseIncome or (cInf and cInf.baseIncome),
						lineDetail = lineDetail,
					})
				end
			end
		end
		table.sort(out, function(a, b)
			return (tonumber(a.sortOrder) or 0) < (tonumber(b.sortOrder) or 0)
		end)
		return out
	end

	local function getRocTeamList(payload)
		local list = normalizeRocInventory((payload and payload.rocInventory) or {})
		if #list > 0 then
			return list
		end
		return buildFallbackTeamRows()
	end

	local function showRocHub(payload)
		-- Build UI in a protected block. If anything errors (streaming, layout helpers, bad payload),
		-- don’t leave a blank, dead window on screen.
		destroyHubGui()
		lastHubPayload = payload

		local ok, err = pcall(function()
			-- FriendsListClient ProfilePopupGUI palette + geometry (360×440, footer TRADE / PvP 1v1).
			local PR = {
			bg = Color3.fromRGB(14, 16, 24),
			card = Color3.fromRGB(22, 26, 38),
			blue = Color3.fromRGB(60, 140, 255),
			green = Color3.fromRGB(80, 220, 120),
			red = Color3.fromRGB(255, 70, 60),
			muted = Color3.fromRGB(120, 125, 140),
			white = Color3.new(1, 1, 1),
			pvpTxt = Color3.fromRGB(255, 100, 80),
			tradeBg = Color3.fromRGB(30, 70, 45),
			pvpBg = Color3.fromRGB(70, 30, 30),
			}
			local POP_W, POP_H = 360, 440

			local st = (type(payload) == "table" and payload.stats) or {}
			local statsLine = string.format(
				"Roc record (global): %d wins · %d losses",
				tonumber(st.npcWins) or 0,
				tonumber(st.npcLosses) or 0
			)

		hubGui = Instance.new("ScreenGui")
		hubGui.Name = "RocHubGui"
		hubGui.ResetOnSpawn = false
		hubGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
		hubGui.DisplayOrder = 101
		hubGui.Parent = playerGui

		local root = Instance.new("Frame")
		root.Name = "Root"
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.new(0.5, 0, 0.5, 0)
		root.Size = UDim2.new(0, POP_W, 0, POP_H)
		root.BackgroundColor3 = PR.bg
		root.BackgroundTransparency = 0.03
		root.BorderSizePixel = 0
		root.Active = true
		pcall(function()
			root.Draggable = true
		end)
		root.Parent = hubGui
		Instance.new("UICorner", root).CornerRadius = UDim.new(0, 14)
		local stroke = Instance.new("UIStroke")
		stroke.Color = PR.blue
		stroke.Thickness = 1
		stroke.Parent = root

		hubView = Instance.new("Frame")
		hubView.Name = "RocHubLayer"
		hubView.BackgroundTransparency = 1
		hubView.Size = UDim2.new(1, 0, 1, 0)
		hubView.ZIndex = 1
		hubView.Parent = root

		local title = Instance.new("TextLabel")
		title.ZIndex = 25
		title.Size = UDim2.new(1, -44, 0, 32)
		title.Position = UDim2.new(0, 12, 0, 6)
		title.BackgroundTransparency = 1
		title.Text = "Roc"
		title.TextColor3 = PR.white
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 14
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = hubView
			if MobileWindowLayout and MobileWindowLayout.MenuHeaderTitleLayout then
				pcall(function()
					MobileWindowLayout.MenuHeaderTitleLayout(title, {
						Position = UDim2.new(0, 12, 0, 6),
						Size = UDim2.new(1, -44, 0, 32),
						TextXAlignment = Enum.TextXAlignment.Left,
					})
				end)
			end

		local closeX = Instance.new("TextButton")
		closeX.Size = UDim2.new(0, 30, 0, 30)
		closeX.Position = UDim2.new(1, -38, 0, 4)
		closeX.BorderSizePixel = 0
		closeX.Parent = hubView
		Instance.new("UICorner", closeX).CornerRadius = UDim.new(0, 6)
		styleRocCloseButton(closeX, 50)
		closeX.MouseButton1Click:Connect(closeAll)

		local rocScroll = Instance.new("ScrollingFrame")
		rocScroll.Name = "RocHubScroll"
		rocScroll.Size = UDim2.new(1, -20, 1, -98)
		rocScroll.Position = UDim2.new(0, 10, 0, 42)
		rocScroll.BackgroundTransparency = 1
		rocScroll.BorderSizePixel = 0
		rocScroll.ScrollBarThickness = 4
		rocScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		-- Do not combine deferred manual CanvasSize updates with AutomaticCanvasSize (can error or fight).
		local okAuto = pcall(function()
			rocScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		end)
		if not okAuto then
			rocScroll.CanvasSize = UDim2.new(0, 0, 0, 2000)
		end
		rocScroll.ZIndex = 1
		rocScroll.Parent = hubView
		local rl = Instance.new("UIListLayout")
		rl.Padding = UDim.new(0, 6)
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Parent = rocScroll

		local order = 0

		local greetLbl = Instance.new("TextLabel")
		greetLbl.Size = UDim2.new(1, -8, 0, 0)
		greetLbl.AutomaticSize = Enum.AutomaticSize.Y
		greetLbl.BackgroundTransparency = 1
		greetLbl.Text = tostring(payload.greeting or "")
		greetLbl.TextColor3 = PR.muted
		greetLbl.Font = Enum.Font.GothamMedium
		greetLbl.TextSize = 11
		greetLbl.TextWrapped = true
		greetLbl.TextXAlignment = Enum.TextXAlignment.Left
		greetLbl.LayoutOrder = order
		greetLbl.Parent = rocScroll
		order += 1

		local statCard = Instance.new("TextLabel")
		statCard.Size = UDim2.new(1, -8, 0, 0)
		statCard.AutomaticSize = Enum.AutomaticSize.Y
		statCard.BackgroundColor3 = PR.card
		statCard.BorderSizePixel = 0
		statCard.Text = statsLine
		statCard.TextColor3 = PR.white
		statCard.Font = Enum.Font.GothamMedium
		statCard.TextSize = 11
		statCard.TextXAlignment = Enum.TextXAlignment.Left
		statCard.TextWrapped = true
		statCard.LayoutOrder = order
		statCard.Parent = rocScroll
		Instance.new("UICorner", statCard).CornerRadius = UDim.new(0, 8)
		do
			local pad = Instance.new("UIPadding", statCard)
			pad.PaddingLeft = UDim.new(0, 8)
			pad.PaddingRight = UDim.new(0, 8)
			pad.PaddingTop = UDim.new(0, 6)
			pad.PaddingBottom = UDim.new(0, 6)
		end
		order += 1

		local secTeam = Instance.new("TextLabel")
		secTeam.Size = UDim2.new(1, -8, 0, 18)
		secTeam.BackgroundTransparency = 1
		secTeam.Text = "ROC'S TEAM (NPC — config + CreatureData)"
		secTeam.TextColor3 = PR.muted
		secTeam.Font = Enum.Font.GothamBold
		secTeam.TextSize = 11
		secTeam.TextXAlignment = Enum.TextXAlignment.Left
		secTeam.LayoutOrder = order
		secTeam.Parent = rocScroll
		order += 1

			local teamRows = getRocTeamList(payload)
		for _, row in ipairs(teamRows) do
			local idKey = (type(row) == "table" and row.id) and tostring(row.id) or ""
			local cInf = idKey ~= "" and CreatureData.GetById(idKey) or nil
			local favRow = Instance.new("Frame")
			local rowH = 52
			if row.baseIncome ~= nil and tonumber(row.baseIncome) then
				rowH = 64
			end
			favRow.Size = UDim2.new(1, 0, 0, rowH)
			favRow.BackgroundColor3 = PR.card
			favRow.BorderSizePixel = 0
			favRow.LayoutOrder = order
			favRow.Parent = rocScroll
			Instance.new("UICorner", favRow).CornerRadius = UDim.new(0, 8)
			order += 1

			local orb = Instance.new("Frame")
			orb.Size = UDim2.new(0, 40, 0, 40)
			orb.Position = UDim2.new(0, 8, 0, 8)
			orb.BackgroundColor3 = (cInf and cInf.primaryColor) or Color3.fromRGB(80, 80, 90)
			orb.BorderSizePixel = 0
			orb.Parent = favRow
			Instance.new("UICorner", orb).CornerRadius = UDim.new(1, 0)
			local orbStroke = Instance.new("UIStroke", orb)
			orbStroke.Transparency = 0.3
			local rar = cInf and cInf.rarity or "Common"
			if rar == "Legendary" then
				orbStroke.Color = Color3.fromRGB(255, 184, 0)
			elseif rar == "Epic" or rar == "Mythic" then
				orbStroke.Color = Color3.fromRGB(180, 80, 255)
			elseif rar == "Rare" then
				orbStroke.Color = Color3.fromRGB(60, 130, 255)
			elseif rar == "Uncommon" then
				orbStroke.Color = Color3.fromRGB(75, 200, 75)
			else
				orbStroke.Color = Color3.fromRGB(180, 180, 180)
			end

			local favName = Instance.new("TextLabel")
			favName.Size = UDim2.new(1, -60, 0, 18)
			favName.Position = UDim2.new(0, 54, 0, 8)
			favName.BackgroundTransparency = 1
			local note = (row.note and row.note ~= "") and ("  ·  " .. tostring(row.note)) or ""
			favName.Text = (row.displayName or "?") .. "  Lv." .. tostring(row.level or 1) .. note
			favName.TextColor3 = PR.white
			favName.Font = Enum.Font.GothamBlack
			favName.TextSize = 12
			favName.TextXAlignment = Enum.TextXAlignment.Left
			favName.Parent = favRow

			local detail = row.lineDetail
			if not detail and cInf and cInf.health then
				detail = string.format(
					"HP %s  ATK %s  DEF %s  SPD %s",
					tostring(cInf.health),
					tostring(cInf.attack),
					tostring(cInf.defense),
					tostring(cInf.speed)
				)
			end
			if detail then
				local statText = Instance.new("TextLabel")
				statText.Size = UDim2.new(1, -54, 0, 14)
				statText.Position = UDim2.new(0, 54, 0, 28)
				statText.BackgroundTransparency = 1
				statText.Text = detail
				statText.TextColor3 = PR.muted
				statText.Font = Enum.Font.GothamMedium
				statText.TextSize = 10
				statText.TextXAlignment = Enum.TextXAlignment.Left
				statText.Parent = favRow
			end
			if row.baseIncome ~= nil and tonumber(row.baseIncome) then
				local inc = Instance.new("TextLabel")
				inc.Size = UDim2.new(1, -54, 0, 12)
				inc.Position = UDim2.new(0, 54, 0, 46)
				inc.BackgroundTransparency = 1
				inc.Text = "≈ " .. tostring(row.baseIncome) .. " coins/min income (reference)"
				inc.TextColor3 = PR.green
				inc.Font = Enum.Font.GothamMedium
				inc.TextSize = 9
				inc.TextXAlignment = Enum.TextXAlignment.Left
				inc.Parent = favRow
			end
		end

		if #teamRows == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, -8, 0, 36)
			empty.BackgroundColor3 = PR.card
			empty.Text = "No team rows — check GameConfig.ArenaRoc.DisplayTeam."
			empty.TextColor3 = PR.muted
			empty.Font = Enum.Font.GothamMedium
			empty.TextSize = 11
			empty.TextWrapped = true
			empty.LayoutOrder = order
			empty.Parent = rocScroll
			Instance.new("UICorner", empty).CornerRadius = UDim.new(0, 8)
			order += 1
		end

			local sw = tonumber(payload.pvpStakeWin) or 10
			local sl = tonumber(payload.pvpStakeLoss) or 10
			local rng = tonumber(payload.pvpRange) or 30
		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(1, -8, 0, 0)
		hint.AutomaticSize = Enum.AutomaticSize.Y
		hint.BackgroundTransparency = 1
		hint.Text = string.format(
			"Footer PvP 1v1 = same rules as player duels (your favorite vs Roc's champion from config). Stakes: win +%d · lose -%d. Nearby players: ≤%d studs.",
			sw,
			sl,
			math.floor(rng)
		)
		hint.TextColor3 = PR.muted
		hint.Font = Enum.Font.GothamMedium
		hint.TextSize = 10
		hint.TextWrapped = true
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.LayoutOrder = order
		hint.Parent = rocScroll
		order += 1

		local nearPvpBtn = Instance.new("TextButton")
		nearPvpBtn.Size = UDim2.new(1, -8, 0, 30)
		nearPvpBtn.BackgroundColor3 = PR.card
		nearPvpBtn.BorderSizePixel = 0
		nearPvpBtn.Text = "Challenge nearest player (PvP invite)"
		nearPvpBtn.TextColor3 = PR.pvpTxt
		nearPvpBtn.Font = Enum.Font.GothamBold
		nearPvpBtn.TextSize = 10
		nearPvpBtn.LayoutOrder = order
		nearPvpBtn.Parent = rocScroll
		Instance.new("UICorner", nearPvpBtn).CornerRadius = UDim.new(0, 8)
		nearPvpBtn.MouseButton1Click:Connect(function()
			if busy or not rocHubBattle then
				return
			end
			busy = true
			rocHubBattle:FireServer()
			busy = false
		end)
		order += 1

		local function refreshRocScrollCanvas()
			if not rocScroll or not rocScroll.Parent or not rl then
				return
			end
			if rocScroll.AutomaticCanvasSize ~= Enum.AutomaticSize.None then
				return
			end
			local h = rl.AbsoluteContentSize.Y + 16
			rocScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(h, 80))
		end
		task.defer(refreshRocScrollCanvas)
		rl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshRocScrollCanvas)

		local rocFooter = Instance.new("Frame")
		rocFooter.Name = "RocFooter"
		rocFooter.Size = UDim2.new(1, -20, 0, 52)
		rocFooter.Position = UDim2.new(0, 10, 1, -56)
		rocFooter.BackgroundTransparency = 1
		rocFooter.ZIndex = 10
		rocFooter.Parent = hubView

		local tradeBtn = Instance.new("TextButton")
		tradeBtn.Size = UDim2.new(0.5, -4, 0, 36)
		tradeBtn.Position = UDim2.new(0, 0, 0, 8)
		tradeBtn.BackgroundColor3 = PR.tradeBg
		tradeBtn.Text = "TRADE"
		tradeBtn.TextColor3 = PR.green
		tradeBtn.Font = Enum.Font.GothamBlack
		tradeBtn.TextSize = 11
		tradeBtn.BorderSizePixel = 0
		tradeBtn.ZIndex = 11
		tradeBtn.Parent = rocFooter
		Instance.new("UICorner", tradeBtn).CornerRadius = UDim.new(0, 10)
		tradeBtn.MouseButton1Click:Connect(function()
			if busy then
				return
			end
			openTradePanel()
		end)

		local battleBtn = Instance.new("TextButton")
		battleBtn.Size = UDim2.new(0.5, -4, 0, 36)
		battleBtn.Position = UDim2.new(0.5, 2, 0, 8)
		battleBtn.BackgroundColor3 = PR.pvpBg
		battleBtn.Text = "PvP 1v1"
		battleBtn.TextColor3 = PR.pvpTxt
		battleBtn.Font = Enum.Font.GothamBlack
		battleBtn.TextSize = 11
		battleBtn.BorderSizePixel = 0
		battleBtn.ZIndex = 11
		battleBtn.Parent = rocFooter
		Instance.new("UICorner", battleBtn).CornerRadius = UDim.new(0, 10)
		battleBtn.MouseButton1Click:Connect(function()
			if not requestNpcBattle then
				toast("Battle unavailable — update server.", C.muted)
				return
			end
			if busy then
				return
			end
			busy = true
			local pOk, a, b = pcall(function()
				return requestNpcBattle:InvokeServer()
			end)
			busy = false
			if not pOk then
				toast(tostring(a), Color3.fromRGB(255, 120, 100))
				return
			end
			if a == true then
				closeAll()
				return
			end
			toast(tostring(b or a or "Could not start battle."), Color3.fromRGB(255, 120, 100))
		end)

			if MobileWindowLayout and MobileWindowLayout.RestoreDesktopWindow then
				pcall(function()
					MobileWindowLayout.RestoreDesktopWindow(root, { draggable = true })
				end)
			end

		-- ZIndexBehavior = Global means every descendant's ZIndex is compared against this frame.
		-- tradeView.ZIndex = 1 (same layer as hubView) — children use higher ZIndex values to layer.
		-- ZIndexBehavior = Global (set on hubGui) means every descendant competes on absolute ZIndex.
		-- Keep tradeView's backdrop transparent so children at any ZIndex are visible; `root` has its own PR.bg fill.
		tradeView = Instance.new("Frame")
		tradeView.Name = "TradeView"
		tradeView.BackgroundColor3 = PR.bg
		tradeView.BackgroundTransparency = 1
		tradeView.Visible = false
		tradeView.Size = UDim2.new(1, 0, 1, 0)
		tradeView.Position = UDim2.new(0, 0, 0, 0)
		tradeView.ZIndex = 1
		tradeView.Parent = root

		-- FriendsListClient TradeGUI-style header (matches multiplayer “TRADE (IN PROGRESS)” tone).
		local tTitle = Instance.new("TextLabel")
		tTitle.ZIndex = 25
		tTitle.BackgroundTransparency = 1
		tTitle.Font = Enum.Font.GothamBlack
		tTitle.TextSize = 13
		tTitle.TextColor3 = PR.white
		tTitle.Text = "TRADE (ROC)"
		tTitle.Size = UDim2.new(1, -44, 0, 16)
		tTitle.Position = UDim2.new(0, 12, 0, 4)
		tTitle.TextXAlignment = Enum.TextXAlignment.Left
		tTitle.Parent = tradeView

		local tBuildStamp = Instance.new("TextLabel")
		tBuildStamp.ZIndex = 25
		tBuildStamp.BackgroundTransparency = 1
		tBuildStamp.Font = Enum.Font.Gotham
		tBuildStamp.TextSize = 9
		tBuildStamp.TextColor3 = C.accent
		tBuildStamp.Text = ROC_BUILD_STAMP
		tBuildStamp.Size = UDim2.new(1, -44, 0, 12)
		tBuildStamp.Position = UDim2.new(0, 12, 0, 20)
		tBuildStamp.TextXAlignment = Enum.TextXAlignment.Left
		tBuildStamp.Parent = tradeView

		local tradeClose = Instance.new("TextButton")
		tradeClose.Size = UDim2.new(0, 30, 0, 30)
		tradeClose.Position = UDim2.new(1, -38, 0, 4)
		tradeClose.Parent = tradeView
		Instance.new("UICorner", tradeClose).CornerRadius = UDim.new(0, 6)
		styleRocCloseButton(tradeClose, 60)
		tradeClose.MouseButton1Click:Connect(backToHub)

		local partnerRow = Instance.new("TextLabel")
		partnerRow.ZIndex = 25
		partnerRow.BackgroundTransparency = 1
		partnerRow.Font = Enum.Font.GothamMedium
		partnerRow.TextSize = 11
		partnerRow.TextColor3 = PR.muted
		partnerRow.Text = "Trading with: Roc"
		partnerRow.Size = UDim2.new(1, -24, 0, 18)
		partnerRow.Position = UDim2.new(0, 12, 0, 36)
		partnerRow.TextXAlignment = Enum.TextXAlignment.Left
		partnerRow.Parent = tradeView

		local rocInvLabel = Instance.new("TextLabel")
		rocInvLabel.ZIndex = 25
		rocInvLabel.BackgroundTransparency = 1
		rocInvLabel.Font = Enum.Font.GothamMedium
		rocInvLabel.TextSize = 10
		rocInvLabel.TextColor3 = PR.muted
		rocInvLabel.Text = "Your inventory (tap to add / remove from your offer)"
		rocInvLabel.Size = UDim2.new(1, -24, 0, 14)
		rocInvLabel.Position = UDim2.new(0, 12, 0, 56)
		rocInvLabel.TextXAlignment = Enum.TextXAlignment.Left
		rocInvLabel.Parent = tradeView

		tradeScroll = Instance.new("ScrollingFrame")
		tradeScroll.Name = "RocTradeInvStrip"
		tradeScroll.BackgroundColor3 = TRADE_INV_STRIP_BG
		tradeScroll.BorderSizePixel = 0
		tradeScroll.Size = UDim2.new(1, -24, 0, 56)
		tradeScroll.Position = UDim2.new(0, 12, 0, 72)
		tradeScroll.ScrollBarThickness = 4
		tradeScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		tradeScroll.ZIndex = 25
		tradeScroll.ClipsDescendants = true
		do
			local okTradeAuto = pcall(function()
				tradeScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
			end)
			if not okTradeAuto then
				tradeScroll.CanvasSize = UDim2.new(0, 0, 0, 2000)
			end
		end
		tradeScroll.Parent = tradeView
		Instance.new("UICorner", tradeScroll).CornerRadius = UDim.new(0, 10)
		local tl = Instance.new("UIListLayout")
		tl.Padding = UDim.new(0, 2)
		tl.SortOrder = Enum.SortOrder.LayoutOrder
		tl.Parent = tradeScroll
		tradeListLayout = tl
		do
			local tradePad = Instance.new("UIPadding", tradeScroll)
			local px = UDim.new(0, 6)
			tradePad.PaddingLeft = px
			tradePad.PaddingRight = px
			tradePad.PaddingTop = px
			tradePad.PaddingBottom = px
		end

		task.defer(refreshTradeScrollCanvasFromLayout)
		tl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(refreshTradeScrollCanvasFromLayout)

		local rocMyOfferFrame = Instance.new("Frame")
		rocMyOfferFrame.Name = "YourOffer"
		rocMyOfferFrame.BackgroundTransparency = 1
		rocMyOfferFrame.Size = UDim2.new(0.5, -14, 1, -178)
		rocMyOfferFrame.Position = UDim2.new(0, 12, 0, 132)
		rocMyOfferFrame.ZIndex = 25
		rocMyOfferFrame.Parent = tradeView

		rocMyOfferTitle = Instance.new("TextLabel")
		rocMyOfferTitle.BackgroundTransparency = 1
		rocMyOfferTitle.Size = UDim2.new(1, -8, 0, 20)
		rocMyOfferTitle.Font = Enum.Font.GothamBold
		rocMyOfferTitle.TextSize = 12
		rocMyOfferTitle.TextColor3 = C.green
		rocMyOfferTitle.TextXAlignment = Enum.TextXAlignment.Left
		rocMyOfferTitle.Text = "YOUR OFFER (0)"
		rocMyOfferTitle.ZIndex = 26
		rocMyOfferTitle.Parent = rocMyOfferFrame

		rocMyOfferScroll = Instance.new("ScrollingFrame")
		rocMyOfferScroll.Name = "YourOfferScroll"
		rocMyOfferScroll.BackgroundColor3 = TRADE_INV_STRIP_BG
		rocMyOfferScroll.BorderSizePixel = 0
		rocMyOfferScroll.Size = UDim2.new(1, 0, 1, -24)
		rocMyOfferScroll.Position = UDim2.new(0, 0, 0, 22)
		rocMyOfferScroll.ScrollBarThickness = 3
		rocMyOfferScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		rocMyOfferScroll.ZIndex = 26
		rocMyOfferScroll.Parent = rocMyOfferFrame
		Instance.new("UICorner", rocMyOfferScroll).CornerRadius = UDim.new(0, 10)
		local myOL = Instance.new("UIListLayout")
		myOL.Padding = UDim.new(0, 2)
		myOL.Parent = rocMyOfferScroll

		local rocTheirFrame = Instance.new("Frame")
		rocTheirFrame.Name = "TheirOffer"
		rocTheirFrame.BackgroundTransparency = 1
		rocTheirFrame.Size = UDim2.new(0.5, -14, 1, -178)
		rocTheirFrame.Position = UDim2.new(0.5, 2, 0, 132)
		rocTheirFrame.ZIndex = 25
		rocTheirFrame.Parent = tradeView

		rocTheirOfferTitle = Instance.new("TextLabel")
		rocTheirOfferTitle.BackgroundTransparency = 1
		rocTheirOfferTitle.Size = UDim2.new(1, -8, 0, 20)
		rocTheirOfferTitle.Font = Enum.Font.GothamBold
		rocTheirOfferTitle.TextSize = 12
		rocTheirOfferTitle.TextColor3 = C.blue
		rocTheirOfferTitle.TextXAlignment = Enum.TextXAlignment.Left
		rocTheirOfferTitle.Text = "THEIR OFFER"
		rocTheirOfferTitle.ZIndex = 26
		rocTheirOfferTitle.Parent = rocTheirFrame

		rocTheirOfferScroll = Instance.new("ScrollingFrame")
		rocTheirOfferScroll.Name = "TheirOfferScroll"
		rocTheirOfferScroll.BackgroundColor3 = TRADE_INV_STRIP_BG
		rocTheirOfferScroll.BorderSizePixel = 0
		rocTheirOfferScroll.Size = UDim2.new(1, 0, 1, -24)
		rocTheirOfferScroll.Position = UDim2.new(0, 0, 0, 22)
		rocTheirOfferScroll.ScrollBarThickness = 3
		rocTheirOfferScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		rocTheirOfferScroll.ZIndex = 26
		rocTheirOfferScroll.Parent = rocTheirFrame
		Instance.new("UICorner", rocTheirOfferScroll).CornerRadius = UDim.new(0, 10)
		local thOL = Instance.new("UIListLayout")
		thOL.Padding = UDim.new(0, 2)
		thOL.Parent = rocTheirOfferScroll

		local acceptBtn = Instance.new("TextButton")
		acceptBtn.ZIndex = 28
		acceptBtn.Text = "ACCEPT"
		acceptBtn.Font = Enum.Font.GothamBlack
		acceptBtn.TextSize = 12
		acceptBtn.TextColor3 = C.green
		acceptBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
		acceptBtn.Size = UDim2.new(0.5, -14, 0, 34)
		acceptBtn.Position = UDim2.new(0, 12, 1, -40)
		acceptBtn.BorderSizePixel = 0
		acceptBtn.Parent = tradeView
		Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 10)
		acceptBtn.MouseButton1Click:Connect(function()
			if busy then
				return
			end
			local arr = {}
			for uid in pairs(selected) do
				table.insert(arr, uid)
			end
			if #arr == 0 then
				toast("Add creatures to your offer.", C.muted)
				return
			end
			busy = true
			local invokeOk, tOk, msg = pcall(function()
				return submitFn:InvokeServer(arr)
			end)
			busy = false
			if not invokeOk then
				toast(tostring(tOk), Color3.fromRGB(255, 120, 100))
				return
			end
			if tOk then
				toast(msg or "Trade complete!", C.green)
				backToHub()
			else
				toast(tostring(msg or "Trade failed."), Color3.fromRGB(255, 120, 100))
			end
		end)

		local cancelTradeBtn = Instance.new("TextButton")
		cancelTradeBtn.ZIndex = 28
		cancelTradeBtn.Text = "CANCEL"
		cancelTradeBtn.Font = Enum.Font.GothamBlack
		cancelTradeBtn.TextSize = 12
		cancelTradeBtn.TextColor3 = C.red
		cancelTradeBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
		cancelTradeBtn.Size = UDim2.new(0.5, -14, 0, 34)
		cancelTradeBtn.Position = UDim2.new(0.5, 2, 1, -40)
		cancelTradeBtn.BorderSizePixel = 0
		cancelTradeBtn.Parent = tradeView
		Instance.new("UICorner", cancelTradeBtn).CornerRadius = UDim.new(0, 10)
		cancelTradeBtn.MouseButton1Click:Connect(backToHub)

			if MobileWindowLayout and MobileWindowLayout.SyncNpcMenuScreenGui then
				pcall(function()
					MobileWindowLayout.SyncNpcMenuScreenGui(hubGui, POP_W, POP_H)
				end)
			end
		end)

		if not ok then
			local es = tostring(err)
			warn("[ArenaRoc] showRocHub failed: " .. es)
			destroyHubGui()
			local short = es
			if #short > 160 then
				short = string.sub(short, 1, 157) .. "..."
			end
			toast("Roc menu failed: " .. short, Color3.fromRGB(255, 120, 100))
		end
	end

	rocOpenHub.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if busy then
			return
		end
		showRocHub(payload)
	end)
end)
