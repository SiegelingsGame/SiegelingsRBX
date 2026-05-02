--[[
	CinematicCellConfig.lua
	ReplicatedStorage/Modules/CinematicCellConfig (ModuleScript)

	Centralized UI config for the "Cinematic Badge" inventory cells.
	Keep all colors + icon mappings here so UI logic can stay clean.
]]

local Config = {}

-- Abbrev -> { name, color }
Config.Rarities = {
	C  = { name = "Common",    color = Color3.fromRGB(160, 160, 170) },
	UC = { name = "Uncommon",  color = Color3.fromRGB(60, 200, 120) },
	R  = { name = "Rare",      color = Color3.fromRGB(110, 170, 255) },
	M  = { name = "Mystic",    color = Color3.fromRGB(180, 80, 255) }, -- placeholder (swap if you use Epic)
	L  = { name = "Legendary", color = Color3.fromRGB(255, 170, 70) },
}

-- Full rarity name -> abbrev (fallbacks)
Config.RarityAbbrevOf = {
	Common = "C",
	Uncommon = "UC",
	Rare = "R",
	Epic = "M",      -- treat Epic as Mystic badge for now
	Mystic = "M",
	Legendary = "L",
}

-- Vibrant panel colors for inventory "model area" (split-card top; silhouettes read on bright ground).
Config.ElementBrightBackgrounds = {
	Fire = Color3.fromRGB(255, 120, 55),
	Ice = Color3.fromRGB(140, 210, 255),
	Water = Color3.fromRGB(70, 170, 255),
	Earth = Color3.fromRGB(210, 160, 85),
	Wind = Color3.fromRGB(140, 240, 190),
	Lightning = Color3.fromRGB(220, 200, 255),
	Shadow = Color3.fromRGB(150, 120, 220),
	Light = Color3.fromRGB(255, 245, 160),
	Psychic = Color3.fromRGB(240, 140, 240),
	Poison = Color3.fromRGB(170, 255, 120),
	Metal = Color3.fromRGB(200, 210, 225),
	Undead = Color3.fromRGB(160, 200, 160),
}

-- Element -> emoji (swap later to rbxassetid:// icons)
Config.Elements = {
	Wind = "🌪️",
	Earth = "🪨",
	Fire = "🔥",
	Water = "💧",
	Ice = "❄️",
	Lightning = "⚡",
	Psychic = "🧠",
	Poison = "☠️",
	Shadow = "🌑",
	Light = "🌟",
	Metal = "⚙️",
	Undead = "🧟",
}

-- Role/Class -> emoji
Config.Roles = {
	Support = "🛟",
	Bruiser = "🥊",
	Guardian = "🛡️",
	Assassin = "🗡️",
	Mage = "🔮",
	Tank = "🧱",
	Healer = "💚",
	Ranger = "🏹",
}

function Config.GetRarityAbbrev(rarityName)
	if type(rarityName) ~= "string" then return "C" end
	return Config.RarityAbbrevOf[rarityName] or "C"
end

function Config.GetRarityColor(abbrevOrName)
	if type(abbrevOrName) ~= "string" then return Config.Rarities.C.color end
	local abbrev = Config.Rarities[abbrevOrName] and abbrevOrName or Config.GetRarityAbbrev(abbrevOrName)
	return (Config.Rarities[abbrev] and Config.Rarities[abbrev].color) or Config.Rarities.C.color
end

function Config.GetElementIcon(elementName)
	if type(elementName) ~= "string" then return "?" end
	local em = Config.Elements[elementName]
	if em then return em end
	-- ASCII fallback if emoji missing from table (still readable in any font)
	return string.upper(string.sub(elementName, 1, 2))
end

function Config.GetElementBrightBackground(elementName)
	if type(elementName) ~= "string" then
		return Color3.fromRGB(90, 92, 110)
	end
	local c = Config.ElementBrightBackgrounds[elementName]
	if c then return c end
	return Color3.fromRGB(120, 125, 150)
end

function Config.GetRoleIcon(roleName)
	if type(roleName) ~= "string" then return "?" end
	local em = Config.Roles[roleName]
	if em then return em end
	return string.upper(string.sub(roleName, 1, 2))
end

return Config

