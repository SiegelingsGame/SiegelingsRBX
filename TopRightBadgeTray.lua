-- TopRightBadgeTray.lua — ReplicatedStorage.Modules
-- Last updated: 2026-04-20 16:00
-- Single top-right HUD row: badges share one horizontal UIListLayout (right-aligned),
-- growing toward the center as more icons appear. Higher LayoutOrder = closer to the right edge.

local Players = game:GetService("Players")

local TRAY_GUI_NAME = "TopRightHudTray"
local ROW_NAME = "BadgeTrayRow"

-- Margins from viewport corner (IgnoreGuiInset = true uses full screen)
local EDGE_RIGHT_PX = 12
local EDGE_TOP_PX = 10

local TopRightBadgeTray = {}

--- Higher value = closer to the screen's right edge (after horizontal flip / right alignment).
TopRightBadgeTray.Order = {
	AchievementUnlock = 20,
	BuffFirst = 45,
	BaseUnderAttack = 170,
	ArenaWatch = 175,
	Dungeon = 180,
	BaseSummaryCrest = 190,
	ArenaCrest = 200,
	MusicMute = 210,
}

local function ensureTray(player)
	player = player or Players.LocalPlayer
	local pg = player:WaitForChild("PlayerGui")
	local tray = pg:FindFirstChild(TRAY_GUI_NAME)
	if tray then
		local root = tray:FindFirstChild("TrayRoot")
		local row = root and root:FindFirstChild(ROW_NAME)
		if row then
			return row
		end
	end

	tray = Instance.new("ScreenGui")
	tray.Name = TRAY_GUI_NAME
	tray.ResetOnSpawn = false
	tray.IgnoreGuiInset = true
	-- Below NotificationGUI (50) so RewardPopup/toasts draw above this strip.
	tray.DisplayOrder = 49
	tray.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	tray.Parent = pg

	local root = Instance.new("Frame")
	root.Name = "TrayRoot"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -EDGE_RIGHT_PX, 0, EDGE_TOP_PX)
	root.Size = UDim2.fromOffset(0, 0)
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = tray

	local row = Instance.new("Frame")
	row.Name = ROW_NAME
	row.Size = UDim2.fromOffset(0, 0)
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Name = "BadgeList"
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	return row
end

function TopRightBadgeTray.GetBadgeRow(player)
	return ensureTray(player)
end

return TopRightBadgeTray
