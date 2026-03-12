--[[
  Base Build Instructions: Haunted House
  =====================================
  Script for the base agent: build a custom base with a HAUNTED HOUSE theme
  while respecting the BasePlacementSystem structure contract.

  Usage: Require this module or read this file to get the contract + theme spec.
  The agent must produce a Plot model (Plot1, Plot2, etc.) that satisfies
  the contract and follows the haunted house aesthetic below.
]]

local Instructions = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 1: BASE STRUCTURE CONTRACT (MANDATORY)
-- ═══════════════════════════════════════════════════════════════════════════
-- All custom bases MUST preserve this structure or placement/visibility will break.

Instructions.StructureContract = {
	Description = "Required hierarchy and naming for compatibility with BasePlacementSystem. Do not reparent or rename; discovery uses GetDescendants + name match.",

	-- 1) Floor folders
	Floors = {
		"Floor1",  -- Ground floor (always visible)
		"Floor2",  -- Second floor (hidden until purchased; must exist)
		"Floor3",  -- Third floor (hidden until purchased; must exist)
	},
	FloorRules = {
		"Floor2 and Floor3 may be hidden until purchased; do not reparent or rename.",
		"Stairs (or equivalent) must live INSIDE Floor2 and INSIDE Floor3 for player access.",
		"setFloorVisibility toggles visibility/collision only; do not remove Stairs.",
	},

	-- 2) Point naming and location
	Points = {
		DefensePoints = {
			{ names = "DefensePoint1 .. DefensePoint6",  floor = "Floor1" },
			{ names = "DefensePoint7 .. DefensePoint12", floor = "Floor2" },
			{ names = "DefensePoint13 .. DefensePoint18", floor = "Floor3" },
		},
		IncomePoints = {
			{ names = "IncomePoint1 .. IncomePoint6",  floor = "Floor1" },
			{ names = "IncomePoint7 .. IncomePoint12", floor = "Floor2" },
			{ names = "IncomePoint13 .. IncomePoint18", floor = "Floor3" },
		},
		BattlePoints = {
			{ names = "BattlePoint1 .. BattlePoint9", floor = "Floor2", folder = "BattleTeam (inside Floor2)" },
		},
	},
	PointRules = {
		"Each point must be a BasePart. Names must match exactly (e.g. DefensePoint1, IncomePoint7, BattlePoint3).",
		"Points can live in subfolders (e.g. Floor1/DefensePoints/DefensePoint1); GetDescendants finds them.",
		"BattleTeam folder must be INSIDE Floor2. There is no separate setBattleTeamVisibility.",
	},

	-- 3) Required plot-level children
	PlotRequiredChildren = {
		"PlotCenter",  -- Used for steal-home radius / plot center logic
		"SignPart",    -- Optional but expected by some UI/placement logic
	},

	-- 4) Anchoring and glass
	Anchoring = "Point parts and floor structure parts are anchored in code when visibility is set; custom bases should keep parts anchored to avoid fall-through.",
	GlassRule = "Parts that should stay transparent: Name contains 'Glass' OR attribute IsGlass = true.",
}

-- Expected hierarchy summary (for quick reference)
Instructions.ExpectedHierarchy = [[
  Plot1/  (or Part1, Plot2, etc. under Plots folder)
    Floor1/
      DefensePoints/  DefensePoint1..6
      IncomePoints/   IncomePoint1..6
    Floor2/
      BattleTeam/     BattlePoint1..9
      DefensePoints/  DefensePoint7..12
      IncomePoints/   IncomePoint7..12
      Stairs
      [Glass parts: name "Glass" or IsGlass = true]
    Floor3/
      DefensePoints/  DefensePoint13..18
      IncomePoints/   IncomePoint13..18
      Stairs
    PlotCenter
    SignPart
]]

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2: HAUNTED HOUSE THEME (AESTHETIC DIRECTIVE)
-- ═══════════════════════════════════════════════════════════════════════════

Instructions.Theme = "HauntedHouse"

Instructions.ThemeBrief = "A spooky, classic haunted mansion: dark, aged, slightly crooked, with gothic and Victorian cues. Must still respect the structure contract above."

