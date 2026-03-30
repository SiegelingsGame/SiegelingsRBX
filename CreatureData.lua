--[[
	CreatureData.lua
	ReplicatedStorage/Modules/CreatureData

	======================================================================
	CENTRAL CREATURE REGISTRY
	All creature definitions, traits, spawning rules, and lookup helpers
	live here. Single source of truth for creature data (client + server).
	======================================================================

	ADDING A NEW CREATURE:
		1. Add an entry to CreatureData.Creatures below
		2. Give it a unique "id" (lowercase_snake_case)
		3. Set element, class, behavior, and rarity (base stats are computed from rarity+class+element+id)
		4. Set spawnPointType to "dungeon" or "boss" if needed
		5. The _byId lookup table auto-rebuilds at the bottom

	ADDING A NEW ELEMENT:
		1. Add it to CreatureData.Elements
		2. Add a zone mapping in CreatureData.ZonePreference
		3. Add a biome folder mapping in CreatureData.ZoneBiomeFolder
		4. Add synergy tiers in CreatureData.Synergies
		5. Create 15 creatures (5C, 4U, 3R, 2E, 1L) for that element

	ADDING A NEW BEHAVIOR:
		1. Document it in the behavior list below
		2. Implement the AI state in CreatureAI.lua
		3. Assign the behavior to creature entries as desired

	ADDING A NEW BIOME:
		1. Create a folder under workspace.Biomes with the biome name
		2. Add SpawnPoint, DungeonPoint, and BossPoint parts inside it
		3. Map the biome in ZoneBiomeFolder below
		4. Outer dual-element biomes (see OuterBiomePrimarySecondary): also add
		   SpawnPoint2, DungeonPoint2, BossPoint2 for the secondary element in that folder

	SPAWN POINT TYPES (spawnPointType field):
		nil / omitted   = Spawns at regular SpawnPoints in its biome
		"dungeon"       = Spawns at DungeonPoints (harder encounters)
		"boss"          = Spawns at BossPoints (one legendary per biome; outer dual biomes also use BossPoint2)

	FLYING (flying field):
		true = Creature hovers at player height (FlyingHoverHeight) above ground
		omit = Creature walks on ground, bottom of model on surface

	CRAWLING (crawling field):
		true = Model is rotated 90 degrees forward (pitch) so upright-standing models appear to move on their bellies.
		Use when walk animations are belly-crawls but the rig idles upright.
		omit = Normal upright orientation

	FUTURE: Cross-Biome Spawning / Events
		The spawnPointType and element-to-biome mapping are designed to be
		overridable. A future EventSystem could:
		- Temporarily add creatures to a different biome's spawn pool
		- Change a creature's spawnPointType during special events
		- Use GetCreaturesByElement() with a different element to spawn
		  "invaders" in foreign biomes
		- Add a "migratory" behavior for creatures that wander between zones

	Behaviors (implemented in CreatureAI.lua):
		pack       - travels in groups (packSize), attacks together
		lone       - solitary, patrols territory, fights intruders
		gentle     - passive, fights back only when attacked
		aggressive - actively hunts creatures and players
		skittish   - flees when approached, must be cornered
		raider     - AI raid system only (not for world spawns)
		stationary - base system only (not for world spawns)

	Rarity Distribution Per Element: 5C, 4U, 3R, 2E, 1L = 15 each
	Total Creatures: 90 (15 x 6 elements)

	MODEL ROTATION:
		modelRotationY = degrees (default nil/0) — Rotate model around vertical axis from its base orientation.
		Use when a model faces left/right instead of forward in idle. Example: modelRotationY = 90

		modelStandUpAngles = {rx, ry, rz} (default nil) — Euler angles in degrees for rigs that export lying down.
		Applied when setting orientation (companion, world spawn, arena). Example: {-90, 0, 0} to stand a horizontal rig.

		modelDisplaySize = number (default nil) — Override display size in studs (max dimension).
		modelScaleMultiplier = number (default 1) — Fine-tune scale. 1.5 = 50% larger, 0.8 = 20% smaller.

		modelPlacementYOffset = number (default nil/0) — Extra Y offset in studs when placed on base points.
		Use when limbs extend below the model's base, or Meshy AI skeletons appear underground.
		Example: modelPlacementYOffset = 2  (positive = lift up so feet sit on point)

		modelPlacementOffset = Vector3 or {x,y,z} (default nil) — Full 3D offset in studs when placed on base points.
		Use when a model sits on the wrong point (e.g. shifted left/right). Example: modelPlacementOffset = Vector3.new(2, -1.5, 0)

	FLYING (flying field):
		true = Creature hovers at player height (FlyingHoverHeight) above ground
		omit = Creature walks on ground, bottom of model on surface

	CRAWLING (crawling field):
		true = Model rotated 90 degrees forward (pitch); use when walk anim is belly-crawl but rig idles upright.
		omit = Normal upright orientation.

	MOUNTING (mount fields):
		mountable = true     — Creature can be ridden by the player as a mount.
		mountType = string   — "Ground" (default), "Flying", "Swimming", or "Special".
		                       Auto-derived from flying/element if omitted.
		mountOffset = {x,y,z} — Player seat offset from Body center (studs). Default {0,3,-1}.
		mountScale = number  — Visual scale multiplier when mounted (default 2.0).
		mountSpeedBonus = number — Extra flat speed bonus on top of base formula (default 0).
		Only creatures with mountable = true can be mounted.
		Common/Uncommon are generally too small; Rare+ creatures are recommended.
]]

local CreatureData = {}

CreatureData.Rarities = {
	Common    = { color = Color3.fromRGB(180, 180, 180), weight = 50, label = "Common",    captureCost = 10 },
	Uncommon  = { color = Color3.fromRGB(75, 200, 75),   weight = 25, label = "Uncommon",  captureCost = 25 },
	Rare      = { color = Color3.fromRGB(60, 130, 255),  weight = 15, label = "Rare",      captureCost = 60 },
	Epic      = { color = Color3.fromRGB(180, 80, 255),  weight = 7,  label = "Epic",      captureCost = 150 },
	Legendary = { color = Color3.fromRGB(255, 184, 0),   weight = 3,  label = "Legendary", captureCost = 400 },
}

-- Rarity order for comparison (higher index = rarer)
-- Used by GetDungeonCreatureId to filter for Rare+ creatures
CreatureData.RarityOrder = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

-- Variant tiers for combining: 3 of same tier combine into next (Normal → Silver → Gold → Legend)d
CreatureData.VariantTiers = { "Normal", "Silver", "Gold", "Legend" }
CreatureData.VariantOrder = { Normal = 1, Silver = 2, Gold = 3, Legend = 4 }
CreatureData.VariantColors = {
	Normal = Color3.fromRGB(200, 200, 200),
	Silver = Color3.fromRGB(192, 192, 192),
	Gold  = Color3.fromRGB(255, 215, 0),
	Legend = Color3.fromRGB(255, 100, 255),
}

-- Starter creatures the player can choose on first join (4 starters, one per element)
CreatureData.Starters = { "cacty", "pursula", "sundile", "ceeponee" }

-- Zone preferences by element (creatures spawn in zone with SpawnPoints/DungeonPoint/BossPoint)
-- Psychic+Undead=Desert, Shadow+Metal=Cave, Electric+Light=Electric, Poison+Water=Ocean; rest unchanged
CreatureData.ZonePreference = {
	Fire      = "volcanic",
	Ice       = "frozen",
	Wind      = "highlands",
	Earth     = "forest",
	Shadow    = "caves",
	Light     = "peaks",     -- Electric zone (with Lightning)
	Lightning = "peaks",
	Water     = "aquatic",
	Psychic   = "desert",
	Metal     = "caves",     -- Cave zone (with Shadow)
	Poison    = "aquatic",   -- Ocean zone (with Water)
	Undead    = "desert",
}

-- Zone name -> Workspace biome folder name (primary name used in Studio)
CreatureData.ZoneBiomeFolder = {
	volcanic  = "VolcanicBiome",
	frozen    = "FrozenBiome",
	highlands = "HighlandsBiome",
	forest    = "ForestBiome",
	caves     = "CaveBiome",
	sanctum   = "SanctumBiome",
	peaks     = "ElectricBiome",
	aquatic   = "OceanBiome",   -- Ocean zone (Water + Poison)
	desert    = "DesertBiome",  -- Psychic + Undead
	-- Legacy zones (no longer used for spawn preference; kept for any other refs)
	mind      = "MindBiome",
	forge     = "ForgeBiome",
	swamp     = "SwampBiome",
	crypt     = "CryptBiome",
}

-- Alternate folder names that also map to the same zone (so any of these in workspace.Biomes work)
CreatureData.ZoneBiomeFolderAliases = {
	aquatic = { "WaterBiome", "AquaticBiome", "Water" },
	peaks   = { "PeaksBiome", "ElectriBiome" },
	desert  = {},  -- DesertBiome only (no alias)
	-- CaveGym also accepts CaveBiome_; cave terrain may use Terrain.CaveBaseplate without Biomes.CaveBiome
	caves   = { "Cave", "CaveBiome_", "CryptBiome", "CavernBiome" },
}

-- Outer baseplate biomes where two elements share one folder. Primary element uses
-- SpawnPoint / DungeonPoint / BossPoint; secondary uses SpawnPoint2 / DungeonPoint2 / BossPoint2.
-- Order: { primaryElement, secondaryElement } — must match ZonePreference for those biomes.
CreatureData.OuterBiomePrimarySecondary = {
	DesertBiome = { "Psychic", "Undead" },
	OceanBiome = { "Water", "Poison" },
	ElectricBiome = { "Lightning", "Light" },
	CaveBiome = { "Shadow", "Metal" },
}

-- Returns { primaryElement, secondaryElement } for dual outer biomes, or nil.
-- Resolves alias folder names (e.g. WaterBiome) to the canonical pair.
function CreatureData.GetOuterBiomeElementPair(biomeFolderName)
	local tbl = CreatureData.OuterBiomePrimarySecondary
	if not tbl then return nil end
	if tbl[biomeFolderName] then
		return tbl[biomeFolderName]
	end
	for _, folderName in pairs(CreatureData.ZoneBiomeFolder) do
		if folderName == biomeFolderName then
			return tbl[folderName]
		end
	end
	local aliases = CreatureData.ZoneBiomeFolderAliases
	if aliases then
		for zone, names in pairs(aliases) do
			for _, alias in ipairs(names) do
				if alias == biomeFolderName then
					local canonical = CreatureData.ZoneBiomeFolder[zone]
					return canonical and tbl[canonical]
				end
			end
		end
	end
	return nil
end

-- "primary" | "secondary" | nil — for routing spawns to SpawnPoint vs SpawnPoint2 (etc.)
function CreatureData.GetOuterBiomeElementSlot(biomeFolderName, element)
	local pair = CreatureData.GetOuterBiomeElementPair(biomeFolderName)
	if not pair then return nil end
	if element == pair[1] then return "primary" end
	if element == pair[2] then return "secondary" end
	return nil
end

-- Get the biome folder name for a creature's element (primary name only)
function CreatureData.GetBiomeFolderForElement(element)
	local zone = CreatureData.ZonePreference[element]
	if not zone then return nil end
	return CreatureData.ZoneBiomeFolder[zone]
end

-- Get all valid folder names for an element (primary first, then aliases). Used by spawner to find existing biome folder.a
function CreatureData.GetBiomeFolderNamesForElement(element)
	local zone = CreatureData.ZonePreference[element]
	if not zone then return {} end
	local primary = CreatureData.ZoneBiomeFolder[zone]
	if not primary then return {} end
	local out = { primary }
	local aliases = CreatureData.ZoneBiomeFolderAliases and CreatureData.ZoneBiomeFolderAliases[zone]
	if aliases then
		for _, name in ipairs(aliases) do table.insert(out, name) end
	end
	return out
end

-- Spawn zone data: name -> { center, radius }
-- These get populated by Init from workspace zone parts
CreatureData.Zones = {}

-- --------------------------------------
-- TRAIT DEFINITIONS
-- --------------------------------------

