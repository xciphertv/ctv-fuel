local Core = exports[Config.CoreResource]:GetCoreObject()
local Utils = require('client.utils')
local SharedUtils = require('shared.utils')

-- Local state variables
local fuelSynced = false
local inGasStation = false
local holdingNozzle = false
local refueling = false
local CurrentLocation = nil
local GasStationZones = {}
local fuelNozzle = nil
local Rope = nil

-- Function to handle fuel consumption
local function HandleFuelConsumption(vehicle)
    if not DecorExistOn(vehicle, Config.FuelDecor) then
        Utils.SetFuel(vehicle, math.random(200, 800) / 10)
    elseif not fuelSynced then
        Utils.SetFuel(vehicle, Utils.GetFuel(vehicle))
        fuelSynced = true
    end

    if IsVehicleEngineOn(vehicle) then
        local currentRpm = SharedUtils.Round(GetVehicleCurrentRpm(vehicle), 1)
        local vehicleClass = GetVehicleClass(vehicle)
        local fuelUsage = Config.FuelUsage[currentRpm] * (Config.Classes[vehicleClass] or 1.0) / 10
        
        Utils.SetFuel(vehicle, Utils.GetFuel(vehicle) - fuelUsage)
    end
end


-- Grab nozzle event handler
RegisterNetEvent('cdn-fuel:client:grabNozzle', function()
    local ped = PlayerPedId()
    
    if holdingNozzle then return end
    
    -- Check for station shutoff
    if Config.PlayerOwnedGasStationsEnabled then
        local shutOff = lib.callback.await('cdn-fuel:server:checkShutoff', false, CurrentLocation)
        
        if shutOff then
            lib.notify({
                title = 'Fuel System',
                description = 'Emergency shutoff is active',
                type = 'error'
            })
            return
        end
    end
    
    -- Animation and sound
    Utils.LoadAnimDict("anim@am_hold_up@male")
    TaskPlayAnim(ped, "anim@am_hold_up@male", "shoplift_high", 2.0, 8.0, -1, 50, 0, 0, 0, 0)
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "pickupnozzle", 0.4)
    Wait(300)
    StopAnimTask(ped, "anim@am_hold_up@male", "shoplift_high", 1.0)
    
    -- Create nozzle object
    fuelNozzle = CreateObject(joaat('prop_cs_fuel_nozle'), 1.0, 1.0, 1.0, true, true, false)
    local leftHand = GetPedBoneIndex(ped, 18905)
    AttachEntityToEntity(fuelNozzle, ped, leftHand, 0.13, 0.04, 0.01, -42.0, -115.0, -63.42, 0, 1, 0, 1, 0, 1)
    
    local nozzlePosition = GetEntityCoords(ped)
    holdingNozzle = true
    
    -- Create pump hose if enabled
    if Config.PumpHose then
        local pumpCoords, pump = Utils.GetClosestPump(nozzlePosition)
        
        if not pump or pump == 0 then
            if Config.FuelDebug then
                print("Failed to find a fuel pump nearby")
            end
            return
        end
        
        -- Load rope textures
        RopeLoadTextures()
        while not RopeAreTexturesLoaded() do Wait(0) end
        
        -- Create rope
        Rope = AddRope(
            pumpCoords.x, pumpCoords.y, pumpCoords.z,
            0.0, 0.0, 0.0,
            3.0, Config.RopeType['fuel'], 8.0,
            0.0, 1.0, false, false, false, 1.0, true
        )
        
        -- Position and attach rope
        ActivatePhysics(Rope)
        Wait(100)
        
        local nozzlePos = GetOffsetFromEntityInWorldCoords(fuelNozzle, 0.0, -0.033, -0.195)
        local pumpHeight = Config.GasStations[CurrentLocation] and Config.GasStations[CurrentLocation].pumpheightadd or 2.1
        
        AttachEntitiesToRope(
            Rope, pump, fuelNozzle,
            pumpCoords.x, pumpCoords.y, pumpCoords.z + pumpHeight,
            nozzlePos.x, nozzlePos.y, nozzlePos.z,
            8.0, false, false, nil, nil
        )
    end
    
    -- Monitor nozzle distance thread
    CreateThread(function()
        while holdingNozzle do
            local currentCoords = GetEntityCoords(ped)
            local dist = #(nozzlePosition - currentCoords)
            
            if dist > 7.5 then
                holdingNozzle = false
                
                if fuelNozzle and DoesEntityExist(fuelNozzle) then
                    DeleteObject(fuelNozzle)
                    fuelNozzle = nil
                end
                
                lib.notify({
                    title = 'Fuel System',
                    description = 'Nozzle cannot reach this far',
                    type = 'error'
                })
                
                if Config.PumpHose and Rope then
                    RopeUnloadTextures()
                    DeleteRope(Rope)
                    Rope = nil
                end
                
                if Config.FuelNozzleExplosion then
                    AddExplosion(nozzlePosition.x, nozzlePosition.y, nozzlePosition.z, 'EXP_TAG_PROPANE', 1.0, true, false, 5.0)
                end
            end
            
            Wait(2500)
        end
    end)
