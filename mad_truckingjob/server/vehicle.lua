local configServer = require 'config.server'
local activeJobVehicles = {}
local expiredVehicles = {}
local jobVehicleOwnerStateKey = 'mad_truckingjob:owner'
local jobVehicleContractStateKey = 'mad_truckingjob:contractId'
local jobVehicleRoleStateKey = 'mad_truckingjob:role'

local function setJobVehicleIdentity(vehicle, citizenId, contractId, role)
    if not vehicle or not DoesEntityExist(vehicle) then
        return
    end

    local state = Entity(vehicle).state
    state:set(jobVehicleOwnerStateKey, citizenId, true)
    state:set(jobVehicleContractStateKey, tostring(contractId), true)
    state:set(jobVehicleRoleStateKey, role, true)
end

local function clearJobVehicleIdentity(vehicle, citizenId, contractId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return
    end

    local state = Entity(vehicle).state
    if state[jobVehicleOwnerStateKey] == citizenId
        and state[jobVehicleContractStateKey] == tostring(contractId) then
        state:set(jobVehicleOwnerStateKey, nil, true)
        state:set(jobVehicleContractStateKey, nil, true)
        state:set(jobVehicleRoleStateKey, nil, true)
    end
end

function SetActiveJobVehiclesForCitizenId(citizenId, truck, trailer, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId=', contractId, '-truck=', truck, '-trailer=', trailer)

    activeJobVehicles[citizenId] = activeJobVehicles[citizenId] or {}  -- initialize the inside struct

    if truck ~= nil then
        activeJobVehicles[citizenId].truck = truck
        setJobVehicleIdentity(truck, citizenId, contractId, 'truck')
    end
    activeJobVehicles[citizenId].trailer = trailer
    if trailer then
        setJobVehicleIdentity(trailer, citizenId, contractId, 'trailer')
    end

    lib.print.debug('[OUT]', func_name, '-vehicles=', activeJobVehicles[citizenId])
end

function GetActiveJobVehiclesForCitizenId(citizenId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId)

    local vehicles = activeJobVehicles[citizenId]

    lib.print.debug('[OUT]', func_name, '-vehicles=', vehicles)
    return vehicles
end

local function restoreVehicleAtCoords(model, vehicleType, coords, citizenId, contractId, vehicleRole)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-model=', model, '-vehicleType=', vehicleType, '-coords=', coords, '-citizenId=', citizenId, '-contractId=', contractId, '-vehicleRole=', vehicleRole)

    local coordsType = type(coords)
    if (coordsType ~= 'table' and coordsType ~= 'vector4')
        or not tonumber(coords.x) or not tonumber(coords.y)
        or not tonumber(coords.z) or not tonumber(coords.w) then
        return nil, false, 'Invalid saved vehicle coordinates'
    end

    local matchingVehicle = nil

    for _, vehicle in ipairs(GetAllVehicles()) do
        if DoesEntityExist(vehicle) then
            local state = Entity(vehicle).state
            if state[jobVehicleOwnerStateKey] == citizenId
                and state[jobVehicleContractStateKey] == tostring(contractId)
                and state[jobVehicleRoleStateKey] == vehicleRole then
                if matchingVehicle then
                    return nil, false, string.format(
                        'Multiple %s vehicles are tagged for contract %s',
                        vehicleRole,
                        contractId
                    )
                end

                matchingVehicle = vehicle
            end
        end
    end

    if matchingVehicle then
        SetEntityOrphanMode(matchingVehicle, 2)
        return matchingVehicle, false
    end

    local modelHash = joaat(model)
    local vehicle = CreateVehicleServerSetter(
        modelHash,
        vehicleType,
        coords.x,
        coords.y,
        coords.z,
        coords.w
    )

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil, false, string.format('Failed to restore vehicle model %s', model)
    end

    SetEntityOrphanMode(vehicle, 2)
    return vehicle, true
end

function RestoreActiveJobVehiclesForCitizenId(citizenId, contractId, truckCoords, trailerCoords)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId=', contractId, '-truckCoords=', truckCoords, '-trailerCoords=', trailerCoords)

    if type(citizenId) ~= 'string' or citizenId == '' or not contractId then
        error('Invalid citizen ID or contract ID!', 1)
    end

    local truckModel = configServer.vehicles.trucks[math.random(#configServer.vehicles.trucks)]
    local truck, truckCreated, truckError = restoreVehicleAtCoords(
        truckModel,
        configServer.vehicles.truckType,
        truckCoords,
        citizenId,
        contractId,
        'truck'
    )
    if not truck then
        return nil, nil, truckError
    end

    local trailer = nil
    local trailerModel = configServer.vehicles.trailers[math.random(#configServer.vehicles.trailers)]
    if trailerCoords then
        local restoredTrailer, _, trailerError = restoreVehicleAtCoords(
            trailerModel,
            configServer.vehicles.trailerType,
            trailerCoords,
            citizenId,
            contractId,
            'trailer'
        )
        trailer = restoredTrailer
        if not trailer then
            if truckCreated then
                DeleteEntity(truck)
            end
            return nil, nil, trailerError
        end
    end

    SetActiveJobVehiclesForCitizenId(citizenId, truck, trailer, contractId)

    lib.print.debug('[OUT]', func_name, '-truck=', truck, '-trailer=', trailer)
    return truck, trailer
end

local function createSpawnAreaZone(coords)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-coords=', coords)

    local spawnArea = lib.zones.box({
                coords = vec3(coords.x, coords.y, coords.z),
                size = configServer.vehicles.spawnAreaSize,
                rotation = coords.w})
    TriggerClientEvent('mad_truckingjob:client:toggleSpawnAreaDebug', source, coords, configServer.vehicles.spawnAreaSize)  -- ONLY FOR DEBUGGING!

    lib.print.debug('[OUT]', func_name, '-spawnArea=', spawnArea)
    return spawnArea
end

-- Approximate trailer footprint in meters, sampled relative to its heading.
local trailerLongitudinalOffsets = {-8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0, 6.0, 8.0}
local trailerLateralOffsets = {-1.5, 0.0, 1.5}

--- If vehicle is 'trailer' type then a check is done for multiple points,
--- roughly covering a trailer in a 2D (rectangle) shape
local function isVehicleInsideSpawnZone(vehicle, spawnAreaZone)
    local vehicleCoords = GetEntityCoords(vehicle)
    if spawnAreaZone:contains(vehicleCoords) then
        return true
    end

    if GetVehicleType(vehicle) ~= 'trailer' then
        return false
    end

    -- Gets the heading direction in degrees (like vec4.w) and converts to radians for sin and cos
    local heading = math.rad(GetEntityHeading(vehicle))
    -- Gets forward X and Y heading of the vehicle (at heading 0: forward is (0, 1), at heading 90: forward is (-1, 0))
    local forwardX, forwardY = -math.sin(heading), math.cos(heading)
    -- Gets right X and Y heading of the vehicle (at heading 0: right is (1, 0), at heading 90: right is (0, 1))
    local rightX, rightY = math.cos(heading), math.sin(heading)

    -- When multiplied by an offset gives how much to move along that axis. 
    -- For example, forwardX * 4 + rightX * 1.5 is X moving 4 metres forward and 1.5 meters to the right.
    for _, forwardOffset in ipairs(trailerLongitudinalOffsets) do
        for _, lateralOffset in ipairs(trailerLateralOffsets) do
            if forwardOffset ~= 0.0 or lateralOffset ~= 0.0 then
                local sampleCoords = vec3(
                    vehicleCoords.x + forwardX * forwardOffset + rightX * lateralOffset,
                    vehicleCoords.y + forwardY * forwardOffset + rightY * lateralOffset,
                    vehicleCoords.z
                )

                if spawnAreaZone:contains(sampleCoords) then
                    return true
                end
            end
        end
    end

    return false
end

local function detSpawnCoords(coordsList)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-coordsList=', coordsList)

    local vehicles = GetAllVehicles()  -- TODO is there a better way to do this?
    local notOccupiedCoords = nil

    for _, spawnCoords in ipairs(coordsList) do
        local spawnAreaZone = createSpawnAreaZone(spawnCoords)
        local isOccupied = false

        for _, vehicle in ipairs(vehicles) do
            if DoesEntityExist(vehicle) and isVehicleInsideSpawnZone(vehicle, spawnAreaZone) then
                isOccupied = true
                break
            end
        end

        if not isOccupied then
            notOccupiedCoords = spawnCoords
            -- break  -- TODO uncomment (debugging)
        end
    end

    lib.print.debug('[OUT]', func_name, '-notOccupiedCoords=', notOccupiedCoords)
    return notOccupiedCoords
end

function RegisterVehiclesForClient(source, citizenId, truck, trailer)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-truck=', truck, '-trailer=', trailer)

    if not trailer or (not truck and not activeJobVehicles[citizenId]) then  -- or activeJobVehicles[citizenId].truck ??
        error('Invalid inputs!', 1)
    end

    local truckNetId = nil

    if truck ~= nil then
        exports.qbx_vehiclekeys:GiveKeys(source, truck)  -- Only need keys for truck, trailers don't have keys

        truckNetId = NetworkGetNetworkIdFromEntity(truck)
    end

    local trailerNetId = NetworkGetNetworkIdFromEntity(trailer)

    -- provide NetId so that vehicle is consistent between client and server, if false the Client Event will notify about problem
    TriggerClientEvent('mad_truckingjob:client:registerVehicleTargets', source, truckNetId, trailerNetId)


    lib.print.debug('[OUT]', func_name, '-truckNetId=', truckNetId, '-trailerNetId=', trailerNetId)
    return truckNetId, trailerNetId
end

function SpawnVehicle(model, type, coordsList)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-model=', model, '-type=', type, '-coords=', coordsList)

    local spawnCoords = detSpawnCoords(coordsList)
    if not spawnCoords then
        return nil, false
    end

    -- Spawn vehicle
    local vehicle = CreateVehicleServerSetter(
        joaat(model),
        type,
        spawnCoords.x,
        spawnCoords.y,
        spawnCoords.z,
        spawnCoords.w
    )

    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        error('Failed to spawn truck!', 1)
    end

    -- Keep entity persistent
    SetEntityOrphanMode(vehicle, 2)

    lib.print.debug('[OUT]', func_name, '-vehicle=', vehicle)
    return vehicle, true, spawnCoords
end

local function isPlayerCloseToVehicle(source, vehicle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source, '-vehicle=', vehicle)

    local playerPed = GetPlayerPed(source)
    local playerCoords = DoesEntityExist(playerPed) and GetEntityCoords(playerPed) or nil
    local isPlayerClose = false

    if playerCoords then
        local vehicleCoords = GetEntityCoords(vehicle)
        local distance = #(playerCoords - vehicleCoords)

        if distance <= 100.0 then  -- TODO test this distance idk
            isPlayerClose = true
        end
    end

    lib.print.debug('[OUT]', func_name, '-isPlayerClose=', isPlayerClose)
    return isPlayerClose
end

local function clearActiveJobVehiclesForCitizenId(citizenId, vehicle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-vehicle=', vehicle)

    local vehicles = activeJobVehicles[citizenId]
    if vehicles then
        if vehicles.truck == vehicle then
            vehicles.truck = nil
        elseif vehicles.trailer == vehicle then
            vehicles.trailer = nil
        end

        if not vehicles.truck and not vehicles.trailer then
            activeJobVehicles[citizenId] = nil
        end
    end

    lib.print.debug('[OUT]', func_name, '-vehicles=', activeJobVehicles[citizenId])
end

function DespawnVehicle(source, citizenId, vehicle, despawnNow, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId=', contractId, '-vehicle=', vehicle)

    if source then
        exports.qbx_vehiclekeys:RemoveKeys(source, vehicle, true)
    end

    clearJobVehicleIdentity(vehicle, citizenId, contractId)

    if despawnNow and isPlayerCloseToVehicle(source, vehicle) then
        DeleteEntity(vehicle)
    else
        expiredVehicles[#expiredVehicles + 1] = vehicle
    end

    clearActiveJobVehiclesForCitizenId(citizenId, vehicle)

    lib.print.debug('[OUT]', func_name, '-')
end

function GetActiveVehiclesCoordsForCitizenId(citizenId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId)

    if type(citizenId) ~= 'string' or citizenId == '' then
        error('Invalid citizen ID!', 1)
    end

    local vehicles = activeJobVehicles[citizenId]
    if not vehicles then
        error(string.format('No active job vehicles found for citizen ID %s', citizenId), 1)
    end

    local function getVehicleVec4(vehicle, vehicleName, required)
        local func_name = debug.getinfo(1, 'n').name
        lib.print.debug('[IN]', func_name, '-vehicleName=', vehicleName, '-vehicle=', vehicle, '-required=', required)

        if vehicle == nil then
            if required then
                error(string.format('No %s found for citizen ID %s', vehicleName, citizenId), 1)
            end
            return nil
        end

        if type(vehicle) ~= 'number' or vehicle <= 0 then
            error(string.format('Invalid %s entity for citizen ID %s', vehicleName, citizenId), 1)
        end

        if not DoesEntityExist(vehicle) then
            error(string.format('%s entity %s does not exist for citizen ID %s', vehicleName, vehicle, citizenId), 1)
        end

        local coords = GetEntityCoords(vehicle)
        local vehicleVec4 = vec4(coords.x, coords.y, coords.z, GetEntityHeading(vehicle))
        lib.print.debug('[OUT]', func_name, '-coords=', vehicleVec4)
        return vehicleVec4
    end

    local truckVec4 = getVehicleVec4(vehicles.truck, 'truck', true)
    local trailerVec4 = getVehicleVec4(vehicles.trailer, 'trailer', false)

    lib.print.debug('[OUT]', func_name, '-truckVec4=', truckVec4, '-trailerVec4=', trailerVec4)
    return truckVec4, trailerVec4
end


AddEventHandler('onResourceStop', function(resource)
    local func_name = 'onResourceStop'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    -- Expired vehicles get deleted when resource is stopped.
    local deletedCount = 0
    for _, vehicle in ipairs(expiredVehicles) do
        DeleteEntity(vehicle)
        deletedCount = deletedCount + 1
    end

    lib.print.debug('[OUT]', func_name, '-deletedExpiredVehicles=', deletedCount)
end)