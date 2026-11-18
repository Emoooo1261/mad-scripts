local configServer = require 'config.server'
local spawnAreaZonesCityDocks = {}
local spawnAreaZonesPaleto = {}
local spawnAreaZonesCoords = {}
--- list of vehicles that are not actively used in a job and are not despawned, because they could still be occupied
--- to be cleaned up on resource stop
local expiredVehicles = {}  -- TODO

for index, truckCoords in ipairs(configServer.vehicles.truckSpawnCoords) do
    local trailerCoords = configServer.vehicles.trailerSpawnCoords[index]
    if not trailerCoords then
        error(('Missing trailer spawn coordinates for truck spawn %s'):format(index), 1)
    end

    spawnAreaZonesCoords[#spawnAreaZonesCoords + 1] = vec4(
        (truckCoords.x + trailerCoords.x) / 2,
        (truckCoords.y + trailerCoords.y) / 2,
        (truckCoords.z + trailerCoords.z) / 2,
        truckCoords.w
    )

    -- the spawn area zones indices match the truck and trailer spawn coords 
    spawnAreaZonesCityDocks[index] = lib.zones.box({
        coords = spawnAreaZonesCoords[index],
        size = configServer.vehicles.spawnAreaSize,
        rotation = truckCoords.w
    })
end

for index, trailerCoords in ipairs(configServer.vehicles.paletoTrailerSpawnCoords) do

    spawnAreaZonesCoords[#spawnAreaZonesCoords + 1] = vec4(
        trailerCoords.x,
        trailerCoords.y,
        trailerCoords.z,
        trailerCoords.w
    )

    -- the spawn area zones indices match the truck and trailer spawn coords 
    spawnAreaZonesPaleto[index] = lib.zones.box({
        coords = trailerCoords,
        size = configServer.vehicles.spawnAreaSize,
        rotation = trailerCoords.w
    })
end

RegisterCommand('truckingjobspawnareadebug', function(source)
    if source == 0 then
        print('[mad_truckingjob] Run /truckingjobspawnareadebug in-game to toggle your spawn-area visualization.')
        return
    end

    TriggerClientEvent(
        'mad_truckingjob:client:toggleSpawnAreaDebug',
        source,
        spawnAreaZonesCoords,
        configServer.vehicles.spawnAreaSize
    )
end, false)

local function spawnVehicle(model, type, coords)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-model=', model, '-type=', type, '-coords=', coords)

    -- lib.requestModel(model)

    -- Spawn vehicle
    local vehicle = CreateVehicleServerSetter(
        joaat(model),
        type,
        coords.x,
        coords.y,
        coords.z,
        coords.w
    )

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        error('Failed to spawn truck!', 1)
    end

    -- Keep entity persistent
    SetEntityOrphanMode(vehicle, 2)

    lib.print.debug('[OUT]', func_name, '-vehicle=', vehicle)

    return vehicle
end

--- This only checks if the center? point of the vehicle entity is inside the box spawn area.
--- That check will be very innacurate with bigger vehicles.
--- Perfect fix would be to have the full (or approximate) dimensions of the vehicle and 
--- check multiple points from it to see if any of them are inside the box.
--- That is too complicated and unnecessary so just make spawn boxes bigger.
local function isVehicleSpawnAreaEmpty(spawnAreaZone)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-spawnAreaZone=', spawnAreaZone.id)

    local vehicles = GetAllVehicles()
    local isEmpty = true

    for _, vehicle in ipairs(vehicles) do
        if spawnAreaZone:contains(GetEntityCoords(vehicle)) then
            isEmpty = false
            break
        end
    end

    lib.print.debug('[OUT]', func_name, '-isEmpty=', isEmpty)

    return isEmpty
end

