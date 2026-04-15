-- AchievementsConfig.lua - ReplicatedStorage.Modules (ModuleScript)
-- Generated achievement definitions and chain metadata for Siegelings.

local CreatureData = require(script.Parent:WaitForChild("CreatureData"))
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local AchievementsConfig = {}

local function defaultRewardData(tierIndex, titleEarned)
	local tier = math.clamp(tonumber(tierIndex) or 1, 1, 5)
	local gemsTable = GameConfig.AchievementGemsByTier or { 5, 12, 24, 45, 80 }
	local xpTable = GameConfig.AchievementXPByTier or { 35, 75, 140, 230, 350 }
	local gems = gemsTable[tier] or gemsTable[#gemsTable]
	local xp = xpTable[tier] or xpTable[#xpTable]
	return {
		type = "title",
		title = titleEarned,
		gems = gems,
		xp = xp,
		future = { coins = 0, cosmetics = {} },
	}
end

AchievementsConfig.TierLabels = { "I", "II", "III", "IV", "V" }

AchievementsConfig.Categories = {
	Capture = {
		label = "Capture",
		accent = Color3.fromRGB(255, 196, 84),
		order = 1,
		description = "Fill the royal card ledger with Siegelings from every walk of life.",
	},
	Evolution = {
		label = "Evolution",
		accent = Color3.fromRGB(145, 214, 255),
		order = 2,
		description = "Guide lines through their ascensions and complete mighty evolution trees.",
	},
	Collection = {
		label = "Collection",
		accent = Color3.fromRGB(126, 228, 156),
		order = 3,
		description = "Build a lasting menagerie of species, elements, and rarities.",
	},
	Battle = {
		label = "Battle",
		accent = Color3.fromRGB(255, 118, 92),
		order = 4,
		description = "Claim honors in the arena and prove your line in gym combat.",
	},
	Base = {
		label = "Base & Defense",
		accent = Color3.fromRGB(247, 146, 84),
		order = 5,
		description = "Turn your fortress into a living bastion of income and defense.",
	},
	Economy = {
		label = "Economy",
		accent = Color3.fromRGB(255, 216, 112),
		order = 6,
		description = "Trade, sell, and grow a thriving kingdom of creature commerce.",
	},
	Exploration = {
		label = "Exploration",
		accent = Color3.fromRGB(180, 175, 255),
		order = 7,
		description = "Chart the realm, open its gates, and climb your knightly journey.",
	},
}

AchievementsConfig.CategoryOrder = {
	"Capture",
	"Evolution",
	"Collection",
	"Battle",
	"Base",
	"Economy",
	"Exploration",
}

AchievementsConfig.ActiveElements = { "Fire", "Ice", "Wind", "Earth", "Shadow", "Lightning", "Water" }
AchievementsConfig.EvolvingElements = { "Fire", "Ice", "Wind", "Earth", "Water" }
AchievementsConfig.LiveZones = {
	{ id = "Earth", label = "Earth Wilds" },
	{ id = "Fire", label = "Fire Wilds" },
	{ id = "Ice", label = "Ice Wilds" },
	{ id = "Wind", label = "Wind Wilds" },
	{ id = "Desert", label = "Desert Expanse" },
	{ id = "Electric", label = "Electric Peaks" },
	{ id = "Ocean", label = "Ocean Reach" },
}

AchievementsConfig.TrackedFamilies = {
	{ id = "sunscale", name = "Sunscale Line", title = "Sunscale Heir", species = { "sundile", "raydile", "solgator" } },
	{ id = "frosthorn", name = "Frosthorn Line", title = "Frosthorn Heir", species = { "fawny", "chilldoe", "frostag" } },
	{ id = "galecourt", name = "Galecourt Line", title = "Galecourt Heir", species = { "pursula", "purseus", "pursephone" } },
	{ id = "thornguard", name = "Thornguard Line", title = "Thornguard Heir", species = { "cacty", "jackedty", "cactyjackedty" } },
	{ id = "tideveil", name = "Tideveil Line", title = "Tideveil Heir", species = { "spoutyl", "droxyl", "hydroxyl" } },
}

AchievementsConfig.TrackedFamiliesById = {}
for _, family in ipairs(AchievementsConfig.TrackedFamilies) do
	AchievementsConfig.TrackedFamiliesById[family.id] = family
end

local STANDARD_THRESHOLDS = { 1, 10, 25, 50, 100 }
local EVOLUTION_THRESHOLDS = { 1, 5, 15, 30, 60 }
local ELEMENT_EVOLUTION_THRESHOLDS = { 1, 3, 8, 15, 30 }
local EVOLUTION_RARITY_THRESHOLDS = {
	Common = { 1, 3, 8, 15, 30 },
	Uncommon = { 1, 3, 8, 15, 30 },
	Rare = { 1, 2, 5, 10, 20 },
}
local HOLDING_THRESHOLDS = { 5, 10, 20, 35, 50 }
local SPECIES_THRESHOLDS = { 5, 15, 30, 50, 75 }
local DISTINCT_ELEMENT_THRESHOLDS = { 1, 2, 3, 5, 7 }
local DISTINCT_RARITY_THRESHOLDS = { 1, 2, 3, 4, 5 }
local ARENA_WIN_THRESHOLDS = { 1, 5, 15, 35, 75 }
local GYM_WIN_THRESHOLDS = { 1, 2, 3, 4, 5 }
local TOTAL_WIN_THRESHOLDS = { 1, 10, 25, 50, 100 }
local STREAK_THRESHOLDS = { 2, 5, 10, 20, 30 }
local ASSIGN_THRESHOLDS = { 1, 3, 10, 25, 50 }
local DEFENSE_KILL_THRESHOLDS = { 1, 10, 25, 50, 100 }
local RAIDER_KILL_THRESHOLDS = { 1, 5, 15, 30, 60 }
local TRADE_THRESHOLDS = { 1, 3, 10, 25, 50 }
local SALE_THRESHOLDS = { 1, 5, 15, 35, 75 }
local SOURCE_THRESHOLDS = { 1, 2, 3, 4, 5 }
local ZONE_VISIT_THRESHOLDS = { 1, 2, 3, 5, 7 }
local PLAYER_LEVEL_THRESHOLDS = { 2, 5, 10, 20, 30 }
local FAMILY_COMPLETION_THRESHOLDS = { 1, 2, 3, 4, 5 }

local function metricCounter(key)
	return { kind = "counter", key = key }
end

local function metricBest(key)
	return { kind = "best", key = key }
end

local function metricSetCount(key)
	return { kind = "set_count", key = key }
end

local function metricSetMember(key, member)
	return { kind = "set_member", key = key, member = member }
end

local function metricDataPath(path)
	return { kind = "data_path", path = path }
end

local function metricListCount(path)
	return { kind = "list_count", path = path }
end

local function metricSum(items)
	return { kind = "sum", items = items }
end

local function metricFamilyOwnedCount(familyId)
	return { kind = "family_owned_count", familyId = familyId }
end

local function metricCompletedFamiliesCount()
	return { kind = "completed_families_count" }
end

local function makeTitles(prefix, ladder)
	local out = {}
	for i, suffix in ipairs(ladder) do
		out[i] = prefix .. " " .. suffix
	end
	return out
end

local CAPTURE_LADDER = { "Carded", "Collector", "Squire", "Siegeknight", "Siegelord" }
local ASCENT_LADDER = { "Awakened", "Molder", "Squire", "Ascendant", "High Ascendant" }
local CURATOR_LADDER = { "Gathered", "Curator", "Steward", "Knight Curator", "Grand Curator" }

local definitions = {}
local chains = {}
local chainById = {}
local definitionsByChain = {}

local function addChain(meta)
	local categoryMeta = AchievementsConfig.Categories[meta.category] or AchievementsConfig.Categories.Capture
	local chain = {
		id = meta.id,
		category = meta.category,
		subcategory = meta.subcategory,
		chainName = meta.chainName,
		badgeKey = meta.badgeKey or meta.id,
		badgeGlyph = meta.badgeGlyph or string.sub(meta.chainName, 1, 1),
		badgeAccent = meta.badgeAccent or categoryMeta.accent,
		sortOrder = #chains + 1,
		description = meta.chainDescription or meta.chainName,
	}

	table.insert(chains, chain)
	chainById[chain.id] = chain
	definitionsByChain[chain.id] = {}

	for tierIndex, required in ipairs(meta.thresholds) do
		local tierLabel = AchievementsConfig.TierLabels[tierIndex] or tostring(tierIndex)
		local titleEarned = meta.titles[tierIndex] or meta.titles[#meta.titles] or meta.chainName
		local rewardData = defaultRewardData(tierIndex, titleEarned)
		if meta.rewardData then
			local custom = meta.rewardData(required, tierIndex, titleEarned)
			if type(custom) == "table" then
				for k, v in pairs(custom) do
					rewardData[k] = v
				end
			end
		end

		local def = {
			id = ("%s_t%d"):format(chain.id, tierIndex),
			category = chain.category,
			subcategory = chain.subcategory,
			chainName = chain.chainName,
			name = ("%s %s"):format(chain.chainName, tierLabel),
			titleEarned = titleEarned,
			description = meta.description(required, tierIndex),
			icon = meta.icon or "",
			badgeKey = chain.badgeKey,
			badgeGlyph = chain.badgeGlyph,
			badgeAccent = chain.badgeAccent,
			requiredProgress = required,
			tier = tierIndex,
			tierChainId = chain.id,
			rewardData = rewardData,
			metric = meta.metric,
			sortOrder = (chain.sortOrder * 10) + tierIndex,
			chainTierCount = #meta.thresholds,
		}

		table.insert(definitions, def)
		table.insert(definitionsByChain[chain.id], def)
	end
end

local function addSingle(meta)
	addChain({
		id = meta.id,
		category = meta.category,
		subcategory = meta.subcategory,
		chainName = meta.name,
		chainDescription = meta.chainDescription or meta.description,
		badgeKey = meta.badgeKey,
		badgeGlyph = meta.badgeGlyph,
		badgeAccent = meta.badgeAccent,
		thresholds = { meta.requiredProgress or 1 },
		titles = { meta.titleEarned },
		description = function()
			return meta.description
		end,
		rewardData = function(required, tierIndex, titleEarned)
			local rewardData = defaultRewardData(tierIndex or 1, titleEarned or meta.titleEarned)
			if meta.rewardData then
				local custom = meta.rewardData
				if type(custom) == "function" then
					custom = custom(required, tierIndex, titleEarned)
				end
				if type(custom) == "table" then
					for k, v in pairs(custom) do
						rewardData[k] = v
					end
				end
			end
			return rewardData
		end,
		metric = meta.metric,
	})
end

addChain({
	id = "capture_total",
	category = "Capture",
	subcategory = "Royal Ledger",
	chainName = "Royal Menagerie",
	badgeGlyph = "C",
	thresholds = STANDARD_THRESHOLDS,
	titles = { "First Binder", "Card Warden", "Menagerie Squire", "Capture Knight", "Grand Binder" },
	description = function(required)
		return ("Capture %d Siegelings total."):format(required)
	end,
	metric = metricCounter("capture.total"),
})

local elementChains = {
	Fire = { name = "Flame Muster", glyph = "F", titles = makeTitles("Fire", CAPTURE_LADDER) },
	Ice = { name = "Frost Muster", glyph = "I", titles = makeTitles("Ice", CAPTURE_LADDER) },
	Wind = { name = "Gale Muster", glyph = "W", titles = makeTitles("Wind", CAPTURE_LADDER) },
	Earth = { name = "Stone Muster", glyph = "E", titles = makeTitles("Earth", CAPTURE_LADDER) },
	Shadow = { name = "Umbral Muster", glyph = "S", titles = makeTitles("Shadow", CAPTURE_LADDER) },
	Lightning = { name = "Storm Muster", glyph = "L", titles = makeTitles("Storm", CAPTURE_LADDER) },
	Water = { name = "Tide Muster", glyph = "T", titles = makeTitles("Tide", CAPTURE_LADDER) },
}

for _, element in ipairs(AchievementsConfig.ActiveElements) do
	local info = elementChains[element]
	addChain({
		id = "capture_element_" .. string.lower(element),
		category = "Capture",
		subcategory = "Elemental Hunts",
		chainName = info.name,
		badgeGlyph = info.glyph,
		thresholds = STANDARD_THRESHOLDS,
		titles = info.titles,
		description = function(required)
			return ("Capture %d %s Siegelings."):format(required, element)
		end,
		metric = metricCounter("capture.element." .. element),
	})
end

local classChains = {
	{ className = "Bruiser", name = "Warband Census", glyph = "B" },
	{ className = "Mage", name = "Spellbound Census", glyph = "M" },
	{ className = "Guardian", name = "Bulwark Census", glyph = "G" },
	{ className = "Assassin", name = "Dagger Census", glyph = "A" },
	{ className = "Support", name = "Banner Census", glyph = "S" },
}

for _, classEntry in ipairs(classChains) do
	local className = classEntry.className
	local info = classEntry
	addChain({
		id = "capture_class_" .. string.lower(className),
		category = "Capture",
		subcategory = "Class Hunts",
		chainName = info.name,
		badgeGlyph = info.glyph,
		thresholds = STANDARD_THRESHOLDS,
		titles = makeTitles(className, CAPTURE_LADDER),
		description = function(required)
			return ("Capture %d %s-class Siegelings."):format(required, className)
		end,
		metric = metricCounter("capture.class." .. className),
	})
end

local rarityChains = {
	{ rarity = "Common", thresholds = { 5, 25, 75, 150, 300 }, glyph = "C" },
	{ rarity = "Uncommon", thresholds = { 1, 10, 25, 50, 100 }, glyph = "U" },
	{ rarity = "Rare", thresholds = { 1, 5, 15, 30, 60 }, glyph = "R" },
	{ rarity = "Epic", thresholds = { 1, 3, 8, 15, 30 }, glyph = "E" },
	{ rarity = "Legendary", thresholds = { 1, 2, 5, 10, 20 }, glyph = "L" },
}

for _, rarityEntry in ipairs(rarityChains) do
	local rarity = rarityEntry.rarity
	local info = rarityEntry
	addChain({
		id = "capture_rarity_" .. string.lower(rarity),
		category = "Capture",
		subcategory = "Rarity Hunts",
		chainName = rarity .. " Ledger",
		badgeGlyph = info.glyph,
		thresholds = info.thresholds,
		titles = makeTitles(rarity, CAPTURE_LADDER),
		description = function(required)
			return ("Capture %d %s Siegelings."):format(required, rarity)
		end,
		metric = metricCounter("capture.rarity." .. rarity),
	})
end

local bossSingles = {
	{ element = "Fire", name = "Crown of Embers", glyph = "F", title = "Cinder Crownclaimer" },
	{ element = "Ice", name = "Crown of Frost", glyph = "I", title = "Frost Crownclaimer" },
	{ element = "Wind", name = "Crown of Gales", glyph = "W", title = "Gale Crownclaimer" },
	{ element = "Earth", name = "Crown of Stone", glyph = "E", title = "Stone Crownclaimer" },
}

for _, entry in ipairs(bossSingles) do
	local bossId = CreatureData.GetBossCreatureId and CreatureData.GetBossCreatureId(entry.element, false)
	local bossData = bossId and CreatureData.GetById(bossId) or nil
	if bossId and bossData then
		addSingle({
			id = "capture_boss_" .. string.lower(entry.element),
			category = "Capture",
			subcategory = "Boss Hunts",
			name = entry.name,
			badgeGlyph = entry.glyph,
			titleEarned = entry.title,
			description = ("Capture %s, the %s elemental boss."):format(bossData.displayName or bossId, entry.element),
			metric = metricCounter("capture.creature." .. bossId),
		})
	end
end

addChain({
	id = "evolution_total",
	category = "Evolution",
	subcategory = "Ascension Record",
	chainName = "Ascension Chronicle",
	badgeGlyph = "E",
	thresholds = EVOLUTION_THRESHOLDS,
	titles = { "First Ascendant", "Morph Adept", "Line Squire", "Ascension Knight", "Ascension Lord" },
	description = function(required)
		return ("Evolve %d Siegelings."):format(required)
	end,
	metric = metricCounter("evolution.total"),
})

local evolutionNames = {
	Fire = { name = "Flame Ascension", glyph = "F" },
	Ice = { name = "Frost Ascension", glyph = "I" },
	Wind = { name = "Gale Ascension", glyph = "W" },
	Earth = { name = "Stone Ascension", glyph = "E" },
	Water = { name = "Tide Ascension", glyph = "T" },
}

for _, element in ipairs(AchievementsConfig.EvolvingElements) do
	local info = evolutionNames[element]
	addChain({
		id = "evolution_element_" .. string.lower(element),
		category = "Evolution",
		subcategory = "Elemental Evolution",
		chainName = info.name,
		badgeGlyph = info.glyph,
		thresholds = ELEMENT_EVOLUTION_THRESHOLDS,
		titles = makeTitles(element, ASCENT_LADDER),
		description = function(required)
			return ("Evolve %d %s Siegelings."):format(required, element)
		end,
		metric = metricCounter("evolution.element." .. element),
	})
end

local evolutionRarityChains = {
	{ rarity = "Common", glyph = "C" },
	{ rarity = "Uncommon", glyph = "U" },
	{ rarity = "Rare", glyph = "R" },
}

for _, rarityEntry in ipairs(evolutionRarityChains) do
	local rarity = rarityEntry.rarity
	addChain({
		id = "evolution_rarity_" .. string.lower(rarity),
		category = "Evolution",
		subcategory = "Rarity Evolution",
		chainName = rarity .. " Ascension",
		badgeGlyph = rarityEntry.glyph,
		thresholds = EVOLUTION_RARITY_THRESHOLDS[rarity],
		titles = makeTitles(rarity, ASCENT_LADDER),
		description = function(required)
			return ("Evolve %d %s Siegelings."):format(required, rarity)
		end,
		metric = metricCounter("evolution.rarity." .. rarity),
	})
end

addChain({
	id = "evolution_families_total",
	category = "Evolution",
	subcategory = "Tree Completion",
	chainName = "Lineage Chronicle",
	badgeGlyph = "L",
	thresholds = FAMILY_COMPLETION_THRESHOLDS,
	titles = { "Line Starter", "Line Keeper", "Line Squire", "Line Knight", "Line Sovereign" },
	description = function(required)
		return ("Complete %d tracked evolution trees."):format(required)
	end,
	metric = metricCompletedFamiliesCount(),
})

for _, family in ipairs(AchievementsConfig.TrackedFamilies) do
	addSingle({
		id = "evolution_family_" .. family.id,
		category = "Evolution",
		subcategory = "Tree Completion",
		name = family.name,
		badgeGlyph = string.sub(family.name, 1, 1),
		titleEarned = family.title,
		description = ("Complete the %s evolution tree."):format(family.name),
		requiredProgress = #family.species,
		metric = metricFamilyOwnedCount(family.id),
	})
end

addChain({
	id = "collection_peak_owned",
	category = "Collection",
	subcategory = "Holdings",
	chainName = "Warstable Reserve",
	badgeGlyph = "H",
	thresholds = HOLDING_THRESHOLDS,
	titles = { "Small Kennel", "Stable Keeper", "Menagerie Steward", "Kennel Knight", "Grand Menagerist" },
	description = function(required)
		return ("Own %d Siegelings at once."):format(required)
	end,
	metric = metricBest("collection.peakOwned"),
})

addChain({
	id = "collection_species_total",
	category = "Collection",
	subcategory = "Bestiary",
	chainName = "Royal Codex",
	badgeGlyph = "S",
	thresholds = SPECIES_THRESHOLDS,
	titles = { "Species Seeker", "Codex Keeper", "Bestiary Squire", "Bestiary Knight", "Grand Archivist" },
	description = function(required)
		return ("Own %d different Siegeling species over time."):format(required)
	end,
	metric = metricSetCount("collection.speciesOwned"),
})

addChain({
	id = "collection_elements_total",
	category = "Collection",
	subcategory = "Elemental Circle",
	chainName = "Elemental Circle",
	badgeGlyph = "O",
	thresholds = DISTINCT_ELEMENT_THRESHOLDS,
	titles = makeTitles("Elemental", CURATOR_LADDER),
	description = function(required)
		return ("Own Siegelings from %d different live elements."):format(required)
	end,
	metric = metricSetCount("collection.elementsOwned"),
})

addChain({
	id = "collection_rarities_total",
	category = "Collection",
	subcategory = "Rarity Circle",
	chainName = "Rarity Circle",
	badgeGlyph = "R",
	thresholds = DISTINCT_RARITY_THRESHOLDS,
	titles = makeTitles("Rarity", CURATOR_LADDER),
	description = function(required)
		return ("Own Siegelings from %d different rarities."):format(required)
	end,
	metric = metricSetCount("collection.raritiesOwned"),
})

addChain({
	id = "battle_arena_wins",
	category = "Battle",
	subcategory = "Arena Honors",
	chainName = "Arena Honors",
	badgeGlyph = "A",
	thresholds = ARENA_WIN_THRESHOLDS,
	titles = { "Arena Initiate", "Arena Contender", "Arena Squire", "Arena Champion", "Arena High Marshal" },
	description = function(required)
		return ("Win %d arena battles."):format(required)
	end,
	metric = metricCounter("battle.arenaWins"),
})

addChain({
	id = "battle_gym_wins",
	category = "Battle",
	subcategory = "Gym Honors",
	chainName = "Gym Honors",
	badgeGlyph = "G",
	thresholds = GYM_WIN_THRESHOLDS,
	titles = { "Gym Novice", "Gym Breaker", "Gym Squire", "Gym Knight", "Gym Sovereign" },
	description = function(required)
		return ("Win %d gym battles."):format(required)
	end,
	metric = metricCounter("battle.gymWins"),
})

addChain({
	id = "battle_total_wins",
	category = "Battle",
	subcategory = "War Ledger",
	chainName = "War Ledger",
	badgeGlyph = "W",
	thresholds = TOTAL_WIN_THRESHOLDS,
	titles = { "Battleblooded", "War Tested", "War Squire", "War Knight", "War Sovereign" },
	description = function(required)
		return ("Win %d total battles across arena and gyms."):format(required)
	end,
	metric = metricSum({
		metricCounter("battle.arenaWins"),
		metricCounter("battle.gymWins"),
	}),
})

addChain({
	id = "battle_arena_streak",
	category = "Battle",
	subcategory = "Streak Honors",
	chainName = "Unbroken Standard",
	badgeGlyph = "U",
	thresholds = STREAK_THRESHOLDS,
	titles = { "Hot Hand", "Unbroken Edge", "Momentum Squire", "Streak Knight", "Untouchable Lord" },
	description = function(required)
		return ("Reach an arena win streak of %d."):format(required)
	end,
	metric = metricBest("battle.arenaStreak"),
})

addChain({
	id = "base_defender_assignments",
	category = "Base",
	subcategory = "Assignments",
	chainName = "Watch Muster",
	badgeGlyph = "D",
	thresholds = ASSIGN_THRESHOLDS,
	titles = { "First Watch", "Watch Keeper", "Watch Squire", "Wall Knight", "Grand Castellan" },
	description = function(required)
		return ("Assign %d unique Siegelings to defense duty."):format(required)
	end,
	metric = metricSetCount("base.defendersAssigned"),
})

addChain({
	id = "base_income_assignments",
	category = "Base",
	subcategory = "Assignments",
	chainName = "Treasury Muster",
	badgeGlyph = "$",
	thresholds = ASSIGN_THRESHOLDS,
	titles = { "Tithe Started", "Coin Keeper", "Revenue Squire", "Guild Knight", "Golden Castellan" },
	description = function(required)
		return ("Assign %d unique Siegelings to income duty."):format(required)
	end,
	metric = metricSetCount("base.incomeAssigned"),
})

addChain({
	id = "base_defense_kills_total",
	category = "Base",
	subcategory = "Fortress Defense",
	chainName = "Bastion Tally",
	badgeGlyph = "K",
	thresholds = DEFENSE_KILL_THRESHOLDS,
	titles = { "Wall Warder", "Fort Keeper", "Bulwark Squire", "Rampart Knight", "Bastion Lord" },
	description = function(required)
		return ("Have your defenses defeat %d enemies."):format(required)
	end,
	metric = metricDataPath({ "stats", "defenseKills" }),
})

addChain({
	id = "base_raider_kills",
	category = "Base",
	subcategory = "Fortress Defense",
	chainName = "Raider Repulse",
	badgeGlyph = "R",
	thresholds = RAIDER_KILL_THRESHOLDS,
	titles = { "Raider Repelled", "Gate Warden", "Siege Squire", "Siege Knight", "Fortress Lord" },
	description = function(required)
		return ("Have your defenses defeat %d raiders or hostile companions."):format(required)
	end,
	metric = metricCounter("base.defenseKills.raider"),
})

addChain({
	id = "base_monster_kills",
	category = "Base",
	subcategory = "Fortress Defense",
	chainName = "Wild Guard",
	badgeGlyph = "M",
	thresholds = DEFENSE_KILL_THRESHOLDS,
	titles = { "Wildbreaker", "Hunt Warden", "Hunt Squire", "Hunt Knight", "Beastwall Lord" },
	description = function(required)
		return ("Have your defenses defeat %d wild monsters."):format(required)
	end,
	metric = metricCounter("base.defenseKills.monster"),
})

addChain({
	id = "base_defense_successes",
	category = "Base",
	subcategory = "Fortress Defense",
	chainName = "Holdfast Record",
	badgeGlyph = "H",
	thresholds = ASSIGN_THRESHOLDS,
	titles = { "Holdfast", "Bulwark", "Keep Squire", "Castle Knight", "Citadel Lord" },
	description = function(required)
		return ("Successfully defend your base %d times."):format(required)
	end,
	metric = metricCounter("base.defenseSuccesses"),
})

addChain({
	id = "economy_trades",
	category = "Economy",
	subcategory = "Trading Hall",
	chainName = "Merchant Oaths",
	badgeGlyph = "T",
	thresholds = TRADE_THRESHOLDS,
	titles = { "Barter Hand", "Broker", "Guild Squire", "Trade Knight", "Grand Factor" },
	description = function(required)
		return ("Complete %d trades with other players."):format(required)
	end,
	metric = metricCounter("economy.tradesCompleted"),
})

addChain({
	id = "economy_sales",
	category = "Economy",
	subcategory = "Market Sales",
	chainName = "Market Tallies",
	badgeGlyph = "S",
	thresholds = SALE_THRESHOLDS,
	titles = { "Vendor", "Merchant", "Market Squire", "Guild Merchant", "High Factor" },
	description = function(required)
		return ("Sell %d Siegelings."):format(required)
	end,
	metric = metricCounter("economy.salesCompleted"),
})

addChain({
	id = "economy_source_diversity",
	category = "Economy",
	subcategory = "Acquisition Routes",
	chainName = "Many Roads",
	badgeGlyph = "P",
	thresholds = SOURCE_THRESHOLDS,
	titles = { "Pathfinder", "Way Broker", "Route Squire", "Route Knight", "Route Master" },
	description = function(required)
		return ("Obtain Siegelings through %d different systems."):format(required)
	end,
	metric = metricSetCount("economy.acquisitionSources"),
})

addChain({
	id = "exploration_zones",
	category = "Exploration",
	subcategory = "Zone Discovery",
	chainName = "Realm March",
	badgeGlyph = "Z",
	thresholds = ZONE_VISIT_THRESHOLDS,
	titles = { "Wayfinder", "Trail Seeker", "Road Squire", "Realm Knight", "High Cartographer" },
	description = function(required)
		return ("Visit %d major zones."):format(required)
	end,
	metric = metricSetCount("exploration.zonesVisited"),
})

addChain({
	id = "exploration_player_level",
	category = "Exploration",
	subcategory = "Player Progression",
	chainName = "Knightly Rise",
	badgeGlyph = "L",
	thresholds = PLAYER_LEVEL_THRESHOLDS,
	titles = { "Initiate", "Adventurer", "Squire", "Knight", "Siegelord" },
	description = function(required)
		return ("Reach player level %d."):format(required)
	end,
	metric = metricDataPath({ "playerLevel" }),
})

local doorAchievements = {
	{ zoneId = "Ocean", name = "Ocean Gate", title = "Keeper of the Ocean Gate", glyph = "O" },
	{ zoneId = "Desert", name = "Desert Gate", title = "Keeper of the Desert Gate", glyph = "D" },
	{ zoneId = "Electric", name = "Electric Gate", title = "Keeper of the Electric Gate", glyph = "E" },
	{ zoneId = "Cave", name = "Cave Gate", title = "Keeper of the Cave Gate", glyph = "C" },
}

for _, door in ipairs(doorAchievements) do
	addSingle({
		id = "exploration_door_" .. string.lower(door.zoneId),
		category = "Exploration",
		subcategory = "Door Unlocks",
		name = door.name,
		badgeGlyph = door.glyph,
		titleEarned = door.title,
		description = ("Unlock the %s zone door."):format(door.zoneId),
		metric = metricSetMember("exploration.doorsUnlocked", door.zoneId),
	})
end

addSingle({
	id = "exploration_floor_two",
	category = "Exploration",
	subcategory = "Player Progression",
	name = "Second Floor",
	badgeGlyph = "2",
	titleEarned = "Hall Builder",
	description = "Unlock Floor 2 of your base.",
	requiredProgress = 2,
	metric = metricListCount({ "ownedFloors" }),
})

addSingle({
	id = "exploration_floor_three",
	category = "Exploration",
	subcategory = "Player Progression",
	name = "Third Floor",
	badgeGlyph = "3",
	titleEarned = "Sky Bastion Builder",
	description = "Unlock Floor 3 of your base.",
	requiredProgress = 3,
	metric = metricListCount({ "ownedFloors" }),
})

AchievementsConfig.Definitions = definitions
AchievementsConfig.Chains = chains
AchievementsConfig.ChainById = chainById
AchievementsConfig.DefinitionsByChain = definitionsByChain
AchievementsConfig.TotalDefinitions = #definitions

AchievementsConfig.ById = {}
for _, def in ipairs(definitions) do
	AchievementsConfig.ById[def.id] = def
end

return AchievementsConfig
