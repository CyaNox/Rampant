local buildUtils = {}

-- imports

local constants = require("Constants")
local mathUtils = require("MathUtils")

local baseRegisterUtils = require("BaseRegisterUtils")

local mapUtils = require("MapUtils")

-- constants

local MAGIC_MAXIMUM_BASE_NUMBER = constants.MAGIC_MAXIMUM_BASE_NUMBER

local AI_NEST_COST = constants.AI_NEST_COST
local AI_WORM_COST = constants.AI_WORM_COST

local NEST_COUNT = constants.NEST_COUNT

local DOUBLE_CHUNK_SIZE = constants.DOUBLE_CHUNK_SIZE

-- imported functions

local registerEnemyBaseStructure = baseRegisterUtils.registerEnemyBaseStructure
local gaussianRandomRange = mathUtils.gaussianRandomRange

local mRandom = math.random

local getChunkByPosition = mapUtils.getChunkByPosition

-- module code

function buildUtils.buildNest(regionMap, base, surface, targetPosition, name)
    local position = surface.find_non_colliding_position(name, targetPosition, DOUBLE_CHUNK_SIZE, 2)
    local chunk = getChunkByPosition(regionMap, position.x, position.y)
    local nest = nil
    if position and chunk and (chunk[NEST_COUNT] < 3) then
	local biterSpawner = {name=name, position=position}
	nest = surface.create_entity(biterSpawner)
	registerEnemyBaseStructure(regionMap, nest, base)
    end
    return nest
end

function buildUtils.buildHive(regionMap, base, surface)
    local valid = false
    local hive = buildUtils.buildNest(regionMap, base, surface, base, "biter-spawner-hive")
    if hive then
	if (#base.hives == 0) then
	    base.x = hive.position.x
	    base.y = hive.position.y
	end
	base.hives[#base.hives+1] = hive
	valid = true
    end
    return valid
end

function buildUtils.buildOutpost(regionMap, natives, base, surface, tendril)
    local foundHive = false
    for _,_ in pairs(base.hives) do
	foundHive = true
	break
    end
    if not foundHive or (base.upgradePoints < 10) then
	return
    end

    if not tendril.unit.valid then
	return
    end
    local position = tendril.unit.position
    local generator = natives.randomGenerator
    generator.re_seed(mRandom(MAGIC_MAXIMUM_BASE_NUMBER))

    for level=0,(base.level * 0.5) do
	local slices = (level * 3)
	slices = gaussianRandomRange(slices, slices * 0.1, slices * 0.6, slices * 1.4, generator)
	local slice = (2 * math.pi) / slices
	local pos = 0
	local thing
	local cost
	local radiusAdjustment
	if (generator() < 0.3) then
	    thing = "small-worm-turret"
	    cost = AI_WORM_COST
	    radiusAdjustment = -4
	else
	    thing = "biter-spawner"
	    cost = AI_NEST_COST
	    radiusAdjustment = 0
	end
	for _ = 1, slices do
	    if (base.upgradePoints < 10) then
		return
	    end
	    local radius = 10 * level
	    local distortion = gaussianRandomRange(radius, 10, radius - 7.5 + radiusAdjustment, radius + 7.5 + radiusAdjustment, generator)
	    local nestPosition = {x = position.x + (distortion * math.cos(pos)),
				  y = position.y + (distortion * math.sin(pos))}
	    local biterSpawner = {name=thing, position=nestPosition}
	    if surface.can_place_entity(biterSpawner)  then
		registerEnemyBaseStructure(regionMap, surface.create_entity(biterSpawner), base)
		base.upgradePoints = base.upgradePoints - cost
	    end
	    pos = pos + slice 
	end
    end    
end

function buildUtils.buildOrder(regionMap, natives, base, surface)
    local foundHive = false
    for _,_ in pairs(base.hives) do
	foundHive = true
	break
    end
    if not foundHive or (base.upgradePoints < 10) then
	return
    end
    
    local generator = natives.randomGenerator
    generator.re_seed(base.pattern)

    for level=0,base.level do
	local slices = (level * 3)
	slices = gaussianRandomRange(slices, slices * 0.1, slices * 0.6, slices * 1.4, generator)
	local slice = (2 * math.pi) / slices
	local pos = 0
	local thing
	local cost
	local radiusAdjustment
	if (generator() < 0.3) then
	    thing = "small-worm-turret"
	    cost = AI_WORM_COST
	    radiusAdjustment = -4
	else
	    thing = "biter-spawner"
	    cost = AI_NEST_COST
	    radiusAdjustment = 0
	end
	for _ = 1, slices do
	    if (base.upgradePoints < 10) then
		return
	    end
	    local radius = 10 * level
	    local distortion = gaussianRandomRange(radius, 10, radius - 7.5 + radiusAdjustment, radius + 7.5 + radiusAdjustment, generator)
	    local nestPosition = {x = base.x + (distortion * math.cos(pos)),
				  y = base.y + (distortion * math.sin(pos))}
	    local biterSpawner = {name=thing, position=nestPosition}
	    if surface.can_place_entity(biterSpawner)  then
		registerEnemyBaseStructure(regionMap, surface.create_entity(biterSpawner), base)
		base.upgradePoints = base.upgradePoints - cost
	    end
	    pos = pos + slice 
	end
    end    
end

return buildUtils
