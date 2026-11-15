local configShared = require 'config.shared'
local activeContracts = {}
local activeJobVehicles = {}
local activeJobCitizenIds = {}
local CONTRACT_TIMEOUT_MS = 45 * 60 * 1000  -- 45mins

-- TODO finish the timeout function
-- TODO i think citizenId needs to be used instead of source, because source gives the current server id of the player,
-- but idk what happens with that id if the player reconnects to the server

local function getDeliveryDestination(contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    local deliveryDestination = nil
    for _, item in pairs(configShared.contracts) do
        if item.title == contractTitle then
            deliveryDestination = item.deliveries[math.random(#item.deliveries)]
            break
        end
    end

    if not deliveryDestination then
        error('Failed to set delivery destination!', 1)
    end

    lib.print.debug('[OUT]', func_name, '-deliveryDestination=', deliveryDestination)
    return deliveryDestination
end

local function isValidContract(source, contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source, '-contractTitle=', contractTitle)

    if not contractTitle or not source then
        error('Invalid input!', 1)
    end

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

-- local function expireActiveContract(source, contractId)
--     if activeContracts[source] ~= contractId then
--         return
--     end

--     local vehicles = activeJobVehicles[source]
--     if not vehicles or vehicles.closing then
--         return
--     end
--     vehicles.closing = true

--     local citizenId = activeJobCitizenIds[source]
--     SetExistingContractToCancelledForCitizenInSQL(citizenId, contractId)

--     local player = exports.qbx_core:GetPlayer(source)
--     local playerStillOwnsContract = player and player.PlayerData.citizenid == citizenId
--     if playerStillOwnsContract then
--         UpdateWorkTicket(source, contractId, 'CANCELLED')
--     end

--     for _, vehicleType in ipairs({'truck', 'trailer'}) do
--         local vehicle = vehicles[vehicleType]
--         if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
--             DeleteEntity(vehicle)
--         end
--     end

--     activeContracts[source] = nil
--     activeJobVehicles[source] = nil
--     activeJobCitizenIds[source] = nil

--     if playerStillOwnsContract then
--         TriggerClientEvent('mad_truckingjob:client:jobExpired', source, contractId)
--     end
-- end


lib.callback.register('mad_truckingjob:server:addActiveContract', function(source, contractTitle)
    lib.print.debug('[IN]mad_truckingjob:server:addActiveContract', '-source=', source, '-contractTitle=', contractTitle)

    if not isValidContract(source, contractTitle) then
        error('Couldn\'t find correct contract!', 1)
    end

    if activeContracts[source] then
        error('Player already has an active trucking job!', 1)
    end

    local truckAndTrailer = SpawnJobVehicle()
    local successRegisteringVehicle = RegisterJobVehicleForClient(truckAndTrailer)

    local contractId = nil
    local destination = nil

    -- Registering vehicle can fail because there is no space to spawn vehicles.
    -- This is not an error, but client needs to retry.
    if successRegisteringVehicle then
        destination = getDeliveryDestination(contractTitle)
        -- TODO implement a way to respawn the truck and trailer on server restart if job is ongoing
        -- TODO add reward

        contractId = AddContractToSQL(source, contractTitle, truckAndTrailer.trailerCoords, destination)

        activeContracts[source] = contractId  -- cache
        activeJobVehicles[source] = {
            truck = truckAndTrailer.truck,
            trailer = truckAndTrailer.trailer
        }
        GiveWorkTicket(source, contractTitle, contractId)

        SetTimeout(CONTRACT_TIMEOUT_MS, function()
            expireActiveContract(source, contractId)
        end)
    else
        lib.print.warn('[]mad_truckingjob:server:addActiveContract', 'Spawning job vehicles failed.')
    end

    lib.print.debug('[OUT]mad_truckingjob:server:addActiveContract', '-successRegisteringVehicle=', successRegisteringVehicle, '-contractId=', contractId, '-destination=', destination)
    return successRegisteringVehicle, contractId, destination
end)

lib.callback.register('mad_truckingjob:server:removeActiveContract', function(source, contractId, vehicleNetId, isTrailer)
    lib.print.debug('[IN]mad_truckingjob:server:removeActiveContract', '-source=', source, '-contractId=', contractId, '-vehicleNetId=', vehicleNetId, '-isTrailer=', isTrailer)

    if not source or not contractId or not vehicleNetId then
        error('Invalid input!', 1)
    end

    if activeContracts[source] == contractId then
        local success = false

        if isTrailer then
            success = UpdateWorkTicket(source, contractId, 'RETURNED_TRAILER')
            if activeJobVehicles[source] then
                activeJobVehicles[source].trailer = nil
            end
        else
            success = UpdateWorkTicket(source, contractId, 'RETURNED_TRUCK')

            SetExistingContractToCompletedInSQL(source, contractId)
            activeContracts[source] = nil
            if activeJobVehicles[source] then
                activeJobVehicles[source].truck = nil
            end
        end
        DespawnJobVehicle(vehicleNetId)
    else
        lib.print.warning('Tried to remove a contract that was not active!')
    end

    lib.print.debug('[OUT]mad_truckingjob:server:removeActiveContract', '-')
end)

lib.callback.register('mad_truckingjob:server:cancelActiveContract', function(source, contractId)
    if not contractId then
        error('Invalid contractId!', 1)
    end

    if activeContracts[source] ~= contractId then
        error('Contract not in local memory!', 1) -- TODO: get active contracts from SQL on resource initialization, to prevent losing job on server restart
    end

    SetExistingContractToCancelledInSQL(source, contractId)
    UpdateWorkTicket(source, contractId, 'CANCELLED')

    local vehicles = activeJobVehicles[source]
    if vehicles then
        for _, vehicle in pairs(vehicles) do
            if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                DeleteEntity(vehicle)
            end
        end
    end

    activeContracts[source] = nil
    activeJobVehicles[source] = nil
    return true
end)