CreatureData.Elements = {
	Fire      = { color = Color3.fromRGB(255, 80, 30),  icon = "" },
	Ice       = { color = Color3.fromRGB(100, 200, 255), icon = "" },
	Wind      = { color = Color3.fromRGB(150, 255, 180), icon = "" },
	Earth     = { color = Color3.fromRGB(180, 140, 80),  icon = "" },
	Shadow    = { color = Color3.fromRGB(120, 50, 180),  icon = "" },
	Light     = { color = Color3.fromRGB(255, 250, 200), icon = "" },
	Lightning = { color = Color3.fromRGB(255, 230, 60),  icon = "" },
	Water     = { color = Color3.fromRGB(50, 150, 255),  icon = "" },
	Psychic   = { color = Color3.fromRGB(200, 150, 255), icon = "" },
	Metal     = { color = Color3.fromRGB(160, 170, 180), icon = "" },
	Poison    = { color = Color3.fromRGB(120, 220, 80),  icon = "" },
	Undead    = { color = Color3.fromRGB(140, 120, 160), icon = "" },
}

CreatureData.Classes = {
	Bruiser   = { color = Color3.fromRGB(220, 80, 60),  icon = "" },
	Mage      = { color = Color3.fromRGB(100, 120, 255), icon = "" },
	Guardian  = { color = Color3.fromRGB(80, 180, 220),  icon = "" },
	Assassin  = { color = Color3.fromRGB(200, 60, 200),  icon = "" },
	Support   = { color = Color3.fromRGB(100, 220, 120), icon = "" },
}

-- Total stat pool per rarity (health + attack + defense + speed). Stats are filled by AllocateBaseStats.
CreatureData.RarityStatBudget = {
	Common = 100,
	Uncommon = 150,
	Rare = 300,
	Epic = 400,
	Legendary = 500,
}

-- Normalized class shapes (health, attack, defense, speed). Element bias is added before renormalize.
CreatureData.ClassStatWeights = {
	Assassin = { 0.14, 0.32, 0.22, 0.32 }, -- fast, strong, squishy; defense varied per id
	Guardian = { 0.40, 0.17, 0.33, 0.10 }, -- slow, tanky; attack varied per id
	Mage = { 0.20, 0.40, 0.11, 0.29 }, -- high attack, low def; health varied per id
	Bruiser = { 0.28, 0.26, 0.28, 0.18 }, -- balanced hp/def; speed varied per id
	Support = { 0.36, 0.14, 0.14, 0.36 }, -- high health + speed
}

-- Small additive biases (same stat order). Wind = Air, Lightning = Electric in design terms..
CreatureData.ElementStatBias = {
	Fire = { 0, 0.07, 0, 0 },
	Earth = { 0.07, 0, 0, 0 },
	Wind = { 0, 0, 0, 0.07 },
	Ice = { 0, 0, 0.07, 0 },
	Water = { 0.04, 0.04, 0, 0 },
	Lightning = { 0, 0.04, 0, 0.04 },
	Poison = { 0.04, 0, 0, 0.04 },
	Metal = { 0.04, 0, 0.04, 0 },
	Psychic = { 0, 0, 0.04, 0.04 },
	Undead = { 0, 0.04, 0.04, 0 },
	Light = { 0.03, 0, 0.03, 0.03 },
	Shadow = { 0, 0.03, 0.03, 0.03 },
}

local function statHash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- Deterministic per-id spread on the class "varied" stat (±~6% relative weight before partition).
local function applyClassStatSpread(class, w, hash)
	local h1 = hash % 131
	local t = (h1 / 130 - 0.5) * 0.12
	if class == "Assassin" then
		w[3] = math.max(0.02, w[3] * (1 + t))
	elseif class == "Guardian" then
		w[2] = math.max(0.02, w[2] * (1 + t))
	elseif class == "Mage" then
		w[1] = math.max(0.02, w[1] * (1 + t))
	elseif class == "Bruiser" then
		w[4] = math.max(0.02, w[4] * (1 + t))
	elseif class == "Support" then
		local u = (hash % 97) / 96 - 0.5
		w[1] = math.max(0.02, w[1] * (1 + u * 0.08))
		w[4] = math.max(0.02, w[4] * (1 - u * 0.08))
	end
end

local function normalizeFour(w)
	local s = w[1] + w[2] + w[3] + w[4]
	if s <= 0 then return { 0.25, 0.25, 0.25, 0.25 } end
	return { w[1] / s, w[2] / s, w[3] / s, w[4] / s }
end

-- Largest-remainder split of `total` across four weights; each stat at least `minEach`.
local function partitionWithMin(total, w, minEach)
	local n = 4
	local floorMin = n * minEach
	if total < floorMin then
		minEach = math.max(0, math.floor(total / n))
		floorMin = n * minEach
	end
	local rem = total - floorMin
	local frac = { w[1] * rem, w[2] * rem, w[3] * rem, w[4] * rem }
	local out = {
		minEach + math.floor(frac[1]),
		minEach + math.floor(frac[2]),
		minEach + math.floor(frac[3]),
		minEach + math.floor(frac[4]),
	}
	local used = out[1] + out[2] + out[3] + out[4]
	local leftover = total - used
	local fr = {
		{ i = 1, f = frac[1] - math.floor(frac[1]) },
		{ i = 2, f = frac[2] - math.floor(frac[2]) },
		{ i = 3, f = frac[3] - math.floor(frac[3]) },
		{ i = 4, f = frac[4] - math.floor(frac[4]) },
	}
	table.sort(fr, function(a, b) return a.f > b.f end)
	for k = 1, leftover do
		out[fr[k].i] = out[fr[k].i] + 1
	end
	return out
end

function CreatureData.AllocateBaseStats(rarity, class, element, creatureId)
	local budget = CreatureData.RarityStatBudget[rarity] or 100
	local cw = CreatureData.ClassStatWeights[class]
	if not cw then
		cw = { 0.25, 0.25, 0.25, 0.25 }
	end
	local eb = CreatureData.ElementStatBias[element]
	if not eb then
		eb = { 0, 0, 0, 0 }
	end
	local w = {
		math.max(0.02, cw[1] + eb[1]),
		math.max(0.02, cw[2] + eb[2]),
		math.max(0.02, cw[3] + eb[3]),
		math.max(0.02, cw[4] + eb[4]),
	}
	w = normalizeFour(w)
	local h = statHash(tostring(creatureId or ""))
	applyClassStatSpread(class, w, h)
	w = normalizeFour(w)
	local minEach = 1
	if budget < 8 then
		minEach = 0
	end
	local parts = partitionWithMin(budget, w, minEach)
	return {
		health = parts[1],
		attack = parts[2],
		defense = parts[3],
		speed = parts[4],
	}
end

-- Synergy bonuses (applied during battle)
CreatureData.Synergies = {
	Fire = {
		{ count = 2, label = "Ember",   bonuses = { attack = 0.10 } },
		{ count = 3, label = "Inferno", bonuses = { attack = 0.25 } },
	},
	Ice = {
		{ count = 2, label = "Frost",    bonuses = { defense = 0.10 } },
		{ count = 3, label = "Blizzard", bonuses = { defense = 0.25, speed = -0.10 } },
	},
	Wind = {
		{ count = 2, label = "Breeze",   bonuses = { speed = 0.15 } },
		{ count = 3, label = "Tempest",  bonuses = { speed = 0.30, attack = 0.10 } },
	},
	Earth = {
		{ count = 2, label = "Roots",    bonuses = { health = 0.10 } },
		{ count = 3, label = "Tectonic", bonuses = { health = 0.25, defense = 0.10 } },
	},
	Shadow = {
		{ count = 2, label = "Dusk",     bonuses = { attack = 0.10, speed = 0.05 } },
		{ count = 3, label = "Eclipse",  bonuses = { attack = 0.20, speed = 0.15 } },
	},
	Light = {
		{ count = 2, label = "Radiant",  bonuses = { defense = 0.10, attack = 0.05 } },
		{ count = 3, label = "Brilliance", bonuses = { defense = 0.20, attack = 0.15 } },
	},
	Lightning = {
		{ count = 2, label = "Spark",    bonuses = { speed = 0.10, attack = 0.05 } },
		{ count = 3, label = "Thunder",  bonuses = { speed = 0.20, attack = 0.15 } },
	},
	Water = {
		{ count = 2, label = "Tide",     bonuses = { defense = 0.10, speed = 0.05 } },
		{ count = 3, label = "Tsunami",  bonuses = { defense = 0.20, speed = 0.15 } },
	},
	Psychic = {
		{ count = 2, label = "Link",     bonuses = { health = 0.10, speed = 0.05 } },
		{ count = 3, label = "Harmony",  bonuses = { health = 0.20, speed = 0.10 } },
	},
	Metal = {
		{ count = 2, label = "Alloy",    bonuses = { defense = 0.12 } },
		{ count = 3, label = "Tempered", bonuses = { defense = 0.25, health = 0.08 } },
	},
	Poison = {
		{ count = 2, label = "Toxin",    bonuses = { attack = 0.08, speed = 0.05 } },
		{ count = 3, label = "Venom",    bonuses = { attack = 0.18, speed = 0.10 } },
	},
	Undead = {
		{ count = 2, label = "Wither",   bonuses = { health = 0.08, defense = 0.08 } },
		{ count = 3, label = "Necrotic", bonuses = { health = 0.18, defense = 0.15 } },
	},
	Bruiser = {
		{ count = 2, label = "Fury",     bonuses = { attack = 0.12 } },
		{ count = 3, label = "Rampage",  bonuses = { attack = 0.25, health = 0.10 } },
	},
	Mage = {
		{ count = 2, label = "Focus",    bonuses = { attack = 0.10 } },
		{ count = 3, label = "Arcane",   bonuses = { attack = 0.20 } },
	},
	Guardian = {
		{ count = 2, label = "Shield",   bonuses = { defense = 0.15 } },
		{ count = 3, label = "Bastion",  bonuses = { defense = 0.30, health = 0.10 } },
	},
	Assassin = {
		{ count = 2, label = "Edge",     bonuses = { speed = 0.10, attack = 0.05 } },
		{ count = 3, label = "Lethal",   bonuses = { speed = 0.20, attack = 0.20 } },
	},
	Support = {
		{ count = 2, label = "Mend",     bonuses = { health = 0.10 } },
		{ count = 3, label = "Harmony",  bonuses = { health = 0.20, defense = 0.10 } },
	},
}

-- --------------------------------------
-- CREATURE DEFINITIONS (90 total)
-- 15 per element: 5 Common, 4 Uncommon, 3 Rare, 2 Epic, 1 Legendary
-- Base stats: filled after this table via AllocateBaseStats (RarityStatBudget + class + element + id).
-- --------------------------------------

