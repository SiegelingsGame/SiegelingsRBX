-- EleminionData.lua - ReplicatedStorage.Modules (ModuleScript)
-- Shared registry for Eleminion NPCs, affinity quests, and elemental legendary egg rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local EleminionData = {}

local function objectiveCapture(creatureId, amount)
	local info = CreatureData.GetById(creatureId)
	return {
		type = "capture",
		creatureId = creatureId,
		amount = math.max(1, tonumber(amount) or 1),
		label = "Capture " .. ((info and info.displayName) or creatureId),
	}
end

local function objectiveLevel(creatureId, targetLevel)
	local info = CreatureData.GetById(creatureId)
	return {
		type = "level",
		creatureId = creatureId,
		targetLevel = math.max(1, tonumber(targetLevel) or 1),
		label = "Raise " .. ((info and info.displayName) or creatureId) .. " to Lv." .. tostring(math.max(1, tonumber(targetLevel) or 1)),
	}
end

local function questStep(id, title, description, affinityReward, rewards, objectives)
	return {
		id = id,
		title = title,
		description = description,
		affinityReward = math.max(0, tonumber(affinityReward) or 0),
		rewards = rewards or {},
		objectives = objectives or {},
	}
end

EleminionData.PointNamePatterns = {
	"eleminionpoint",
	"epoint",
}

EleminionData.Definitions = {
	Fire = {
		element = "Fire",
		npcCreatureId = "hotty",
		biomeLabel = "Volcanic Biome",
		title = "Hotty, Ember Guide",
		subtitle = "Affinity of fire grows through bold captures and disciplined training.",
		pointHints = { "FireEPoint", "HottyEPoint", "FireEleminionPoint", "HottyEleminionPoint" },
		quests = {
			questStep(
				1,
				"Starter Sparks",
				"Show Hotty that you can handle the smallest flames before moving deeper into the caldera.",
				25,
				{ coins = 250, playerXP = 25 },
				{
					objectiveCapture("sundile", 1),
					objectiveCapture("draco", 1),
				}
			),
			questStep(
				2,
				"Heat Of The Pack",
				"Temper a reliable partner and bring back one of the volcanic hunters that stalk the smoke vents.",
				35,
				{ coins = 450, gems = 3, playerXP = 50 },
				{
					objectiveLevel("sundile", 5),
					objectiveCapture("emberfin", 1),
				}
			),
			questStep(
				3,
				"Living Cinders",
				"Only bonded knights can steady the rarer fire creatures that rule the dungeon lava channels.",
				40,
				{ coins = 850, gems = 6, playerXP = 80, legendaryEggElement = "Fire" },
				{
					objectiveCapture("dracoil", 1),
					objectiveLevel("emberfin", 8),
				}
			),
		},
	},
	Ice = {
		element = "Ice",
		npcCreatureId = "frosty",
		biomeLabel = "Frozen Biome",
		title = "Frosty, Winter Guide",
		subtitle = "Affinity of ice is earned with patience, calm captures, and steady leveling.",
		pointHints = { "IceEPoint", "FrostyEPoint", "IceEleminionPoint", "FrostyEleminionPoint" },
		quests = {
			questStep(
				1,
				"First Chill",
				"Frosty asks for proof that you can cross the snowfields without rushing the bond.",
				25,
				{ coins = 250, playerXP = 25 },
				{
					objectiveCapture("fawny", 1),
					objectiveCapture("icewee", 1),
				}
			),
			questStep(
				2,
				"Snowbound Bond",
				"Raise a dependable companion and return with a colder, sharper predator from the frozen ridge.",
				35,
				{ coins = 450, gems = 3, playerXP = 50 },
				{
					objectiveLevel("fawny", 5),
					objectiveCapture("falcoat", 1),
				}
			),
			questStep(
				3,
				"Crown Of Ice",
				"Frosty's final trial calls for one of the frozen wastes' rarer guardians and a hardened frontline ally.",
				40,
				{ coins = 850, gems = 6, playerXP = 80, legendaryEggElement = "Ice" },
				{
					objectiveCapture("peatbeak", 1),
					objectiveLevel("chilldoe", 8),
				}
			),
		},
	},
	Wind = {
		element = "Wind",
		npcCreatureId = "lofty",
		biomeLabel = "Highlands Biome",
		title = "Lofty, Gale Guide",
		subtitle = "Affinity of wind favors quick responses, clean captures, and agile companions.",
		pointHints = { "WindEPoint", "LoftyEPoint", "WindEleminionPoint", "LoftyEleminionPoint" },
		quests = {
			questStep(
				1,
				"Open Skies",
				"Lofty wants to see you catch the creatures that first learn to ride the highland currents.",
				25,
				{ coins = 250, playerXP = 25 },
				{
					objectiveCapture("breezee", 1),
					objectiveCapture("pursula", 1),
				}
			),
			questStep(
				2,
				"Rising Gusts",
				"Train one of your earliest wind partners and return with a hunter forged by the ridge winds.",
				35,
				{ coins = 450, gems = 3, playerXP = 50 },
				{
					objectiveLevel("breezee", 5),
					objectiveCapture("cloudwisp", 1),
				}
			),
			questStep(
				3,
				"Storm Discipline",
				"Lofty's final lesson demands a rare sky ruler and a spellcaster fast enough to keep up with the storm.",
				40,
				{ coins = 850, gems = 6, playerXP = 80, legendaryEggElement = "Wind" },
				{
					objectiveCapture("hurricrane", 1),
					objectiveLevel("purseus", 8),
				}
			),
		},
	},
	Earth = {
		element = "Earth",
		npcCreatureId = "mossy",
		biomeLabel = "Forest Biome",
		title = "Mossy, Grove Guide",
		subtitle = "Affinity of earth grows from loyalty, resilience, and careful nurturing of your biome team.",
		pointHints = { "EarthEPoint", "MossyEPoint", "EarthEleminionPoint", "MossyEleminionPoint" },
		quests = {
			questStep(
				1,
				"Roots Of Trust",
				"Earn Mossy's respect by bringing back two creatures that thrive close to the forest floor.",
				25,
				{ coins = 250, playerXP = 25 },
				{
					objectiveCapture("cacty", 1),
					objectiveCapture("squirebud", 1),
				}
			),
			questStep(
				2,
				"Stone And Sap",
				"Strengthen a trusted companion and prove you can track one of the forest's ambushers.",
				35,
				{ coins = 450, gems = 3, playerXP = 50 },
				{
					objectiveLevel("cacty", 5),
					objectiveCapture("bonoblade", 1),
				}
			),
			questStep(
				3,
				"Heartwood Trial",
				"Mossy's last test asks for a rare guardian of the grove and a stalwart bruiser ready for the deep woods.",
				40,
				{ coins = 850, gems = 6, playerXP = 80, legendaryEggElement = "Earth" },
				{
					objectiveCapture("generoot", 1),
					objectiveLevel("jackedty", 8),
				}
			),
		},
	},
}

