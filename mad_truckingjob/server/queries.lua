local function getCharInfo(source)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source)

    local Player = exports.qbx_core:GetPlayer(source)

    if not Player then
        return nil
    end

    local citizenId = Player.PlayerData.citizenid
    local charinfo = Player.PlayerData.charinfo
    local charName = ('%s %s'):format(charinfo.firstname, charinfo.lastname)

    lib.print.debug('[OUT]', func_name, '-citizenId=', citizenId, '-charName', charName)
    return citizenId, charName
end

-- Need to round coords before saving to SQL, otherwise they are saved with too many decimals
local function roundCoord(value)
    local scale = 100

    if not value then return end -- incase of nil value, just ignore and return nil

    if value >= 0 then
        return math.floor(value * scale + 0.5) / scale
    end

    return math.ceil(value * scale - 0.5) / scale
end

local function serializeCoords(coords)
    -- when coords are vec3 coords.w is nil
    local coordsLst = {roundCoord(coords.x),
                    roundCoord(coords.y),
                    roundCoord(coords.z),
                    roundCoord(coords.w)}

    return json.encode(coordsLst)
end

function AddContractToSQL(source, contractTitle, startCoords, endCoords)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source, '-contractTitle', contractTitle, '-startCoords', startCoords, '-endCoords', endCoords)

    local citizenid, charName = getCharInfo(source)
    local status = 'active'
    local reward = 1000

    local contractId = MySQL.insert.await([[
        INSERT INTO mad_truckingjob_contracts
            (citizenid, char_name, job_title, start_coords, end_coords, status, reward)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        charName,
        contractTitle,
        serializeCoords(startCoords),
        serializeCoords(endCoords),
        status,
        reward
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
        error(('Failed to set contract %s to %s for player %s'):format(contractId, status, citizenId), 1)
    end

    lib.print.debug('[OUT]', func_name, '-updatedRows=', updatedRows)
    return true
end

function SetExistingContractToCompletedInSQL(citizenId, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId', contractId)

    local result = setExistingContractStatusInSQL(citizenId, contractId, 'completed')

    lib.print.debug('[OUT]', func_name, '-result=', result)
    return result
end

function SetExistingContractToCancelledInSQL(citizenId, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId', contractId)

    local result = setExistingContractStatusInSQL(citizenId, contractId, 'cancelled')

    lib.print.debug('[OUT]', func_name, '-result=', result)
    return result
end