CreatureData.Creatures = {

	-- ============================
	-- FIRE CREATURES (5C, 4U, 3R, 2E, 1L)
	-- ============================

	-- Fire Common (5)
	{
		id = "firsky", displayName = "Firsky", rarity = "Common",
		element = "Fire", class = "Mage", behavior = "aggressive",
		spawnWeight = 15, baseIncome = 1, captureTime = 0.5,
		description = "A small flame spirit that actively hunts smaller creatures.",
		modelName = "Firsky", primaryColor = Color3.fromRGB(255, 140, 50),
		evolvesTo = "Coming Soon",
	},
	{
		id = "pylook", displayName = "Pylook", rarity = "Common",
		element = "Fire", class = "Assassin", behavior = "skittish",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.6,
		description = "Some say the spirits of lost SiegeKnights burning with rage become pylooks",
		modelName = "Pylook", primaryColor = Color3.fromRGB(255, 120, 60),
		evolvesTo = "pyleer",
		flying = true,
	},
	{
		id = "sundile", displayName = "Sundile", rarity = "Common",
		element = "Fire", class = "Guardian", behavior = "gentle",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5,
		description = "These scaled lizards are known to have an affinity for lava pools and tracking time",
		modelName = "Sundile", primaryColor = Color3.fromRGB(140, 90, 70),
		evolvesTo = "raydile",
		crawling = true,
	},
	{
		id = "draco", displayName = "Draco", rarity = "Common",
		element = "Fire", class = "Bruiser", behavior = "pack",
		spawnWeight = 17, baseIncome = 1, captureTime = 0.5, packSize = {2, 4},
		description = "Their coiled tails lash out at anything that dares to cross their path. Always found in groups",
		modelName = "Draco", primaryColor = Color3.fromRGB(255, 90, 30),evolvesTo = "dracoil",
	},
	{
		id = "emberfox", displayName = "Emberfox", rarity = "Common",
		element = "Fire", class = "Support", behavior = "gentle",
		spawnWeight = 16, baseIncome = 1, captureTime = 0.6,
		description = "The gentle emberfox, found in many homes as a pet. Perfect for winter snuggles",
		modelName = "Emberfox", primaryColor = Color3.fromRGB(200, 110, 40),
	},

	-- Fire Uncommon (4)
	{
		id = "emberpup", displayName = "Emberpup", rarity = "Uncommon",
		element = "Fire", class = "Bruiser", behavior = "pack",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.0,
		description = "A fiery puppy that leaves scorch marks wherever it walks. Attacks on sight!",
		modelName = "Emberpup", primaryColor = Color3.fromRGB(255, 100, 40),
	},
	{
		id = "raydile", displayName = "Raydile", rarity = "Uncommon",
		element = "Fire", class = "Guardian", behavior = "lone",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A salamander with a molten core. These lone sieglings seek the heat of the sun.",
		modelName = "Raydile", primaryColor = Color3.fromRGB(200, 60, 20),
		evolvesFrom = "sundile",
		evolvesTo = "solgator",
		modelDisplaySize = 5.0,modelScaleMultiplier = 1.5,
		crawling = true,
	},
	{
		id = "hotty", displayName = "Hotty", rarity = "Uncommon",
		element = "Fire", class = "Support", behavior = "pack",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.0, packSize = {2, 3},
		description = "Hotty's are helpers of the Fire Eleminion",
		modelName = "Hotty", primaryColor = Color3.fromRGB(255, 160, 80),
	},
	{
		id = "emberfin", displayName = "Emberfin", rarity = "Uncommon",
		element = "Fire", class = "Assassin", behavior = "aggressive",
		spawnWeight = 8, baseIncome = 3, captureTime = 1.2,
		description = "A predator that hides in smoke clouds, striking with superheated fangs before vanishing again.",
		modelName = "Emberfin", primaryColor = Color3.fromRGB(80, 50, 40),
		evolvesTo = "Cindergil",flying = true, 
	},

	-- Fire Rare (3)
	{
		id = "dracoil", displayName = "Dracoil", rarity = "Rare",
		element = "Fire", class = "Assassin", behavior = "lone",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "Dracoil's leave the safety of the pack to travel alone, but they are known to return when the pack is in danger",
		modelName = "Dracoil", primaryColor = Color3.fromRGB(255, 60, 20),
		spawnPointType = "dungeon",evolvesFrom = "draco",
		modelDisplaySize = 5.0,modelScaleMultiplier = 1.5,
		mountable = true, mountOffset = {0, 3, -1.5}, mountScale = 2.0,
	},
	{
		id = "cindergil", displayName = "Cindergil", rarity = "Rare",
		element = "Fire", class = "Support", behavior = "skittish",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A majestic stag with antlers of living flame. It heals allies as it runs, but catching it requires persistence.",
		modelName = "Cindergil", primaryColor = Color3.fromRGB(255, 180, 60),
		mountable = true, mountOffset = {0, 3, -1.5}, mountScale = 2.0,
	},
	{
		id = "hotdog", displayName = "Hotdog", rarity = "Rare",
		element = "Fire", class = "Bruiser", behavior = "pack",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "Its gullet is a literal furnace. Once it locks its jaws, the heat alone does half the work.",
		modelName = "Hotdog", primaryColor = Color3.fromRGB(220, 50, 10),
		spawnPointType = "dungeon",modelDisplaySize = 8,modelScaleMultiplier = 1.5
	},

	-- Fire Epic (2)
	{
		id = "pyleer", displayName = "Pyleer", rarity = "Epic",
		element = "Fire", class = "Mage", behavior = "lone",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "The pylook's evolved form, formed on many pylook's fused into a single ghastly creature",
		modelName = "Pyleer", primaryColor = Color3.fromRGB(255, 50, 0),
		spawnPointType = "dungeon",modelDisplaySize = 8.0,modelScaleMultiplier = 2.0,
		evolvesFrom = "pylook", flying = true,
		mountable = true, mountType = "Flying", mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
	},
	{
		id = "solgator", displayName = "Solgator", rarity = "Epic",
		element = "Fire", class = "Guardian", behavior = "aggressive",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "The Solgator guards the lava pools of the Fire lands, they attack anything that dares to cross their path",
		modelName = "Solgator", primaryColor = Color3.fromRGB(180, 40, 10),
		spawnPointType = "dungeon",
		evolvesFrom = "raydile", crawling = true,modelDisplaySize = 8.0,modelScaleMultiplier = 2.0,
		mountable = true, mountOffset = {0, 3, -2}, mountScale = 2.2, mountType = "Ground",
	},

	-- Fire Legendary (1)
	{
		id = "pylord", displayName = "Pylord", rarity = "Legendary",
		element = "Fire", class = "Bruiser", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "This ancient Siegling is said to be the soul of a powerful SiegLord who jumped into the Volcano to become Fire itself",
		modelName = "Pylord", primaryColor = Color3.fromRGB(255, 200, 30),
		spawnPointType = "boss",modelDisplaySize = 16.0,
		mountable = true, mountType = "Ground", mountOffset = {0, 4, -2}, mountScale = 2.5,
	},

	-- ============================
	-- ICE CREATURES (5C, 4U, 3R, 2E, 1L)
	-- ============================123

	-- Ice Common (5)
	{
		id = "fawny", displayName = "Fawny", rarity = "Common",
		element = "Ice", class = "Bruiser", behavior = "pack",
		spawnWeight = 15, baseIncome = 1, captureTime = 0.5,
		description = "Bundled up from within the snow, these small deerlike creatures are known to be shy",
		modelName = "Fawny", primaryColor = Color3.fromRGB(200, 230, 255),
		evolvesTo = "chilldoe",
	},
	{
		id = "frostfly", displayName = "Frostfly", rarity = "Common",
		element = "Ice", class = "Assassin", behavior = "gentle",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5,
		description = "Frostflies are found fluttering along snowflakes, they rest on pine trees and have a fondness for winter berries",
		modelName = "Frostfly", primaryColor = Color3.fromRGB(150, 200, 240), flying = true, crawling = true
	},
	{
		id = "icewee", displayName = "Ice-Wee", rarity = "Common",
		element = "Ice", class = "Assassin", behavior = "aggressive",
		spawnWeight = 16, baseIncome = 1, captureTime = 0.6,
		description = "The Ice-Weee is a odd creature, its Ice-Cube shaped body can grow to intimidate other creatures",
		modelName = "Icewee", primaryColor = Color3.fromRGB(180, 220, 255),
		evolvesTo = "icecuewee",
	},
	{
		id = "falcool", displayName = "Falcool", rarity = "Common",
		element = "Ice", class = "Support", behavior = "lone",
		spawnWeight = 17, baseIncome = 1, captureTime = 0.5,
		description = "Ceeponee float through the winter winds and are known to be a bit shy",
		modelName = "Falcool", primaryColor = Color3.fromRGB(130, 190, 255), 
		evolvesTo = "peatbeak"
	},
	{
		id = "cozycub", displayName = "Cozycub", rarity = "Common",
		element = "Ice", class = "Mage", behavior = "lone",
		spawnWeight = 15, baseIncome = 1, captureTime = 0.6, packSize = {2, 3},
		description = "Large and imposing these cuddly creatures only want to find their companion and stay warm.",
		modelName = "Cozycub", primaryColor = Color3.fromRGB(220, 240, 255),
		modelDisplaySize = 9.0,modelScaleMultiplier = 1.5,
	},

	-- Ice Uncommon (4)
	{
		id = "frosty", displayName = "Frosty", rarity = "Uncommon",
		element = "Ice", class = "Mage", behavior = "lone",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.0,
		description = "A ghostly wisp wrapped in a permanent chill. Patrols alone.",
		modelName = "Frosty", primaryColor = Color3.fromRGB(140, 210, 255),

	},
	{
		id = "chilldoe", displayName = "Chilldoe", rarity = "Uncommon",
		element = "Ice", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.0, packSize = {2, 4},
		description = "Trading the puffy for a Hooded Jacker, the Chilldoe has honed its fist into fearsome weapons",
		modelName = "Chilldoe", primaryColor = Color3.fromRGB(160, 210, 240),
		evolvesFrom = "fawny", evolvesTo = "frostag",modelDisplaySize = 4.0,modelScaleMultiplier = 1.5,
	},
	{
		id = "icecuewee", displayName = "Ice-Cue-Wee", rarity = "Uncommon",
		element = "Ice", class = "Assassin", behavior = "skittish",
		spawnWeight = 8, baseIncome = 3, captureTime = 1.2,
		description = "A gentle fawn made of crystallized snow. It heals nearby allies w.ith its aura but flees from conflict.",
		modelName = "Icecuewee", primaryColor = Color3.fromRGB(200, 240, 250),
		evolvesFrom = "icewee"
	},
	{
		id = "falcoat", displayName = "Falcoat", rarity = "Uncommon",
		element = "Ice", class = "Assassin", behavior = "lone",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A well dressed predator that blends into ice fields. By the time you see it, its fangs are already at your throat.",
		modelName = "Falcoat", primaryColor = Color3.fromRGB(100, 170, 230),evolvesTo ="Peatbeak", evolvesFrom = "falcool",
		modelDisplaySize = 5.0,modelScaleMultiplier = 1.5,
	},

	-- Ice Rare (3)
	{
		id = "peatbeak", displayName = "Peatbeak", rarity = "Rare",
		element = "Ice", class = "Guardian", behavior = "gentle",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "An ancient ice fowl. Nearly impervious to physical blows. Peaceful unless provoked.",
		modelName = "peatbeak", primaryColor = Color3.fromRGB(80, 160, 240),
		evolvesFrom = "falcoat",
		modelDisplaySize = 9.0,modelScaleMultiplier = 1.5,
	},
	{
		id = "lumina", displayName = "Lumina", rarity = "Rare",
		element = "Ice", class = "Mage", behavior = "pack",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A floating ice crystal that conjures devastating hailstorms. It aggressively pursues anything generating heat.",
		modelName = "Lumina", primaryColor = Color3.fromRGB(60, 140, 255),
		spawnPointType = "dungeon", flying = true
	},

	-- Ice Epic (2)
	{
		id = "frostag", displayName = "Frostag", rarity = "Epic",
		element = "Ice", class = "Assassin", behavior = "lone",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A spectral blade given sentient form. It glides through blizzards, striking with lethal cold precision.",
		modelName = "Frostag", primaryColor = Color3.fromRGB(50, 120, 220),
		spawnPointType = "dungeon", modelDisplaySize = 8.0, modelScaleMultiplier = 2.0,
		evolvesFrom = "chilldoe",
		mountable = true, mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
	},

	-- Ice Legendary (1)
	{
		id = "glaciemperor", displayName = "Glaciemperor", rarity = "Legendary",
		element = "Ice", class = "Mage", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "An ancient ice wyrm that commands blizzards with a thought. Entire regions freeze in its wake. The undisputed ruler of the frozen wastes.",
		modelName = "Glaciemperor", primaryColor = Color3.fromRGB(40, 100, 200),
		spawnPointType = "boss",modelDisplaySize = 15.0,
		mountable = true, mountOffset = {0, 4, -2}, mountScale = 2.5,
	},

	-- ============================
	-- WIND CREATURES (5C, 4U, 3R, 2E, 1L)
	-- ============================

	-- Wind Common (5)
	{
		id = "breezee", displayName = "Breezee", rarity = "Common",
		element = "Wind", class = "Assassin", behavior = "pack",
		spawnWeight = 17, baseIncome = 1, captureTime = 0.5, packSize = {3, 5},
		description = "Tiny birds that gather in murmuration flocks. Their synchronized wingbeats create cutting air blades.",
		modelName = "Breezee", primaryColor = Color3.fromRGB(180, 220, 170),
		flying = true,
		evolvesTo ="gagglestand",
		modelDisplaySize = 2.0,modelScaleMultiplier = 1.0, 
	},
	{
		id = "pursula", displayName = "Pursula", rarity = "Common",
		element = "Wind", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 16, baseIncome = 1, captureTime = 0.5,
		description = "A hyperactive wind hound that barrels into anything it sees. Fast, reckless, and surprisingly tough.",
		modelName = "Pursula", primaryColor = Color3.fromRGB(140, 255, 160),
		evolvesTo = "purseus",
	},
	{
		id = "cloudpuff", displayName = "Cloudpuff", rarity = "Common",
		element = "Wind", class = "Guardian", behavior = "skittish",
		spawnWeight = 15, baseIncome = 1, captureTime = 0.6,
		description = "A cottontail made of solidified cloud. Surprisingly resilient but bolts at any sudden movement.",
		modelName = "Cloudpuff", primaryColor = Color3.fromRGB(230, 250, 240),
		spawnPointType = "dungeon",evolvesTo = "cloudwisp"
	},

	-- Wind Uncommon (4)
	{
		id = "lofty", displayName = "Lofty", rarity = "Uncommon",
		element = "Wind", class = "Assassin", behavior = "lone",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.0,
		description = "A sleek predator that strikes from sudden gusts. Solitary hunter.",
		modelName = "Lofty", primaryColor = Color3.fromRGB(170, 240, 200),
	},
	{
		id = "gagglestand", displayName = "Gagglestand", rarity = "Uncommon",
		element = "Wind", class = "Support", behavior = "gentle",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A flowering plant creature that disperses healing pollen on the wind. Peaceful and slow to anger.",
		modelName = "Gagglestand", primaryColor = Color3.fromRGB(120, 220, 150),
		evolvesFrom = "breezee", evolvesTo = "hurricrane",
		modelDisplaySize = 5.0,modelScaleMultiplier = 1.5, flying = true
	},
	{
		id = "purseus", displayName = "Purseus", rarity = "Uncommon",
		element = "Wind", class = "Mage", behavior = "aggressive",
		spawnWeight = 8, baseIncome = 3, captureTime = 1.2,
		flying = true,
		description = "A swirling vortex with glowing eyes. It hurls cutting wind blades at anything it spots.",
		modelName = "Purseus", primaryColor = Color3.fromRGB(100, 200, 160),evolvesTo = "pursephone",evolvesFrom = "pursula",modelDisplaySize = 5.0,modelScaleMultiplier = 1.5
	},
	{
		id = "cloudwisp", displayName = "Cloudwisp", rarity = "Uncommon",
		element = "Wind", class = "Bruiser", behavior = "lone",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.0,
		description = "A raptor with wind-hardened talons that patrols mountain ridges. Its diving attacks hit like a battering ram.",
		modelName = "Cloudwisp", primaryColor = Color3.fromRGB(150, 200, 170),
		evolvesFrom = "cloudpuff",evolvesTo = "cloudsprite"
	},

	-- Wind Rare (3)
	{
		id = "hurricrane", displayName = "Hurricrane", rarity = "Rare",
		element = "Wind", class = "Mage", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		flying = true,
		description = "A manta ray that swims through the sky, trailing stormclouds. Its wing sweeps conjure devastating gales.",
		modelName = "Hurricrane", primaryColor = Color3.fromRGB(100, 180, 200),
		evolvesFrom = "gagglestand",modelDisplaySize = 8.0,modelScaleMultiplier = 2.0,crawling = true,
		mountable = true, mountType = "Flying", mountOffset = {0, 3, -1.5}, mountScale = 2.0,
	},
	{
		id = "cloudsprite", displayName = "Cloudsprite", rarity = "Rare",
		element = "Wind", class = "Mage", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		flying = true,
		description = "A manta ray that swims through the sky, trailing stormclouds. Its wing sweeps conjure devastating gales.",
		modelName = "Cloudsprite", primaryColor = Color3.fromRGB(100, 180, 200),
		evolvesFrom = "cloudpuff",modelDisplaySize = 3.0,modelScaleMultiplier = 2.0,crawling = true
	},
	{
		id = "shellshock", displayName = "Shellshock", rarity = "Rare",
		element = "Wind", class = "Assassin", behavior = "aggressive",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "A scorching desert wind given physical form. It hunts relentlessly, searing targets with superheated air currents.",
		modelName = "Shellshock", primaryColor = Color3.fromRGB(240, 220, 160),
		spawnPointType = "dungeon",evolvesTo = "strikehawk", flying = true,modelDisplaySize = 5.0,modelScaleMultiplier = 2.0
	},
	{
		id = "pursephone", displayName = "Pursephone", rarity = "Rare",
		element = "Wind", class = "Assassin", behavior = "aggressive",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "A towering fog golem that drifts through highland passes. It protects lost travelers and only retaliates when harmed.",
		modelName = "Pursephone", primaryColor = Color3.fromRGB(200, 230, 220),
		spawnPointType = "dungeon",modelDisplaySize = 7.0,modelScaleMultiplier = 2.0
	},

	-- Wind Epic (2)
	{
		id = "skydon", displayName = "Skydon", rarity = "Epic",
		element = "Wind", class = "Support", behavior = "skittish",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "Weaves healing currents from the wind itself. Extremely hard to catch.",
		modelName = "Skydon", primaryColor = Color3.fromRGB(200, 255, 220),
		spawnPointType = "dungeon", flying = true,modelDisplaySize = 15.0,
		mountable = true, mountType = "Flying", mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
	},
	{
		id = "strikehawk", displayName = "Strikehawk", rarity = "Epic",
		element = "Wind", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A massive gryphon wreathed in perpetual hurricane winds. It hunts from the eye of its own personal storm.",
		modelName = "Strikehawk", primaryColor = Color3.fromRGB(80, 200, 150),
		spawnPointType = "dungeon",modelDisplaySize = 15.0,flying = true, evolvesFrom = "shellshock",
		mountable = true, mountType = "Flying", mountOffset = {0, 3, -1.5}, mountScale = 2.0,
	},

	-- Wind Legendary (1)
	{
		id = "aerovane", displayName = "Aerovane", rarity = "Legendary",
		element = "Wind", class = "Assassin", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "The sovereign of all skies. Aerovane moves faster than sight and strikes harder than a thunderbolt. Legends say it can split mountains with a wingbeat.",
		modelName = "Aerovane", primaryColor = Color3.fromRGB(80, 255, 180),
		spawnPointType = "boss", flying = true,modelDisplaySize = 16.0,
		mountable = true, mountType = "Flying", mountOffset = {0, 4, -2}, mountScale = 2.5,
	},

	-- ============================
	-- EARTH CREATURES (5C, 4U, 3R, 2E, 1L)
	-- ============================

	-- Earth Common (5)
	{
		id = "cacty", displayName = "Cacty", rarity = "Common",
		element = "Earth", class = "Bruiser", behavior = "pack",
		spawnWeight = 20, baseIncome = 1, captureTime = 0.5, packSize = {2, 4},
		description = "A blobby little creature made of mysterious goo. Travels in packs.",
		modelName = "Cacty", primaryColor = Color3.fromRGB(120, 200, 80),
		evolvesTo = "jackedty",modelDisplaySize = 2.0,modelScaleMultiplier = 1.0
	},
	{
		id = "applehead", displayName = "Applehead", rarity = "Common",
		element = "Earth", class = "Guardian", behavior = "gentle",
		spawnWeight = 20, baseIncome = 1, captureTime = 0.5,
		description = "A tiny rock creature that rolls around aimlessly. Only fights back when provoked.",
		modelName = "AppleHead", primaryColor = Color3.fromRGB(160, 140, 110),
	},
	{
		id = "sleaf", displayName = "Sleaf", rarity = "Common",
		element = "Earth", class = "Assassin", behavior = "pack",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A hulking beast covered in razor-sharp thorns. Charges at intruders.",
		modelName = "sleaf", primaryColor = Color3.fromRGB(50, 140, 60),
		modelDisplaySize = 4.0, modelScaleMultiplier = 2.0,evolvesTo = "sleafwyrm",
	},
	{
		id = "squirebud", displayName = "Squire Bud", rarity = "Common",
		element = "Earth", class = "Assassin", behavior = "skittish",
		spawnWeight = 16, baseIncome = 1, captureTime = 0.6,
		description = "A squirrel-like creature armored in bark. Incredibly fast and flighty, it vanishes into the underbrush in a blink.",
		modelName = "SquireBud", primaryColor = Color3.fromRGB(130, 100, 60),
		evolvesTo = "floraknight",
	},
	{
		id = "pylme", displayName = "Pylme", rarity = "Common",
		element = "Earth", class = "Mage", behavior = "pack",
		spawnWeight = 15, baseIncome = 1, captureTime = 0.6, packSize = {2, 3},
		description = "Tiny mud elementals that hurl clods of enchanted earth. Their aim improves dramatically when they group up.",
		modelName = "Pylme", primaryColor = Color3.fromRGB(110, 90, 50),
		spawnPointType = "dungeon",evolvesTo = "bonoblade",
		-- Model sits left of its green circle; shift right and down to align with placement pointss
	},

	-- Earth Uncommon (4)
	{
		id = "jackedty", displayName = "Jacked'ty", rarity = "Uncommon",
		element = "Earth", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 8, baseIncome = 3, captureTime = 1.2,
		description = "An ancient stone golem draped in living moss. A true gentle giant.",
		modelName = "Jackedty", primaryColor = Color3.fromRGB(100, 160, 80),
		evolvesFrom = "cacty", evolvesTo = "cactyjackedty",modelDisplaySize = 3.0,modelScaleMultiplier = 2.0,
	},
	{
		id = "mossy", displayName = "Mossy", rarity = "Uncommon",
		element = "Earth", class = "Bruiser", behavior = "gentle",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.0,
		description = "A bearlike creature with fists of solid granite. It charges anything that enters its territory.",
		modelName = "Mossy", primaryColor = Color3.fromRGB(150, 130, 100),
	},
	{
		id = "floraknight", displayName = "Flora Knight", rarity = "Uncommon",
		element = "Earth", class = "Mage", behavior = "lone",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A serpentine creature woven from fern fronds and ancient vines. It channels nature magic to entangle prey.",
		modelName = "FloraKnight", primaryColor = Color3.fromRGB(60, 150, 50),
		evolvesFrom = "squirebud",evolvesTo = "generoot",modelDisplaySize = 5.0,modelScaleMultiplier = 1.5
	},
	{
		id = "bonoblade", displayName = "Bonoblade", rarity = "Uncommon",
		element = "Earth", class = "Assassin", behavior = "aggressive",
		spawnWeight = 8, baseIncome = 3, captureTime = 1.2,
		description = "A burrowing predator that erupts from the ground to ambush unsuspecting prey with snapping jaws.",
		modelName = "Bonoblade", primaryColor = Color3.fromRGB(100, 80, 40),
		evolvesFrom = "pylme",evolvesTo = "guerilla",modelDisplaySize = 5.0,modelScaleMultiplier = 1.5
	},

	-- Earth Rare (3)sddf
	{
		id = "generoot", displayName = "Generoot", rarity = "Rare",
		element = "Earth", class = "Bruiser", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A hulking beast covered in razor-sharp thorns. Charges at intruders.",
		modelName = "Generoot", primaryColor = Color3.fromRGB(50, 140, 60),
		evolvesFrom = "floraknight",modelDisplaySize = 8.0, modelScaleMultiplier = 2.0,
	},
	{
		id = "guerilla", displayName = "Guerilla", rarity = "Rare",
		element = "Earth", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "A regal stag with antlers of living crystal that resonate with healing frequencies. Fiercely shy and nearly impossible to corner.",
		modelName = "Guerilla", primaryColor = Color3.fromRGB(180, 200, 160),
		modelDisplaySize = 8.0,modelScaleMultiplier = 2.0,
		spawnPointType = "dungeon",
	},
	{
		id = "sleafwyrm", displayName = "Sleafwyrm", rarity = "Rare",
		element = "Earth", class = "Assassin", behavior = "lone",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A living garden on legs. Flowers and herbs grow across its shell, providing potent healing to all nearby allies.",
		modelName = "Sleafwyrm", primaryColor = Color3.fromRGB(70, 180, 70),
		spawnPointType = "dungeon",
		mountable = true, mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
		modelDisplaySize = 10,modelScaleMultiplier = 2.0,flying = true,
		evolvesFrom = "sleaf",
		evolvesTo = "dracosleaf",
	},

	-- Earth Epic (2)rfr
	{
		id = "cactyjackedty", displayName = "CactyJackedty", rarity = "Epic",
		element = "Earth", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A massive burrowing beast whose footsteps cause tremors. When it surfaces, the ground splits open around it.",
		modelName = "CactyJackedty", primaryColor = Color3.fromRGB(120, 100, 50),
		spawnPointType = "dungeon",
		evolvesFrom = "jackedty", modelDisplaySize = 8.0, modelScaleMultiplier = 2.0,
		modelPlacementYOffset = 2,  -- limbs extend below base; lift so feet sit on point
		mountable = true, mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
	},
	{
		id = "dracosleaf", displayName = "Dracosleaf", rarity = "Epic",
		element = "Earth", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "Forged in the planet's core. An immovable gentle giant.",
		modelName = "Dracosleaf", primaryColor = Color3.fromRGB(200, 160, 60),
		spawnPointType = "dungeon",modelDisplaySize = 10, modelScaleMultiplier = 2.0,
		mountable = true, mountOffset = {0, 5, -2}, mountScale = 2.5,
		evolvesFrom = "sleafwrym", flying = true,
	},

	-- Earth Legendary (1)s
	{
		id = "gymstone", displayName = "Gymstone", rarity = "Legendary",
		element = "Earth", class = "Guardian", behavior = "gentle",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "Forged in the planet's core. An immovable gentle giant.",
		modelName = "Gymstone", primaryColor = Color3.fromRGB(200, 160, 60),
		spawnPointType = "boss",modelDisplaySize = 10, modelScaleMultiplier = 2.0,
		mountable = true, mountOffset = {0, 5, -2}, mountScale = 2.5,
	},
	

	-- ============================
	-- SHADOW CREATURES (5C, 4U, 3R, 2E, 1L)
	-- ============================

	-- Shadow Common (5)
	{
		id = "echo", displayName = "Echo", rarity = "Common",
		element = "Shadow", class = "Assassin", behavior = "lone",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5, packSize = {3, 5},
		description = "Shadowy vermin that swarm in dark corners. Individually pathetic, but a pack of them can overwhelm the unprepared.",
		modelName = "Echo", primaryColor = Color3.fromRGB(80, 50, 100),
		evolvesTo = "echowing",
	},

	-- Shadow Uncommon (4)
	{
		id = "echowing", displayName = "Echowing", rarity = "Uncommon",
		element = "Shadow", class = "Assassin", behavior = "aggressive",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A bat-like hunter that drops from cave ceilings with razor talons extended. Silent until the moment of impact.",
		modelName = "Echowing", primaryColor = Color3.fromRGB(60, 30, 90),
		evolvesFrom = "echo",evolvesTo = "echolustrious",
	},
	-- Shadow Rare (3)
	{
		id = "echolustrious", displayName = "Echolustrious", rarity = "Rare",
		element = "Shadow", class = "Assassin", behavior = "lone",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "Slips between shadows. You only see it when it wants you to.",
		modelName = "Echolustrious", primaryColor = Color3.fromRGB(60, 30, 100),
		spawnPointType = "dungeon",evolvesFrom = "echowing",
	},

	-- Shadow Epic (2)
	{
		id = "umbralwyrm", displayName = "Umbralwyrm", rarity = "Epic",
		element = "Shadow", class = "Mage", behavior = "lone",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A serpentine wyrm made of living darkness. It devours light itself, casting devastating shadow magic from the void.",
		modelName = "Umbralwyrm", primaryColor = Color3.fromRGB(50, 20, 80),
		spawnPointType = "dungeon",
		mountable = true, mountType = "Flying", mountOffset = {0, 3.5, -2}, mountScale = 2.2,
	},

	-- Shadow Legendary (1)
	{
		id = "voidmaw", displayName = "Voidmaw", rarity = "Legendary",
		element = "Shadow", class = "Mage", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "An ancient horror from the space between worlds. Extremely rare and dangerous.",
		modelName = "Voidmaw", primaryColor = Color3.fromRGB(30, 0, 50),
		spawnPointType = "boss",
		mountable = true, mountOffset = {0, 4, -2}, mountScale = 2.5,
	},

	-- ============================
	-- LIGHTNING CREATURES (5C, 4U, 3R, 2E, 1L)
	-- ============================

	-- Lightning Common (5)
	{
		id = "monkwatt", displayName = "Monkwatt", rarity = "Common",
		element = "Lightning", class = "Mage", behavior = "skittish",
		spawnWeight = 17, baseIncome = 1, captureTime = 0.6,
		description = "A tiny orb of crackling electricity. It panics when approached, discharging sparks in every direction as it flees.",
		modelName = "Monkwatt", primaryColor = Color3.fromRGB(255, 240, 100),
	},
	{
		id = "newt", displayName = "Newt", rarity = "Common",
		element = "Lightning", class = "support", behavior = "lone",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5, packSize = {3, 5},
		description = "Electrified ants that march in formation. Their synchronized shocks can stun creatures many times their size.",
		modelName = "Newt", primaryColor = Color3.fromRGB(240, 220, 60),
	},
	{
		id = "staticap", displayName = "Staticap", rarity = "Common",
		element = "Lightning", class = "bruiser", behavior = "aggressive",
		spawnWeight = 16, baseIncome = 1, captureTime = 0.5,
		description = "A woodpecker whose beak delivers electric shocks. It aggressively pecks at anything shiny or metallic.",
		modelName = "Staticap", primaryColor = Color3.fromRGB(255, 200, 40), evolvesTo = "joltram",
	},
	{
		id = "blinky", displayName = "Blinky", rarity = "Common",
		element = "Lightning", class = "Guardian", behavior = "gentle",
		spawnWeight = 17, baseIncome = 1, captureTime = 0.5,
		description = "A tortoise whose shell crackles with stored static. It shocks anything that touches it, but never initiates conflict.",
		modelName = "Blinky", primaryColor = Color3.fromRGB(200, 190, 80),
	},

	-- Lightning Uncommon (4)
	{
		id = "simicircuit", displayName = "Simicircuit", rarity = "Uncommon",
		element = "Lightning", class = "Support", behavior = "pack",
		spawnWeight = 8, baseIncome = 3, captureTime = 1.2, packSize = {2, 3},
		description = "Tiny bolts arc between its tendrils, energizing allies nearby.",
		modelName = "Simicircuit", primaryColor = Color3.fromRGB(255, 245, 130),
		modelDisplaySize = 5.0,modelScaleMultiplier = 1.5
	},
	{
		id = "Joltram", displayName = "Joltram", rarity = "Uncommon",
		element = "Lightning", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.0,
		description = "A burrowing creature that erupts from the ground in a shower of electric sparks. It headbutts targets with a charged skull.",
		modelName = "Joltram", primaryColor = Color3.fromRGB(220, 200, 50),evolvesFrom = "staticap", evolvesTo = "bleetstrike",
		modelDisplaySize = 5.0,modelScaleMultiplier = 1.5
	},

	-- Lightning Rare (3)
	{
		id = "kilokong", displayName = "Kilokong", rarity = "Rare",
		element = "Lightning", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "A serpent of pure plasma that moves like living lightning. Its strikes paralyze, and it never stops hunting once it has a target.",
		modelName = "Kilokong", primaryColor = Color3.fromRGB(160, 120, 255),
		spawnPointType = "dungeon",modelDisplaySize = 12,modelScaleMultiplier = 1.5,
		mountable = true, mountOffset = {0, 3.5, -2}, mountScale = 2.0,
	},
	{
		id = "newton", displayName = "New Ton", rarity = "Rare",
		element = "Lightning", class = "Guardian", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A rhinoceros-like beast with a horn that acts as a lightning rod. Its charges are accompanied by deafening thunderclaps.",
		modelName = "Newton", primaryColor = Color3.fromRGB(200, 180, 60),modelDisplaySize = 12,modelScaleMultiplier = 1.5,evolvesFrom = "newt",
	},
	{
		id = "bleetsrike", displayName = "Bleetsrike", rarity = "Rare",
		element = "Lightning", class = "Bruiser", behavior = "lone",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "A floating jellyfish-like creature that drifts through mountain peaks, weaving devastating chain-lightning between its tendrils.",
		modelName = "Bleetsrike", primaryColor = Color3.fromRGB(140, 100, 255),
		spawnPointType = "dungeon",evolvesFrom="joltram",modemodelDisplaySize = 12,modelScaleMultiplier = 1.5,
	},

	-- Lightning Epic (2)
	{
		id = "stormclaw", displayName = "Stormclaw", rarity = "Epic",
		element = "Lightning", class = "Bruiser", behavior = "aggressive",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "Lightning crackles between its claws. Hunts anything that moves.",
		modelName = "Stormclaw", primaryColor = Color3.fromRGB(100, 80, 255),
		spawnPointType = "dungeon",
		mountable = true, mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
	},

	-- Lightning Legendary (1)
	{
		id = "thunderlord", displayName = "Thunderlord", rarity = "Legendary",
		element = "Lightning", class = "Mage", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "The living embodiment of the storm. Thunderlord calls down apocalyptic lightning from perpetual thunderheads. Where it walks, the sky itself obeys.",
		modelName = "Thunderlord", primaryColor = Color3.fromRGB(120, 80, 255),
		spawnPointType = "boss",
		mountable = true, mountType = "Flying", mountOffset = {0, 4, -2}, mountScale = 2.5,
	},

	-- ============================
	-- WATER CREATURES (5C, 4U, 3R, 2E, 1L)
	-- ============================

	-- Water Common (5)
	{
		id = "spoutyl", displayName = "Spoutyl", rarity = "Common",
		element = "Water", class = "assassin", behavior = "gentle",
		spawnWeight = 15, baseIncome = 1, captureTime = 0.5,
		description = "A tiny water spirit that heals allies with soothing droplets. Commonly found near pools and streams.",
		modelName = "Spoutyl", primaryColor = Color3.fromRGB(80, 180, 255),
		evolvesTo = "droxyl",
	},
	{
		id = "shellpack", displayName = "Shellpack", rarity = "Common",
		element = "Water", class = "support", behavior = "skittish",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.6,
		description = "A sleek creature that darts across water surfaces. Vanishes beneath the surface when startled.",
		modelName = "Shellpack", primaryColor = Color3.fromRGB(60, 160, 220),
		evolvesTo = "torqlander",
	},
	{
		id = "jawby", displayName = "Jawby", rarity = "Common",
		element = "Water", class = "Guardian", behavior = "gentle",
		spawnWeight = 16, baseIncome = 1, captureTime = 0.5,
		description = "A creature draped in kelp-like fronds. Its thick hide absorbs blows while it waits in tide pools.",
		modelName = "Jawby", primaryColor = Color3.fromRGB(40, 140, 100),
		evolvesTo = "jawbite",
	},
	{
		id = "ceeponee", displayName = "Ceeponee", rarity = "Common",
		element = "Water", class = "Bruiser", behavior = "pack",
		spawnWeight = 17, baseIncome = 1, captureTime = 0.5, packSize = {2, 4},
		description = "Ceeponee float through the winter winds and are known to be a bit shy",
		modelName = "Ceeponee", primaryColor = Color3.fromRGB(70, 170, 255),
		flying = true, evolvesTo = "ceehorcee"
	},

	-- Water Uncommon (4).
	{
		id = "droxyl", displayName = "Droxyl", rarity = "Uncommon",
		element = "Water", class = "Assassin", behavior = "pack",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A fox adapted to river life. Strikes with razor-sharp water blades from the shadows of rapids.",
		modelName = "Droxyl", primaryColor = Color3.fromRGB(90, 180, 240),
		evolvesTo = "hydroxyl", evolvesFrom = "spoutyl",modelDisplaySize = 6.0,modelScaleMultiplier = 1.5,
	},
	{
		id = "clawkid", displayName = "Clawkid", rarity = "Uncommon",
		element = "Water", class = "Guardian", behavior = "pack",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.0,
		description = "A turtle-like creature with a coral shell. Its hardened armor deflects most attacks.",
		modelName = "Clawkid", primaryColor = Color3.fromRGB(255, 100, 100),
		evolvesTo = "clawqueen",modelDisplaySize = 5.0,modelScaleMultiplier = 1.5,
	},
	{
		id = "torqlander", displayName = "Torqlander", rarity = "Uncommon",
		element = "Water", class = "Mage", behavior = "lone",
		spawnWeight = 8, baseIncome = 3, captureTime = 1.2,
		description = "Emerges from morning mist to strike with condensed water bolts. Fades back into fog when threatened.",
		modelName = "Torqlander", primaryColor = Color3.fromRGB(180, 210, 255),
		evolvesTo = "shellnaut",modelDisplaySize = 4.0,modelScaleMultiplier = 1.5,
		evolvesFrom = "shellpack",flying = true,
	},
	{
		id = "ceehorcee", displayName = "Ceehorcee", rarity = "Uncommon",
		element = "Water", class = "Assassin", behavior = "pack",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A translucent predator that blends into ice fields. By the time you see it, its fangs are already at your throat.",
		modelName = "Ceehorcee", primaryColor = Color3.fromRGB(100, 170, 230),flying = true, evolvesTo ="ceesteed", evolvesFrom = "ceeponee",
		modelDisplaySize = 5.0,modelScaleMultiplier = 1.5,
	},

	-- Water Rare (3)
	{
		id = "hydroxyl", displayName = "Hydroxyl", rarity = "Rare",
		element = "Water", class = "Assassin", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A serpent that flows like water. Constricts and drowns prey in whirlpools of its own making.",
		modelName = "Hydroxyl", primaryColor = Color3.fromRGB(40, 120, 200),
		spawnPointType = "dungeon", evolvesFrom = "droxyl",modelDisplaySize = 10,modelScaleMultiplier = 1.5,
		mountable = true,
	},
	{
		id = "Shellnaut", displayName = "Shellnaut", rarity = "Rare",
		element = "Water", class = "Guardian", behavior = "lone",
		spawnWeight = 4, baseIncome = 8, captureTime = 2.0,
		description = "A massive crab-like guardian. Rises with the tide to shield allies behind walls of water.",
		modelName = "Shellnaut", primaryColor = Color3.fromRGB(60, 140, 220),
		spawnPointType = "dungeon",modelDisplaySize = 10,modelScaleMultiplier = 1.5,
		evolvesFrom = "torqlander",mountable = true,
	},
	{
		id = "jawbite", displayName = "Jawbite", rarity = "Rare",
		element = "Water", class = "Support", behavior = "gentle",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "Summons healing rains and cleansing waves. Allies fight longer when a Brinecaller watches over them.",
		modelName = "Jawbite", primaryColor = Color3.fromRGB(80, 160, 240),modelDisplaySize = 10,modelScaleMultiplier = 1.5,
		evolvesFrom = "jawby",
	},

	-- Water Epic (2)
	{
		id = "clawqueen", displayName = "Claw Queen", rarity = "Epic",
		element = "Water", class = "Mage", behavior = "aggressive",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "Commands storm surges and lightning-struck seas. Its tidal blasts devastate entire shorelines.",
		modelName = "Clawqueen", primaryColor = Color3.fromRGB(50, 100, 200),
		spawnPointType = "dungeon",modelDisplaySize = 12,modelScaleMultiplier = 1.5,
		mountable = true, mountType = "Swimming", mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
		evolvesFrom = "clawkid",
	},
	{
		id = "ceesteed", displayName = "Ceesteed", rarity = "Epic",
		element = "Ice", class = "Guardian", behavior = "gentle",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A massive yeti-like creature of compacted snow. It ignores most threats, but when provoked, nothing stops it.",
		modelName = "Ceesteed", primaryColor = Color3.fromRGB(180, 210, 240),
		spawnPointType = "dungeon",evolvesFrom = "ceehorcee",modelDisplaySize = 8.0,modelScaleMultiplier = 2.0,
		mountable = true, mountOffset = {0, 3.5, -1.5}, mountScale = 2.2,
	},

	-- Water Legendary (1)
	{
		id = "conchious", displayName = "Conchious", rarity = "Legendary",
		element = "Water", class = "Mage", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "The sovereign of the darkest depths. Abyssalking controls pressure, cold, and crushing darkness. Few who dive deep ever return.",
		modelName = "Conchious", primaryColor = Color3.fromRGB(20, 50, 120),
		spawnPointType = "boss",modelDisplaySize = 13,modelScaleMultiplier = 1.5,
		mountable = true, mountType = "Swimming", mountOffset = {0, 4, -2}, mountScale = 2.5,
	},

	-- ============================
	-- STAND-IN SIEGLINGS (placeholder until full rosters exist)
	-- Evolve chains among stand-ins: Light, Poison, Undead only (not Psychic / Metal).
	-- ============================

	-- Light stand-ins (evolve chain only for this element among stand-ins)
	{
		id = "light_siegling_standin", displayName = "Light Siegling", rarity = "Common",
		element = "Light", class = "Support", behavior = "gentle",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5,
		description = "A radiant placeholder Siegling. Full Light roster coming soon.",
		modelName = "Egg", primaryColor = Color3.fromRGB(255, 250, 200),
		evolvesTo = "light_daybreak",
	},
	{
		id = "light_daybreak", displayName = "Light Siegling (Daybreak)", rarity = "Uncommon",
		element = "Light", class = "Support", behavior = "gentle",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.1,
		description = "Brighter placeholder form on the Light evolve path.",
		modelName = "Egg", primaryColor = Color3.fromRGB(255, 248, 210),
		evolvesFrom = "light_siegling_standin", evolvesTo = "light_solbanner",
	},
	{
		id = "light_solbanner", displayName = "Light Siegling (Solbanner)", rarity = "Rare",
		element = "Light", class = "Guardian", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "Rare capstone of the Light stand-in line.",
		modelName = "Egg", primaryColor = Color3.fromRGB(255, 245, 190),
		spawnPointType = "dungeon",
		evolvesFrom = "light_daybreak",
	},
	-- Psychic stand-ins (full rarity spread)
	-- Psychic Common (5)
	{
		id = "mentaroo", displayName = "Mentaroo", rarity = "Common",
		element = "Psychic", class = "Mage", behavior = "gentle",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5,
		description = "A mind-touched placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "Mentaroo", primaryColor = Color3.fromRGB(200, 150, 255),
	},
	{
		id = "luvy", displayName = "Luvy", rarity = "Common",
		element = "Psychic", class = "Support", behavior = "skittish",
		spawnWeight = 17, baseIncome = 1, captureTime = 0.5,
		description = "A mind-touched placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "Luvy", primaryColor = Color3.fromRGB(195, 145, 250),
		evolvesTo = "luvysore",
	},
	{
		id = "papap", displayName = "Papap", rarity = "Common",
		element = "Psychic", class = "Assassin", behavior = "lone",
		spawnWeight = 16, baseIncome = 1, captureTime = 0.5,
		description = "A mind-touched placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "papap", primaryColor = Color3.fromRGB(205, 160, 255),
	},
	{
		id = "ragguette", displayName = "Ragguette", rarity = "Common",
		element = "Psychic", class = "Support", behavior = "skittish",
		spawnWeight = 15, baseIncome = 1, captureTime = 0.5,
		description = "A mind-touched placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "Ragguette", primaryColor = Color3.fromRGB(190, 140, 245),
	},
	-- Psychic Uncommon (4)
	{
		id = "luvysore", displayName = "Luvysore", rarity = "Uncommon",
		element = "Psychic", class = "Support", behavior = "lone",
		spawnWeight = 9, baseIncome = 3, captureTime = 1.1,
		description = "A mind-touched placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "LuvySore", primaryColor = Color3.fromRGB(205, 155, 255),
		evolvesFrom = "luvy",evolvesTo = "luvyduvysore",modelDisplaySize = 4,modelScaleMultiplier = 1.5,
	},
	-- Psychic Rare (3)
	{
		id = "psychic_siegling_r1", displayName = "Psychic Siegling R1", rarity = "Rare",
		element = "Psychic", class = "Mage", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A mind-touched placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "mentaroo", primaryColor = Color3.fromRGB(210, 165, 255),
		spawnPointType = "dungeon",
	},
	-- Psychic Epic (2)
	{
		id = "luvyduvysore", displayName = "Luvy Duvysore", rarity = "Epic",
		element = "Psychic", class = "Mage", behavior = "lone",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A powerful placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "LuvyDuvySore", primaryColor = Color3.fromRGB(220, 175, 255),
		spawnPointType = "dungeon",evolvesFrom = "luvysore",modelDisplaySize = 8,modelScaleMultiplier = 1.5,
	},
	-- Psychic Legendary (1)
	{
		id = "psychic_siegling_l1", displayName = "Psychic Siegling L1", rarity = "Legendary",
		element = "Psychic", class = "Mage", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "A sovereign placeholder Siegling. Full Psychic roster coming soon.",
		modelName = "mentaroo", primaryColor = Color3.fromRGB(230, 185, 255),
		spawnPointType = "boss",
	},
	-- Metal stand-ins (full rarity spread)
	-- Metal Common (5)
	{
		id = "bearby", displayName = "Bearby", rarity = "Common",
		element = "Metal", class = "Guardian", behavior = "gentle",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5,
		description = "A metallic placeholder Siegling. Full Metal roster coming soon.",
		modelName = "Bearby", primaryColor = Color3.fromRGB(160, 170, 180),
		evolvesTo = "bearnade",
	},
	-- Metal Uncommon (4)
	{
		id = "bearnade", displayName = "Bearnade", rarity = "Uncommon",
		element = "Metal", class = "Guardian", behavior = "gentle",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.1,
		description = "A metallic placeholder Siegling. Full Metal roster coming soon.",
		modelName = "Bearnade", primaryColor = Color3.fromRGB(170, 180, 190),modelDisplaySize = 5,modelScaleMultiplier = 1.5,
		evolvesFrom = "bearby",evolvesTo = "bearzooka",
	},
	-- Metal Rare (3)d
	{
		id = "bearzooka", displayName = "Bearzooka", rarity = "Rare",
		element = "Metal", class = "Guardian", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "A reinforced placeholder Siegling. Full Metal roster coming soon.",
		modelName = "Bearzooka", primaryColor = Color3.fromRGB(175, 185, 195),
		spawnPointType = "dungeon",evolvesFrom = "bearnade",modelDisplaySize = 12,modelScaleMultiplier = 1.5,
	},
	-- Metal Epic (2)
	{
		id = "metal_siegling_e1", displayName = "Metal Siegling E1", rarity = "Epic",
		element = "Metal", class = "Guardian", behavior = "lone",
		spawnWeight = 2, baseIncome = 20, captureTime = 2.5,
		description = "A hardened placeholder Siegling. Full Metal roster coming soon.",
		modelName = "Egg", primaryColor = Color3.fromRGB(180, 190, 200),
		spawnPointType = "dungeon",
	},
	-- Metal Legendary (1)
	{
		id = "metal_siegling_l1", displayName = "Metal Siegling L1", rarity = "Legendary",
		element = "Metal", class = "Guardian", behavior = "lone",
		spawnWeight = 1, baseIncome = 50, captureTime = 3.5,
		description = "An indomitable placeholder Siegling. Full Metal roster coming soon.",
		modelName = "Egg", primaryColor = Color3.fromRGB(190, 200, 210),
		spawnPointType = "boss",
	},
	-- Poison stand-ins (evolve chain only for this element among stand-ins)
	{
		id = "poison_siegling_standin", displayName = "Poison Siegling", rarity = "Common",
		element = "Poison", class = "Assassin", behavior = "skittish",
		spawnWeight = 1, baseIncome = 1, captureTime = 0.5,
		description = "A toxic placeholder Siegling. Full Poison roster coming soon.",
		modelName = "Egg", primaryColor = Color3.fromRGB(120, 220, 80),
		evolvesTo = "poison_venomidge",
	},
	{
		id = "poison_venomidge", displayName = "Poison Siegling (Venomidge)", rarity = "Uncommon",
		element = "Poison", class = "Assassin", behavior = "skittish",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.1,
		description = "Uncommon step on the Poison stand-in evolve path.",
		modelName = "Egg", primaryColor = Color3.fromRGB(125, 225, 75),
		evolvesFrom = "poison_siegling_standin", evolvesTo = "poison_venomapex",
	},
	{
		id = "poison_venomapex", displayName = "Poison Siegling (Venomapex)", rarity = "Rare",
		element = "Poison", class = "Assassin", behavior = "aggressive",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "Rare capstone of the Poison stand-in line.",
		modelName = "Egg", primaryColor = Color3.fromRGB(115, 220, 70),
		spawnPointType = "dungeon",
		evolvesFrom = "poison_venomidge",
	},
	-- Undead stand-ins (evolve chain only for this element among stand-ins).
	{
		id = "spookyweed", displayName = "Spooky Weed", rarity = "Common",
		element = "Undead", class = "Bruiser", behavior = "lone",
		spawnWeight = 18, baseIncome = 1, captureTime = 0.5,
		description = "An undead placeholder Siegling. Full Undead roster coming soon.",
		modelName = "Spookyweed", primaryColor = Color3.fromRGB(140, 120, 160),
		evolvesTo = "livingwood",
	},
	{
		id = "livingwood", displayName = "Living Wood", rarity = "Uncommon",
		element = "Undead", class = "Mage", behavior = "lone",
		spawnWeight = 10, baseIncome = 3, captureTime = 1.1,
		description = "Uncommon step on the Undead stand-in evolve path.",
		modelName = "livingwood", primaryColor = Color3.fromRGB(135, 115, 155),
		evolvesFrom = "spookyweed",
	},
	{
		id = "golor", displayName = "Golor", rarity = "Rare",
		element = "Undead", class = "Guardian", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "Rare capstone of the Undead stand-in line.",
		modelName = "Golor", primaryColor = Color3.fromRGB(100, 85, 120),
		spawnPointType = "dungeon",modelDisplaySize = 8, modelScaleMultiplier = 2.0,
	},
	{
		id = "sheenx", displayName = "Sheenx", rarity = "Epic",
		element = "Undead", class = "Guardian", behavior = "lone",
		spawnWeight = 5, baseIncome = 8, captureTime = 1.8,
		description = "Rare capstone of the Undead stand-in line.",
		modelName = "Sheenx", primaryColor = Color3.fromRGB(100, 85, 120),
		spawnPointType = "dungeon",modelDisplaySize = 12, modelScaleMultiplier = 2.0,
	},
}

