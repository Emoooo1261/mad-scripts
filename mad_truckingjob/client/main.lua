local contract = {
    id = nil,
    destination = nil,
    blip = nil,
    truck = nil,
    trailer = nil
}
local spawnAreaDebugZones = {}


local function createDropOffBlip(destination)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    if contract.blip then
        RemoveBlip(contract.blip)
    end

    contract.blip = AddBlipForCoord(
        destination.x,
        destination.y,
        destination.z
    )

    SetBlipSprite(contract.blip, 477)
    SetBlipColour(contract.blip, 5)
    SetBlipScale(contract.blip, 0.9)
    SetBlipRoute(contract.blip, true)
    SetBlipRouteColour(contract.blip, 5)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString("Cargo drop off")
    EndTextCommandSetBlipName(contract.blip)

    lib.print.debug('[OUT]', func_name, '-')
end

function CreateJobContract(contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    local successRegisteringVehicle, contractId, destination = lib.callback.await('mad_truckingjob:server:addActiveContract', false, contractTitle)

    if successRegisteringVehicle == false then
        lib.notify({
            title = 'Trucking job',
            description = 'Couldn\'t spawn job vehicle. Is spawn area occupied?',
            type = 'error'
        })

        lib.print.warn('[-]', func_name, 'Couldn\'t spawn job vehicle. Maybe spawn area is occupied.')
        lib.print.debug('[OUT]', func_name, '-successRegisteringVehicle=', successRegisteringVehicle)
        return nil
    elseif successRegisteringVehicle == nil or not contractId or not destination then
        error("Server returned invalid parameters when trying to create a job contract!", 1)
    end

    contract.id = contractId
    contract.destination = destination

    createDropOffBlip(destination)

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

local function finishJobContract()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    if contract.blip then
        RemoveBlip(contract.blip)
    end

    contract.id = nil
    contract.destination = nil
    contract.blip = nil
    contract.truck = nil
    contract.trailer = nil
    SetCurrentJob(nil)

    lib.print.debug('[OUT]', func_name, '-')
end

function CancelJobContract()
    if not contract.id then
        error('Contract ID not found!', 1)
    end

    local cancelled = lib.callback.await('mad_truckingjob:server:cancelActiveContract', false, contract.id)
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

    finishJobContract()

    -- Clean up anyway before throwing an error
    if not cancelled then
        error('Server was unable to cancel active job!', 1)
    end

    lib.notify({
        title = 'Trucking job',
        description = 'The active job was cancelled.',
        type = 'success'
    })
    return true
end

-- TODO add a timeout for the job to expire
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

    if isInReturnDistance() then  -- TODO IS THIS CHECK NEEDED?
        exports.ox_target:removeLocalEntity(vehicle)

        local vehicleNetId = NetworkGetNetworkIdFromEntity(vehicle)
        lib.callback.await('mad_truckingjob:server:removeActiveContract', false, contract.id, vehicleNetId, isTrailer)

        lib.notify({
            title = 'Vehicle returned!',
            type = 'info'
        })

        if isTrailer then
            contract.trailer = nil
        else
            finishJobContract()
        end
    end

    lib.print.debug('[OUT]', func_name, '-')
end

RegisterNetEvent('mad_truckingjob:client:registerVehicleTargets', function(truckNetId, trailerNetId)
    lib.print.debug('[IN]mad_truckingjob:client:registerTruckTarget', '-truckNetId=', truckNetId, '-trailerNetId=', trailerNetId)

    if not truckNetId or not trailerNetId then
        error('Received invalid truck and trailer net IDs', 1)
    end

    local truck = 0
    local trailer = 0

    local retries = 0
    while truck == 0 or trailer == 0 or not DoesEntityExist(truck) or not DoesEntityExist(trailer) do
        if retries >= 10 then -- TODO does it need more retries?
            error("Truck and trailer creation failed!", 1)
        end

        Wait(1000)  -- NEEDS TIME TO SYNCHRONIZE SLOW ASS

        truck = NetworkGetEntityFromNetworkId(truckNetId)
        trailer = NetworkGetEntityFromNetworkId(trailerNetId)

        retries = retries + 1
    end

    Entity(truck).state.fuel = 100

    contract.truck = truck
    contract.trailer = trailer

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

    exports.ox_target:addLocalEntity(truck, {
        {
            name = 'mad_truckingjob:return_truck',
            icon = 'fa-solid fa-truck',
            label = 'Return Truck',
            distance = 2.5,

            canInteract = function(entity)
                return entity == truck and contract.destination ~= nil and isInReturnDistance()  -- is this check too much?
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

    lib.print.debug('[OUT]mad_truckingjob:client:registerTruckTarget', '-')
end)

RegisterNetEvent('mad_truckingjob:client:toggleSpawnAreaDebug', function(truckSpawnCoords, trailerSpawnCoords, spawnAreaSize)
    if #spawnAreaDebugZones > 0 then
        for _, zone in ipairs(spawnAreaDebugZones) do
            zone:remove()
        end
        spawnAreaDebugZones = {}
        lib.notify({
            title = 'Trucking job',
            description = 'Spawn area debug disabled.',
            type = 'info'
        })
        return
    end

    for index, truckCoords in ipairs(truckSpawnCoords) do
        local trailerCoords = trailerSpawnCoords[index]
        local center = vec3(
            (truckCoords.x + trailerCoords.x) / 2,
            (truckCoords.y + trailerCoords.y) / 2,
            (truckCoords.z + trailerCoords.z) / 2
        )

        local zone = lib.zones.box({
            coords = center,
            size = spawnAreaSize,
            rotation = truckCoords.w
        })
        zone:setDebug(true)
        spawnAreaDebugZones[#spawnAreaDebugZones + 1] = zone
    end

    lib.notify({
        title = 'Trucking job',
        description = 'Spawn area debug enabled. Use /truckingjobdebug to disable it.',
        type = 'info'
    })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for _, zone in ipairs(spawnAreaDebugZones) do
        zone:remove()
    end
end)
