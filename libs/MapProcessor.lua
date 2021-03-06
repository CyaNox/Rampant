local mapProcessor = {}

-- imports

local unitGroupUtils = require("UnitGroupUtils")
local pheromoneUtils = require("PheromoneUtils")
local aiAttackWave = require("AIAttackWave")
local aiPredicates = require("AIPredicates")
local constants = require("Constants")
local mapUtils = require("MapUtils")
local playerUtils = require("PlayerUtils")
local chunkUtils = require("ChunkUtils")
local mathUtils = require("MathUtils")

-- constants

local PROCESS_QUEUE_SIZE = constants.PROCESS_QUEUE_SIZE

local SCAN_QUEUE_SIZE = constants.SCAN_QUEUE_SIZE

local CHUNK_SIZE = constants.CHUNK_SIZE
local DOUBLE_CHUNK_SIZE = constants.DOUBLE_CHUNK_SIZE
local TRIPLE_CHUNK_SIZE = constants.TRIPLE_CHUNK_SIZE

local PROCESS_PLAYER_BOUND = constants.PROCESS_PLAYER_BOUND
local CHUNK_TICK = constants.CHUNK_TICK

local SENTINEL_IMPASSABLE_CHUNK  = constants.SENTINEL_IMPASSABLE_CHUNK

local AI_SQUAD_COST = constants.AI_SQUAD_COST
local AI_VENGENCE_SQUAD_COST = constants.AI_VENGENCE_SQUAD_COST

local MOVEMENT_PHEROMONE = constants.MOVEMENT_PHEROMONE

-- imported functions

local scents = pheromoneUtils.scents
local processPheromone = pheromoneUtils.processPheromone
local playerScent = pheromoneUtils.playerScent

local formSquads = aiAttackWave.formSquads

local getChunkByPosition = mapUtils.getChunkByPosition
local getChunkByXY = mapUtils.getChunkByXY

local recycleBiters = unitGroupUtils.recycleBiters

local validPlayer = playerUtils.validPlayer

local analyzeChunk = chunkUtils.analyzeChunk

local getNestCount = chunkUtils.getNestCount
local getEnemyStructureCount = chunkUtils.getEnemyStructureCount

local canAttack = aiPredicates.canAttack

local euclideanDistanceNamed = mathUtils.euclideanDistanceNamed

local mMin = math.min

local mRandom = math.random

-- module code

