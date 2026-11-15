local configShared = require 'config.shared'

RegisterNetEvent('qbx-trailerdoors:server:setDoors', function(netId, open)
    lib.print.debug('[IN]', 'qbx-trailerdoors:server:setDoors', '-netId=', netId, '-open=', open)

    local src = source

    if type(netId) ~= 'number' or type(open) ~= 'boolean' then
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        return
    end

    local ped = GetPlayerPed(src)

    if ped == 0 then return end

    local playerCoords = GetEntityCoords(ped)
    local vehicleCoords = GetEntityCoords(vehicle)

    if #(playerCoords - vehicleCoords) > configShared.InteractionDistance then  -- Length of the difference (# calculates the distance for the 2 3D vectors)
        return
    end

    -- Replicate the door state to all clients.
    Entity(vehicle).state:set(configShared.StateBag, open, true)

    lib.print.debug('[OUT]', 'qbx-trailerdoors:server:setDoors', '-')
end)