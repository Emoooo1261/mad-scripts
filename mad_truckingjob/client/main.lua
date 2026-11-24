local contract = {
    id = nil,
    destination = nil,
    truck = nil,
    trailer = nil
}

local spawnAreaDebugZones = {}


function GetContract()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    lib.print.debug('[OUT]', func_name, '-contractId=', contract.id)
    return contract
end

function StartJob(contractTitle, startBossId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    local isFirstDelivery = true
    local successSpawningVehicles, destination, contractId = lib.callback.await('mad_truckingjob:server:startNewDelivery', false, nil, contractTitle, startBossId, isFirstDelivery)

    if successSpawningVehicles == nil then
        error("Server returned invalid parameters when trying to create a job contract!", 1)
    elseif successSpawningVehicles == false then
        lib.notify({
            title = 'Trucking job',
            description = 'Couldn\'t spawn job vehicle. Is spawn area occupied?',
            type = 'error'
        })
        warn(string.format('%s - Couldn\'t spawn job vehicle. Maybe spawn area is occupied.', func_name))
        lib.print.debug('[OUT]', func_name, '-successSpawningVehicles=', successSpawningVehicles)
        return nil
    end

    if not contractId or not destination then
        error("Server returned invalid parameters when trying to create a job contract!", 1)
    end

    contract.id = contractId
    contract.destination = destination

    CreateDropOffBlip(destination)

    lib.print.debug('[OUT]', func_name, '-contractId=', contractId)
    return contractId
end

local function isInReturnDistance()
    -- local func_name = debug.getinfo(1, 'n').name
    -- lib.print.debug('[IN]', func_name, '-')  -- function is called too often to log

    local coords = GetEntityCoords(PlayerPedId())
    local distance = #(coords - contract.destination) < 15.0

    -- lib.print.debug('[OUT]', func_name, '-distance=', distance)
    return distance
end

function ClearJobContract()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    ClearBlips()

    contract.id = nil
    contract.destination = nil
    contract.truck = nil
    contract.trailer = nil
    SetTrailerDelivered(true)
    ClearCurrentJob()

    lib.print.debug('[OUT]', func_name, '-')
end

function CancelJobContract()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    if not contract.id then
        error('Contract ID not found!', 1)
    end

    local cancelled = lib.callback.await('mad_truckingjob:server:cancelJobContract', false, contract.id)
    if not cancelled then
        lib.notify({
            title = 'Trucking job',
            description = 'Could not cancel the active job.',
            type = 'error'
        })
    end

    if contract.truck and DoesEntityExist(contract.truck) then
        exports.ox_target:removeLocalEntity(contract.truck)
    end
    if contract.trailer and DoesEntityExist(contract.trailer) then
        exports.ox_target:removeLocalEntity(contract.trailer)
    end

    ClearJobContract()

    -- Clean up anyway before throwing an error
    if not cancelled then
        error('Server was unable to cancel active job!', 1)
    end

    lib.notify({
        title = 'Trucking job',
        description = 'The active job was cancelled.',
        type = 'success'
    })

    lib.print.debug('[OUT]', func_name, '-')
    return true
end

function StartNewDelivery(contractTitle, startBossId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local isFirstDelivery = false
    local successSpawningVehicle, destination = lib.callback.await('mad_truckingjob:server:startNewDelivery', false, contract.id, contractTitle, startBossId, isFirstDelivery)

    if successSpawningVehicle == nil then
        error("Server returned invalid parameters when trying to create a job contract!", 1)
    elseif successSpawningVehicle == false then
        lib.notify({
            title = 'Trucking job',
            description = 'Couldn\'t spawn job vehicle. Is spawn area occupied?',
            type = 'error'
        })
        warn(string.format('%s - Couldn\'t spawn job vehicle. Maybe spawn area is occupied.', func_name))
        return false
    end

    contract.destination = destination
    CreateDropOffBlip(destination)

    lib.print.debug('[OUT]', func_name, '-')
    return true
end

local function returnDeliveryVehicle(vehicle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-vehicle=', vehicle)

    local isTrailer = false
    if contract.truck and contract.truck == vehicle then
        isTrailer = false
    elseif contract.trailer and contract.trailer == vehicle then
        isTrailer = true
    else
        error('Invalid truck and trailer!', 1)
    end

    if isInReturnDistance() then  -- extra check prolly not needed
        exports.ox_target:removeLocalEntity(vehicle)

        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        lib.callback.await('mad_truckingjob:server:completeJobContract', false, contract.id, vehicleNetId, isTrailer)

        lib.notify({
            title = 'Vehicle returned!',
            type = 'info'
        })

        if isTrailer then
            RemoveTrailerBlip()
            contract.trailer = nil
            local destBossCords = GetBossCoords()
            -- CreateDropOffBlip(destBossCords) -- TODO do we want an extra blip telling the player to go talk with the boss?
            SetTrailerDelivered(true)
        else
            ClearJobContract()
        end
    end

    lib.print.debug('[OUT]', func_name, '-')
end

local function getVehicleEntityFromNetworkId(vehNetId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-vehNetId=', vehNetId)

    if type(vehNetId) ~= 'number' or vehNetId <= 0 then
        error(string.format('Invalid vehicle network ID: %s', tostring(vehNetId)), 1)
    end

    local veh = 0
    local attempts = 0
    local max_attempts = 10

    while veh == 0 or not DoesEntityExist(veh) do
        if attempts >= max_attempts then
            error("Vehicle creation failed!", 1)
        end

        Wait(1000)  -- NEEDS TIME TO SYNCHRONIZE SLOW ASS

        veh = NetworkGetEntityFromNetworkId(vehNetId)

        attempts = attempts + 1
    end

    if attempts >= max_attempts then
        error(string.format('Vehicle network ID %d did not become available on this client within %d seconds!', vehNetId, attempts), 1)
    end

    lib.print.debug('[OUT]', func_name, '-veh=', veh)
    return veh
end

local function registerTruckTarget(truckNetId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-truckNetId=', truckNetId)

    local truck = getVehicleEntityFromNetworkId(truckNetId)

    exports.ox_target:addLocalEntity(truck, {
        {
            name = 'mad_truckingjob:return_truck',
            icon = 'fa-solid fa-truck',
            label = 'Return Truck',
            distance = 2.5,

            canInteract = function(entity)
                return not contract.trailer and entity == truck and contract.destination ~= nil and isInReturnDistance()  -- is this check too much?
            end,
            onSelect = function(data)
                if contract.trailer ~= nil then
                    lib.notify({title = 'Can\'t return truck!',
                                description = 'You have to return the trailer first.',
                                type = 'error'})
                else
                    returnDeliveryVehicle(data.entity)
                end
            end
        }
    })

    if Entity(truck).state.fuel == nil then
        Entity(truck).state.fuel = 100
    end

    lib.print.debug('[OUT]', func_name, '-truck=', truck)
    return truck
end

local function registerTrailerTarget(trailerNetId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-trailerNetId=', trailerNetId)

    local trailer = getVehicleEntityFromNetworkId(trailerNetId)

    exports.ox_target:addLocalEntity(trailer, {
        {
            name = 'mad_truckingjob:return_trailer',
            icon = 'fa-solid fa-trailer',
            label = 'Return Trailer',
            distance = 2.5,

            canInteract = function(entity)
                return entity == trailer and contract.destination ~= nil and isInReturnDistance()  -- is this check too much?
            end,
            onSelect = function(data)
                returnDeliveryVehicle(data.entity)
            end
        }
    })

    lib.print.debug('[OUT]', func_name, '-trailer=', trailer)
    return trailer
end

RegisterNetEvent('mad_truckingjob:client:registerVehicleTargets', function(truckNetId, trailerNetId)
    local func_name = 'mad_truckingjob:client:registerVehicleTargets'
    lib.print.debug('[IN]', func_name, '-truckNetId=', truckNetId, '-trailerNetId=', trailerNetId)

    if not truckNetId and not contract.truck then
        error('Received invalid truck net ID', 1)
    end

    if truckNetId and not contract.truck then
        local truck = registerTruckTarget(truckNetId)
        contract.truck = truck
        CreateTruckBlip(truck)

    end

    if trailerNetId then
        local trailer = registerTrailerTarget(trailerNetId)
        contract.trailer = trailer
        CreateTrailerBlip(trailer)
    else
        contract.trailer = nil
    end

    lib.print.debug('[OUT]', func_name, '-')
end)

RegisterNetEvent('mad_truckingjob:client:jobExpired', function(contractId)
    local func_name = 'mad_truckingjob:client:jobExpired'
    lib.print.debug('[IN]', func_name, '-contractId=', contractId)

    if not contractId then
        error('Received invalid contractId', 1)
    end

    ClearJobContract()

    lib.notify({
            title = 'Trucking job',
            description = 'Contract expired! You failed to deliver the cargo on time.',
            type = 'error'
        })


    lib.print.debug('[OUT]', func_name, '-')
end)

RegisterNetEvent('mad_truckingjob:client:toggleSpawnAreaDebug', function(coords, size)
    local func_name = 'mad_truckingjob:client:toggleSpawnAreaDebug'
    lib.print.debug('[IN]', func_name, '-coords=', coords, '-size=', size)

    local spawnArea = lib.zones.box({
                coords = vec3(coords.x, coords.y, coords.z),
                size = size,
                rotation = coords.w})
    spawnArea:setDebug(true)
    spawnAreaDebugZones[#spawnAreaDebugZones + 1] = spawnArea

    lib.print.debug('[OUT]', func_name, '-spawnArea=', spawnArea)
end)

--- Restore the active job on resource restart or player reload
local isRestoringActiveJob = false
local function restoreActiveJob()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractId=', contract.id)

    if isRestoringActiveJob or contract.id then
        lib.print.debug('[OUT]', func_name, '-skipped=', 'restore already in progress or job already loaded')
        return
    end
    if not QBX or not QBX.PlayerData or not QBX.PlayerData.citizenid then
        lib.print.debug('[OUT]', func_name, '-skipped=', 'player data not loaded')
        return
    end

    isRestoringActiveJob = true
    local success, savedJob = pcall(function()
        return lib.callback.await('mad_truckingjob:server:getActiveJob', false)
    end)
    isRestoringActiveJob = false

    if not success then
        error(savedJob, 0)
    end
    if not savedJob then
        return
    end
    if not savedJob.id or not savedJob.contractTitle or not savedJob.destination
        or not savedJob.destinationBossId or not savedJob.truckNetId then
        error('Server returned invalid saved trucking job data', 1)
    end

    contract.id = savedJob.id
    contract.destination = vec3(
        savedJob.destination.x,
        savedJob.destination.y,
        savedJob.destination.z
    )
    RestoreCurrentJob(savedJob.contractTitle, savedJob.destinationBossId, not savedJob.trailerNetId)
    CreateDropOffBlip(contract.destination)
    TriggerEvent(
        'mad_truckingjob:client:registerVehicleTargets',
        savedJob.truckNetId,
        savedJob.trailerNetId
    )

    lib.print.debug('[OUT]', func_name, '-contractId=', contract.id)
end

AddEventHandler('onClientResourceStart', function(resource)
    local func_name = 'onClientResourceStart'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        lib.print.debug('[OUT]', func_name, '-ignored=', resource)
        return
    end

    restoreActiveJob()

    lib.print.debug('[OUT]', func_name, '-')
end)

AddEventHandler('QBCore:Client:OnPlayerLoaded', restoreActiveJob)

AddEventHandler('onResourceStop', function(resource)
    local func_name = 'onResourceStop'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    if contract.truck and DoesEntityExist(contract.truck) then
        exports.ox_target:removeLocalEntity(contract.truck)
    end
    if contract.trailer and DoesEntityExist(contract.trailer) then
        exports.ox_target:removeLocalEntity(contract.trailer)
    end

    for _, zone in ipairs(spawnAreaDebugZones) do
        if zone then
            zone:setDebug(false)
            zone:remove()
        end
    end
    spawnAreaDebugZones = {}

    ClearJobContract()
    lib.print.debug('[OUT]', func_name, '-')
end)

