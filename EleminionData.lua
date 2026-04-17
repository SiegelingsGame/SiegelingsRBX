-- EleminionData.lua - ReplicatedStorage.Modules (ModuleScript)
-- Shared registry for Eleminion NPCs, affinity quests, and elemental legendary egg rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local EleminionData = {}

local function npcProfile(id, displayName, modelName, extra)
	local profile = {
		id = id,
		displayName = displayName,
		modelName = modelName or displayName,
		targetSize = 6,
	}
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			profile[key] = value
		end
	end
	return profile
end

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

local function rewardPack(coins, playerXP, gems, extra)
	local rewards = {}
	if tonumber(coins) and coins > 0 then
		rewards.coins = math.floor(coins)
	end
	if tonumber(gems) and gems > 0 then
		rewards.gems = math.floor(gems)
	end
	if tonumber(playerXP) and playerXP > 0 then
		rewards.playerXP = math.floor(playerXP)
	end
	if type(extra) == "table" then
		for key, value in pairs(extra) do
			rewards[key] = value
		end
	end
	return rewards
end

EleminionData.PointNamePatterns = {
	"eleminionpoint",
	"epoint",
}

EleminionData.Definitions = {
	Fire = {
		element = "Fire",
		npcCreatureId = "hotty",
		npc = npcProfile("hotty", "Hotty", "Hotty"),
		biomeLabel = "Volcanic Biome",
		title = "Hotty, Ember Guide",
		subtitle = "Affinity of fire grows through bold captures and disciplined training.",
		pointHints = { "FireEPoint", "HottyEPoint", "FireEleminionPoint", "HottyEleminionPoint" },
		quests = {
			questStep(
				1,
				"Starter Sparks",
				"Show Hotty that you can handle the smallest flames before moving deeper into the caldera.",
				15,
				rewardPack(250, 25),
				{
					objectiveCapture("sundile", 1),
					objectiveCapture("draco", 1),
				}
			),
			questStep(
				2,
				"Caldera Scout",
				"Trace the outer rim, return with two calm cinders, and prove you can raise a partner under pressure.",
				20,
				rewardPack(400, 45, 1),
				{
					objectiveCapture("firsky", 1),
					objectiveCapture("emberfox", 1),
					objectiveLevel("sundile", 5),
				}
			),
			questStep(
				3,
				"Pack Heat",
				"Pylooks vanish through ash gusts. Round up a pair and show that your earliest bruisers are battle ready.",
				25,
				rewardPack(650, 70, 2),
				{
					objectiveCapture("pylook", 2),
					objectiveLevel("draco", 8),
				}
			),
			questStep(
				4,
				"Vent Patrol",
				"The vents get hotter and the hunts get meaner. Bring back two stronger wildfire creatures from the inner paths.",
				30,
				rewardPack(900, 95, 3),
				{
					objectiveCapture("emberpup", 1),
					objectiveCapture("raydile", 1),
					objectiveLevel("sundile", 10),
				}
			),
			questStep(
				5,
				"Smoke Stalker",
				"Emberfin circle the smoke pockets in pairs. Match them with a trained guardian that can keep pace.",
				35,
				rewardPack(1200, 125, 4),
				{
					objectiveCapture("emberfin", 2),
					objectiveLevel("raydile", 12),
				}
			),
			questStep(
				6,
				"Lava Channel Trial",
				"The lava channels are no place for half-trained teams. Return with two hard catches and a stronger Raydile.",
				40,
				rewardPack(1600, 160, 5),
				{
					objectiveCapture("dracoil", 1),
					objectiveCapture("hotdog", 1),
					objectiveLevel("raydile", 18),
				}
			),
			questStep(
				7,
				"Cinder March",
				"March deeper into the volcanic heart. Hotty wants proof you can secure rarer prey and maintain a veteran assassin.",
				45,
				rewardPack(2100, 205, 7),
				{
					objectiveCapture("cindergil", 1),
					objectiveCapture("dracoil", 2),
					objectiveLevel("dracoil", 25),
				}
			),
			questStep(
				8,
				"Forge Of Ash",
				"The forge caverns only open to persistent hunters. Claim an epic flame and return with a second Hotdog from the depths.",
				55,
				rewardPack(2800, 260, 9),
				{
					objectiveCapture("pyleer", 1),
					objectiveCapture("hotdog", 2),
					objectiveLevel("dracoil", 30),
				}
			),
			questStep(
				9,
				"Sunscale Command",
				"Only seasoned tamers command both spectral fire and living magma. Build a high-rank fire roster worthy of the caldera throne.",
				65,
				rewardPack(3600, 325, 12),
				{
					objectiveCapture("solgator", 1),
					objectiveCapture("cindergil", 2),
					objectiveLevel("pyleer", 35),
				}
			),
			questStep(
				10,
				"Heart Of The Caldera",
				"Hotty's last trial demands a complete volcanic strike force: two epic captures and a Solgator raised deep into mastery.",
				80,
				rewardPack(5000, 425, 16, { legendaryEggElement = "Fire" }),
				{
					objectiveCapture("pyleer", 2),
					objectiveCapture("solgator", 2),
					objectiveLevel("solgator", 40),
				}
			),
		},
	},
	Ice = {
		element = "Ice",
		npcCreatureId = "frosty",
		npc = npcProfile("frosty", "Frosty", "Frosty"),
		biomeLabel = "Frozen Biome",
		title = "Frosty, Winter Guide",
		subtitle = "Affinity of ice is earned with patience, calm captures, and steady leveling.",
		pointHints = { "IceEPoint", "FrostyEPoint", "IceEleminionPoint", "FrostyEleminionPoint" },
		quests = {
			questStep(
				1,
				"First Chill",
				"Frosty asks for proof that you can cross the snowfields without rushing the bond.",
				15,
				rewardPack(250, 25),
				{
					objectiveCapture("fawny", 1),
					objectiveCapture("icewee", 1),
				}
			),
			questStep(
				2,
				"Snowfield Supplies",
				"Glide across the open drifts, secure two more winter companions, and toughen your first capture for longer treks.",
				20,
				rewardPack(400, 45, 1),
				{
					objectiveCapture("frostfly", 1),
					objectiveCapture("falcool", 1),
					objectiveLevel("fawny", 5),
				}
			),
			questStep(
				3,
				"Winter Tracks",
				"The wind hides weaker footsteps. Frosty wants a heavier trail to follow and a sharpened Ice-Wee beside you.",
				25,
				rewardPack(650, 70, 2),
				{
					objectiveCapture("cozycub", 2),
					objectiveLevel("icewee", 8),
				}
			),
			questStep(
				4,
				"Ridge Runner",
				"The frozen ridge belongs to quicker hunters. Bring back evolved snow roamers and a fully prepared scout.",
				30,
				rewardPack(900, 95, 3),
				{
					objectiveCapture("chilldoe", 1),
					objectiveCapture("falcoat", 1),
					objectiveLevel("falcool", 10),
				}
			),
			questStep(
				5,
				"Crystal Patrol",
				"Frosty's patrols grow longer now. Hold the line with more evolved ice creatures and a sturdier bruiser.",
				35,
				rewardPack(1200, 125, 4),
				{
					objectiveCapture("icecuewee", 1),
					objectiveCapture("cozycub", 3),
					objectiveLevel("chilldoe", 12),
				}
			),
			questStep(
				6,
				"Frozen Watch",
				"The wastes beyond the ridge are guarded by older, colder creatures. Return from them with proof.",
				40,
				rewardPack(1600, 160, 5),
				{
					objectiveCapture("peatbeak", 1),
					objectiveCapture("lumina", 1),
					objectiveLevel("falcoat", 15),
				}
			),
			questStep(
				7,
				"Deep Freeze",
				"The storm thickens. Frosty expects repeat success against rare prey and an evolved assassin raised through the cold.",
				45,
				rewardPack(2100, 205, 7),
				{
					objectiveCapture("icecuewee", 2),
					objectiveCapture("lumina", 2),
					objectiveLevel("icecuewee", 20),
				}
			),
			questStep(
				8,
				"Shard Crown",
				"The deepest caves only answer to patience. Claim an epic frost beast and bring back a second Peatbeak for the caravan.",
				55,
				rewardPack(2800, 260, 9),
				{
					objectiveCapture("frostag", 1),
					objectiveCapture("peatbeak", 2),
					objectiveLevel("icecuewee", 25),
				}
			),
			questStep(
				9,
				"Glacier Marshal",
				"Marshal your frozen team across the long night. Frosty wants repeat late-night hunts and a Peatbeak nearing its peak.",
				65,
				rewardPack(3600, 325, 12),
				{
					objectiveCapture("lumina", 3),
					objectiveCapture("falcoat", 2),
					objectiveLevel("peatbeak", 35),
				}
			),
			questStep(
				10,
				"Throne Of Winter",
				"Frosty's final lesson is endurance itself: multiple high-tier captures and a Frostag trained deep into mastery.",
				80,
				rewardPack(5000, 425, 16, { legendaryEggElement = "Ice" }),
				{
					objectiveCapture("frostag", 2),
					objectiveCapture("peatbeak", 3),
					objectiveLevel("frostag", 40),
				}
			),
		},
	},
	Wind = {
		element = "Wind",
		npcCreatureId = "lofty",
		npc = npcProfile("lofty", "Lofty", "Lofty"),
		biomeLabel = "Highlands Biome",
		title = "Lofty, Gale Guide",
		subtitle = "Affinity of wind favors quick responses, clean captures, and agile companions.",
		pointHints = { "WindEPoint", "LoftyEPoint", "WindEleminionPoint", "LoftyEleminionPoint" },
		quests = {
			questStep(
				1,
				"Open Skies",
				"Lofty wants to see you catch the creatures that first learn to ride the highland currents.",
				15,
				rewardPack(250, 25),
				{
					objectiveCapture("breezee", 1),
					objectiveCapture("pursula", 1),
				}
			),
			questStep(
				2,
				"Ridge Drafts",
				"Drift along the first ridges, gather one more cloud rider, and prove your starting flock can keep formation.",
				20,
				rewardPack(400, 45, 1),
				{
					objectiveCapture("cloudpuff", 1),
					objectiveCapture("breezee", 2),
					objectiveLevel("breezee", 5),
				}
			),
			questStep(
				3,
				"Crosswinds",
				"The currents turn rougher above the passes. Capture a second Cloudpuff and keep your frontline on pace.",
				25,
				rewardPack(650, 70, 2),
				{
					objectiveCapture("cloudpuff", 2),
					objectiveLevel("pursula", 8),
				}
			),
			questStep(
				4,
				"Updraft Patrol",
				"Lofty's patrols cover the upper cliffs now. Bring back evolved wind allies and a common flyer raised to its limit.",
				30,
				rewardPack(900, 95, 3),
				{
					objectiveCapture("gagglestand", 1),
					objectiveCapture("cloudwisp", 1),
					objectiveLevel("breezee", 10),
				}
			),
			questStep(
				5,
				"Gale Circle",
				"The highland rings are only safe with stronger escorts. Build out your support line and train a healer through the climb.",
				35,
				rewardPack(1200, 125, 4),
				{
					objectiveCapture("purseus", 1),
					objectiveCapture("gagglestand", 2),
					objectiveLevel("gagglestand", 12),
				}
			),
			questStep(
				6,
				"Storm Signs",
				"Distant thunder means stronger prey. Return with a rare sky tyrant, a dungeon hunter, and a Cloudwisp tough enough to hold the line.",
				40,
				rewardPack(1600, 160, 5),
				{
					objectiveCapture("hurricrane", 1),
					objectiveCapture("shellshock", 1),
					objectiveLevel("cloudwisp", 15),
				}
			),
			questStep(
				7,
				"Thunder Pass",
				"The mountain pass tests precision over speed. Bring back two rarer strikers and raise your spellcaster through the squall.",
				45,
				rewardPack(2100, 205, 7),
				{
					objectiveCapture("cloudsprite", 1),
					objectiveCapture("pursephone", 1),
					objectiveLevel("purseus", 20),
				}
			),
			questStep(
				8,
				"Eye Of The Ridge",
				"The eye of the storm opens above the highest cliffs. Claim an epic hunter and return with another Hurricrane from the gale line.",
				55,
				rewardPack(2800, 260, 9),
				{
					objectiveCapture("strikehawk", 1),
					objectiveCapture("hurricrane", 2),
					objectiveLevel("cloudsprite", 25),
				}
			),
			questStep(
				9,
				"Highstorm Command",
				"Now Lofty wants command presence: an epic support flyer, another strikehawk, and a storm beast trained into veteran strength.",
				65,
				rewardPack(3600, 325, 12),
				{
					objectiveCapture("skydon", 1),
					objectiveCapture("strikehawk", 2),
					objectiveLevel("hurricrane", 35),
				}
			),
			questStep(
				10,
				"Sky Sovereign Trial",
				"Lofty's final trial demands a complete highland air wing: repeated epic captures and a Strikehawk raised into mastery.",
				80,
				rewardPack(5000, 425, 16, { legendaryEggElement = "Wind" }),
				{
					objectiveCapture("skydon", 2),
					objectiveCapture("hurricrane", 3),
					objectiveLevel("strikehawk", 40),
				}
			),
		},
	},
	Earth = {
		element = "Earth",
		npcCreatureId = "mossy",
		npc = npcProfile("mossy", "Mossy", "Mossy"),
		biomeLabel = "Forest Biome",
		title = "Mossy, Grove Guide",
		subtitle = "Affinity of earth grows from loyalty, resilience, and careful nurturing of your biome team.",
		pointHints = { "EarthEPoint", "MossyEPoint", "EarthEleminionPoint", "MossyEleminionPoint" },
		quests = {
			questStep(
				1,
				"Roots Of Trust",
				"Earn Mossy's respect by bringing back two creatures that thrive close to the forest floor.",
				15,
				rewardPack(250, 25),
				{
					objectiveCapture("cacty", 1),
					objectiveCapture("squirebud", 1),
				}
			),
			questStep(
				2,
				"Grove Forager",
				"Search the calmer glades for two more earth creatures and raise your first bruiser for longer forest marches.",
				20,
				rewardPack(400, 45, 1),
				{
					objectiveCapture("applehead", 1),
					objectiveCapture("pylme", 1),
					objectiveLevel("cacty", 5),
				}
			),
			questStep(
				3,
				"Underbrush Watch",
				"The thorns get thicker under the canopy. Mossy wants a pair of Sleaf and a faster scout ready for ambush paths.",
				25,
				rewardPack(650, 70, 2),
				{
					objectiveCapture("sleaf", 2),
					objectiveLevel("squirebud", 8),
				}
			),
			questStep(
				4,
				"Bark And Stone",
				"The inner grove is guarded by heavier forms. Return with two evolved protectors and a Pylme trained to its limit.",
				30,
				rewardPack(900, 95, 3),
				{
					objectiveCapture("jackedty", 1),
					objectiveCapture("floraknight", 1),
					objectiveLevel("pylme", 10),
				}
			),
			questStep(
				5,
				"Burrow Lessons",
				"The forest floor is alive with burrowers. Match Mossy's pace with a Bonoblade and a sturdier guardian line.",
				35,
				rewardPack(1200, 125, 4),
				{
					objectiveCapture("bonoblade", 1),
					objectiveCapture("applehead", 2),
					objectiveLevel("jackedty", 12),
				}
			),
			questStep(
				6,
				"Deep Grove Hunt",
				"Only patient tamers make it back from the deep grove. Bring home two rare earth guardians and a refined spellblade.",
				40,
				rewardPack(1600, 160, 5),
				{
					objectiveCapture("generoot", 1),
					objectiveCapture("guerilla", 1),
					objectiveLevel("floraknight", 15),
				}
			),
			questStep(
				7,
				"Thornwall Ascent",
				"The old trees hide stronger predators above the roots. Mossy expects repeated success and a Bonoblade honed for the climb.",
				45,
				rewardPack(2100, 205, 7),
				{
					objectiveCapture("sleafwyrm", 1),
					objectiveCapture("bonoblade", 2),
					objectiveLevel("bonoblade", 20),
				}
			),
			questStep(
				8,
				"Ancient Canopy",
				"The canopy trials are long and punishing. Claim an epic earth titan, then return with another Generoot from the old paths.",
				55,
				rewardPack(2800, 260, 9),
				{
					objectiveCapture("cactyjackedty", 1),
					objectiveCapture("generoot", 2),
					objectiveLevel("generoot", 30),
				}
			),
			questStep(
				9,
				"Rootcrown Muster",
				"The rootcrown is where only veteran tamers endure. Add a second apex guardian and raise your epic bruiser into true command.",
				65,
				rewardPack(3600, 325, 12),
				{
					objectiveCapture("dracosleaf", 1),
					objectiveCapture("sleafwyrm", 2),
					objectiveLevel("cactyjackedty", 35),
				}
			),
			questStep(
				10,
				"Heartwood Champion",
				"Mossy's last trial is a full deep-forest campaign: repeat epic captures, repeat ancient hunts, and one champion raised to mastery.",
				80,
				rewardPack(5000, 425, 16, { legendaryEggElement = "Earth" }),
				{
					objectiveCapture("cactyjackedty", 2),
					objectiveCapture("dracosleaf", 2),
					objectiveLevel("dracosleaf", 40),
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

function EleminionData.GetNpcProfile(value)
	local def = value
	if type(value) == "string" then
		def = EleminionData.GetByElement(value) or EleminionData.GetByNpcCreatureId(value)
	end
	if type(def) ~= "table" then
		return nil
	end
	return def.npc
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