function RegisterJobVehicleForClient(source, truckAndTrailerData)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-truck=', truckAndTrailerData.truck, '-truckCoords=', truckAndTrailerData.truckCoords, '-trailer=', truckAndTrailerData.trailer, '-trailerCoords=', truckAndTrailerData.trailerCoords)

    local success = false
    if truckAndTrailerData.truck and truckAndTrailerData.trailer then
        success = true
        exports.qbx_vehiclekeys:GiveKeys(source, truckAndTrailerData.truck)  -- Only need keys for truck, trailers don't have keys

        local truckNetId = NetworkGetNetworkIdFromEntity(truckAndTrailerData.truck)
        local trailerNetId = NetworkGetNetworkIdFromEntity(truckAndTrailerData.trailer)

        -- provide NetId so that vehicle is consistent between client and server, if false the Client Event will notify about problem
        TriggerClientEvent('mad_truckingjob:client:registerVehicleTargets', source, truckNetId, trailerNetId)
    end

    lib.print.debug('[OUT]', func_name, '-success=', success)
    return success
end

function SpawnSecondTrailer()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local trailerModel = joaat(configServer.vehicles.trailers[1])
    local trailerType = configServer.vehicles.trailerType
    local result = {truck = nil,
                    trailer = nil,
                    truckCoords = nil,
                    trailerCoords = nil}

    for index, trailerCoords in ipairs(configServer.vehicles.paletoTrailerSpawnCoords) do
        if isVehicleSpawnAreaEmpty(spawnAreaZonesPaleto[index]) then
            result.trailer = spawnVehicle(trailerModel, trailerType, trailerCoords)
            result.trailerCoords = trailerCoords
            break
        end
    end

    lib.print.debug('[OUT]', func_name, '-truck=', result.truck, '-truckCoords=', result.truckCoords, '-trailer=', result.trailer, '-trailerCoords=', result.trailerCoords)
    return result
end

function SpawnJobVehicle()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local truckModel = joaat(configServer.vehicles.trucks[1])  -- LUA LISTS START AT 1???????!?!?!?!?
    local truckType = configServer.vehicles.truckType
    -- local truckSpawnCoords = configServer.vehicles.truckSpawnCoords

    local trailerModel = joaat(configServer.vehicles.trailers[1])
    local trailerType = configServer.vehicles.trailerType

    local result = {truck = nil,
                    trailer = nil,
                    truckCoords = nil,
                    trailerCoords = nil}

    -- for index, truckCoords in ipairs(truckSpawnCoords) do
    --     local trailerCoords = configServer.vehicles.trailerSpawnCoords[index]
    --     if isVehicleSpawnAreaEmpty(spawnAreaZonesCityDocks[index]) then
    --         result.truck = spawnVehicle(truckModel, truckType, truckCoords)
    --         result.truckCoords = truckCoords

    --         result.trailer = spawnVehicle(trailerModel, trailerType, trailerCoords)
    --         result.trailerCoords = trailerCoords

    --         break
    --     end
    -- end  -- TODO COMMENTED OUT FOR TESTING

    result.truck = spawnVehicle(truckModel, truckType, vec4(157.54, 6428.02, 31.53, 339.99))    -- PALETO SPAWN FIX AFTER DEBUG
    result.trailer = spawnVehicle(trailerModel, trailerType, vec4(147.54, 6428.02, 31.53, 339.99)) -- PALETO SPAWN FIX AFTER DEBUG
        result.truckCoords = vec4(157.54, 6428.02, 31.53, 339.99)
        result.trailerCoords = vec4(147.54, 6428.02, 31.53, 339.99)


    lib.print.debug('[OUT]', func_name, '-truck=', result.truck, '-truckCoords=', result.truckCoords, '-trailer=', result.trailer, '-trailerCoords=', result.trailerCoords)
    return result
end

-- TODO check when vehicle is being despawned.
-- It shouldn't be despawned when job expires or if it is not close to the owner?
function DespawnJobVehicle(vehicleNetId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-vehicle=', vehicleNetId)

    local vehicle = NetworkGetEntityFromNetworkId(vehicleNetId)

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    DeleteEntity(vehicle)

    lib.print.debug('[OUT]', func_name, '-')
end