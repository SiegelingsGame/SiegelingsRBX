-- FurnitureCatalog.lua — ReplicatedStorage.Modules

local FurnitureCatalog = {}

local ENTRIES = {
	{ id = "chair_wood_01", category = "Chair", displayName = "Wood Chair", coinCost = 400, modelName = "PlaceholderCube" },
	{ id = "chair_plush_01", category = "Chair", displayName = "Plush Chair", coinCost = 650, modelName = "PlaceholderCube" },
	{ id = "bed_single_01", category = "Bed", displayName = "Single Bed", coinCost = 900, modelName = "PlaceholderCube" },
	{ id = "bed_bunk_01", category = "Bed", displayName = "Bunk Frame", coinCost = 1200, modelName = "PlaceholderCube" },
	{ id = "lamp_floor_01", category = "Lamp", displayName = "Floor Lamp", coinCost = 350, modelName = "PlaceholderCube" },
	{ id = "lamp_desk_01", category = "Lamp", displayName = "Desk Lamp", coinCost = 280, modelName = "PlaceholderCube" },
	{ id = "table_dining_01", category = "Table", displayName = "Dining Table", coinCost = 700, modelName = "PlaceholderCube" },
	{ id = "table_side_01", category = "Table", displayName = "Side Table", coinCost = 450, modelName = "PlaceholderCube" },
	{ id = "dresser_01", category = "Dresser", displayName = "Dresser", coinCost = 800, modelName = "PlaceholderCube" },
	{ id = "dresser_tall_01", category = "Dresser", displayName = "Tall Dresser", coinCost = 950, modelName = "PlaceholderCube" },
	{ id = "drawer_unit_01", category = "Drawer", displayName = "Drawer Unit", coinCost = 550, modelName = "PlaceholderCube" },
	{ id = "drawer_night_01", category = "Drawer", displayName = "Nightstand", coinCost = 420, modelName = "PlaceholderCube" },
	{ id = "appliance_fridge_01", category = "Appliance", displayName = "Fridge", coinCost = 1100, modelName = "PlaceholderCube" },
	{ id = "appliance_stove_01", category = "Appliance", displayName = "Stove", coinCost = 1000, modelName = "PlaceholderCube" },
	{ id = "other_rug_01", category = "Other", displayName = "Rug", coinCost = 300, modelName = "PlaceholderCube" },
	{ id = "other_plant_01", category = "Other", displayName = "Potted Plant", coinCost = 250, modelName = "PlaceholderCube" },
}

local byId = {}
for _, e in ipairs(ENTRIES) do
	byId[e.id] = e
end

function FurnitureCatalog.GetById(id)
	return byId[id]
end

function FurnitureCatalog.GetAll()
	return ENTRIES
end

function FurnitureCatalog.GetByCategory(category)
	local t = {}
	for _, e in ipairs(ENTRIES) do
		if e.category == category then
			table.insert(t, e)
		end
	end
	return t
end

local CATEGORIES = { "Chair", "Bed", "Lamp", "Table", "Dresser", "Drawer", "Appliance", "Other" }

function FurnitureCatalog.GetCategories()
	return CATEGORIES
end

return FurnitureCatalog
