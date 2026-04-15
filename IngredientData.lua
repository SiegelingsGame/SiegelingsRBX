-- IngredientData.lua - ReplicatedStorage/Modules/IngredientData
-- 8 biomes × 5 rarities; crafting rules and buff resolution.
-- Last updated: 2026-03-28 14:30

local CreatureData = require(script.Parent.CreatureData)

local IngredientData = {}

local RARITY_ORDER = CreatureData.RarityOrder
local RARITY_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local function rarityToIndex(name)
	return RARITY_ORDER[name] or 1
end

local function indexToRarity(idx)
	idx = math.clamp(math.floor(idx + 0.5), 1, #RARITY_NAMES)
	return RARITY_NAMES[idx]
end

--- @class IngredientDef
--- id, displayName, region, rarity, description
--- affinityType: "element" | "class"
--- affinity: element or class name string

local function row(id, displayName, region, rarity, affinityType, affinity, description)
	return {
		id = id,
		displayName = displayName,
		region = region,
		rarity = rarity,
		affinityType = affinityType,
		affinity = affinity,
		description = description,
	}
end

-- 8 regions × 5 rarities (biome-themed names)
IngredientData.Ingredients = {
	-- DesertSky
	row("ing_desert_c", "Dune Dust", "DesertSky", "Common", "element", "Psychic", "Fine grit carried on desert wind."),
	row("ing_desert_u", "Oasis Herb", "DesertSky", "Uncommon", "element", "Undead", "Bitter leaves that grow where water hides."),
	row("ing_desert_r", "Saltglass Shard", "DesertSky", "Rare", "class", "Mage", "Crystallized heat that hums faintly."),
	row("ing_desert_e", "Mirage Silk", "DesertSky", "Epic", "class", "Assassin", "Thread spun from shimmering air."),
	row("ing_desert_l", "Pharaoh Relic Mote", "DesertSky", "Legendary", "element", "Light", "A golden speck of forgotten sun."),

	-- ElectricSky
	row("ing_electric_c", "Static Mote", "ElectricSky", "Common", "element", "Lightning", "Tiny spark frozen in resin."),
	row("ing_electric_u", "Coil Fiber", "ElectricSky", "Uncommon", "element", "Light", "Copper-bright strand from storm pylons."),
	row("ing_electric_r", "Storm Shard", "ElectricSky", "Rare", "class", "Guardian", "Glassy fragment that grounds rage."),
	row("ing_electric_e", "Tesla Core Dust", "ElectricSky", "Epic", "class", "Bruiser", "Powdered charge from old coils."),
	row("ing_electric_l", "Overdrive Heartseed", "ElectricSky", "Legendary", "element", "Metal", "Pulses like a second heartbeat."),

	-- WaterSky
	row("ing_water_c", "Kelp Strand", "WaterSky", "Common", "element", "Water", "Rubbery ribbon from the shallows."),
	row("ing_water_u", "Pearl Grit", "WaterSky", "Uncommon", "element", "Poison", "Iridescent sand from deep vents."),
	row("ing_water_r", "Brine Essence", "WaterSky", "Rare", "class", "Support", "A drop that tastes of tides."),
	row("ing_water_e", "Abyss Scale Flake", "WaterSky", "Epic", "class", "Mage", "Shedding from something vast below."),
	row("ing_water_l", "Tidal Crown Fragment", "WaterSky", "Legendary", "element", "Ice", "Blue-white coral shaped like royalty."),

	-- EarthSky (inner forest wedge)
	row("ing_earth_c", "Root Fiber", "EarthSky", "Common", "element", "Earth", "Tough cord from old growth."),
	row("ing_earth_u", "Clay Nodule", "EarthSky", "Uncommon", "element", "Wind", "Packed earth that whistles when dry."),
	row("ing_earth_r", "Moss Resin", "EarthSky", "Rare", "class", "Guardian", "Sticky shield-sap from deep shade."),
	row("ing_earth_e", "Grove Amber", "EarthSky", "Epic", "class", "Support", "Trapped pollen from ancient trees."),
	row("ing_earth_l", "Worldheart Seed", "EarthSky", "Legendary", "element", "Earth", "Heavy; the ground leans toward it."),

	-- FireSky
	row("ing_fire_c", "Ash Fleck", "FireSky", "Common", "element", "Fire", "Still warm long after the flame."),
	row("ing_fire_u", "Cinder Nut", "FireSky", "Uncommon", "element", "Fire", "Charred shell with a soft ember core."),
	row("ing_fire_r", "Magma Drop", "FireSky", "Rare", "class", "Bruiser", "Glassed tear of molten stone."),
	row("ing_fire_e", "Obsidian Ember", "FireSky", "Epic", "class", "Assassin", "Black glass that cuts light."),
	row("ing_fire_l", "Phoenix Cinder", "FireSky", "Legendary", "element", "Light", "Feather-light ash that refuses to scatter."),

	-- IceSky
	row("ing_ice_c", "Frost Mote", "IceSky", "Common", "element", "Ice", "Snowflake that never melts in hand."),
	row("ing_ice_u", "Glacial Shard", "IceSky", "Uncommon", "element", "Water", "Blue ice from a crevasse."),
	row("ing_ice_r", "Rime Crystal", "IceSky", "Rare", "class", "Mage", "Fog frozen into geometry."),
	row("ing_ice_e", "Permafrost Tear", "IceSky", "Epic", "class", "Guardian", "A droplet locked in eternal chill."),
	row("ing_ice_l", "Aurora Core", "IceSky", "Legendary", "element", "Wind", "Ribbon of colored cold."),

	-- WindSky
	row("ing_wind_c", "Gust Petal", "WindSky", "Common", "element", "Wind", "Spirals upward when released."),
	row("ing_wind_u", "Dandelion Silk", "WindSky", "Uncommon", "element", "Lightning", "Carries charge from high air."),
	row("ing_wind_r", "Gale Feather", "WindSky", "Rare", "class", "Assassin", "So light it vanishes sideways."),
	row("ing_wind_e", "Skyglass Splinter", "WindSky", "Epic", "class", "Support", "Clear as horizon light."),
	row("ing_wind_l", "Cyclone Eye", "WindSky", "Legendary", "element", "Wind", "Still point wrapped in howl."),

	-- Cave
	row("ing_cave_c", "Spore Mote", "CaveSky", "Common", "element", "Poison", "Bioluminescent dust."),
	row("ing_cave_u", "Flint Chip", "CaveSky", "Uncommon", "element", "Shadow", "Sharp edge from the deep."),
	row("ing_cave_r", "Deep Fungus", "CaveSky", "Rare", "class", "Bruiser", "Rubbery cap with iron taste."),
	row("ing_cave_e", "Geode Dust", "CaveSky", "Epic", "class", "Mage", "Crystal powder that catches thought."),
	row("ing_cave_l", "Abyssal Geode Heart", "CaveSky", "Legendary", "element", "Undead", "Hollow stone that whispers."),
}

local byId = {}
for _, ing in ipairs(IngredientData.Ingredients) do
	byId[ing.id] = ing
end
IngredientData.ById = byId

function IngredientData.GetById(id)
	return byId[id]
end

-- Pattern minigame recipes (entered at campfire before crafting completes).
-- Tokens are simple directional words for button-based UI.
IngredientData.RecipePatterns = {
	neutral_attack = {
		{ id = "atk_1", seq = { "Up", "Right", "Up", "Left" } },
		{ id = "atk_2", seq = { "Right", "Up", "Right", "Down" } },
		{ id = "atk_3", seq = { "Up", "Up", "Right", "Left" } },
	},
	neutral_speed = {
		{ id = "spd_1", seq = { "Left", "Right", "Left", "Right" } },
		{ id = "spd_2", seq = { "Up", "Down", "Up", "Right" } },
		{ id = "spd_3", seq = { "Right", "Left", "Down", "Right" } },
	},
	neutral_health = {
		{ id = "hp_1", seq = { "Down", "Left", "Down", "Right" } },
		{ id = "hp_2", seq = { "Left", "Down", "Right", "Down" } },
		{ id = "hp_3", seq = { "Down", "Down", "Left", "Up" } },
	},
	siegeling_element = {
		{ id = "elem_1", seq = { "Up", "Down", "Left", "Right", "Up" } },
		{ id = "elem_2", seq = { "Right", "Left", "Up", "Down", "Right" } },
		{ id = "elem_3", seq = { "Up", "Right", "Down", "Left", "Up" } },
	},
	siegeling_class = {
		{ id = "class_1", seq = { "Left", "Up", "Left", "Down", "Right" } },
		{ id = "class_2", seq = { "Down", "Right", "Up", "Left", "Down" } },
		{ id = "class_3", seq = { "Right", "Up", "Left", "Down", "Right" } },
	},
}

function IngredientData.GetRandomIngredientIdForRegion(region)
	local pool = {}
	for _, ing in ipairs(IngredientData.Ingredients) do
		if ing.region == region then
			table.insert(pool, ing.id)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

function IngredientData.GetAllRegions()
	return {
		"DesertSky",
		"ElectricSky",
		"WaterSky",
		"EarthSky",
		"FireSky",
		"IceSky",
		"WindSky",
		"CaveSky",
	}
end

--- Normalize mix: { { id = string, qty = number }, ... } or { {1}=id, {2}=qty } pairs
function IngredientData.NormalizeMix(raw)
	if type(raw) ~= "table" then
		return {}
	end
	local out = {}
	if raw[1] ~= nil then
		for _, entry in ipairs(raw) do
			if type(entry) == "table" then
				local id = tostring(entry.id or entry[1] or "")
				local qty = math.floor(tonumber(entry.qty or entry[2] or 0) or 0)
				if id ~= "" and qty > 0 then
					table.insert(out, { id = id, qty = qty })
				end
			end
		end
	else
		for id, qty in pairs(raw) do
			local sid = tostring(id)
			local q = math.floor(tonumber(qty) or 0)
			if sid ~= "" and q > 0 then
				table.insert(out, { id = sid, qty = q })
			end
		end
	end
	return out
end

--- Snapshot from PlayerDataManager.GetCraftingMix: dense [1..maxSlots], empty slots as {id="",qty=0} or false.
--- @return flat { {id,qty}, ... } in slot order (for consume), slotsByIndex { [i] = {id,qty}? }
function IngredientData.ParseCraftingMixRaw(raw, maxSlots)
	maxSlots = maxSlots or 4
	local flat = {}
	local slotsByIndex = {}
	if type(raw) ~= "table" then
		return flat, slotsByIndex
	end
	for i = 1, maxSlots do
		local e = raw[i]
		if type(e) == "table" and tostring(e.id or "") ~= "" and (tonumber(e.qty) or 0) > 0 then
			local id = tostring(e.id)
			local qty = math.floor(tonumber(e.qty) or 0)
			slotsByIndex[i] = { id = id, qty = qty }
			table.insert(flat, { id = id, qty = qty })
		else
			slotsByIndex[i] = nil
		end
	end
	return flat, slotsByIndex
end

function IngredientData.SlotOccupancyMask(slotsByIndex, maxSlots)
	local mask = 0
	maxSlots = maxSlots or 4
	if type(slotsByIndex) ~= "table" then
		return mask
	end
	for i = 1, maxSlots do
		if slotsByIndex[i] then
			mask = mask + 2 ^ (i - 1)
		end
	end
	return mask
end

--- @param mixNormalized { {id, qty} } slot-ordered flat list (same ids/qty as slots; used for consume)
--- @param cfg GameConfig.Cooking or nil
--- @param slotsByIndex optional { [1..max] = {id,qty}? } — when set, affinity scoring uses slot position as weight so layout changes the dish.
function IngredientData.ComputeCraft(mixNormalized, cfg, slotsByIndex)
	cfg = cfg or {}
	local minN = tonumber(cfg.MinMixIngredients) or 3
	local maxN = tonumber(cfg.MaxMixIngredients) or 4
	local divBonus = tonumber(cfg.DiversityBonusRaritySteps) or 0.25

	local total = 0
	for _, e in ipairs(mixNormalized) do
		total += e.qty
	end
	if total < minN then
		return nil, "Need at least " .. tostring(minN) .. " ingredients."
	end
	if total > maxN then
		return nil, "Use at most " .. tostring(maxN) .. " ingredients."
	end

	-- Pass nil for legacy unweighted behavior; pass ParseCraftingMixRaw's second return for layout-aware crafts.
	local useSlots = slotsByIndex ~= nil
	local sumR = 0
	local raritySeen = {}
	local elemVotes = {}
	local classVotes = {}
	local elemScore = 0
	local classScore = 0

	if useSlots then
		for i = 1, maxN do
			local e = slotsByIndex[i]
			if type(e) == "table" and e.id and tostring(e.id) ~= "" and (tonumber(e.qty) or 0) > 0 then
				local ing = byId[e.id]
				if not ing then
					return nil, "Unknown ingredient: " .. tostring(e.id)
				end
				raritySeen[ing.rarity] = true
				local wBase = e.qty
				local w = wBase * i
				sumR += rarityToIndex(ing.rarity) * wBase
				if ing.affinityType == "element" then
					elemScore += w
					elemVotes[ing.affinity] = (elemVotes[ing.affinity] or 0) + w
				elseif ing.affinityType == "class" then
					classScore += w
					classVotes[ing.affinity] = (classVotes[ing.affinity] or 0) + w
				end
			end
		end
	else
		for _, e in ipairs(mixNormalized) do
			local ing = byId[e.id]
			if not ing then
				return nil, "Unknown ingredient: " .. tostring(e.id)
			end
			raritySeen[ing.rarity] = true
			local w = e.qty
			sumR += rarityToIndex(ing.rarity) * w
			if ing.affinityType == "element" then
				elemScore += w
				elemVotes[ing.affinity] = (elemVotes[ing.affinity] or 0) + w
			elseif ing.affinityType == "class" then
				classScore += w
				classVotes[ing.affinity] = (classVotes[ing.affinity] or 0) + w
			end
		end
	end

	local avg = sumR / total
	local distinct = 0
	for _ in pairs(raritySeen) do
		distinct = distinct + 1
	end
	if distinct >= 3 then
		avg = math.min(5, avg + divBonus)
	end

	local outRarity = indexToRarity(avg)

	local slotMask = useSlots and IngredientData.SlotOccupancyMask(slotsByIndex, maxN) or 0
	local sumIdx = 0
	if useSlots then
		for i = 1, maxN do
			if slotsByIndex[i] then
				sumIdx += i
			end
		end
	end

	local winElement, winElementN = nil, 0
	for k, v in pairs(elemVotes) do
		if v > winElementN then
			winElementN = v
			winElement = k
		end
	end
	local winClass, winClassN = nil, 0
	for k, v in pairs(classVotes) do
		if v > winClassN then
			winClassN = v
			winClass = k
		end
	end

	local buffId
	local meta = { craftRarity = outRarity, slotMask = slotMask, slotIndexSum = sumIdx }

	if elemScore > classScore and winElement then
		buffId = "craft_siegeling_element"
		meta.element = winElement
	elseif classScore > elemScore and winClass then
		buffId = "craft_siegeling_class"
		meta.class = winClass
	else
		-- Tie or no signal: neutrals — total mod 3, shifted by which slots are used (sparse layouts differ).
		local r = (total + slotMask * 3 + sumIdx) % 3
		if r == 0 then
			buffId = "craft_neutral_attack"
		elseif r == 1 then
			buffId = "craft_neutral_speed"
		else
			buffId = "craft_neutral_health"
		end
	end

	local displayName
	if buffId == "craft_siegeling_element" then
		displayName = outRarity .. " " .. tostring(meta.element) .. " Feast"
	elseif buffId == "craft_siegeling_class" then
		displayName = outRarity .. " " .. tostring(meta.class) .. " Ration"
	elseif buffId == "craft_neutral_attack" then
		displayName = outRarity .. " Warrior Skewer"
	elseif buffId == "craft_neutral_speed" then
		displayName = outRarity .. " Trail Mix"
	else
		displayName = outRarity .. " Hearty Stew"
	end

	return {
		buffId = buffId,
		meta = meta,
		outputRarity = outRarity,
		displayName = displayName,
		consume = mixNormalized,
	}
end

function IngredientData.GetCraftFamilyFromResult(craftResult)
	if type(craftResult) ~= "table" then return nil end
	local buffId = craftResult.buffId
	if buffId == "craft_neutral_attack" then return "neutral_attack" end
	if buffId == "craft_neutral_speed" then return "neutral_speed" end
	if buffId == "craft_neutral_health" then return "neutral_health" end
	if buffId == "craft_siegeling_element" then return "siegeling_element" end
	if buffId == "craft_siegeling_class" then return "siegeling_class" end
	return nil
end

--- Deterministic pattern pick from result family + seed.
--- @param craftResult table
--- @param seed number|string|nil
--- @return table|nil patternEntry
function IngredientData.GetPatternForResult(craftResult, seed)
	local family = IngredientData.GetCraftFamilyFromResult(craftResult)
	if not family then return nil end
	local pool = IngredientData.RecipePatterns[family]
	if type(pool) ~= "table" or #pool == 0 then
		return nil
	end
	local n
	if type(seed) == "number" then
		n = math.floor(seed)
	else
		local s = tostring(seed or "")
		local h = 17
		for i = 1, #s do
			h = (h * 31 + string.byte(s, i)) % 2147483647
		end
		n = h
	end
	if n < 0 then n = -n end
	local idx = (n % #pool) + 1
	return pool[idx]
end

--- Compute quality from entered sequence and elapsed time.
--- @return grade string, qualityScore number(0..1), accuracy number(0..1), speedScore number(0..1)
function IngredientData.ComputePatternQuality(expectedSeq, enteredSeq, elapsedMs, timeLimitSec)
	if type(expectedSeq) ~= "table" or #expectedSeq == 0 then
		return "Poor", 0, 0, 0
	end
	enteredSeq = type(enteredSeq) == "table" and enteredSeq or {}
	local matched = 0
	for i = 1, #expectedSeq do
		local a = tostring(expectedSeq[i])
		local b = tostring(enteredSeq[i] or "")
		if a == b then matched += 1 end
	end
	local accuracy = matched / #expectedSeq
	local limitMs = math.max(1, math.floor((tonumber(timeLimitSec) or 12) * 1000))
	local usedMs = math.max(0, math.floor(tonumber(elapsedMs) or limitMs))
	local speedScore = math.clamp(1 - (usedMs / limitMs), 0, 1)
	local quality = (accuracy * 0.8) + (speedScore * 0.2)
	local grade = "Poor"
	if quality >= 0.90 then
		grade = "Perfect"
	elseif quality >= 0.75 then
		grade = "Great"
	elseif quality >= 0.55 then
		grade = "Good"
	end
	return grade, quality, accuracy, speedScore
end

-- Unique display titles per campfire craft buff id (internal ids stay snake_case; UI uses these).
local CRAFT_BUFF_TYPE_TITLES = {
	craft_neutral_attack = "Berserker Skewer",
	craft_neutral_speed = "Sprinter's Trail Mix",
	craft_neutral_health = "Emberheart Stew",
	craft_siegeling_element = "Primal Element Banquet",
	craft_siegeling_class = "Archetype Ration",
}

-- Minigame / quality tier — shown on cooking toasts (gamefied, no raw enum strings).
local QUALITY_PLATE_NAMES = {
	Poor = "Apprentice Plating",
	Good = "Line Cook's Seal",
	Great = "Sous-Chef's Glory",
	Perfect = "Mythic Plate",
}

-- Short effect lines for toast (matches BuffShopSystem / stat logic).
local CRAFT_BUFF_EFFECT_BLURBS = {
	craft_neutral_attack = "Bonus attack damage in combat",
	craft_neutral_speed = "Increased walk speed",
	craft_neutral_health = "Increased max health",
	craft_siegeling_element = "Element-aligned Siegeling stat boost",
	craft_siegeling_class = "Class-aligned Siegeling stat boost",
}

local function titleCaseWords(str)
	str = tostring(str or ""):gsub("_", " ")
	str = str:gsub("(%a)([%w']*)", function(first, rest)
		return first:upper() .. rest:lower()
	end)
	return str
end

--- Human label for any buff id when no shop config exists: removes underscores, title case.
function IngredientData.PrettifyBuffId(buffId)
	return titleCaseWords(buffId)
end

--- Stable, unique name for each craft buff type (for HUD / toasts).
function IngredientData.GetCraftBuffTypeTitle(buffId)
	if not buffId then
		return "Campfire Boon"
	end
	local id = tostring(buffId)
	return CRAFT_BUFF_TYPE_TITLES[id] or IngredientData.PrettifyBuffId(id)
end

--- One-line effect summary for notifications (shown in parentheses).
function IngredientData.GetCraftBuffEffectBlurb(buffId)
	if not buffId then
		return ""
	end
	return CRAFT_BUFF_EFFECT_BLURBS[tostring(buffId)] or ""
end

--- Gamefied tier line for recipe minigame quality.
function IngredientData.GetQualityPlateName(grade)
	if not grade then
		return ""
	end
	local g = tostring(grade)
	return QUALITY_PLATE_NAMES[g] or titleCaseWords(g)
end

--- Single line for ShowNotification (cooking category adds a client-side banner prefix).
--- @param result table from ComputeCraft
--- @param qualityGrade string|nil Poor/Good/Great/Perfect or nil for simple craft
function IngredientData.FormatCookingNotification(result, qualityGrade)
	local dish = "Mystery Dish"
	if type(result) == "table" and result.displayName then
		dish = tostring(result.displayName)
	end
	local buffId = (type(result) == "table") and result.buffId
	local typeTitle = IngredientData.GetCraftBuffTypeTitle(buffId)
	local plate = IngredientData.GetQualityPlateName(qualityGrade)
	local blurb = IngredientData.GetCraftBuffEffectBlurb(buffId)
	local core
	if plate ~= "" then
		core = string.format("%s · %s · %s", typeTitle, dish, plate)
	else
		core = string.format("%s · %s", typeTitle, dish)
	end
	if blurb ~= "" then
		return core .. " (" .. blurb .. ")"
	end
	return core
end

return IngredientData
