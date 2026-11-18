local configShared = require 'config.shared'
local activeContracts = {}
local activeJobVehicles = {}
local activeJobCitizenIds = {}
local isExpirationThreadRunning = false
local CONTRACT_TIMEOUT_MS = 45 * 60 * 1000  -- 45mins


local function getDeliveryDestination(contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    local deliveryDestination = nil
    for _, item in pairs(configShared.contracts) do
        if item.title == contractTitle then
            deliveryDestination = item.deliveriesPaleto[math.random(#item.deliveriesPaleto)]
            break
        end
    end

    if not deliveryDestination then
        error('Failed to set delivery destination!', 1)
    end

    lib.print.debug('[OUT]', func_name, '-deliveryDestination=', deliveryDestination)
    return deliveryDestination
end

local function isValidContract(contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    local isContractFound = false
    for _, contract in ipairs(configShared.contracts) do  -- TODO: Need list of available contracts instead of all contracts
        if contract.title == contractTitle then
            isContractFound = true
            break
        end
    end

    lib.print.debug('[OUT]', func_name, '-isContractFound=', isContractFound)
    return isContractFound
end

local function expireActiveContract(citizenId, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId', citizenId, '-contractId=', contractId)

    if activeContracts[citizenId].id ~= contractId then
        error(string.format('%s - Invalid contract id for citizen id= %s.', contractId, citizenId), 1)
    end

    SetExistingContractToCancelledInSQL(citizenId, contractId)

    -- Need to update source because player might have reconnected and not have the original server id.
    -- Or player can be offline.
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    local playerSource = player and player.PlayerData.source

    if playerSource then
        -- UpdateWorkTicket(citizenId, contractId, 'EXPIRED')
        TriggerClientEvent('mad_truckingjob:client:jobExpired', playerSource, contractId)
    end

    activeContracts[citizenId] = nil
    activeJobVehicles[citizenId] = nil
end

local function startExpirationThread()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    if isExpirationThreadRunning then
        lib.print.debug('[-]', func_name, 'Expiration thread already running.')
        return
    end

    isExpirationThreadRunning = true

    CreateThread(function()
        lib.print.debug('[-]', func_name, 'Expiration thread started.')
        while next(activeContracts) do
            local now = GetGameTimer()

            for citizenId, contract in pairs(activeContracts) do
                if now >= contract.expiresAt then
                    expireActiveContract(citizenId, contract.id)
                end
            end

            Wait(60 * 1000) -- 1 minute 
        end

        lib.print.debug('[-]', func_name, 'Expiration thread stopped.')
        isExpirationThreadRunning = false
    end)

    lib.print.debug('[OUT]', func_name, '-')
end

local function getCitizenIdFromSource(source)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source)

    local Player = exports.qbx_core:GetPlayer(source)
    if not Player then
        error(string.format("Failed to get player from source = %s", source))
    end
    local citizenId = Player.PlayerData.citizenid

    lib.print.debug('[OUT]', func_name, '-citizenId=', citizenId)
    return citizenId
end

local function validateExpectedVehicleNetIdForCitizenId(vehNetId, citizenId, isTrailer)
    local vehicles = activeJobVehicles[citizenId]
    if not vehicles then
        error('No active job vehicles found!', 1)
    end

    local expectedEntity
    if isTrailer then
        expectedEntity = vehicles.trailer
    else
        expectedEntity = vehicles.truck
    end

    if not expectedEntity or expectedEntity == 0 or not DoesEntityExist(expectedEntity) then
        error('Expected job vehicle does not exist!', 1)
    end

    local expectedNetId = NetworkGetNetworkIdFromEntity(expectedEntity)
    if expectedNetId ~= vehNetId then
        error(string.format('Invalid vehicle net ID: expected %d, received %d', expectedNetId, vehNetId), 1)
    end
end

lib.callback.register('mad_truckingjob:server:startSecondDelivery', function(source, contractId)
    lib.print.debug('[IN]mad_truckingjob:server:startSecondDelivery', '-source=', source, '-contractId=', contractId)

    if not source or not contractId then
        error('Invalid input parameters!', 1)
    end

    local citizenId = getCitizenIdFromSource(source)
    if not activeContracts[citizenId] or activeContracts[citizenId].id ~= contractId then
        error(string.format('Player with citizenId= %s doesn\'t have an active delivery job!', citizenId))
    end

    local secondTrailer = SpawnSecondTrailer()
    if not secondTrailer or not secondTrailer.trailer or
           secondTrailer.trailer == 0 or not DoesEntityExist(secondTrailer.trailer) then
        warn('mad_truckingjob:server:startSecondDelivery - No Paleto trailer spawn area available.')
        return false, nil
    end

    local trailerNetId = NetworkGetNetworkIdFromEntity(secondTrailer.trailer)
    TriggerClientEvent('mad_truckingjob:client:registerVehicleTargets', source, nil, trailerNetId)
    -- local successRegisteringVehicle = RegisterJobVehicleForClient(source, secondTrailer)

    local destination = configShared.contracts[1].deliveriesPaleto[1]  -- TODO FIX THIS
    activeJobVehicles[citizenId].trailer = secondTrailer.trailer

    lib.print.debug('[OUT]mad_truckingjob:server:startSecondDelivery', '-successRegisteringVehicle=', successRegisteringVehicle, '-destination=', destination)
    return true, destination
end)

lib.callback.register('mad_truckingjob:server:addJobContract', function(source, contractTitle)
    lib.print.debug('[IN]mad_truckingjob:server:addJobContract', '-source=', source, '-contractTitle=', contractTitle)

    if not source or not contractTitle then
        error('Invalid input parameters!', 1)
    end

    if not isValidContract(contractTitle) then
        error('Couldn\'t find correct contract!', 1)
    end

    local citizenId = getCitizenIdFromSource(source)

    if activeContracts[citizenId] then
        error(string.format('Player with citizenId= %s already has an active trucking job!', citizenId))
    end

    local truckAndTrailer = SpawnJobVehicle()
    local successRegisteringVehicle = RegisterJobVehicleForClient(source, truckAndTrailer)

    local contractId = nil
    local destination = nil

    -- Registering vehicle can fail because there is no space to spawn vehicles.
    -- This is not an error, but client needs to retry.
    if successRegisteringVehicle then
        destination = getDeliveryDestination(contractTitle)
        -- TODO implement a way to respawn the truck and trailer on server restart if job is ongoing
        -- TODO add reward

        contractId = AddContractToSQL(source, contractTitle, truckAndTrailer.trailerCoords, destination)

        activeContracts[citizenId] = {id = contractId,
                                      expiresAt = GetGameTimer() + CONTRACT_TIMEOUT_MS}

        activeJobVehicles[citizenId] = {
            truck = truckAndTrailer.truck,
            trailer = truckAndTrailer.trailer
        }
        -- GiveWorkTicket(source, contractTitle, contractId)

        startExpirationThread()
    else
        warn(string.format('mad_truckingjob:server:addJobContract - Spawning job vehicles failed.'))
    end

    lib.print.debug('[OUT]mad_truckingjob:server:addJobContract', '-successRegisteringVehicle=', successRegisteringVehicle, '-contractId=', contractId, '-destination=', destination)
    return successRegisteringVehicle, contractId, destination
end)

lib.callback.register('mad_truckingjob:server:completeJobContract', function(source, contractId, vehicleNetId, isTrailer)
    lib.print.debug('[IN]mad_truckingjob:server:completeJobContract', '-source=', source, '-contractId=', contractId, '-vehicleNetId=', vehicleNetId, '-isTrailer=', isTrailer)

    if not source or not contractId or not vehicleNetId or isTrailer == nil then
        error('Invalid input parameters!', 1)
    end

    local citizenId = getCitizenIdFromSource(source)

    if not activeContracts[citizenId] or activeContracts[citizenId].id ~= contractId then
        error(string.format('Tried to complete contract %d for citizenId=%d that was not active!', contractId, citizenId))
    end

    validateExpectedVehicleNetIdForCitizenId(vehicleNetId, citizenId, isTrailer)

    local success = false

    if isTrailer then
        -- success = UpdateWorkTicket(citizenId, contractId, 'RETURNED_TRAILER')
        activeJobVehicles[citizenId].trailer = nil
    else
        -- success = UpdateWorkTicket(citizenId, contractId, 'RETURNED_TRUCK')

        SetExistingContractToCompletedInSQL(citizenId, contractId)

        activeJobVehicles[citizenId].truck = nil
        activeContracts[citizenId] = nil
    end
    DespawnJobVehicle(vehicleNetId)

    lib.print.debug('[OUT]mad_truckingjob:server:completeJobContract', '-')
end)

lib.callback.register('mad_truckingjob:server:cancelJobContract', function(source, contractId)
    lib.print.debug('[IN]', 'mad_truckingjob:server:cancelJobContract', '-contractId=', contractId)

    if not source or not contractId then
        error('Invalid input parameters!', 1)
    end

    local citizenId = getCitizenIdFromSource(source)

    if not activeContracts[citizenId] or activeContracts[citizenId].id ~= contractId then
        error(string.format('No active contract %s for citizen id %s', contractId, citizenId))
    end

    SetExistingContractToCancelledInSQL(citizenId, contractId)
    -- UpdateWorkTicket(citizenId, contractId, 'CANCELLED')

    local vehicles = activeJobVehicles[citizenId]
    if vehicles then
        for _, vehicle in pairs(vehicles) do
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
        end
    end

    activeContracts[citizenId] = nil
    activeJobVehicles[citizenId] = nil

    lib.print.debug('[OUT]', 'mad_truckingjob:server:cancelJobContract', '-')
    return true
end)
