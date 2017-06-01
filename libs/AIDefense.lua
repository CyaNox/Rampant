local aiDefense = {}

-- imports

local constants = require("Constants")
local mapUtils = require("MapUtils")
local unitGroupUtils = require("UnitGroupUtils")
local neighborUtils = require("NeighborUtils")

-- constants

local RETREAT_GRAB_RADIUS = constants.RETREAT_GRAB_RADIUS

local MOVEMENT_PHEROMONE = constants.MOVEMENT_PHEROMONE
local PLAYER_PHEROMONE = constants.PLAYER_PHEROMONE
local BASE_PHEROMONE = constants.BASE_PHEROMONE

local HALF_CHUNK_SIZE = constants.HALF_CHUNK_SIZE

local SQUAD_RETREATING = constants.SQUAD_RETREATING

local RETREAT_FILTER = constants.RETREAT_FILTER

local RETREAT_TRIGGERED = constants.RETREAT_TRIGGERED

local INTERVAL_LOGIC = constants.INTERVAL_LOGIC

local NEST_COUNT = constants.NEST_COUNT
local WORM_COUNT = constants.WORM_COUNT

-- imported functions

local getNeighborChunksWithDirection = mapUtils.getNeighborChunksWithDirection
local findNearBySquad = unitGroupUtils.findNearBySquad
local addSquadMovementPenalty = unitGroupUtils.addSquadMovementPenalty
local createSquad = unitGroupUtils.createSquad
local membersToSquad = unitGroupUtils.membersToSquad
local scoreNeighborsWithDirection = neighborUtils.scoreNeighborsWithDirection
local canMoveChunkDirection = mapUtils.canMoveChunkDirection

-- module code

local function validRetreatLocation(x, chunk, neighborChunk)
    return canMoveChunkDirection(x, chunk, neighborChunk)
end

local function scoreRetreatLocation(squad, neighborChunk, surface)
    local safeScore = -neighborChunk[BASE_PHEROMONE] + neighborChunk[MOVEMENT_PHEROMONE]
    local dangerScore = surface.get_pollution(neighborChunk) + (neighborChunk[PLAYER_PHEROMONE] * 100) --+ (neighborChunk[ENEMY_BASE_GENERATOR] * 50)
    return safeScore - dangerScore
end

function aiDefense.retreatUnits(chunk, squad, regionMap, surface, natives, tick)
    if (tick - chunk[RETREAT_TRIGGERED] > INTERVAL_LOGIC) and (chunk[NEST_COUNT] == 0) and (chunk[WORM_COUNT] == 0) then
	local performRetreat = false
	local enemiesToSquad = nil
	local tempNeighbors = {false, false, false, false, false, false, false, false}
	
	if not squad then
	    enemiesToSquad = surface.find_enemy_units(chunk, RETREAT_GRAB_RADIUS)
	    performRetreat = #enemiesToSquad > 0
	elseif squad.group.valid and (squad.status ~= SQUAD_RETREATING) and not squad.kamikaze then
	    performRetreat = #squad.group.members > 1
	end
	
	if performRetreat then
	    chunk[RETREAT_TRIGGERED] = tick
	    local exitPath,_  = scoreNeighborsWithDirection(chunk,
							    getNeighborChunksWithDirection(regionMap, chunk.cX, chunk.cY, tempNeighbors),
							    validRetreatLocation,
							    scoreRetreatLocation,
							    nil,
							    surface,
							    false)
	    if exitPath then
		local retreatPosition = { x = exitPath.x + HALF_CHUNK_SIZE,
					  y = exitPath.y + HALF_CHUNK_SIZE }
                
		-- in order for units in a group attacking to retreat, we have to create a new group and give the command to join
		-- to each unit, this is the only way I have found to have snappy mid battle retreats even after 0.14.4
                
		local newSquad = findNearBySquad(natives, retreatPosition, HALF_CHUNK_SIZE, RETREAT_FILTER)
                
		if not newSquad then
		    newSquad = createSquad(retreatPosition, surface, natives)
		    newSquad.status = SQUAD_RETREATING
		    newSquad.cycles = 4
		end
		
		if enemiesToSquad then
		    membersToSquad(newSquad, enemiesToSquad, false)
		else
		    membersToSquad(newSquad, squad.group.members, true)
		    newSquad.penalties = squad.penalties
		    if squad.rabid then
			newSquad.rabid = true
		    end
		end
		addSquadMovementPenalty(newSquad, chunk.cX, chunk.cY)
	    end
	end
    end
end

return aiDefense
