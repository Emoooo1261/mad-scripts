local configShared = require 'config.shared'
local configClient = require 'config.client'
local bossPed = nil
local currentJob = nil

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

local function openJobsMenu()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local options = {}
    local contextTitle = nil

    if currentJob then
        contextTitle = 'You have an active trucking job.'

        options[#options + 1] = {
            title = 'Cancel active job',
            description = ('Current job: %s.\nCancel this job and return the provided vehicles.'):format(currentJob),
            icon = 'xmark',

            onSelect = function()
                CancelJobContract()
            end
        }
    else
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

local function createBoss()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local model = joaat(configClient.bossPed.model)
    lib.requestModel(model)

    local coords = configClient.bossPed.coords
    bossPed = CreatePed(
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
    if configClient.bossPed.scenario then
        TaskStartScenarioInPlace(
            bossPed,
            configClient.bossPed.scenario,
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
            distance = configClient.bossPed.targetDistance,

            onSelect = function()
                openJobsMenu()
            end
        }
    })

    -- lib.requestModel(model) loads the ped model into memory.
    -- CreatePed() creates the npc using that loaded model.
    -- SetModelAsNoLongerNeeded(model) frees the model from memory. 
    -- Ped is already spawned no need to keep the memory available.
    SetModelAsNoLongerNeeded(model)

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

    if bossPed and DoesEntityExist(bossPed) then
        exports.ox_target:removeLocalEntity(bossPed)
        DeleteEntity(bossPed)
    end

    lib.print.debug('[OUT]onResourceStop', '-')
end)