local function nonRepeatingRandom(players)
    local ordering = {}
    for _,player in pairs(players) do
	ordering[#ordering+1] = player.index
    end
    for i=#ordering,1,-1 do
	local s = mRandom(i)
	local t = ordering[i]
	ordering[i] = ordering[s]
	ordering[s] = t
    end
    return ordering
end

--[[
    processing is not consistant as it depends on the number of chunks that have been generated
    so if we process 400 chunks an iteration and 200 chunks have been generated than these are
    processed 3 times a second and 1200 generated chunks would be processed once a second
    In theory, this might be fine as smaller bases have less surface to attack and need to have 
    pheromone dissipate at a faster rate.
--]]
function mapProcessor.processMap(regionMap, surface, natives, tick)
    local roll = regionMap.processRoll
    local index = regionMap.processIndex
    
    if (index == 1) then
        roll = mRandom()
        regionMap.processRoll = roll
    end
    
    local squads = canAttack(natives, surface) and (0.11 <= roll) and (roll <= 0.35) and (natives.points >= AI_SQUAD_COST)
    
    local processQueue = regionMap.processQueue
    local endIndex = mMin(index + PROCESS_QUEUE_SIZE, #processQueue)
    for x=index,endIndex do
        local chunk = processQueue[x]
	
	if (chunk[CHUNK_TICK] ~= tick) then
	    chunk[CHUNK_TICK] = tick
	    
	    processPheromone(regionMap, chunk)

	    if squads and (getNestCount(regionMap, chunk) > 0) then
		formSquads(regionMap, surface, natives, chunk, AI_SQUAD_COST)
		squads = (natives.points >= AI_SQUAD_COST) and (#natives.squads < natives.maxSquads)
	    end
	    
	    scents(regionMap, chunk)
	end
    end
    
    if (endIndex == #processQueue) then
        regionMap.processIndex = 1
    else
        regionMap.processIndex = endIndex + 1
    end
end

--[[
    Localized player radius were processing takes place in realtime, doesn't store state
    between calls.
    vs 
    the slower passive version processing the entire map in multiple passes.
--]]
function mapProcessor.processPlayers(players, regionMap, surface, natives, tick)
    -- put down player pheromone for player hunters
    -- randomize player order to ensure a single player isn't singled out
    local playerOrdering = nonRepeatingRandom(players)

    local roll = mRandom()

    local allowingAttacks = canAttack(natives, surface)

    local squads = allowingAttacks and (0.11 <= roll) and (roll <= 0.20) and (natives.points >= AI_SQUAD_COST)
    
    for i=1,#playerOrdering do
	local player = players[playerOrdering[i]]
	if validPlayer(player) then 
	    local playerChunk = getChunkByPosition(regionMap, player.character.position)
	    
	    if (playerChunk ~= SENTINEL_IMPASSABLE_CHUNK) then
		playerScent(playerChunk)
	    end
	end
    end
    for i=1,#playerOrdering do
	local player = players[playerOrdering[i]]
	if validPlayer(player) then 
	    local playerChunk = getChunkByPosition(regionMap, player.character.position)
	    
	    if (playerChunk ~= SENTINEL_IMPASSABLE_CHUNK) then
		local vengence = (allowingAttacks and
				      (natives.points >= AI_VENGENCE_SQUAD_COST) and
				      ((getEnemyStructureCount(regionMap, playerChunk) > 0) or (playerChunk[MOVEMENT_PHEROMONE] < natives.retreatThreshold)))
		
		for x=playerChunk.x - PROCESS_PLAYER_BOUND, playerChunk.x + PROCESS_PLAYER_BOUND, 32 do
		    for y=playerChunk.y - PROCESS_PLAYER_BOUND, playerChunk.y + PROCESS_PLAYER_BOUND, 32 do
			local chunk = getChunkByXY(regionMap, x, y)
			
			if (chunk ~= SENTINEL_IMPASSABLE_CHUNK) and (chunk[CHUNK_TICK] ~= tick) then
			    chunk[CHUNK_TICK] = tick

			    processPheromone(regionMap, chunk)

			    if (getNestCount(regionMap, chunk) > 0) then
				if squads then
				    formSquads(regionMap, surface, natives, chunk, AI_SQUAD_COST)
				    squads = (natives.points >= AI_SQUAD_COST) and (#natives.squads < natives.maxSquads)
				end
				if vengence then
				    formSquads(regionMap, surface, natives, chunk, AI_VENGENCE_SQUAD_COST)
				    vengence = (natives.points >= AI_VENGENCE_SQUAD_COST) and (#natives.squads < natives.maxSquads)
				end
			    end
			    
			    scents(regionMap, chunk)
			end
		    end
		end
	    end
	end
    end
end

--[[
    Passive scan to find entities that have been generated outside the factorio event system
--]]
function mapProcessor.scanMap(regionMap, surface, natives)
    local index = regionMap.scanIndex

    local unitCountQuery = regionMap.filteredEntitiesEnemyUnitQuery
    local offset = unitCountQuery.area[2]
    local chunkBox = unitCountQuery.area[1]

    local processQueue = regionMap.processQueue
    local endIndex = mMin(index + SCAN_QUEUE_SIZE, #processQueue)
    
    for x=index,endIndex do
	local chunk = processQueue[x]

	chunkBox[1] = chunk.x
	chunkBox[2] = chunk.y
	
	offset[1] = chunk.x + CHUNK_SIZE
	offset[2] = chunk.y + CHUNK_SIZE
	
	local unitCount = surface.count_entities_filtered(unitCountQuery)

	if (unitCount > 300) then
	    local closeBy = false
	    local squads = natives.squads
	    for i=1, #squads do
		local squadGroup = squads[i].group
		if squadGroup.valid and (euclideanDistanceNamed(squadGroup.position, chunk) < DOUBLE_CHUNK_SIZE) then
		    closeBy = true
		    break
		end
	    end
	    
	    if not closeBy then
		recycleBiters(natives, surface.find_enemy_units(chunk, TRIPLE_CHUNK_SIZE))
	    end
	end

	analyzeChunk(chunk, natives, surface, regionMap)
    end

    if (endIndex == #processQueue) then
	regionMap.scanIndex = 1
    else
	regionMap.scanIndex = endIndex + 1
    end
end

return mapProcessor
