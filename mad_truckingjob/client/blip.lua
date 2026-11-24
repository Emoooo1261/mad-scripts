local bossBlips = {}
local destBlip = nil
local truckBlip = nil
local trailerBlip = nil
local isTruckBlipThreadRunning = false

local function startTruckBlipThread()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    if isTruckBlipThreadRunning then
        lib.print.debug('[-]', func_name, 'Truck blip thread already running.')
        return
    end

    isTruckBlipThreadRunning = true

    CreateThread(function()
        lib.print.debug('[-]', func_name, 'Truck blip thread started.')
        while truckBlip do
            local contract = GetContract()
            local playerPed = PlayerPedId()
            local shouldHide = contract.truck ~= nil
                and DoesEntityExist(contract.truck)
                and GetPedInVehicleSeat(contract.truck, -1) == playerPed

            SetBlipDisplay(truckBlip, shouldHide and 0 or 2)  -- 0 hides, 2 shows the blip
            Wait(5000)

        end

        lib.print.debug('[-]', func_name, 'Truck blip thread stopped.')
        isTruckBlipThreadRunning = false
    end)

    lib.print.debug('[OUT]', func_name, '-')
end

function CreateTruckBlip(truck)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-truck=', truck)

    if truckBlip then
        RemoveBlip(truckBlip)
    end

    truckBlip = AddBlipForEntity(truck)

    SetBlipSprite(truckBlip, 477)
    SetBlipColour(truckBlip, 30)
    SetBlipScale(truckBlip, 0.6)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Job Truck')
    EndTextCommandSetBlipName(truckBlip)

    startTruckBlipThread()

    lib.print.debug('[OUT]', func_name, '-blip=', truckBlip)
end

function CreateDropOffBlip(destination)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-destination=', destination)

    if destBlip then
        RemoveBlip(destBlip)
    end

    destBlip = AddBlipForCoord(
        destination.x,
        destination.y,
        destination.z
    )

    SetBlipSprite(destBlip, 478)
    SetBlipColour(destBlip, 5)
    SetBlipScale(destBlip, 0.8)
    SetBlipRoute(destBlip, true)
    SetBlipRouteColour(destBlip, 5)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString("Cargo drop off")
    EndTextCommandSetBlipName(destBlip)

    lib.print.debug('[OUT]', func_name, '-')
end

function CreateBossBlip(coords)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local newBossBlip = AddBlipForCoord(
        coords.x,
        coords.y,
        coords.z
    )

    SetBlipSprite(newBossBlip, 477)
    SetBlipColour(newBossBlip, 5)
    SetBlipScale(newBossBlip, 0.8)
    SetBlipAsShortRange(newBossBlip, true)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString("Trucking job")
    EndTextCommandSetBlipName(newBossBlip)

    bossBlips[#bossBlips + 1] = newBossBlip

    lib.print.debug('[OUT]', func_name, '-')
end

function CreateTrailerBlip(trailer)
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-trailer=', trailer)

    if trailerBlip then
        RemoveBlip(trailerBlip)
    end

    trailerBlip = AddBlipForEntity(trailer)

    SetBlipSprite(trailerBlip, 479)
    SetBlipColour(trailerBlip, 30)
    SetBlipScale(trailerBlip, 0.6)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Job Trailer')
    EndTextCommandSetBlipName(trailerBlip)

    lib.print.debug('[OUT]', func_name, '-blip=', trailerBlip)
end

function SetBlipsToFinishJob()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    local contract = GetContract()
    CreateDropOffBlip(contract.destination)
    -- createTruckBlip(contract.truck)

    lib.print.debug('[OUT]', func_name, '-')
end

function RemoveTrailerBlip()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    if trailerBlip then
        RemoveBlip(trailerBlip)
    end
    trailerBlip = nil

    lib.print.debug('[OUT]', func_name, '-')
end

function ClearBlips()
    local func_name = debug.getinfo(1, 'n').name
    lib.print.debug('[IN]', func_name, '-')

    RemoveTrailerBlip()

    if destBlip then
        RemoveBlip(destBlip)
    end
    if truckBlip then
        RemoveBlip(truckBlip)
    end

    destBlip = nil
    truckBlip = nil

    lib.print.debug('[OUT]', func_name, '-')
end


AddEventHandler('onResourceStop', function(resource)
    local func_name = 'onResourceStop'
    lib.print.debug('[IN]', func_name, '-resource=', resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    for _, bossBlip in ipairs(bossBlips) do
        if bossBlip then
            RemoveBlip(bossBlip)
        end
    end
    bossBlips = {}

    ClearBlips()

    isTruckBlipThreadRunning = false

    lib.print.debug('[OUT]', func_name, '-')
end)