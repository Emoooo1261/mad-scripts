local configShared = require 'config.shared'

-- Helper functions --

local function isTrailer(vehicle)    -- do we need to check if entity is a trailer when the models are hardcoded?
    -- local func_name = debug.getinfo(1, 'n').name
    -- lib.print.debug('[IN]', func_name, '-vehicle=', vehicle) -- function is called too often to log

    if not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        -- lib.print.debug('[OUT]', func_name, '-isTrailer=', false)
        return false
    end

    local model = GetEntityModel(vehicle)

    for _, trailerModel in ipairs(configShared.TrailerModels) do
        if model == trailerModel then
            -- lib.print.debug('[OUT]', func_name, '-isTrailer=', true)
            return true
        end
    end

    -- lib.print.debug('[OUT]', func_name, '-isTrailer=', false)
    return false
end

local function getDoors(vehicle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-vehicle=', vehicle)

    local model = GetEntityModel(vehicle)
    local modelName = string.lower(GetDisplayNameFromVehicleModel(model))
    local modelDoors = configShared.ModelDoors[modelName]

    lib.print.debug('[OUT]', func_name, '-modelDoors=', modelDoors)
    return doors
end

-- Door handling functions --

local function applyTrailerDoors(vehicle, open)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-vehicle=', vehicle, '-open', open)

    if not DoesEntityExist(vehicle) then return end

    local doors = getDoors(vehicle)

    for _, door in ipairs(doors) do
        if open then
            SetVehicleDoorOpen(vehicle, door, false, false)
        else
            SetVehicleDoorShut(vehicle, door, false)
        end
    end

    lib.print.debug('[OUT]', func_name, '-')
end

local function requestDoorChange(vehicle, open)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-vehicle=', vehicle, '-open', open)

    if not DoesEntityExist(vehicle) then return end
    if not isTrailer(vehicle) then return end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local vehicleCoords = GetEntityCoords(vehicle)

    if #(playerCoords - vehicleCoords) > configShared.InteractionDistance then
        return
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)

    if not netId or netId == 0 then return end

    TriggerServerEvent('qbx-trailerdoors:server:setDoors', netId, open)

    lib.print.debug('[OUT]', func_name, '-')
end

-- Apply synchronized state to streamed vehicles.
-- Triggered when StateBag changes for anything (not just trailers).
-- Applies the new StateBag for the client if vehicle is a trailer only.
AddStateBagChangeHandler(configShared.StateBag, nil, function(bagName, _, value)
    lib.print.debug('[IN]', 'AddStateBagChangeHandler', '-stateBag=', configShared.StateBag)

    if value == nil then return end

    local vehicle = GetEntityFromStateBagName(bagName)


    if vehicle ~= 0 and DoesEntityExist(vehicle) and isTrailer(vehicle) then
        applyTrailerDoors(vehicle, value)
    end

    lib.print.debug('[OUT]', 'AddStateBagChangeHandler', '-')
end)

-- ox_target interactions
exports.ox_target:addModel(configShared.TrailerModels, {
    {
        name = 'trailerdoors_open',
        icon = 'fa-solid fa-door-open',
        label = configShared.TargetLabelOpen,
        distance = configShared.TargetDistance,

        canInteract = function(entity)
            return isTrailer(entity) and Entity(entity).state[configShared.StateBag] ~= true -- in current state doors are closed
        end,

        onSelect = function(data)
            requestDoorChange(data.entity, true)
        end
    },

    {
        name = 'trailerdoors_close',
        icon = 'fa-solid fa-door-closed',
        label = configShared.TargetLabelClose,
        distance = configShared.TargetDistance,

        canInteract = function(entity)
            return isTrailer(entity) and Entity(entity).state[configShared.StateBag] == true -- in current state doors are open
        end,

        onSelect = function(data)
            requestDoorChange(data.entity, false)
        end
    }
})
