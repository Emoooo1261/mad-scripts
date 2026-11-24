local configShared = require 'config.shared'
local configServer = require 'config.server'
local activeContracts = {}
local isActiveContractCacheLoaded = false
local isExpirationThreadRunning = false
local START_CONTRACT_TIMEOUT_S = 45 * 60  -- 45mins
local ADD_CONTRACT_TIMEOUT_S = 20 * 60  -- 20mins

--- Use this function to get spawn coordinates for a truck based on trailer vec4
-- local function truckSpawnInFrontOfTrailer()
--     local distance = 12

--     for _, trailerSpawnCoords in ipairs(configShared.bossPeds[3].trailerSpawnCoords) do
--         local heading = math.rad(trailerSpawnCoords.w)
--         local forwardX = -math.sin(heading)
--         local forwardY = math.cos(heading)

--         print('TRUCK COORDS:', vec4(
--             trailerSpawnCoords.x + forwardX * distance,
--             trailerSpawnCoords.y + forwardY * distance,
--             trailerSpawnCoords.z,
--             trailerSpawnCoords.w
--         ))
--     end
-- end
-- truckSpawnInFrontOfTrailer()


local function getDeliveryDestination(contract)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contract.title)

    local deliveryOptions = contract.deliveries
    local deliveryDestination = deliveryOptions[math.random(#deliveryOptions)]

    if not deliveryDestination then
        error('Failed to set delivery destination!', 1)
    end

    lib.print.debug('[OUT]', func_name, '-deliveryDestination=', deliveryDestination)
    return deliveryDestination
end

local function getContractData(contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    for _, bossData in ipairs(configShared.bossPeds) do
        for _, contract in ipairs(bossData.contracts) do
            if contract.title == contractTitle then
                lib.print.debug('[OUT]', func_name, '-contractTitle=', contract.title)
                return contract, bossData
            end
        end
    end

    lib.print.debug('[OUT]', func_name, '-contractTitle=', nil)
end

local function getBossDataById(bossId)
    if type(bossId) ~= 'number' then
        return nil
    end

    for _, bossData in ipairs(configShared.bossPeds) do
        if bossData.id == bossId then
            return bossData
        end
    end

    return nil
end

local function expireActiveContract(citizenId, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId', citizenId, '-contractId=', contractId)

    if activeContracts[citizenId].id ~= contractId then
        error(string.format('%s - Invalid contract id for citizen id= %s.', contractId, citizenId), 1)
    end

    local secondsToExpire = math.max(0, activeContracts[citizenId].expiresAt - os.time())
    SetExistingContractToCancelledInSQL(citizenId, contractId, secondsToExpire)

    -- Need to update source because player might have reconnected and not have the original server id.
    -- Or player can be offline.
    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    local playerSource = player and player.PlayerData.source

    if playerSource then
        TriggerClientEvent('mad_truckingjob:client:jobExpired', playerSource, contractId)
    end

    local activeVehicles = GetActiveJobVehiclesForCitizenId(citizenId)
    if activeVehicles then
        for _, vehicleEntity in pairs(activeVehicles) do
            DespawnVehicle(playerSource, citizenId, vehicleEntity, false, contractId)
        end
    end

    activeContracts[citizenId] = nil

    lib.print.debug('[OUT]', func_name, '-')
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
            local now = os.time()

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

local function payPlayerForJob(source, citizenId, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source, '-citizenId=', citizenId, '-contractId=', contractId)

    local reward = activeContracts[citizenId].reward
    if not reward or reward <= 0 then
        error(string.format('Invalid reward for contract %s', contractId), 1)
    end

    local player = exports.qbx_core:GetPlayer(source)
    if not player then
        error('Player is no longer connected to the server!', 1)
    end

    local paid = player.Functions.AddMoney('bank', reward, 'trucking-job-completed')
    if not paid then
        error(string.format('Failed to pay player %s for contract %s', citizenId, contractId), 1)
    end

    lib.print.debug('Payout', reward, 'paid to citizenId=', citizenId)
    lib.print.debug('[OUT]', func_name, '-reward=', reward)
    return reward
end


-- Job update callbacks --

lib.callback.register('mad_truckingjob:server:startNewDelivery', function(source, contractId, contractTitle, startBossId, isFirstDelivery)
    local func_name = 'mad_truckingjob:server:startNewDelivery'
    lib.print.debug('[IN]', func_name, '-source=', source, '-contractId=', contractId, '-contractTitle=', contractTitle, '-isFirstDelivery=', isFirstDelivery)

    if not source or isFirstDelivery == nil then
        error('Invalid input parameters!', 1)
    end

    local startBoss = getBossDataById(startBossId)
    if not startBoss then
        error(string.format('Invalid start boss ID %s', tostring(startBossId)), 1)
    end

    local contract, contractBoss = getContractData(contractTitle)
    if not contract then
        error(string.format('Couldn\'t find correct contract with title %s', contractTitle), 1)
    end
    if contractBoss.id == startBossId then
        error(string.format('Start boss ID %s cannot be the same boss as contract "%s"', tostring(startBossId), contractTitle), 1)
    end

    local citizenId = GetCitizenIdFromSource(source)

    if isFirstDelivery then
        if activeContracts[citizenId] then
            error(string.format('Player with citizenId= %s already has an active trucking job!', citizenId), 1)
        end
    else
        if not contractId then
            error('Invalid contract ID!', 1)
        end
        if not activeContracts[citizenId] or activeContracts[citizenId].id ~= contractId then
            error(string.format('Player with citizenId= %s doesn\'t have an active delivery job!', citizenId), 1)
        end
    end

    local truck = nil
    local isTruckSpawnAreaEmpty = false
    local truckSpawnCoords = nil
    if isFirstDelivery then
        -- Spawning vehicles can fail because there another vehicle obstructing the spawn.
        -- This is not an error, but client needs to retry.
        local truckModel = configServer.vehicles.trucks[math.random(#configServer.vehicles.trucks)]
        truck, isTruckSpawnAreaEmpty, truckSpawnCoords = SpawnVehicle(truckModel, configServer.vehicles.truckType, startBoss.truckSpawnCoords)
        if not isTruckSpawnAreaEmpty then
            warn(string.format('mad_truckingjob:server:startJobContract - Truck spawn area is occupied.'))
            return false, nil, nil
        end
    end

    local trailerModel = configServer.vehicles.trailers[math.random(#configServer.vehicles.trailers)]
    local trailer, isTrailerSpawnAreaEmpty, trailerSpawnCoords = SpawnVehicle(trailerModel, configServer.vehicles.trailerType, startBoss.trailerSpawnCoords)
    if not isTrailerSpawnAreaEmpty then
        if truck then
            DeleteEntity(truck)
        end
        warn(string.format('mad_truckingjob:server:startJobContract - Trailer spawn area is occupied.'))
        return false, nil, nil
    end
    RegisterVehiclesForClient(source, citizenId, truck, trailer)

    local destination = getDeliveryDestination(contract)
    local reward = CalculatePayReward(trailerSpawnCoords, destination)

    local newContractId = nil
    if isFirstDelivery then
        newContractId = AddContractToSQL(
            source,
            citizenId,
            contractTitle,
            trailerSpawnCoords,
            destination,
            truckSpawnCoords,
            trailerSpawnCoords,
            reward,
            START_CONTRACT_TIMEOUT_S
        )

        activeContracts[citizenId] = {id = newContractId,
                                      contractTitle = contractTitle,
                                      currDestination = destination,
                                      reward = reward,
                                      expiresAt = (os.time() + START_CONTRACT_TIMEOUT_S)}
        SetActiveJobVehiclesForCitizenId(citizenId, truck, trailer, newContractId)
        startExpirationThread()
    else
        activeContracts[citizenId].contractTitle = contractTitle
        activeContracts[citizenId].currDestination = destination
        activeContracts[citizenId].reward = activeContracts[citizenId].reward + reward
        activeContracts[citizenId].expiresAt = activeContracts[citizenId].expiresAt + ADD_CONTRACT_TIMEOUT_S  -- add X minutes to expiration timer
        SetActiveJobVehiclesForCitizenId(citizenId, truck, trailer, activeContracts[citizenId].id)
        local currTruckCoords, currTrailerCoords = GetActiveVehiclesCoordsForCitizenId(citizenId)
        local secondsToExpire = math.max(0, activeContracts[citizenId].expiresAt - os.time())

        UpdateExistingContractInSQL(activeContracts[citizenId].id,
                                    activeContracts[citizenId].contractTitle,
                                    activeContracts[citizenId].currDestination,
                                    currTruckCoords,
                                    currTrailerCoords,
                                    activeContracts[citizenId].reward,
                                    secondsToExpire)
    end

    lib.print.debug('[OUT]', func_name, '-successRegisteringVehicle=', true, '-destination=', destination, '-newContractId=', newContractId)
    return true, destination, newContractId
end)

lib.callback.register('mad_truckingjob:server:completeJobContract', function(source, contractId, vehicleNetId, isTrailer)
    local func_name = 'mad_truckingjob:server:completeJobContract'
    lib.print.debug('[IN]', func_name, '-source=', source, '-contractId=', contractId, '-vehicleNetId=', vehicleNetId, '-isTrailer=', isTrailer)

    if not source or not contractId or not vehicleNetId or type(isTrailer) ~= 'boolean' then
        error('Invalid input parameters!', 1)
    end

    local citizenId = GetCitizenIdFromSource(source)

    if not activeContracts[citizenId] or activeContracts[citizenId].id ~= contractId then
        error(string.format('Tried to complete contract %d for citizenId=%d that was not active!', contractId, citizenId))
    end

    local vehicle = ValidateVehicleReturnForCitizen(
        source,
        citizenId,
        vehicleNetId,
        isTrailer,
        activeContracts[citizenId].currDestination
    )

    local success = false

    local secondsToExpire = math.max(0, activeContracts[citizenId].expiresAt - os.time())
    if isTrailer then
        SetActiveJobVehiclesForCitizenId(citizenId, nil, nil, contractId)
        local currTruckCoords, currTrailerCoords = GetActiveVehiclesCoordsForCitizenId(citizenId)
        UpdateExistingContractInSQL(contractId,
                                    activeContracts[citizenId].contractTitle,
                                    activeContracts[citizenId].currDestination,
                                    currTruckCoords,
                                    currTrailerCoords,
                                    activeContracts[citizenId].reward,
                                    secondsToExpire)
    else
        SetExistingContractToCompletedInSQL(citizenId, contractId, secondsToExpire)
        payPlayerForJob(source, citizenId, contractId)

        activeContracts[citizenId] = nil
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        warn(string.format('Couldn\'t get vehicle entity from net ID = %s', vehicleNetId))
    else
        DespawnVehicle(source, citizenId, vehicle, true, contractId)
    end

    lib.print.debug('[OUT]', func_name, '-')
end)


lib.callback.register('mad_truckingjob:server:cancelJobContract', function(source, contractId)
    local func_name = 'mad_truckingjob:server:cancelJobContract'
    lib.print.debug('[IN]', func_name, '-contractId=', contractId)

    if not source or not contractId then
        error('Invalid input parameters!', 1)
    end

    local citizenId = GetCitizenIdFromSource(source)

    if not activeContracts[citizenId] or activeContracts[citizenId].id ~= contractId then
        error(string.format('No active contract %s for citizen id %s', contractId, citizenId))
    end

    local secondsToExpire = math.max(0, activeContracts[citizenId].expiresAt - os.time())
    SetExistingContractToCancelledInSQL(citizenId, contractId, secondsToExpire)

    local vehicles = GetActiveJobVehiclesForCitizenId(citizenId)
    if vehicles then
        for _, vehicle in pairs(vehicles) do
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                -- When canceling the job the vehicles will be despawned only if they are close by the player.
                DespawnVehicle(source, citizenId, vehicle, true, contractId)
            end
        end
    end

    activeContracts[citizenId] = nil

    lib.print.debug('[OUT]', func_name, '-')
    return true
end)


-- Start, stop, restart handling --

lib.callback.register('mad_truckingjob:server:getActiveJob', function(source)
    local func_name = 'mad_truckingjob:server:getActiveJob'
    lib.print.debug('[IN]', func_name, '-source=', source)

    local attempts = 0
    while not isActiveContractCacheLoaded and attempts < 10 do
        Wait(1000)
        attempts = attempts + 1
    end
    if not isActiveContractCacheLoaded then
        warn('Cannot restore trucking job: active contracts have not loaded from SQL yet.')
        return nil
    end

    local citizenId = GetCitizenIdFromSource(source)
    local contract = activeContracts[citizenId]
    if not contract then
        return nil
    end

    local vehicles = GetActiveJobVehiclesForCitizenId(citizenId)
    if not vehicles or not vehicles.truck or not DoesEntityExist(vehicles.truck) then
        warn(string.format('Cannot restore contract %s: saved truck is unavailable.', contract.id))
        return nil
    end

    local _, destinationBoss = getContractData(contract.contractTitle)
    if not destinationBoss then
        error(string.format('Could not find destination boss for contract %s', contract.contractTitle), 1)
    end

    local destination = contract.currDestination
    if vehicles.trailer and not DoesEntityExist(vehicles.trailer) then
        warn(string.format('Cannot restore contract %s: saved trailer is unavailable.', contract.id))
        return nil
    end

    local truckNetId = NetworkGetNetworkIdFromEntity(vehicles.truck)
    if not truckNetId or truckNetId <= 0 then
        warn(string.format('Cannot restore contract %s: truck network ID is invalid.', contract.id))
        return nil
    end

    local trailerNetId
    if vehicles.trailer then
        trailerNetId = NetworkGetNetworkIdFromEntity(vehicles.trailer)
        if not trailerNetId or trailerNetId <= 0 then
            warn(string.format('Cannot restore contract %s: trailer network ID is invalid.', contract.id))
            return nil
        end
    end

    exports.qbx_vehiclekeys:GiveKeys(source, vehicles.truck)

    local savedJob = {
        id = contract.id,
        contractTitle = contract.contractTitle,
        destination = destination,
        destinationBossId = destinationBoss.id,
        truckNetId = truckNetId,
        trailerNetId = trailerNetId
    }

    lib.print.debug('[OUT]', func_name, '-contractId=', contract.id, '-truckNetId=', truckNetId, '-trailerNetId=', trailerNetId)
    return savedJob
end)

local function restoreActiveContractsFromCache()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local contracts = GetActiveContractsFromSQL()
    lib.print.debug('[IN]', func_name, '-activeContractCount=', #contracts)
    local restoredCount = 0

    for _, contract in ipairs(contracts) do
        lib.print.debug(
            '[ACTIVE CONTRACT FROM SQL]',
            '-id=', contract.id,
            '-citizenid=', contract.citizenid,
            '-created_at=', contract.created_at
        )

        local citizenId = contract.citizenid
        local contractTitle = contract.contract_title
        local secondsToExpire = tonumber(contract.seconds_to_expire)
        local reward = tonumber(contract.reward)
        local destination = DecodeSavedVec4(contract.dest_coords)
        local truckCoords = DecodeSavedVec4(contract.truck_vec4)
        local trailerCoords = DecodeSavedVec4(contract.trailer_vec4)

        if not citizenId or not contract.id or not contractTitle or not secondsToExpire or not reward
            or not destination or not truckCoords
            or (contract.trailer_vec4 ~= nil and contract.trailer_vec4 ~= 'null' and not trailerCoords) then
            warn(string.format('Skipping restore for active contract %s: saved contract or vehicle data is invalid.', tostring(contract.id)))
        elseif not getContractData(contractTitle) then
            warn(string.format('Skipping restore for contract %s: configured contract "%s" was not found.', contract.id, contractTitle))
        else
            local truck, trailer, restoreError = RestoreActiveJobVehiclesForCitizenId(
                citizenId,
                contract.id,
                truckCoords,
                trailerCoords
            )

            if not truck then
                warn(string.format('Skipping restore for contract %s: %s', contract.id, restoreError or 'vehicle restore failed'))
            else
                activeContracts[citizenId] = {
                    id = contract.id,
                    contractTitle = contractTitle,
                    currDestination = vec3(destination.x, destination.y, destination.z),
                    reward = reward,
                    expiresAt = os.time() + secondsToExpire
                }
                restoredCount = restoredCount + 1
            end
        end

    end

    isActiveContractCacheLoaded = true
    lib.print.debug('[OUT]', func_name, '-restoredCount=', restoredCount)
end

AddEventHandler('onResourceStart', function(resource)
    local func_name = 'onResourceStart'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    restoreActiveContractsFromCache()

    startExpirationThread()
    lib.print.debug('[OUT]', func_name, '-')
end)

AddEventHandler('onResourceStop', function(resource)
    local func_name = 'onResourceStop'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    local updatedContracts = 0
    for citizenId, contract in pairs(activeContracts) do
        local secondsToExpire = math.max(0, contract.expiresAt - os.time())
        local currTruckCoords, currTrailerCoords = GetActiveVehiclesCoordsForCitizenId(citizenId)
        UpdateExistingContractInSQL(
            contract.id,
            contract.contractTitle,
            contract.currDestination,
            currTruckCoords,
            currTrailerCoords,
            contract.reward,
            secondsToExpire
        )
        updatedContracts = updatedContracts + 1
    end

    lib.print.debug('[OUT]', func_name, '-updatedContracts=', updatedContracts)
end)
