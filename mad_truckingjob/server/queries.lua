local function getCharName(source)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source)

    local Player = exports.qbx_core:GetPlayer(source)

    if not Player then
        return nil
    end

    local charinfo = Player.PlayerData.charinfo
    local charName = string.format('%s %s', charinfo.firstname, charinfo.lastname)

    lib.print.debug('[OUT]', func_name, '-charName', charName)
    return charName
end

-- Need to round coords before saving to SQL, otherwise they are saved with too many decimals
local function roundCoord(value)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-value=', value)

    local scale = 100

    if not value then return end -- incase of nil value, just ignore and return nil

    if value >= 0 then
        local rounded = math.floor(value * scale + 0.5) / scale
        lib.print.debug('[OUT]', func_name, '-rounded=', rounded)
        return rounded
    end

    local rounded = math.ceil(value * scale - 0.5) / scale
    lib.print.debug('[OUT]', func_name, '-rounded=', rounded)
    return rounded
end

local function serializeCoords(coords)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-coords=', coords)

    -- when coords are vec3 coords.w is nil
    local coordsLst = {roundCoord(coords.x),
                    roundCoord(coords.y),
                    roundCoord(coords.z),
                    roundCoord(coords.w)}

    local serializedCoords = json.encode(coordsLst)
    lib.print.debug('[OUT]', func_name, '-serializedCoords=', serializedCoords)
    return serializedCoords
end

function AddContractToSQL(source, citizenId, contractTitle, startCoords, destCoords, truckCoords, trailerCoords, reward, secondsToExpire)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source, '-citizenId=', citizenId, '-contractTitle', contractTitle, '-startCoords', startCoords, '-destCoords', destCoords, '-truckCoords=', truckCoords, '-trailerCoords=', trailerCoords, '-reward=', reward, '-secondsToExpire=', secondsToExpire)

    local charName = getCharName(source)
    local status = 'active'

    local contractId = MySQL.insert.await([[
        INSERT INTO mad_truckingjob_contracts
            (citizenid, char_name, contract_title, start_coords, dest_coords, truck_vec4, trailer_vec4, status, reward, seconds_to_expire)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenId,
        charName,
        contractTitle,
        serializeCoords(startCoords),
        serializeCoords(destCoords),
        serializeCoords(truckCoords),
        serializeCoords(trailerCoords),
        status,
        reward,
        secondsToExpire
    })

    if not contractId then
        error('Failed to get contractId!', 1)
    end

    lib.print.debug('[OUT]', func_name, '-contractId=', contractId)
    return contractId
end

local function setExistingContractStatusInSQL(citizenId, contractId, status)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId=', contractId, '-status', status)

    if not citizenId or not contractId or not status then
        error('Invalid input parameters!', 1)
    end

    local updatedRows
    updatedRows = MySQL.update.await([[
        UPDATE mad_truckingjob_contracts
        SET status = ?, closed_at = CURRENT_TIMESTAMP
        WHERE id = ? AND citizenid = ?
    ]], {
        status,
        contractId,
        citizenId
    })

    if updatedRows ~= 1 then
        error(string.format('Failed to set contract %s to %s for player %s', contractId, status, citizenId), 1)
    end

    lib.print.debug('[OUT]', func_name, '-updatedRows=', updatedRows)
    return true
end

function SetExistingContractToCompletedInSQL(citizenId, contractId, secondsToExpire)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId', contractId)

    local result = setExistingContractStatusInSQL(citizenId, contractId, 'completed')

    lib.print.debug('[OUT]', func_name, '-result=', result)
    return result
end

function SetExistingContractToCancelledInSQL(citizenId, contractId, secondsToExpire)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId', contractId)

    local result = setExistingContractStatusInSQL(citizenId, contractId, 'cancelled')

    lib.print.debug('[OUT]', func_name, '-result=', result)
    return result
end

function GetActiveContractsFromSQL()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local contracts = MySQL.query.await([[
        SELECT *
        FROM mad_truckingjob_contracts
        WHERE status = ?
    ]], { 'active' })

    lib.print.debug('[OUT]', func_name, '-contractCount=', #contracts)
    return contracts
end

function UpdateExistingContractInSQL(contractId, contractTitle, destCoords, currTruckCoords, currTrailerCoords, reward, secondsToExpire)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug(
        '[IN]', func_name,
        '-contractId=', contractId,
        '-contractTitle=', contractTitle,
        '-destCoords=', destCoords,
        '-currTruckCoords=', currTruckCoords,
        '-currTrailerCoords=', currTrailerCoords,
        '-reward=', reward,
        '-secondsToExpire=', secondsToExpire
    )

    local updateQuery
    local parameters

    if currTrailerCoords then
        updateQuery = [[
            UPDATE mad_truckingjob_contracts
            SET contract_title = ?,
                dest_coords = ?,
                truck_vec4 = ?,
                trailer_vec4 = ?,
                reward = ?,
                seconds_to_expire = ?
            WHERE id = ? AND status = 'active'
        ]]
        parameters = {
            contractTitle,
            serializeCoords(destCoords),
            serializeCoords(currTruckCoords),
            serializeCoords(currTrailerCoords),
            reward,
            secondsToExpire,
            contractId
        }
    else
        updateQuery = [[
            UPDATE mad_truckingjob_contracts
            SET contract_title = ?,
                dest_coords = ?,
                truck_vec4 = ?,
                trailer_vec4 = NULL,
                reward = ?,
                seconds_to_expire = ?
            WHERE id = ? AND status = 'active'
        ]]
        parameters = {
            contractTitle,
            serializeCoords(destCoords),
            serializeCoords(currTruckCoords),
            reward,
            secondsToExpire,
            contractId
        }
    end

    local updatedRows = MySQL.update.await(updateQuery, parameters)

    if updatedRows ~= 1 then
        error(string.format('Failed to update active contract %s', contractId), 1)
    end

    lib.print.debug('[OUT]', func_name, '-updatedRows=', updatedRows)
end