-- EleminionData.lua - ReplicatedStorage.Modules (ModuleScript)
-- Shared registry for Eleminion NPCs, affinity quests, and elemental legendary egg rewards.
-- Last updated: 2026-04-19 13:14

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

	Water = {
		element = "Water",
		npcCreatureId = "moisty",
		npc = npcProfile("moisty", "Moisty", "Moisty"),
		biomeLabel = "Ocean Biome",
		title = "Moisty, Tide Guide",
		subtitle = "Affinity of water grows through reef patrols, careful captures, and steady leveling.",
		pointHints = { "WaterEPoint", "MoistyEPoint", "WaterEleminionPoint", "MoistyEleminionPoint" },
		quests = {
			questStep(1, "First Tide", "Moisty wants proof you can read the shallows before you chase deeper currents.", 15, rewardPack(250, 25), { objectiveCapture("spoutyl", 1), objectiveCapture("shellpack", 1) }),
			questStep(2, "River Scouts", "Trace two common river runners and toughen your first partner for longer swims.", 20, rewardPack(400, 45, 1), { objectiveCapture("droxyl", 1), objectiveCapture("jawby", 1), objectiveLevel("spoutyl", 5) }),
			questStep(3, "Shoal Practice", "The shoals thicken. Return with paired drifters and a steadier scout.", 25, rewardPack(650, 70, 2), { objectiveCapture("ceeponee", 2), objectiveLevel("shellpack", 8) }),
			questStep(4, "Rapid Line", "The rapids guard heavier shells. Bring back evolved tide-breakers.", 30, rewardPack(900, 95, 3), { objectiveCapture("clawkid", 1), objectiveCapture("torqlander", 1), objectiveLevel("droxyl", 10) }),
			questStep(5, "Breaker Patrol", "Moisty sends you along the breaker line with aerial hunters and hardened guardians.", 35, rewardPack(1200, 125, 4), { objectiveCapture("ceehorcee", 1), objectiveCapture("ceeponee", 2), objectiveLevel("jawby", 12) }),
			questStep(6, "Deep Shelf", "The shelf drops away; rare predators wait below. Return with proof from the trench approaches.", 40, rewardPack(1600, 160, 5), { objectiveCapture("hydroxyl", 1), objectiveCapture("shellnaut", 1), objectiveLevel("clawkid", 15) }),
			questStep(7, "Pressure Trial", "Pressure favors creatures that endure. Repeat rare catches and sharpen your strike lead.", 45, rewardPack(2100, 205, 7), { objectiveCapture("jawbite", 2), objectiveCapture("hydroxyl", 2), objectiveLevel("torqlander", 20) }),
			questStep(8, "Storm Shelf", "Storm tides expose apex hunters. Claim an epic ruler of the surge.", 55, rewardPack(2800, 260, 9), { objectiveCapture("clawqueen", 1), objectiveCapture("jawbite", 2), objectiveLevel("hydroxyl", 25) }),
			questStep(9, "Abyssal Command", "Only veterans command sky-reflected seas and abyssal bruisers alike.", 65, rewardPack(3600, 325, 12), { objectiveCapture("ceesteed", 1), objectiveCapture("clawqueen", 2), objectiveLevel("shellnaut", 35) }),
			questStep(10, "Throne Of Depths", "Moisty demands a complete ocean strike force and a sovereign raised into mastery.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Water" }), { objectiveCapture("conchious", 2), objectiveCapture("ceesteed", 2), objectiveLevel("conchious", 40) }),
		},
	},
	Poison = {
		element = "Poison",
		npcCreatureId = "slimy",
		npc = npcProfile("slimy", "Slimy", "Slimy"),
		biomeLabel = "Ocean Biome",
		title = "Slimy, Venom Guide",
		subtitle = "Affinity of poison grows by hunting toxic lines, patient captures, and disciplined leveling.",
		pointHints = { "PoisonEPoint", "PoisonEpoint", "SlimyEPoint", "PoisonEleminionPoint", "SlimyEleminionPoint" },
		quests = {
			questStep(1, "First Dose", "Slimy tests whether you can handle mild venom before deeper brews.", 15, rewardPack(250, 25), { objectiveCapture("toxleaf", 1), objectiveCapture("poison_venomidge", 1) }),
			questStep(2, "Stronger Serum", "Follow the uncommon trail and toughen your opener for longer hunts.", 20, rewardPack(400, 45, 1), { objectiveCapture("poison_venomapex", 1), objectiveCapture("toxleaf", 2), objectiveLevel("toxleaf", 5) }),
			questStep(3, "Toxic Repeat", "Repeat exposure builds tolerance. Bring back concentrated catches.", 25, rewardPack(650, 70, 2), { objectiveCapture("poison_venomapex", 2), objectiveLevel("poison_venomidge", 8) }),
			questStep(4, "Spore Lane", "The lane thickens with duplicates. Prove you can stockpile safely.", 30, rewardPack(900, 95, 3), { objectiveCapture("toxleaf", 4), objectiveCapture("poison_venomapex", 1), objectiveLevel("poison_venomapex", 10) }),
			questStep(5, "Double Flask", "Pair uncommon strains with rare apex samples.", 35, rewardPack(1200, 125, 4), { objectiveCapture("poison_venomidge", 2), objectiveCapture("poison_venomapex", 2), objectiveLevel("toxleaf", 12) }),
			questStep(6, "Venom Stack", "Stack repeated apex captures against a wider toxin base.", 40, rewardPack(1600, 160, 5), { objectiveCapture("poison_venomapex", 3), objectiveCapture("toxleaf", 5), objectiveLevel("poison_venomidge", 15) }),
			questStep(7, "Acid Proof", "High doses demand discipline. Triple up on both strains.", 45, rewardPack(2100, 205, 7), { objectiveCapture("poison_venomidge", 3), objectiveCapture("poison_venomapex", 3), objectiveLevel("poison_venomapex", 20) }),
			questStep(8, "Overbrew", "Overbrew trials mix quantity with lethal rarity.", 55, rewardPack(2800, 260, 9), { objectiveCapture("toxleaf", 8), objectiveCapture("poison_venomapex", 3), objectiveLevel("poison_venomapex", 25) }),
			questStep(9, "Toxin Command", "Command means repeating apex mastery across long campaigns.", 65, rewardPack(3600, 325, 12), { objectiveCapture("poison_venomapex", 5), objectiveCapture("poison_venomidge", 5), objectiveLevel("poison_venomapex", 35) }),
			questStep(10, "Crown Of Venom", "Slimy's final trial is total saturation: apex dominance and depth-level bonds.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Poison" }), { objectiveCapture("poison_venomapex", 8), objectiveCapture("toxleaf", 10), objectiveLevel("poison_venomapex", 40) }),
		},
	},
	Metal = {
		element = "Metal",
		npcCreatureId = "steamy",
		npc = npcProfile("steamy", "Steamy", "Steamy"),
		biomeLabel = "Cave Biome",
		title = "Steamy, Alloy Guide",
		subtitle = "Affinity of metal is forged through steady captures, repeated tempering, and veteran training.",
		pointHints = { "MetalEPoint", "SteamyEPoint", "MetalEleminionPoint", "SteamyEleminionPoint" },
		quests = {
			questStep(1, "First Ingot", "Steamy asks for proof you can read ore country before hauling rare alloys.", 15, rewardPack(250, 25), { objectiveCapture("bearby", 1), objectiveCapture("drillbo", 1) }),
			questStep(2, "Temper Line", "Advance the evolve line and toughen your starter shell.", 20, rewardPack(400, 45, 1), { objectiveCapture("bearnade", 1), objectiveCapture("bearby", 2), objectiveLevel("bearby", 5) }),
			questStep(3, "Layered Plate", "Layer plates by repeating uncommon forms.", 25, rewardPack(650, 70, 2), { objectiveCapture("drillbo", 3), objectiveLevel("bearnade", 8) }),
			questStep(4, "Rare Forge", "Rare alloys appear deeper in the tunnels.", 30, rewardPack(900, 95, 3), { objectiveCapture("bearzooka", 1), objectiveCapture("bearnade", 2), objectiveLevel("bearby", 10) }),
			questStep(5, "Dungeon Ingot", "Dungeon-tier metal demands heavier duplicates.", 35, rewardPack(1200, 125, 4), { objectiveCapture("bearzooka", 2), objectiveCapture("drillbo", 4), objectiveLevel("bearzooka", 12) }),
			questStep(6, "Epic Hammer", "Epic strain enters the forge chain.", 40, rewardPack(1600, 160, 5), { objectiveCapture("metal_siegling_e1", 1), objectiveCapture("bearzooka", 2), objectiveLevel("bearnade", 15) }),
			questStep(7, "Legend Bloom", "Legendary ore awakens only for persistent smiths.", 45, rewardPack(2100, 205, 7), { objectiveCapture("metal_siegling_l1", 1), objectiveCapture("bearzooka", 3), objectiveLevel("bearzooka", 20) }),
			questStep(8, "Twin Bloom", "Twin apex blooms temper the epic line.", 55, rewardPack(2800, 260, 9), { objectiveCapture("metal_siegling_e1", 2), objectiveCapture("metal_siegling_l1", 1), objectiveLevel("metal_siegling_e1", 28) }),
			questStep(9, "Forge Marshal", "Marshal legendaries alongside dungeon veterans.", 65, rewardPack(3600, 325, 12), { objectiveCapture("metal_siegling_l1", 2), objectiveCapture("bearzooka", 4), objectiveLevel("bearzooka", 35) }),
			questStep(10, "Crown Alloy", "Steamy demands apex dominance across the full metallic ladder.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Metal" }), { objectiveCapture("metal_siegling_l1", 3), objectiveCapture("metal_siegling_e1", 3), objectiveLevel("metal_siegling_l1", 40) }),
		},
	},
	Shadow = {
		element = "Shadow",
		npcCreatureId = "umbry",
		npc = npcProfile("umbry", "Umbry", "Umbry"),
		biomeLabel = "Cave Biome",
		title = "Umbry, Gloom Guide",
		subtitle = "Affinity of shadow rewards patience, repeated hunts in the dark, and fearless leveling.",
		pointHints = { "ShadowEPoint", "UmbryEPoint", "ShadowEleminionPoint", "UmbryEleminionPoint" },
		quests = {
			questStep(1, "First Whisper", "Umbry listens for the smallest echoes before trusting you with deeper gloom.", 15, rewardPack(250, 25), { objectiveCapture("echo", 1), objectiveCapture("echowing", 1) }),
			questStep(2, "Bat Spiral", "Double the swarm and sharpen your scout.", 20, rewardPack(400, 45, 1), { objectiveCapture("echowing", 2), objectiveCapture("echo", 2), objectiveLevel("echo", 5) }),
			questStep(3, "Rare Murk", "Rare hunters slip between stalactites. Prove you can grab them cleanly.", 25, rewardPack(650, 70, 2), { objectiveCapture("echolustrious", 1), objectiveCapture("echo", 3), objectiveLevel("echowing", 8) }),
			questStep(4, "Dungeon Coil", "Dungeon-class shadows test nerve.", 30, rewardPack(900, 95, 3), { objectiveCapture("umbralwyrm", 1), objectiveCapture("echolustrious", 1), objectiveLevel("echo", 10) }),
			questStep(5, "Murk Stack", "Stack rare catches until the cavern feels crowded.", 35, rewardPack(1200, 125, 4), { objectiveCapture("echolustrious", 2), objectiveCapture("echowing", 3), objectiveLevel("echolustrious", 12) }),
			questStep(6, "Wyrm Wake", "Epic coils tighten; bring duplicates from the deep paths.", 40, rewardPack(1600, 160, 5), { objectiveCapture("umbralwyrm", 2), objectiveCapture("echolustrious", 2), objectiveLevel("echowing", 15) }),
			questStep(7, "Void Touch", "Legendary dread stirs where wyrms overlap.", 45, rewardPack(2100, 205, 7), { objectiveCapture("voidmaw", 1), objectiveCapture("umbralwyrm", 2), objectiveLevel("echolustrious", 20) }),
			questStep(8, "Night Apex", "Night apex hunts demand repeated epic proof.", 55, rewardPack(2800, 260, 9), { objectiveCapture("voidmaw", 2), objectiveCapture("umbralwyrm", 2), objectiveLevel("umbralwyrm", 25) }),
			questStep(9, "Abyss Marshal", "Marshal twin legends against long dungeon campaigns.", 65, rewardPack(3600, 325, 12), { objectiveCapture("voidmaw", 2), objectiveCapture("echolustrious", 3), objectiveLevel("voidmaw", 35) }),
			questStep(10, "Throne Of Gloom", "Umbry demands mastery over the deepest night: repeated void crowns and apex levels.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Shadow" }), { objectiveCapture("voidmaw", 3), objectiveCapture("umbralwyrm", 3), objectiveLevel("voidmaw", 40) }),
		},
	},
	Lightning = {
		element = "Lightning",
		npcCreatureId = "zappy",
		npc = npcProfile("zappy", "Zappy", "Zappy"),
		biomeLabel = "Electric Biome",
		title = "Zappy, Storm Guide",
		subtitle = "Affinity of lightning favors fast captures, loud patrols, and relentless training.",
		pointHints = { "ElectricEPoint", "LightningEPoint", "ZappyEPoint", "LightningEleminionPoint", "ZappyEleminionPoint" },
		quests = {
			questStep(1, "First Spark", "Zappy wants to see you ground the smallest arcs before chasing thunder.", 15, rewardPack(250, 25), { objectiveCapture("monkwatt", 1), objectiveCapture("newt", 1) }),
			questStep(2, "Static Trail", "Follow early sparks into heavier shocks.", 20, rewardPack(400, 45, 1), { objectiveCapture("staticap", 1), objectiveCapture("blinky", 1), objectiveLevel("monkwatt", 5) }),
			questStep(3, "Surge Duo", "Pair uncommon circuit runners.", 25, rewardPack(650, 70, 2), { objectiveCapture("simicircuit", 1), objectiveCapture("joltram", 1), objectiveLevel("newt", 8) }),
			questStep(4, "Dungeon Bolt", "Dungeon-tier bolts arrive with Kilokong lines.", 30, rewardPack(900, 95, 3), { objectiveCapture("kilokong", 1), objectiveCapture("newton", 1), objectiveLevel("staticap", 10) }),
			questStep(5, "Chain Patrol", "Chain jelly hunters across the cliffs.", 35, rewardPack(1200, 125, 4), { objectiveCapture("bleetstrike", 1), objectiveCapture("joltram", 2), objectiveLevel("joltram", 12) }),
			questStep(6, "Thunder Guard", "Stormclaw stalks the upper tiers.", 40, rewardPack(1600, 160, 5), { objectiveCapture("stormclaw", 1), objectiveCapture("kilokong", 1), objectiveLevel("simicircuit", 15) }),
			questStep(7, "Overload Path", "Overload paths demand duplicate rare bruisers.", 45, rewardPack(2100, 205, 7), { objectiveCapture("newton", 2), objectiveCapture("bleetstrike", 2), objectiveLevel("kilokong", 20) }),
			questStep(8, "Eye Of Thunder", "Epic dominance stacks before the lord encounter.", 55, rewardPack(2800, 260, 9), { objectiveCapture("stormclaw", 2), objectiveCapture("bleetstrike", 2), objectiveLevel("stormclaw", 25) }),
			questStep(9, "Storm Marshal", "Marshal thunderlords against layered dungeon clears.", 65, rewardPack(3600, 325, 12), { objectiveCapture("thunderlord", 1), objectiveCapture("stormclaw", 2), objectiveLevel("newton", 35) }),
			questStep(10, "Sky Sovereign", "Zappy crowns sky sovereigns who chain epic storms into mastery.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Lightning" }), { objectiveCapture("thunderlord", 2), objectiveCapture("stormclaw", 2), objectiveLevel("thunderlord", 40) }),
		},
	},
	Light = {
		element = "Light",
		npcCreatureId = "glowy",
		npc = npcProfile("glowy", "Glowy", "Glowy"),
		biomeLabel = "Electric Biome",
		title = "Glowy, Dawn Guide",
		subtitle = "Affinity of light gathers through radiant captures, hopeful duplicates, and steady mentorship.",
		pointHints = { "LightEPoint", "GlowyEPoint", "LightEleminionPoint", "GlowyEleminionPoint" },
		quests = {
			questStep(1, "First Dawn", "Glowy asks for gentle proof before brighter trials.", 15, rewardPack(250, 25), { objectiveCapture("light_siegling_standin", 1), objectiveCapture("light_daybreak", 1) }),
			questStep(2, "Brighter Band", "Stack early radiance and toughen your dawn partner.", 20, rewardPack(400, 45, 1), { objectiveCapture("light_solbanner", 1), objectiveCapture("light_siegling_standin", 2), objectiveLevel("light_siegling_standin", 5) }),
			questStep(3, "Twin Sunrise", "Twin sunrises demand disciplined repeats.", 25, rewardPack(650, 70, 2), { objectiveCapture("light_daybreak", 2), objectiveLevel("light_daybreak", 8) }),
			questStep(4, "Banner Rise", "Banners lift as rare sol steel appears.", 30, rewardPack(900, 95, 3), { objectiveCapture("light_solbanner", 2), objectiveCapture("light_daybreak", 2), objectiveLevel("light_solbanner", 10) }),
			questStep(5, "Solar Stack", "Solar stacks mean triplicate banners.", 35, rewardPack(1200, 125, 4), { objectiveCapture("light_solbanner", 3), objectiveCapture("light_siegling_standin", 3), objectiveLevel("light_daybreak", 12) }),
			questStep(6, "High Glare", "High glare mixes sol banners with dawn swells.", 40, rewardPack(1600, 160, 5), { objectiveCapture("light_daybreak", 3), objectiveCapture("light_solbanner", 2), objectiveLevel("light_siegling_standin", 15) }),
			questStep(7, "Radiant Proof", "Radiant proof piles rare sol forms together.", 45, rewardPack(2100, 205, 7), { objectiveCapture("light_solbanner", 4), objectiveCapture("light_daybreak", 3), objectiveLevel("light_solbanner", 20) }),
			questStep(8, "Noon Apex", "Noon apex shines on repeated sol banners.", 55, rewardPack(2800, 260, 9), { objectiveCapture("light_solbanner", 5), objectiveCapture("light_daybreak", 4), objectiveLevel("light_solbanner", 25) }),
			questStep(9, "Daybridge", "Daybridge marshals dawn and banner in long campaigns.", 65, rewardPack(3600, 325, 12), { objectiveCapture("light_solbanner", 6), objectiveCapture("light_siegling_standin", 5), objectiveLevel("light_daybreak", 35) }),
			questStep(10, "High Noon Crown", "Glowy crowns keepers who stack radiance into true mastery.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Light" }), { objectiveCapture("light_solbanner", 8), objectiveCapture("light_daybreak", 6), objectiveLevel("light_solbanner", 40) }),
		},
	},
	Psychic = {
		element = "Psychic",
		npcCreatureId = "thinky",
		npc = npcProfile("thinky", "Thinky", "Thinky"),
		biomeLabel = "Desert Biome",
		title = "Thinky, Mind Guide",
		subtitle = "Affinity of psychic power grows through mindful captures, layered study, and calm leveling.",
		pointHints = { "PsychicEPoint", "PsychicEpoint", "ThinkyEPoint", "PsychicEleminionPoint", "ThinkyEleminionPoint" },
		quests = {
			questStep(1, "First Thought", "Thinky listens for gentle minds before trusting harder riddles.", 15, rewardPack(250, 25), { objectiveCapture("mentaroo", 1), objectiveCapture("luvy", 1) }),
			questStep(2, "Warm Echo", "Warm echoes pair with sharper meditation.", 20, rewardPack(400, 45, 1), { objectiveCapture("papap", 1), objectiveCapture("ragguette", 1), objectiveLevel("mentaroo", 5) }),
			questStep(3, "Heart Lattice", "Emotion trails twist into uncommon lattices.", 25, rewardPack(650, 70, 2), { objectiveCapture("luvysore", 1), objectiveCapture("luvy", 2), objectiveLevel("luvy", 8) }),
			questStep(4, "Deep Recall", "Rare recall pulls Mentarak into focus.", 30, rewardPack(900, 95, 3), { objectiveCapture("mentarak", 1), objectiveCapture("papap", 2), objectiveLevel("luvysore", 10) }),
			questStep(5, "Mind Palace", "Mind palaces stack emotion and memory together.", 35, rewardPack(1200, 125, 4), { objectiveCapture("luvysore", 2), objectiveCapture("ragguette", 2), objectiveLevel("mentarak", 12) }),
			questStep(6, "Third Eye Path", "Epic third eyes open along the duel path.", 40, rewardPack(1600, 160, 5), { objectiveCapture("luvyduvysore", 1), objectiveCapture("mentarak", 2), objectiveLevel("papap", 15) }),
			questStep(7, "Crown Mind", "Legendary mind-sovereigns arrive for veterans only.", 45, rewardPack(2100, 205, 7), { objectiveCapture("psychic_siegling_l1", 1), objectiveCapture("luvyduvysore", 1), objectiveLevel("luvyduvysore", 20) }),
			questStep(8, "Twin Crown", "Twin crowns demand repeated epic mastery.", 55, rewardPack(2800, 260, 9), { objectiveCapture("psychic_siegling_l1", 2), objectiveCapture("mentarak", 3), objectiveLevel("psychic_siegling_l1", 28) }),
			questStep(9, "Thought Marshal", "Marshal sovereign thoughts across desert nights.", 65, rewardPack(3600, 325, 12), { objectiveCapture("luvyduvysore", 2), objectiveCapture("psychic_siegling_l1", 2), objectiveLevel("mentarak", 35) }),
			questStep(10, "Omnibus Mind", "Thinky demands omnibus mastery across the psychic ladder.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Psychic" }), { objectiveCapture("psychic_siegling_l1", 3), objectiveCapture("luvyduvysore", 2), objectiveLevel("psychic_siegling_l1", 40) }),
		},
	},
	Undead = {
		element = "Undead",
		npcCreatureId = "bony",
		npc = npcProfile("bony", "Bony", "Bony"),
		biomeLabel = "Desert Biome",
		title = "Bony, Crypt Guide",
		subtitle = "Affinity of undeath rises from patient graveyard sweeps, repeated haunts, and hardened bonds.",
		pointHints = { "UndeadEPoint", "BonyEPoint", "UndeadEleminionPoint", "BonyEleminionPoint" },
		quests = {
			questStep(1, "Cold Ground", "Bony wants humble haunts before deeper crypts.", 15, rewardPack(250, 25), { objectiveCapture("spookyweed", 1), objectiveCapture("livingwood", 1) }),
			questStep(2, "Grave Soil", "Grave soil deepens with rare guardians.", 20, rewardPack(400, 45, 1), { objectiveCapture("golor", 1), objectiveCapture("spookyweed", 2), objectiveLevel("spookyweed", 5) }),
			questStep(3, "Echo Bones", "Echo bones stack uncommon wood forms.", 25, rewardPack(650, 70, 2), { objectiveCapture("livingwood", 2), objectiveLevel("livingwood", 8) }),
			questStep(4, "Crypt Rare", "Rare crypt giants stir.", 30, rewardPack(900, 95, 3), { objectiveCapture("golor", 2), objectiveCapture("livingwood", 2), objectiveLevel("spookyweed", 10) }),
			questStep(5, "Haunt Stack", "Haunt stacks demand epic sheen.", 35, rewardPack(1200, 125, 4), { objectiveCapture("sheenx", 1), objectiveCapture("golor", 2), objectiveLevel("golor", 12) }),
			questStep(6, "Grim Duplication", "Duplicate haunts tighten the spiral.", 40, rewardPack(1600, 160, 5), { objectiveCapture("sheenx", 2), objectiveCapture("livingwood", 3), objectiveLevel("livingwood", 15) }),
			questStep(7, "Twin Crypt", "Twin epic guards stalk the dunes.", 45, rewardPack(2100, 205, 7), { objectiveCapture("sheenx", 2), objectiveCapture("golor", 3), objectiveLevel("golor", 20) }),
			questStep(8, "Bone Apex", "Bone apex shines through repeated Sheenx crowns.", 55, rewardPack(2800, 260, 9), { objectiveCapture("sheenx", 3), objectiveCapture("livingwood", 4), objectiveLevel("sheenx", 25) }),
			questStep(9, "Desert Marshal", "Marshal spectral elites across night patrols.", 65, rewardPack(3600, 325, 12), { objectiveCapture("sheenx", 4), objectiveCapture("golor", 4), objectiveLevel("sheenx", 35) }),
			questStep(10, "Thanatos Crown", "Bony crowns crypt kings who haunt until mastery.", 80, rewardPack(5000, 425, 16, { legendaryEggElement = "Undead" }), { objectiveCapture("sheenx", 6), objectiveCapture("golor", 5), objectiveLevel("sheenx", 40) }),
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