function EleminionData.GetByElement(element)
	return EleminionData.Definitions[element]
end

function EleminionData.GetByNpcCreatureId(creatureId)
	for _, def in pairs(EleminionData.Definitions) do
		if def.npcCreatureId == creatureId then
			return def
		end
	end
	return nil
end

function EleminionData.GetAll()
	local list = {}
	for _, def in pairs(EleminionData.Definitions) do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return tostring(a.element) < tostring(b.element)
	end)
	return list
end

function EleminionData.GetMaxAffinity(element)
	local def = EleminionData.GetByElement(element)
	if not def then
		return 0
	end
	local total = 0
	for _, quest in ipairs(def.quests or {}) do
		total += math.max(0, tonumber(quest.affinityReward) or 0)
	end
	return total
end

local function getElementPool(element, rarity, onlyWithModels)
	local fallback = {}
	local withModels = {}
	for _, creature in ipairs(CreatureData.Creatures) do
		if creature.element == element
			and creature.rarity == rarity
			and creature.npcOnly ~= true
			and creature.modelName ~= "Egg" then
			table.insert(fallback, creature.id)
			if not onlyWithModels or CreatureData.CreatureHasModel(creature) then
				table.insert(withModels, creature.id)
			end
		end
	end
	if onlyWithModels and #withModels > 0 then
		return withModels
	end
	if #withModels > 0 then
		return withModels
	end
	return fallback
end

local function rollLegendaryEggRarity()
	local rareWeight = tonumber(GameConfig.EggLegendary_RarePct) or 30
	local epicWeight = tonumber(GameConfig.EggLegendary_MythicPct) or 40
	local legendaryWeight = tonumber(GameConfig.EggLegendary_LegendaryPct) or 30
	local total = math.max(0, rareWeight) + math.max(0, epicWeight) + math.max(0, legendaryWeight)
	if total <= 0 then
		return "Legendary"
	end

	local roll = math.random() * total
	if roll <= rareWeight then
		return "Rare"
	end
	if roll <= (rareWeight + epicWeight) then
		return "Epic"
	end
	return "Legendary"
end

function EleminionData.RollLegendaryEggCreatureId(element, onlyWithModels)
	local wantedRarity = rollLegendaryEggRarity()
	local priority = { wantedRarity, "Legendary", "Epic", "Rare", "Uncommon", "Common" }
	local seen = {}
	for _, rarity in ipairs(priority) do
		if not seen[rarity] then
			seen[rarity] = true
			local pool = getElementPool(element, rarity, onlyWithModels)
			if #pool > 0 then
				return pool[math.random(1, #pool)], rarity
			end
		end
	end
	return nil, nil
end

return EleminionData