end)


-- Return nozzle event handler
RegisterNetEvent('cdn-fuel:client:returnNozzle', function()
    holdingNozzle = false
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "putbacknozzle", 0.4)
    Wait(250)
    
    if fuelNozzle and DoesEntityExist(fuelNozzle) then
        DeleteObject(fuelNozzle)
        fuelNozzle = nil
    end
    
    if Config.PumpHose and Rope then
        RopeUnloadTextures()
        DeleteRope(Rope)
        Rope = nil
    end
end)

-- Refuel menu event handler
RegisterNetEvent('cdn-fuel:client:refuelMenu', function()
    if not holdingNozzle then 
        lib.notify({
            title = 'Fuel System',
            description = 'You need to grab the nozzle first',
            type = 'error'
        })
        return 
    end
    
    local vehicle = Utils.GetClosestVehicle()
    
    -- Check if vehicle is electric
    local vehModel = GetEntityModel(vehicle)
    local vehName = string.lower(GetDisplayNameFromVehicleModel(vehModel))
    local isElectric = Config.ElectricVehicles[vehName] and Config.ElectricVehicles[vehName].isElectric
    
    if isElectric then
        lib.notify({
            title = 'Fuel System',
            description = 'This is an electric vehicle. Use an electric charger.',
            type = 'error'
        })
        return
    end
    
    local curFuel = Utils.GetFuel(vehicle)
    
    if curFuel >= 95 then
        lib.notify({
            title = 'Fuel System',
            description = 'Tank is already full',
            type = 'error'
        })
        return
    end
    
    local maxFuel = math.ceil(100 - curFuel)
    local fuelPrice = Config.PlayerOwnedGasStationsEnabled and StationFuelPrice or Config.CostMultiplier
    local totalCost = (maxFuel * fuelPrice) + SharedUtils.GlobalTax(maxFuel * fuelPrice)
    
    local input = lib.inputDialog('Gas Station', {
        {
            type = 'input',
            label = 'Fuel Price',
            default = '$' .. fuelPrice .. ' per liter',
            disabled = true
        },
        {
            type = 'input',
            label = 'Current Fuel',
            default = math.floor(curFuel) .. ' liters',
            disabled = true
        },
        {
            type = 'slider',
            label = 'Amount to Refuel',
            default = maxFuel,
            min = 1,
            max = maxFuel,
            step = 1
        },
        {
            type = 'select',
            label = 'Payment Method',
            options = {
                { value = 'cash', label = 'Cash' },
                { value = 'bank', label = 'Bank' }
            }
        }
    })
    
    if input then
        local amount = input[3]
        local paymentType = input[4]
        local finalCost = (amount * fuelPrice) + SharedUtils.GlobalTax(amount * fuelPrice)
        
        -- Confirm purchase
        local confirm = lib.alertDialog({
            header = 'Confirm Purchase',
            content = 'Purchase ' .. amount .. ' liters of fuel for $' .. math.ceil(finalCost) .. '?',
            centered = true,
            cancel = true
        })
        
        if confirm == 'confirm' then
            -- Check if player can afford
            local playerMoney = nil
            if paymentType == 'bank' then
                playerMoney = Core.Functions.GetPlayerData().money['bank']
            else
                playerMoney = Core.Functions.GetPlayerData().money['cash']
            end
            
            if playerMoney < finalCost then
                lib.notify({
                    title = 'Fuel System',
                    description = 'Not enough money',
                    type = 'error'
                })
                return
            end
            
            -- Start refueling process
            local success = lib.progressBar({
                duration = amount * Config.RefuelTime,
                label = 'Refueling Vehicle',
                useWhileDead = false,
                canCancel = true,
                disable = {
                    car = true,
                    move = true,
                    combat = true
                },
                anim = {
                    dict = Config.RefuelAnimationDictionary,
                    clip = Config.RefuelAnimation
                }
            })
            
            if success then
                -- Pay for fuel
                TriggerServerEvent('cdn-fuel:server:payForFuel', finalCost, paymentType, fuelPrice)
                
                -- Update vehicle fuel
                local newFuel = curFuel + amount
                if newFuel > 100 then newFuel = 100 end
                Utils.SetFuel(vehicle, newFuel)
                
                -- Update station reserves if player-owned
                if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel then
                    TriggerServerEvent('cdn-fuel:station:server:updateReserves', "remove", amount, ReserveLevels, CurrentLocation)
                    TriggerServerEvent('cdn-fuel:station:server:updateBalance', "add", amount, StationBalance, CurrentLocation, fuelPrice)
                end
                
                lib.notify({
                    title = 'Fuel System',
                    description = 'Vehicle refueled successfully',
                    type = 'success'
                })
            else
                lib.notify({
                    title = 'Fuel System',
                    description = 'Refueling cancelled',
                    type = 'error'
                })
            end
        end
    end
end)