Instructions.HauntedHouseSpec = {
	-- Mood and setting
	Mood = {
		"Spooky but readable: players need to see Defense/Income/Battle points and navigate stairs.",
		"Dark palette with deep purples, blacks, grays, desaturated greens; avoid full black so UI and orbs stay visible.",
		"Creepy but not gory; family-friendly haunted house.",
	},

	-- Architecture
	Architecture = {
		"House shape: tall, multi-floor mansion (2–3 floors). Asymmetric or slightly crooked silhouette is encouraged.",
		"Roof: steep gothic/Victorian peaks, broken tiles or weathered shingles; optional small towers or spires.",
		"Walls: aged wood, dark brick, or stone; cracked or vine-covered sections fit the theme.",
		"Windows: arched or rectangular, with window frames; use Glass parts (name contains 'Glass' or IsGlass = true) for transparency where appropriate.",
		"Stairs: interior stairs for Floor2 and Floor3; can look like old wooden or stone steps, spiral optional.",
	},

	-- Materials and colors
	Materials = {
		Brick = "Dark grays, dark reds, or charcoal; optionally use Cobblestone or cracked textures.",
		Wood = "Dark wood (e.g. Walnut, Bark) for beams, doors, trim.",
		Metal = "Tarnished or dark metal for railings, fences, gates.",
		Accents = "Deep purple, muted green, or dull gold for trim or details.",
	},

	-- Props and detail (optional, do not replace required points)
	Props = {
		"Fences: wrought-iron style around yard or balconies.",
		"Pumpkins, candles, or lanterns (non-blocking) for atmosphere.",
		"Dead trees, bare branches, or twisted trees near the plot.",
		"Sign or placard on SignPart: e.g. 'Haunted Manor', 'Beware', or player name.",
		"Doors and archways to frame entrances to each floor.",
		"Bats, ravens, or spider webs as small decorative models (low poly).",
	},

	-- Lighting
	Lighting = {
		"Dim overall; use PointLights or SpotLights in purple, green, or orange (pumpkin) tint.",
		"Candle or lantern glow near stairs and key areas so gameplay remains clear.",
		"Optional flicker on some lights (script or attribute-driven) for creepiness.",
	},

	-- Placement of points (thematic integration)
	PointIntegration = {
		"DefensePoints: on walls, balconies, or rooftop positions as 'guard posts' or turrets.",
		"IncomePoints: in courtyard, garden, or interior 'treasure' spots.",
		"BattlePoints (Floor2): in a clear arena area (e.g. ballroom, courtyard) so 9 points stay unobstructed.",
		"PlotCenter: logical center of the building or front yard; used for steal-home radius.",
	},

	-- Don'ts
	Restrictions = {
		"Do not obscure or rename DefensePoint1..18, IncomePoint1..18, or BattlePoint1..9.",
		"Do not remove or reparent Floor1, Floor2, Floor3, or Stairs inside Floor2/Floor3.",
		"Do not place point parts inside moving or animated parts that change position.",
		"Keep collision and anchoring so players and orbs don't fall through floors.",
	},
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 2.5: EXTERIOR BOUNDS (FOR UI AGENT / BASE EXTERIOR SYSTEM)
-- ═══════════════════════════════════════════════════════════════════════════
-- The backend (BaseExteriorSystem) computes bounds from Floor3 for exterior updates:
--   - Farther bound: Floor3 platform/wall extent in X and Z (size of Floor 3).
--   - Highest wall: top of Floor3 wall parts (WallFront, WallBack, WallLeft, WallRight).
--   - Decoration zone: space above highest wall for toppers/decoration (default 8 studs).
-- UI agent can call: GetExteriorBounds (invoke) → returns bounds table; RefreshExterior (fire) to update.

Instructions.ExteriorBoundsNote = {
	Source = "Floor3",
	FartherBoundXZ = "Floor 3 size (halfSizeX, halfSizeZ from Floor3 AABB).",
	HighestWallY = "Top of Floor 3 walls (topOfWallsY in model space).",
	DecorationSpaceAbove = "Studs above topOfWallsY for toppers (e.g. 8).",
	DecorationTopY = "topOfWallsY + decorationSpaceAbove.",
	Remotes = "GetExteriorBounds (InvokeServer), GetBuildInstructions (InvokeServer(themeName)), RefreshExterior (FireServer).",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- PART 3: AGENT CHECKLIST (VERIFY BEFORE SUBMITTING BASE)
-- ═══════════════════════════════════════════════════════════════════════════

Instructions.AgentChecklist = {
	"Plot has exactly Floor1, Floor2, Floor3 (Model or Folder).",
	"Floor1 contains DefensePoint1..6 and IncomePoint1..6 (in any subfolder).",
	"Floor2 contains DefensePoint7..12, IncomePoint7..12, BattlePoint1..9 (e.g. in BattleTeam), and Stairs.",
	"Floor3 contains DefensePoint13..18, IncomePoint13..18, and Stairs.",
	"Plot has PlotCenter and (optionally) SignPart.",
	"All point parts are BaseParts with exact names; no typos.",
	"Glass parts use name 'Glass' or attribute IsGlass = true if they should stay transparent.",
	"Parts are anchored where appropriate; no unintended fall-through.",
	"Haunted house theme applied: dark palette, gothic/Victorian cues, optional props and lighting.",
}

-- ═══════════════════════════════════════════════════════════════════════════
-- EXPORT
-- ═══════════════════════════════════════════════════════════════════════════

return Instructions
