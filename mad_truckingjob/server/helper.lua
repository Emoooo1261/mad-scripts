--- City docks to Paleto = ~10km
--- If we want to pay $500 for that trip, the math would be:
--- Pay for longest route (500) / (Longest path (10km) * Meters (1000)) or: 500 * 0.1 * 0.001
local BASE_PAY_PER_METER = 500 * 0.1 * 0.001


function CalculatePayReward(start, finish)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-start=', start, '-finish=', finish)

    local startVec3 = vec3(start.x, start.y, start.z)
    local reward =  math.floor(#(startVec3 - finish) * BASE_PAY_PER_METER)

    -- This is client side only :/
    -- local distance = CalculateTravelDistanceBetweenPoints(
    --     start.x, start.y, start.z,
    --     finish.x, finish.y, finish.z
    -- )

    lib.print.debug('[OUT]', func_name, '-reward=', reward)
    return reward
end

function GetCitizenIdFromSource(source)
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

function ValidateExpectedVehicleNetIdForCitizenId(vehNetId, citizenId, isTrailer)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-vehNetId=', vehNetId, '-citizenId=', citizenId, '-isTrailer=', isTrailer)

    local vehicles = GetActiveJobVehiclesForCitizenId(citizenId)
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

    lib.print.debug('[OUT]', func_name, '-expectedNetId=', expectedNetId)
end

function ValidateVehicleReturnForCitizen(source, citizenId, vehNetId, isTrailer, destination)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug(
        '[IN]', func_name,
        '-source=', source,
        '-citizenId=', citizenId,
        '-vehNetId=', vehNetId,
        '-isTrailer=', isTrailer,
        '-destination=', destination
    )

    if type(vehNetId) ~= 'number' or vehNetId <= 0 or type(isTrailer) ~= 'boolean' then
        error('Invalid vehicle return parameters!', 1)
    end
    if not destination then
        error('Active contract has no delivery destination!', 1)
    end

    local vehicles = GetActiveJobVehiclesForCitizenId(citizenId)
    if not vehicles then
        error('No active job vehicles found!', 1)
    end

    if not isTrailer and vehicles.trailer then
        error('Return the job trailer before returning the truck!', 1)
    end

    ValidateExpectedVehicleNetIdForCitizenId(vehNetId, citizenId, isTrailer)

    local vehicle = isTrailer and vehicles.trailer or vehicles.truck
    local playerPed = GetPlayerPed(source)
    if not DoesEntityExist(playerPed) then
        error('Player ped is unavailable for vehicle return!', 1)
    end

    local playerCoords = GetEntityCoords(playerPed)
    if #(playerCoords - destination) > 15.0 then
        error('Player is too far from the delivery destination!', 1)
    end

    if #(playerCoords - GetEntityCoords(vehicle)) > 15.0 then
        error('Player is too far from the job vehicle!', 1)
    end

    lib.print.debug('[OUT]', func_name, '-vehicle=', vehicle)
    return vehicle
end

function DecodeSavedVec4(value)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-value=', value)

    if value == nil or value == 'null' then
        return nil
    end

    local coordinates = value
    if type(value) == 'string' then
        coordinates = json.decode(value)
    end

    if type(coordinates) ~= 'table' then
        return nil
    end

    local x = tonumber(coordinates[1] or coordinates.x)
    local y = tonumber(coordinates[2] or coordinates.y)
    local z = tonumber(coordinates[3] or coordinates.z)
    local heading = tonumber(coordinates[4] or coordinates.w)

    if not x or not y or not z then
        return nil
    end

    local coords = vec4(x, y, z, heading or 0.0)
    lib.print.debug('[OUT]', func_name, '-coords=', coords)
    return coords
end