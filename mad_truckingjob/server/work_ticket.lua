local configShared = require 'config.shared'


function GiveWorkTicket(source, contractTitle, contractId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-source=', source, '-contractTitle=', contractTitle, '-contractId=', contractId)

    local metadata = nil
    for _, contract in ipairs(configShared.contracts) do
        if contract.title == contractTitle then
            metadata = {
                title = contract.title,
                description = contract.description,
                contractId = contractId,
            }
            break
        end
    end

    if not metadata then
        error('Couldn\'t find correct contract!', 1)
    else
        if exports.ox_inventory:CanCarryItem(source, 'stickynote', 1, metadata) then
            exports.ox_inventory:AddItem(
                source,
                'stickynote',
                1,
                metadata
            )
        else
            -- Doesn't stop the job from being created, but player will not have a work ticket in their inventory
            warn(string.format('Player %s cannot carry work ticket!', source))
        end
    end

    lib.print.debug('[OUT]', func_name, '-')
end


function UpdateWorkTicket(citizenId, contractId, status)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-citizenId=', citizenId, '-contractId=', contractId, '-status', status)

    local player = exports.qbx_core:GetPlayerByCitizenId(citizenId)
    local playerSource = player and player.PlayerData.source

    if not playerSource then
        if status == 'EXPIRED' then  -- Job can expire when player is offline
            warn(string.format('Couldn\'t update work ticket to EXPIRED for %s', citizenId))
            return false
        else
            error(string.format('Couldn\'t get source for citizenId= %s', citizenId), 1)
        end
    end

    local itemSlots = exports.ox_inventory:Search(playerSource, 'slots', 'stickynote')

    local result = false
    for _, item in pairs(itemSlots) do
        if item.metadata.contractId == contractId then
            local newDescription = nil

            if status == 'RETURNED_TRAILER' then
                newDescription = string.format('%s Trailer RETURNED', item.metadata.description)
            elseif status == 'RETURNED_TRUCK' then
                newDescription = string.format('%s Truck RETURNED and Job COMPLETED!', item.metadata.description)
            elseif status == 'CANCELLED' then
                newDescription = string.format('%s Job CANCELLED!', item.metadata.description)
            elseif status == 'EXPIRED' then
                newDescription = string.format('%s Job EXPIRED!', item.metadata.description)
            end

            local newMetadata = {title = item.metadata.title,
                                description = newDescription,
                                contractId = item.metadata.contractId,
                                status = status}

            exports.ox_inventory:SetMetadata(playerSource, item.slot, newMetadata)
            result = true
        end
    end

    lib.print.debug('[OUT]', func_name, '-result=', result)
    return result
end