-- Main fuel consumption thread
CreateThread(function()
    DecorRegister(Config.FuelDecor, 1)
    
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        
        if IsPedInAnyVehicle(ped) then
            local vehicle = GetVehiclePedIsIn(ped)
            
            if not Utils.IsVehicleBlacklisted(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped then
                HandleFuelConsumption(vehicle)
            end
        else
            if fuelSynced then fuelSynced = false end
            Wait(500)
        end
    end
end)

-- Initialize gas stations with ox_lib zones
CreateThread(function()
    for stationId, station in pairs(Config.GasStations) do
        -- Convert the polygon points to the format ox_lib expects
        local points = {}
        for i, point in ipairs(station.zones) do
            points[i] = vec3(point.x, point.y, (station.minz + station.maxz) / 2)
        end
        
        -- Create the polygon zone
        GasStationZones[stationId] = lib.zones.poly({
            points = points,
            thickness = station.maxz - station.minz,
            debug = Config.ZoneDebug,
            onEnter = function()
                inGasStation = true
                CurrentLocation = stationId
                
                if Config.PlayerOwnedGasStationsEnabled then
                    TriggerEvent('cdn-fuel:stations:updateLocation', stationId)
                end
            end,
            onExit = function()
                inGasStation = false
                
                if Config.PlayerOwnedGasStationsEnabled then
                    TriggerEvent('cdn-fuel:stations:updateLocation', nil)
                end
            end
        })
    end
end)

-- Setup target interactions
CreateThread(function()
    exports.ox_target:addModel(Config.FuelPumpModels, {
        {
            name = 'grab_fuel_nozzle',
            icon = 'fas fa-gas-pump',
            label = 'Grab Fuel Nozzle',
            distance = 2.0,
            canInteract = function()
                return not IsPedInAnyVehicle(PlayerPedId()) and not holdingNozzle and inGasStation
            end,
            onSelect = function()
                TriggerEvent('cdn-fuel:client:grabNozzle')
            end
        },
        {
            name = 'purchase_jerrycan',
            icon = 'fas fa-fire-flame-simple',
            label = 'Buy Jerry Can',
            distance = 2.0,
            canInteract = function()
                return not IsPedInAnyVehicle(PlayerPedId()) and not holdingNozzle and inGasStation
            end,
            onSelect = function()
                TriggerEvent('cdn-fuel:client:purchaseJerryCan')
            end
        },
        {
            name = 'return_nozzle',
            icon = 'fas fa-hand',
            label = 'Return Nozzle',
            distance = 2.0,
            canInteract = function()
                return holdingNozzle and not refueling
            end,
            onSelect = function()
                TriggerEvent('cdn-fuel:client:returnNozzle')
            end
        }
    })
    
    exports.ox_target:addGlobalVehicle({
        {
            name = 'refuel_vehicle',
            icon = 'fas fa-gas-pump',
            label = 'Refuel Vehicle',
            distance = 2.0,
            canInteract = function(entity)
                -- Get vehicle model name
                local vehModel = GetEntityModel(entity)
                local vehName = string.lower(GetDisplayNameFromVehicleModel(vehModel))
                
                -- First check if it's an electric vehicle
                local isElectric = Config.ElectricVehicles[vehName] and Config.ElectricVehicles[vehName].isElectric
                
                -- If it's electric, we should not be able to use regular fuel pumps
                if isElectric then
                    return false
                end
                
                -- Otherwise, proceed with normal checks
                return holdingNozzle and not refueling and inGasStation
            end,
            onSelect = function()
                TriggerEvent('cdn-fuel:client:refuelMenu')
            end
        }
    })
end)