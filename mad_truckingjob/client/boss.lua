local configShared = require 'config.shared'
local bossPeds = {}
local currentJob = {
    contract = nil,
    destBossId = nil
}

local isTrailerDelivered = true  -- job has not started
local selectedFinishJob = false


function GetCurrentJob()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    lib.print.debug('[OUT]', func_name, '-currentJob=', currentJob)
    return currentJob
end

function RestoreCurrentJob(contractTitle, destinationBossId, trailerDelivered)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle, '-destinationBossId=', destinationBossId, '-trailerDelivered=', trailerDelivered)

    if type(contractTitle) ~= 'string' or contractTitle == '' or not destinationBossId
        or type(trailerDelivered) ~= 'boolean' then
        error('Invalid saved trucking job data!', 1)
    end

    currentJob.contract = contractTitle
    currentJob.destBossId = destinationBossId
    isTrailerDelivered = trailerDelivered
    selectedFinishJob = false

    lib.print.debug('[OUT]', func_name, '-currentJob=', currentJob)
end

function ClearCurrentJob()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-currentJob=', currentJob)

    currentJob.contract = nil
    currentJob.destBossId = nil
    isTrailerDelivered = true
    selectedFinishJob = false

    lib.print.debug('[OUT]', func_name, '-currentJob=', currentJob)
end

function GetBossCoords()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-destinationBossId=', currentJob.destBossId)

    for _, bossData in ipairs(configShared.bossPeds) do
        if bossData.id == currentJob.destBossId then
            return bossData.coords
        end
    end

    lib.print.debug('[OUT]', func_name, '-coords=', nil)
end

function SetTrailerDelivered(isDelivered)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-isDelivered=', isDelivered)

    isTrailerDelivered = isDelivered

    lib.print.debug('[OUT]', func_name, '-isTrailerDelivered=', isTrailerDelivered)
end

local function selectContract(contractTitle, startBossId, destBossPedId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle, '-destBossPedId=', destBossPedId)

    local contractId = StartJob(contractTitle, startBossId)

    if contractId then
        currentJob.contract = contractTitle
        currentJob.destBossId = destBossPedId

        isTrailerDelivered = false
    end

    lib.print.debug('[OUT]', func_name, '-')
end

local function filterContractsForBoss(pedId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-pedId=', pedId)

    local contracts = {}
    for _, bossPed in ipairs(configShared.bossPeds) do
        if bossPed.id ~= pedId then
            contracts[bossPed.id] = bossPed.contracts
        end
    end

    lib.print.debug('[OUT]', func_name, '-nrContracts=', #contracts)
    return contracts
end

local function openJobsMenu(contracts, currBossPedId)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local options = {}
    local contextTitle = ''

    if not currentJob.contract then
        contextTitle = 'Select from available jobs.'
        -- Create menu option for each contract
        for destBossPedId, bossContracts in pairs(contracts) do
            for _, contract in ipairs(bossContracts) do
                options[#options + 1] = {
                    title = contract.title,
                    description = contract.description,
                    icon = 'truck',

                    onSelect = function()
                        selectContract(contract.title, currBossPedId, destBossPedId)
                    end
                }
            end
        end
    else
        if selectedFinishJob then
            contextTitle = 'Return truck to finish the job.'
        elseif isTrailerDelivered and currentJob.destBossId == currBossPedId then
            contextTitle = 'Get new trailer. Select from available jobs.'
            local title = 'Return truck and finish job.'
            local description = 'Go return the truck and come back to get paid.'

            options[1] = {
                title = title,
                description = description,
                icon = 'truck',

                onSelect = function()
                    SetBlipsToFinishJob()
                    selectedFinishJob = true
                end
            }

            for _, bossContracts in pairs(contracts) do
                for _, contract in ipairs(bossContracts) do
                    options[#options + 1] = {
                        title = contract.title,
                        description = contract.description,
                        icon = 'truck',

                        onSelect = function()
                            local startedNewDelivery = StartNewDelivery(contract.title, currBossPedId)
                            if startedNewDelivery then
                                isTrailerDelivered = false
                            end
                        end
                    }
                end
            end
        end
    end

    if currentJob.contract then
        contextTitle = 'You have an active trucking job.'
            options[#options + 1] = {
                title = 'Cancel active job',
                description = string.format('Current job: %s.\nCancel this job and return the provided vehicles.\nYou will not get paid if you cancel the job!', currentJob.contract),
                icon = 'xmark',

                onSelect = function()
                    CancelJobContract()
                end
            }
    end

    lib.registerContext({
        id = 'truckingjob_contracts',
        title = contextTitle,
        options = options,
    })

    lib.showContext('truckingjob_contracts')

    lib.print.debug('[OUT]', func_name, '-')
end

local function createBossPed(pedData)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local model = joaat(pedData.model)
    lib.requestModel(model)

    local coords = pedData.coords
    local bossPed = CreatePed(
        0,
        model,
        coords.x,
        coords.y,
        coords.z - 1.0,
        coords.w,
        false,
        false
    )

    SetEntityInvincible(bossPed, true)
    FreezeEntityPosition(bossPed, true)
    SetBlockingOfNonTemporaryEvents(bossPed, true)

    -- Give ped scenario (action the npc is doing)
    if pedData.scenario then
        TaskStartScenarioInPlace(
            bossPed,
            pedData.scenario,
            0,
            true
        )
    end

    -- Enable interaction with ped
    exports.ox_target:addLocalEntity(bossPed, {
        {
            name = 'mad_truckingjob',
            icon = 'fa-solid fa-truck',
            label = 'Talk to Boss',
            distance = pedData.targetDistance,

            onSelect = function()
                local contracts = filterContractsForBoss(pedData.id)
                openJobsMenu(contracts, pedData.id)
            end
        }
    })

    -- lib.requestModel(model) loads the ped model into memory.
    -- CreatePed() creates the npc using that loaded model.
    -- SetModelAsNoLongerNeeded(model) frees the model from memory. 
    -- Ped is already spawned no need to keep the memory available.
    SetModelAsNoLongerNeeded(model)

    lib.print.debug('[OUT]', func_name, '-')
    return bossPed
end

local function createBoss()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    for i, pedData in pairs(configShared.bossPeds) do
        local bossPed = createBossPed(pedData)
        if bossPed and bossPed ~= 0 then
            bossPeds[i] = bossPed
            CreateBossBlip(pedData.coords)
        else
            error('Failed to create trucking job boss peds!', 1)
        end
    end

    lib.print.debug('[OUT]', func_name, '-')
end

-- Start main functionality when Client resource starts
AddEventHandler('onClientResourceStart', function(resource)
    local func_name = 'onClientResourceStart'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    createBoss()

    lib.print.debug('[OUT]', func_name, '-')
end)


-- Cleanup when resource is stopped
AddEventHandler('onResourceStop', function(resource)
    local func_name = 'onResourceStop'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then return end

    for _, bossPed in ipairs(bossPeds) do
        if bossPed and DoesEntityExist(bossPed) then
            exports.ox_target:removeLocalEntity(bossPed)
            DeleteEntity(bossPed)
        end
    end

    bossPeds = {}

    lib.print.debug('[OUT]', func_name, '-')
end)