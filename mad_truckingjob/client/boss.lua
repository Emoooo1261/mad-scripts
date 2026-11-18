local configShared = require 'config.shared'
local configClient = require 'config.client'
local bossPeds = {}
local currentJob = nil
local isFirstDeliveryDone = false
local isSecondDeliveryOngoing = false

function SetFirstDeliveryDone(isDeliveryDone)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-isDeliveryDone=', isDeliveryDone)

    isFirstDeliveryDone = isDeliveryDone

    lib.print.debug('[OUT]', func_name, '-')
end

function SetCurrentJob(contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    currentJob = contractTitle

    lib.print.debug('[OUT]', func_name, '-')
end

local function selectContract(contractTitle)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-contractTitle=', contractTitle)

    if CreateJobContract(contractTitle) then
        SetCurrentJob(contractTitle)
    end

    lib.print.debug('[OUT]', func_name, '-')
end

local function openJobsMenu(isMainBoss)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local options = {}
    local contextTitle = ''

    if not currentJob then
        if isMainBoss then
            contextTitle = 'Select from available jobs.'
            -- Create menu option for each contract
            for _, contract in ipairs(configShared.contracts) do
                options[#options + 1] = {
                    title = contract.title,
                    description = 'DESCRIPTION',
                    icon = 'truck',

                    onSelect = function()
                        selectContract(contract.title)
                    end
                }
            end
        else
            contextTitle = 'Get a job.'
        end
    else
        if not isSecondDeliveryOngoing and isFirstDeliveryDone and not isMainBoss then
            contextTitle = 'Get new trailer.'
            options[1] = {
                title = 'Return new trailer back to the city docks',
                description = 'DESCRIPTION',
                icon = 'truck',

                onSelect = function()
                    StartSecondTrailerDelivery()
                    isSecondDeliveryOngoing = true
                end
            }
        elseif not isFirstDeliveryDone or isSecondDeliveryOngoing then
            contextTitle = 'You have an active trucking job.'
            options[#options + 1] = {
                title = 'Cancel active job',
                description = ('Current job: %s.\nCancel this job and return the provided vehicles.'):format(currentJob),
                icon = 'xmark',

                onSelect = function()
                    CancelJobContract()
                end
            }
        end
    end

    options[#options + 1] = {
        title = 'Exit',
        description = 'Close this menu.',
        icon = 'xmark',

        onSelect = function()
            lib.hideContext()
        end
    }

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
                openJobsMenu(pedData.isMainBoss)
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

    for i, pedData in pairs(configClient.bossPeds) do
        local bossPed = createBossPed(pedData)
        if bossPed and bossPed ~= 0 then
            bossPeds[i] = bossPed
        else
            error('Failed to create trucking job boss peds!', 1)
        end
    end

    lib.print.debug('[OUT]', func_name, '-')
end

-- Start main functionality when Client resource starts
AddEventHandler('onClientResourceStart', function(resource)
    lib.print.debug('[IN]onClientResourceStart', '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    createBoss()

    lib.print.debug('[OUT]onClientResourceStart', '-')
end)


-- Cleanup when resource is stopped
AddEventHandler('onResourceStop', function(resource)
    lib.print.debug('[IN]onResourceStop', '-resource=', resource)

    if resource ~= GetCurrentResourceName() then return end

    for i, bossPed in pairs(bossPeds) do
        if bossPed and DoesEntityExist(bossPed) then
            exports.ox_target:removeLocalEntity(bossPed)
            DeleteEntity(bossPed)
        end
    end

    bossPeds = nil

    lib.print.debug('[OUT]onResourceStop', '-')
end)