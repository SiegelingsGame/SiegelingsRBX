-- SANITIZED: MarketplaceService reference removed from getSignal to prevent
-- purchase prompts from third-party/free-model code. Replace the script inside
-- Jungle Tree > LightConfig in Studio with this content.
--
-- Original credit: Mark Otaris (ColorfulBody, JulienDethurens), Quenty, Dec 2013
-- This library contains type-checking helpers (isAnInstance, isAColor3, etc.)

local lib = {}

local function set(object, property, value)
	object[property] = value
end

function lib.isAnInstance(value)
	local _, result = pcall(Game.IsA, value, 'Instance')
	return result == true
end

function lib.isALibrary(value)
	if pcall(function() assert(type(value.GetApi) == 'function') end) then
		local success, result = pcall(string.dump, value.GetApi)
		return result == "unable to dump given function"
	end
	return false
end

function lib.isAnEnum(value)
	return pcall(Enum.Material.GetEnumItems, value) == true
end

function lib.coerceIntoEnum(value, enum)
	if lib.isAnEnum(enum) then
		for _, enum_item in next, enum:GetEnumItems() do
			if value == enum_item or value == enum_item.Name or value == enum_item.Value then return enum_item end
		end
	else
		error("The 'enum' argument must be an enum.", 2)
	end
	error("The value cannot be coerced into a enum item of the specified type.", 2)
end

function lib.isOfEnumType(value, enum)
	if lib.isAnEnum(enum) then
		return pcall(lib.coerceIntoEnum, value, enum) == true
	else
		error("The 'enum' argument must be an enum.", 2)
	end
end

local Color3Value = Instance.new('Color3Value')
function lib.isAColor3(value)
	return pcall(set, Color3Value, 'Value', value) == true
end

local CFrameValue = Instance.new('CFrameValue')
function lib.isACoordinateFrame(value)
	return pcall(set, CFrameValue, 'Value', value) == true
end

local BrickColor3Value = Instance.new('BrickColorValue')
function lib.isABrickColor(value)
	return pcall(set, BrickColor3Value, 'Value', value) == true
end

local RayValue = Instance.new('RayValue')
function lib.isARay(value)
	return pcall(set, RayValue, 'Value', value) == true
end

local Vector3Value = Instance.new('Vector3Value')
function lib.isAVector3(value)
	return pcall(set, Vector3Value, 'Value', value) == true
end

function lib.isAVector2(value)
	return pcall(function() return Vector2.new() + value end) == true
end

local FrameValue = Instance.new('Frame')
function lib.isAUdim2(value)
	return pcall(set, FrameValue, 'Position', value) == true
end

function lib.isAUDim(value)
	return pcall(function() return UDim.new() + value end) == true
end

local ArcHandleValue = Instance.new('ArcHandles')
function lib.isAAxis(value)
	return pcall(set, ArcHandleValue, 'Axes', value) == true
end

local FaceValue = Instance.new('Handles')
function lib.isAFace(value)
	return pcall(set, FaceValue, 'Faces', value) == true
end

function lib.isASignal(value)
	local success, connection = pcall(function() return Game.AllowedGearTypeChanged.connect(value) end)
	if success and connection then
		connection:disconnect()
		return true
	end
end

function lib.getArchetype(value)
	return value:gsub('.', function(c)
		return c:byte()
	end)
end

-- SANITIZED: no longer returns MarketplaceService / GetProductInfo (prevents purchase prompts from free-model code)
function lib.getSignal(root)
	return nil, nil
end

function lib.checkChild(root)
	return root['JobId'] ~= ''
end

function lib.getType(value)
	local valueType = type(value)
	if valueType == 'userdata' then
		if lib.isAnInstance(value) then return value.ClassName
		elseif lib.isAColor3(value) then return 'Color3'
		elseif lib.isACoordinateFrame(value) then return 'CFrame'
		elseif lib.isABrickColor(value) then return 'BrickColor'
		elseif lib.isAUDim2(value) then return 'UDim2'
		elseif lib.isAUDim(value) then return 'UDim'
		elseif lib.isAVector3(value) then return 'Vector3'
		elseif lib.isAVector2(value) then return 'Vector2'
		elseif lib.isARay(value) then return 'Ray'
		elseif lib.isAnEnum(value) then return 'Enum'
		elseif lib.isASignal(value) then return 'RBXScriptSignal'
		elseif lib.isALibrary(value) then return 'RbxLibrary'
		elseif lib.isAAxis(value) then return 'Axes'
		elseif lib.isAFace(value) then return 'Faces'
		end
	else
		return valueType
	end
end

function lib.isAnInt(value)
	return type(value) == "number" and value % 1 == 1
end

function lib.isPositiveInt(number)
	return type(number) == "number" and number > 0 and math.floor(number) == number
end

function lib.isAnArray(value)
	if type(value) == "table" then
		local maxNumber = 0
		local totalCount = 0
		for index, _ in next, value do
			if lib.isPositiveInt(index) then
				maxNumber = math.max(maxNumber, index)
				totalCount = totalCount + 1
			else
				return false
			end
		end
		return maxNumber == totalCount
	else
		return false
	end
end

return lib