for _, c in ipairs(CreatureData.Creatures) do
	local s = CreatureData.AllocateBaseStats(c.rarity, c.class, c.element, c.id)
	c.health = s.health
	c.attack = s.attack
	c.defense = s.defense
	c.speed = s.speed
end

for _, c in ipairs(CreatureData.Creatures) do
	local sum = c.health + c.attack + c.defense + c.speed
	local expected = CreatureData.RarityStatBudget[c.rarity]
	assert(
		expected and sum == expected,
		("[CreatureData] %s stat sum %d ~= rarity budget %s"):format(
			tostring(c.id),
			sum,
			tostring(expected)
		)
	)
end

-- ======================================
-- LOOKUP HELPERS
-- ======================================
-- These rebuild automatically from the Creatures table.
-- After adding a creature, these work with no additional changes....

-- Fast O(1) lookup by creature id
CreatureData._byId = {}
for _, creature in ipairs(CreatureData.Creatures) do
	CreatureData._byId[creature.id] = creature
end

-- Get a creature definition by its unique id
-- Returns: creature table or nil
function CreatureData.GetById(id)
	return CreatureData._byId[id]
end

-- Get all creature definitions
-- Returns: array of creature tables
function CreatureData.GetAll()
	return CreatureData.Creatures
end

-- Get the coin cost to capture a creature of a given rarity..
-- Returns: number
function CreatureData.GetCaptureCost(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then return 0 end
	local rarityInfo = CreatureData.Rarities[info.rarity]
	return rarityInfo and rarityInfo.captureCost or 10
end

-- ======================================
-- EVOLUTION & VARIANT (COMBINE) HELPERS
-- ======================================

-- Get the next variant tier when combining 3 of same (Normal→Silver→Gold→Legend). Returns nil if already Legend.
function CreatureData.GetNextVariant(variant)
	if variant == "Legend" then return nil end
	local order = CreatureData.VariantOrder
	if not order or not order[variant] then return "Silver" end
	local nextIdx = order[variant] + 1
	for name, idx in pairs(order) do
		if idx == nextIdx then return name end
	end
	return nil
end

-- Stat multiplier for variant tier (Silver/Gold/Legend stronger than Normal)
function CreatureData.GetVariantStatMultiplier(variant)
	if not variant or variant == "Normal" then return 1.0 end
	local mult = { Silver = 1.15, Gold = 1.35, Legend = 1.6 }
	return mult[variant] or 1.0
end

-- Check if creature has a next stage in data (may still be unavailable in-game)
function CreatureData.CanEvolve(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.evolvesTo ~= nil
end

-- Check if evolution is actually available in-game: has next stage, not marked "coming soon", and target has a model.
-- Use this for UI (show Evolve button) and server validation. Creatures without evolvesTo never show evolve.
-- Set evolutionComingSoon = true on a creature to disable evolving until the next stage is ready.
function CreatureData.CanEvolveInGame(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info or not info.evolvesTo then return false end
	if info.evolutionComingSoon == true then return false end
	local nextInfo = CreatureData.GetById(info.evolvesTo)
	if not nextInfo then return false end
	return CreatureData.CreatureHasModel(nextInfo)
end

-- Get the creature id this evolves into, or nil
function CreatureData.GetEvolvesTo(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.evolvesTo or nil
end

-- Get the creature id this evolved from, or nil
function CreatureData.GetEvolvesFrom(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.evolvesFrom or nil
end

-- Max level depends on evolution stage: base=10, evolved=25, final=50 (avoids require(GameConfig) to prevent recursive require crash)
function CreatureData.GetMaxCreatureLevel(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then return 10 end
	local baseMax, evolvedMax, finalMax = 10, 25, 50

	if not info.evolvesFrom then return baseMax end   -- base form
	if CreatureData.CanEvolveInGame(creatureId) then return evolvedMax end  -- can evolve again
	return finalMax  -- final form
end

-- ======================================
-- SPAWN SELECTION HELPERS
-- ======================================
-- Used by CreatureSpawner.lua to pick which creature to spawn
-- at different point types (SpawnPoint, DungeonPoint, BossPoint).

-- Rotation offset for models: stand-up (if lying) + yaw + crawling (only when walking).
-- creature can be creature table or creature id string.
-- context: "world" (default) for world spawns / CreatureAI; "companion" for FavoriteCreatureSystem (PivotTo/model-based).
-- isWalking: when true and creature has crawling, add 90° pitch for belly-crawl during Move animation only.
function CreatureData.GetModelRotationOffset(creature, context, isWalking)
	local info = type(creature) == "string" and CreatureData.GetById(creature) or creature
	if not info then return CFrame.identity end
	local standUp = CFrame.identity
	if info.modelStandUpAngles and #info.modelStandUpAngles >= 3 then
		standUp = CFrame.Angles(
			math.rad(info.modelStandUpAngles[1]),
			math.rad(info.modelStandUpAngles[2]),
			math.rad(info.modelStandUpAngles[3])
		)
	end
	local yaw = info.modelRotationY and CFrame.Angles(0, math.rad(info.modelRotationY), 0) or CFrame.identity
	-- Crawling: only during walking for world context. Companion crawl is handled separately
	-- in FavoriteCreatureSystem.getCompanionRotationOffset() because PivotTo-based positioning
	-- requires a different rotation approach than direct body.CFrame assignment (FIX #15).
	local crawlDeg = nil
	if info.crawling == true and isWalking and context ~= "companion" then
		crawlDeg = -90
	end
	local crawl = crawlDeg and CFrame.Angles(math.rad(crawlDeg), 0, 0) or CFrame.identity
	return standUp * yaw * crawl
end

-- Extra Y offset (studs) when placing creature on base defense/income points.
-- Use for models whose limbs extend below their base (e.g. CactyJackedty).
-- Returns 0 if not set.
function CreatureData.GetModelPlacementYOffset(creature)
	local info = type(creature) == "string" and CreatureData.GetById(creature) or creature
	if not info or type(info.modelPlacementYOffset) ~= "number" then return 0 end
	return info.modelPlacementYOffset
end

-- Full 3D placement offset (studs) when placing creature on base points.
-- Use when a model renders on the wrong point (e.g. shifted left/right from its green circle).
-- Returns Vector3.zero if not set. Accepts Vector3 or {x,y,z} in data.
function CreatureData.GetModelPlacementOffset(creature)
	local info = type(creature) == "string" and CreatureData.GetById(creature) or creature
	if not info then return Vector3.zero end
	local o = info.modelPlacementOffset
	if not o then return Vector3.zero end
	-- Luau: type(Vector3) is "Vector3", not "userdata"
	if type(o) == "Vector3" then return o end
	if type(o) == "table" and type(o.X) == "number" then return Vector3.new(o.X, o.Y or 0, o.Z or 0) end
	if type(o) == "table" and o[1] then return Vector3.new(o[1], o[2] or 0, o[3] or 0) end
	if type(o) == "userdata" and o.X then return o end
	return Vector3.zero
end

-- Returns true if creature is a flying type (hovers at player height above ground)
function CreatureData.IsFlying(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.flying == true
end

-- Returns true if creature can swim in water (Water element only). Used for companion recall when player swims.
-- Ice creatures are carded like Fire/Earth when player enters water.
function CreatureData.IsWaterType(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info or not info.element then return false end
	return info.element == "Water"
end

-- Returns true if creature uses crawling orientation (model rotated 90° forward for belly-crawl walk)
function CreatureData.IsCrawling(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.crawling == true
end

-- Returns true if creature should only use belly-crawl during Move, not Attack (stand upright when attacking)
function CreatureData.CrawlOnlyOnMove(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.crawlOnlyOnMove == true
end

-- ======================================
-- MOUNT HELPERS
-- ======================================

-- Returns true if creature can be ridden as a mount
function CreatureData.IsMountable(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.mountable == true
end

-- Returns mount type: "Ground", "Flying", "Swimming", or "Special".
-- Auto-derives from flying/element if mountType not explicitly set.
function CreatureData.GetMountType(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info or not info.mountable then return nil end
	if info.mountType then return info.mountType end
	if info.flying then return "Flying" end
	if info.element == "Water" or info.element == "Ice" then return "Swimming" end
	return "Ground"
end

-- Returns Vector3 offset for player seat position relative to creature body center.
-- Accepts {x,y,z} table or Vector3 in data. Default {0, 3, -1}.
function CreatureData.GetMountOffset(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then return Vector3.new(0, 3, -1) end
	local o = info.mountOffset
	if not o then return Vector3.new(0, 3, -1) end
	if typeof(o) == "Vector3" then return o end
	if type(o) == "table" and o[1] then return Vector3.new(o[1], o[2] or 0, o[3] or 0) end
	return Vector3.new(0, 3, -1)
end

-- Returns visual scale multiplier for mount model (default 2.0)
function CreatureData.GetMountScale(creatureId)
	local info = CreatureData.GetById(creatureId)
	return (info and info.mountScale) or 2.0
end

-- Returns flat speed bonus for mount (default 0)
function CreatureData.GetMountSpeedBonus(creatureId)
	local info = CreatureData.GetById(creatureId)
	return (info and info.mountSpeedBonus) or 0
end

-- Returns array of elemental bonuses active while riding this creature.
-- Bonus strings: "LavaImmunity", "NoOxygenLoss", "IcePenaltyImmunity",
--   "ElectricHazardImmunity", "GlideBonus", "Flight", "SwimMount"
function CreatureData.GetMountBonuses(creatureId)
	local info = CreatureData.GetById(creatureId)
	if not info then return {} end
	local bonuses = {}
	local elem = info.element
	if elem == "Fire" then table.insert(bonuses, "LavaImmunity") end
	if elem == "Water" then table.insert(bonuses, "NoOxygenLoss") end
	if elem == "Ice" then table.insert(bonuses, "IcePenaltyImmunity") end
	if elem == "Lightning" then table.insert(bonuses, "ElectricHazardImmunity") end
	if elem == "Wind" then table.insert(bonuses, "GlideBonus") end
	local mountType = CreatureData.GetMountType(creatureId)
	if mountType == "Flying" then table.insert(bonuses, "Flight") end
	if mountType == "Swimming" then table.insert(bonuses, "SwimMount") end
	return bonuses
end

-- Returns true if creature has a model in ReplicatedStorage.CreatureModels
function CreatureData.CreatureHasModel(creature)
	if not creature or not creature.modelName then return false end
	local mod = game:GetService("ReplicatedStorage"):FindFirstChild("Modules")
		and game.ReplicatedStorage.Modules:FindFirstChild("CreatureModelLoader")
	if mod then
		return require(mod).HasTemplate(creature.modelName, creature.displayName)
	end
	local mf = game.ReplicatedStorage:FindFirstChild("CreatureModels")
	return mf and (mf:FindFirstChild(creature.modelName) or (creature.displayName and mf:FindFirstChild(creature.displayName)))
end

-- Pick a random creature for regular SpawnPoints (weighted by spawnWeight).
-- preferCommon: when true, Common/Uncommon get 3x weight so SpawnPoints stay abundant with common monsters
-- onlyWithModels: when true, only consider creatures that have models in CreatureModels
-- Returns: creature id string
function CreatureData.GetRandomCreatureId(onlyWithModels, preferCommon)
	local totalWeight = 0
	local weights = {}
	for _, creature in ipairs(CreatureData.Creatures) do
		if not creature.spawnPointType then
			if not onlyWithModels or CreatureData.CreatureHasModel(creature) then
				local w = creature.spawnWeight or 10
				if preferCommon then
					if creature.rarity == "Common" then w = w * 3
					elseif creature.rarity == "Uncommon" then w = w * 2
					else w = w * 0.3 end  -- Rare+ much less common at SpawnPoints
				end
				weights[creature] = w
				totalWeight = totalWeight + w
			end
		end
	end
	if totalWeight <= 0 then
		for _, creature in ipairs(CreatureData.Creatures) do
			if not creature.spawnPointType then return creature.id end
		end
		return CreatureData.Creatures[1].id
	end
	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, creature in ipairs(CreatureData.Creatures) do
		if not creature.spawnPointType and (not onlyWithModels or CreatureData.CreatureHasModel(creature)) then
			cumulative = cumulative + (weights[creature] or creature.spawnWeight)
			if roll <= cumulative then return creature.id end
		end
	end
	for _, creature in ipairs(CreatureData.Creatures) do
		if not creature.spawnPointType and (not onlyWithModels or CreatureData.CreatureHasModel(creature)) then
			return creature.id
		end
	end
	return CreatureData.Creatures[1].id
end

-- Pick a random creature for a DungeonPoint in a specific element's biome.
-- DungeonPoints spawn harder encounters:
--   1. Creatures with spawnPointType = "dungeon" of that element
--   2. Regular creatures of that element with rarity >= Rare
-- Weighted by spawnWeight. Boss creatures are excluded.
-- onlyWithModels: when true, only consider creatures that have models
-- Returns: creature id string or nil
function CreatureData.GetDungeonCreatureId(element, onlyWithModels)
	local pool = {}
	local totalWeight = 0

	for _, creature in ipairs(CreatureData.Creatures) do
		if creature.element == element then
			local isDungeonType = (creature.spawnPointType == "dungeon")
			local rarityRank = CreatureData.RarityOrder[creature.rarity] or 0
			local isRareOrHigher = rarityRank >= CreatureData.RarityOrder["Rare"]
			-- Include if: marked as dungeon spawn, OR rare+ but not a boss
			if isDungeonType or (isRareOrHigher and creature.spawnPointType ~= "boss") then
				if not onlyWithModels or CreatureData.CreatureHasModel(creature) then
					table.insert(pool, creature)
					totalWeight = totalWeight + creature.spawnWeight
				end
			end
		end
	end

	if #pool == 0 then return nil end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, creature in ipairs(pool) do
		cumulative = cumulative + creature.spawnWeight
		if roll <= cumulative then return creature.id end
	end
	return pool[1].id
end

-- Get the legendary boss creature for a specific element (for BossPoints).
-- Each element has exactly one Legendary with spawnPointType = "boss".
-- onlyWithModels: when true, return nil if the boss has no model (caller may skip spawn)
-- Returns: creature id string or nil
function CreatureData.GetBossCreatureId(element, onlyWithModels)
	for _, creature in ipairs(CreatureData.Creatures) do
		if creature.element == element
			and creature.rarity == "Legendary"
			and creature.spawnPointType == "boss" then
			if not onlyWithModels or CreatureData.CreatureHasModel(creature) then
				return creature.id
			end
			return nil  -- boss exists but has no model, skip
		end
	end
	return nil
end

-- Get all creatures of a specific element.
-- Useful for event systems that spawn creatures in foreign biomes.
-- Returns: array of creature tables
function CreatureData.GetCreaturesByElement(element)
	local result = {}
	for _, creature in ipairs(CreatureData.Creatures) do
		if creature.element == element then
			table.insert(result, creature)
		end
	end
	return result
end

-- Get all creatures of a specific rarity.
-- Returns: array of creature tables
function CreatureData.GetCreaturesByRarity(rarity)
	local result = {}
	for _, creature in ipairs(CreatureData.Creatures) do
		if creature.rarity == rarity then
			table.insert(result, creature)
		end
	end
	return result
end

-- Rarity chain for Recycler: next tier up (Common→Uncommon→Rare→Epic→Legendary). Returns nil if already Legendary.
local RARITY_CHAIN = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
function CreatureData.GetNextRarity(rarity)
	for i, r in ipairs(RARITY_CHAIN) do
		if r == rarity and i < #RARITY_CHAIN then return RARITY_CHAIN[i + 1] end
	end
	return nil
end

-- Return a random creature id of the given rarity (for Recycler "egg" reward).
function CreatureData.GetRandomCreatureIdByRarity(rarity)
	local list = CreatureData.GetCreaturesByRarity(rarity)
	if not list or #list == 0 then return nil end
	return list[math.random(#list)].id
end

-- Reverse lookup: biome folder name -> one element (first match; ambiguous on dual outer biomes).
-- For outer dual biomes, CreatureSpawner uses OuterBiomePrimarySecondary + * / *2 parts instead.
-- Returns: element string or nil
function CreatureData.GetElementForBiomeFolder(biomeFolderName)
	for zone, folderName in pairs(CreatureData.ZoneBiomeFolder) do
		if folderName == biomeFolderName then
			for element, zoneName in pairs(CreatureData.ZonePreference) do
				if zoneName == zone then return element end
			end
		end
	end
	-- Check aliases (e.g. WaterBiome, OceanBiome -> Water)
	local aliases = CreatureData.ZoneBiomeFolderAliases
	if aliases then
		for zone, names in pairs(aliases) do
			for _, name in ipairs(names) do
				if name == biomeFolderName then
					for element, zoneName in pairs(CreatureData.ZonePreference) do
						if zoneName == zone then return element end
					end
				end
			end
		end
	end
	return nil
end

-- ======================================
-- SYNERGY CALCULATION
-- ======================================

-- Calculate active synergies from a list of creature IDs
-- Returns: activeSynergies array, elementCounts table, classCounts table
function CreatureData.CalculateSynergies(creatureIds)
	local elementCounts = {}
	local classCounts = {}

	for _, cid in ipairs(creatureIds) do
		local info = CreatureData.GetById(cid)
		if info then
			elementCounts[info.element] = (elementCounts[info.element] or 0) + 1
			classCounts[info.class] = (classCounts[info.class] or 0) + 1
		end
	end

	local active = {}

	for element, count in pairs(elementCounts) do
		local synDef = CreatureData.Synergies[element]
		if synDef then
			local bestTier = nil
			for _, tier in ipairs(synDef) do
				if count >= tier.count then bestTier = tier end
			end
			if bestTier then
				table.insert(active, {
					trait = element, traitType = "element", count = count,
					label = bestTier.label, bonuses = bestTier.bonuses,
					color = CreatureData.Elements[element].color,
				})
			end
		end
	end

	for class, count in pairs(classCounts) do
		local synDef = CreatureData.Synergies[class]
		if synDef then
			local bestTier = nil
			for _, tier in ipairs(synDef) do
				if count >= tier.count then bestTier = tier end
			end
			if bestTier then
				table.insert(active, {
					trait = class, traitType = "class", count = count,
					label = bestTier.label, bonuses = bestTier.bonuses,
					color = CreatureData.Classes[class].color,
				})
			end
		end
	end

	return active, elementCounts, classCounts
end

-- Elemental weakness chart:
--   Fire → Ice → Earth → Wind → Fire (cycle)
--   Quad 1: Water strong vs Fire, Earth; weak vs Ice, Lightning. Lightning strong vs Ice, Water; weak vs Earth, Metal.
--   Metal strong vs Earth, Wind, Lightning; weak vs Fire, Lightning. Poison strong vs Water, Earth; weak vs Metal, Fire.
--   Quad 2 (4-cycle): Light → Shadow → Psychic → Undead → Light; each 1 strong, 1 weak.
-- Returns damage multiplier: >1 when attacker has advantage, <1 when defender has advantage, 1 when neutral.
-- Tuning is in GameConfig (ElementalAdvantageMultiplier / ElementalDisadvantageMultiplier); callers apply those if desired.
local function elementBeats(attacker, defender, beats)
	local a = beats[attacker]
	if not a then return false end
	if type(a) == "string" then return a == defender end
	for _, d in ipairs(a) do if d == defender then return true end end
	return false
end
function CreatureData.GetElementalDamageMultiplier(attackerElement, defenderElement)
	attackerElement = attackerElement or "Fire"
	defenderElement = defenderElement or "Fire"
	local beats = {
		-- Fire → Ice → Earth → Wind → Fire cycle; Quad 1 (Water, Lightning, Metal, Poison)
		Fire     = { "Ice", "Poison", "Metal" },
		Ice      = { "Earth", "Water" },
		Earth    = { "Wind", "Lightning" },
		Wind     = "Fire",
		Water    = { "Fire", "Earth" },
		Lightning = { "Ice", "Water" },
		Metal    = { "Earth", "Wind", "Lightning" },
		Poison   = { "Water", "Earth" },
		-- Quad 2: 4-cycle Light → Shadow → Psychic → Undead → Light
		Light   = "Shadow",
		Shadow  = "Psychic",
		Psychic = "Undead",
		Undead  = "Light",
	}
	if elementBeats(attackerElement, defenderElement, beats) then
		return 1.5  -- advantage
	end
	if elementBeats(defenderElement, attackerElement, beats) then
		return 0.5  -- disadvantage
	end
	return 1.0
end

-- Calculate stats with synergy bonuses applied
-- Returns: { health, attack, defense, speed } table or nil
function CreatureData.GetBoostedStats(creatureId, activeSynergies)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end
	local stats = { health = info.health, attack = info.attack, defense = info.defense, speed = info.speed }
	for _, syn in ipairs(activeSynergies) do
		for stat, mult in pairs(syn.bonuses) do
			if stats[stat] then stats[stat] = stats[stat] + (info[stat] * mult) end
		end
	end
	stats.health = math.floor(stats.health)
	stats.attack = math.floor(stats.attack)
	stats.defense = math.floor(stats.defense)
	stats.speed = math.floor(stats.speed)
	return stats
end

return CreatureData
