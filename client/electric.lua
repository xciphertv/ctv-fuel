-- Imports and variables
local Utils = require 'client.utils'
local SharedUtils = require 'shared.utils'
local Core = exports[Config.CoreResource]:GetCoreObject()

-- Check if electric vehicle charging is enabled
if not Config.ElectricVehicleCharging then
    return
end

-- State management
local HoldingElectricNozzle = false
local ElectricChargerZones = {}
local ElectricNozzle = nil
local ElectricRope = nil

-- Helper functions
function IsHoldingElectricNozzle()
    return HoldingElectricNozzle
end
exports('IsHoldingElectricNozzle', IsHoldingElectricNozzle)

function SetElectricNozzle(state)
    if state == "putback" then
        TriggerServerEvent("InteractSound_SV:PlayOnSource", "putbackcharger", 0.4)
        Wait(250)
        
        if Config.FuelTargetExport then 
            exports[Config.TargetResource]:AllowRefuel(false, true) 
        end
        
        DeleteObject(ElectricNozzle)
        ElectricNozzle = nil
        HoldingElectricNozzle = false
        
        if Config.PumpHose and ElectricRope then
            RopeUnloadTextures()
            DeleteRope(ElectricRope)
            ElectricRope = nil
        end
    elseif state == "pickup" then
        TriggerEvent('cdn-fuel:client:grabElectricNozzle')
        HoldingElectricNozzle = true
    else
        if Config.FuelDebug then 
            print("State is not valid, it must be pickup or putback.") 
        end
    end
end
exports('SetElectricNozzle', SetElectricNozzle)

-- Grab electric nozzle event
RegisterNetEvent('cdn-fuel:client:grabElectricNozzle', function()
    local ped = PlayerPedId()
    
    if HoldingElectricNozzle then return end
    
    -- Animation for grabbing nozzle
    Utils.LoadAnimDict("anim@am_hold_up@male")
    TaskPlayAnim(ped, "anim@am_hold_up@male", "shoplift_high", 2.0, 8.0, -1, 50, 0, 0, 0, 0)
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "pickupnozzle", 0.4)
    Wait(300)
    StopAnimTask(ped, "anim@am_hold_up@male", "shoplift_high", 1.0)
    
    -- Create nozzle object
    ElectricNozzle = CreateObject(joaat('electric_nozzle'), 1.0, 1.0, 1.0, true, true, false)
    local leftHand = GetPedBoneIndex(ped, 18905)
    AttachEntityToEntity(ElectricNozzle, ped, leftHand, 0.24, 0.10, -0.052, -45.0, 120.0, 75.00, 0, 1, 0, 1, 0, 1)
    
    local nozzlePosition = GetEntityCoords(ped)
    HoldingElectricNozzle = true
    
    -- Create charging cable if enabled
    if Config.PumpHose then
        local pumpCoords, pump = Utils.GetClosestPump(nozzlePosition, true)
        
        if not pump or pump == 0 then
            if Config.FuelDebug then
                print("Failed to find an electric charger nearby")
            end
            return
        end
        
        -- Load rope textures
        RopeLoadTextures()
        while not RopeAreTexturesLoaded() do
            Wait(10)
        end
        
        -- Create rope
        ElectricRope = AddRope(
            pumpCoords.x, pumpCoords.y, pumpCoords.z,
            0.0, 0.0, 0.0,
            3.0, Config.RopeType['electric'], 1000.0,
            0.0, 1.0, false, false, false, 1.0, true
        )
        
        -- Position and attach rope
        ActivatePhysics(ElectricRope)
        Wait(100)
        
        local nozzlePos = GetEntityCoords(ElectricNozzle)
        nozzlePos = GetOffsetFromEntityInWorldCoords(ElectricNozzle, -0.005, 0.185, -0.05)
        
        AttachEntitiesToRope(
            ElectricRope, pump, ElectricNozzle,
            pumpCoords.x, pumpCoords.y, pumpCoords.z + 1.76,
            nozzlePos.x, nozzlePos.y, nozzlePos.z,
            5.0, false, false, nil, nil
        )
    end
    
    -- Monitor nozzle distance thread
    CreateThread(function()
        local TargetCreated = false
        
        while HoldingElectricNozzle do
            local currentCoords = GetEntityCoords(ped)
            local dist = #(nozzlePosition - currentCoords)
            
            if not TargetCreated and Config.FuelTargetExport then
                exports[Config.TargetResource]:AllowRefuel(true, true)
                TargetCreated = true
            end
            
            if dist > 7.5 then
                if TargetCreated and Config.FuelTargetExport then
                    exports[Config.TargetResource]:AllowRefuel(false, true)
                end
                
                HoldingElectricNozzle = false
                DeleteObject(ElectricNozzle)
                ElectricNozzle = nil
                
                lib.notify({
                    title = 'Electric Charger',
                    description = 'Nozzle cannot reach this far',
                    type = 'error'
                })
                
                if Config.PumpHose and ElectricRope then
                    RopeUnloadTextures()
                    DeleteRope(ElectricRope)
                    ElectricRope = nil
                end
            end
            
            Wait(2500)
        end
    end)
end)

-- Check if vehicle is electric
local function IsVehicleElectric(vehicle)
    if not vehicle or vehicle == 0 then return false end
    
    local vehModel = GetEntityModel(vehicle)
    local vehName = string.lower(GetDisplayNameFromVehicleModel(vehModel))
    
    return Config.ElectricVehicles[vehName] and Config.ElectricVehicles[vehName].isElectric
end

-- Electric charging menu event
RegisterNetEvent('cdn-fuel:client:electric:showMenu', function()
    if not HoldingElectricNozzle then
        lib.notify({
            title = 'Electric Charger',
            description = 'You need to grab the charging nozzle first',
            type = 'error'
        })
        return
    end
    
    local vehicle = Utils.GetClosestVehicle()
    
    if not vehicle or vehicle == 0 then
        lib.notify({
            title = 'Electric Charger',
            description = 'No vehicle found nearby',
            type = 'error'
        })
        return
    end
    
    if not IsVehicleElectric(vehicle) then
        lib.notify({
            title = 'Electric Charger',
            description = 'This vehicle is not electric',
            type = 'error'
        })
        return
    end
    
    if not Utils.IsPlayerNearVehicle() then
        lib.notify({
            title = 'Electric Charger',
            description = 'You are too far from the vehicle',
            type = 'error'
        })
        return
    end
    
    local curCharge = Utils.GetFuel(vehicle)
    
    if curCharge >= 95 then
        lib.notify({
            title = 'Electric Charger',
            description = 'Battery is already fully charged',
            type = 'error'
        })
        return
    end
    
    -- Show payment method selection
    lib.registerContext({
        id = 'electric_payment_menu',
        title = 'Electric Charging',
        options = {
            {
                title = 'Pay with Cash',
                description = 'Current Cash: $' .. Core.Functions.GetPlayerData().money['cash'],
                icon = 'fas fa-money-bill',
                onSelect = function()
                    TriggerEvent('cdn-fuel:client:electric:showChargingMenu', 'cash')
                end
            },
            {
                title = 'Pay with Bank',
                description = 'Use bank account for payment',
                icon = 'fas fa-credit-card',
                onSelect = function()
                    TriggerEvent('cdn-fuel:client:electric:showChargingMenu', 'bank')
                end
            }
        }
    })
    
    lib.showContext('electric_payment_menu')
end)

-- Electric charging input menu
RegisterNetEvent('cdn-fuel:client:electric:showChargingMenu', function(paymentType)
    local vehicle = Utils.GetClosestVehicle()
    local curCharge = Utils.GetFuel(vehicle)
    local maxCharge = math.ceil(100 - curCharge)
    
    -- Get charge price
    local chargePrice = Config.ElectricChargingPrice
    
    -- Apply emergency services discount if applicable
    if Config.EmergencyServicesDiscount.enabled then
        local plyJob = Core.Functions.GetPlayerData().job
        local isEligible = false
        
        if type(Config.EmergencyServicesDiscount.job) == "table" then
            for i = 1, #Config.EmergencyServicesDiscount.job do
                if plyJob.name == Config.EmergencyServicesDiscount.job[i] then
                    isEligible = true
                    break
                end
            end
        elseif plyJob.name == Config.EmergencyServicesDiscount.job then
            isEligible = true
        end
        
        if isEligible then
            if Config.EmergencyServicesDiscount.ondutyonly and not plyJob.onduty then
                lib.notify({
                    title = 'Electric Charger',
                    description = 'You need to be on duty for discount',
                    type = 'info'
                })
            else
                local discount = Config.EmergencyServicesDiscount.discount
                if discount > 0 then
                    if discount >= 100 then
                        chargePrice = 0
                    else
                        chargePrice = chargePrice * (1 - (discount / 100))
                    end
                end
            end
        end
    }
    
    -- Calculate total cost
    local totalCost = (maxCharge * chargePrice) + SharedUtils.GlobalTax(maxCharge * chargePrice)
    
    -- Display charging input dialog
    local input = lib.inputDialog('Electric Charger', {
        {
            type = 'input',
            label = 'Electricity Price',
            default = '$' .. chargePrice .. ' per kWh',
            disabled = true
        },
        {
            type = 'input',
            label = 'Current Charge',
            default = math.floor(curCharge) .. ' kWh',
            disabled = true
        },
        {
            type = 'slider',
            label = 'Amount to Charge',
            default = maxCharge,
            min = 1,
            max = maxCharge,
            step = 1
        }
    })
    
    if not input then return end
    
    local amount = input[3]
    local finalCost = (amount * chargePrice) + SharedUtils.GlobalTax(amount * chargePrice)
    
    -- Check if player can afford
    local playerMoney = nil
    if paymentType == 'bank' then
        playerMoney = Core.Functions.GetPlayerData().money['bank']
    else
        playerMoney = Core.Functions.GetPlayerData().money['cash']
    end
    
    if playerMoney < finalCost then
        lib.notify({
            title = 'Electric Charger',
            description = 'Not enough money',
            type = 'error'
        })
        return
    end
    
    -- Confirm purchase
    local confirm = lib.alertDialog({
        header = 'Confirm Charging',
        content = 'Charge ' .. amount .. ' kWh for $' .. math.ceil(finalCost) .. '?',
        centered = true,
        cancel = true
    })
    
    if confirm ~= 'confirm' then return end
    
    -- Start charging process
    Utils.LoadAnimDict(Config.RefuelAnimationDictionary)
    TaskPlayAnim(PlayerPedId(), Config.RefuelAnimationDictionary, Config.RefuelAnimation, 8.0, 1.0, -1, 1, 0, 0, 0, 0)
    
    -- Start charging sound
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "charging", 0.3)
    
    -- Charging progress bar
    local success = lib.progressBar({
        duration = amount * Config.RefuelTime,
        label = 'Charging Vehicle',
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })
    
    -- Stop animation and sound
    StopAnimTask(PlayerPedId(), Config.RefuelAnimationDictionary, Config.RefuelAnimation, 1.0)
    TriggerServerEvent("InteractSound_SV:PlayOnSource", "chargestop", 0.4)
    
    if success then
        -- Pay for charging
        TriggerServerEvent('cdn-fuel:server:electric:payForCharging', finalCost, paymentType, chargePrice)
        
        -- Update vehicle charge
        local newCharge = curCharge + amount
        if newCharge > 99.0 then newCharge = 100.0 end
        Utils.SetFuel(vehicle, newCharge)
        
        lib.notify({
            title = 'Electric Charger',
            description = 'Vehicle charged successfully',
            type = 'success'
        })
    else
        lib.notify({
            title = 'Electric Charger',
            description = 'Charging cancelled',
            type = 'error'
        })
    end
end)

-- Spawn electric chargers
CreateThread(function()
    if not Config.ElectricChargerModel then return end
    
    -- Load charger model
    lib.requestModel('electric_charger')
    
    if Config.FuelDebug then
        print("Electric Charger Model Loaded!")
    end
    
    -- Spawn chargers at gas stations
    for i = 1, #Config.GasStations do
        if Config.GasStations[i].electricchargercoords then
            local coords = Config.GasStations[i].electricchargercoords
            local heading = coords.w - 180
            
            Config.GasStations[i].electriccharger = CreateObject(
                'electric_charger',
                coords.x, coords.y, coords.z,
                false, true, true
            )
            
            if Config.FuelDebug then
                print("Created Electric Charger @ Location #" .. i)
            end
            
            SetEntityHeading(Config.GasStations[i].electriccharger, heading)
            FreezeEntityPosition(Config.GasStations[i].electriccharger, true)
        end
    end
end)

-- Setup ox_target interactions for electric chargers
CreateThread(function()
    exports.ox_target:addModel('electric_charger', {
        {
            name = 'grab_electric_nozzle',
            icon = 'fas fa-bolt',
            label = 'Grab Charging Nozzle',
            distance = 2.0,
            canInteract = function()
                return not HoldingElectricNozzle and not IsPedInAnyVehicle(PlayerPedId())
            end,
            onSelect = function()
                TriggerEvent('cdn-fuel:client:grabElectricNozzle')
            end
        },
        {
            name = 'return_electric_nozzle',
            icon = 'fas fa-hand',
            label = 'Return Charging Nozzle',
            distance = 2.0,
            canInteract = function()
                return HoldingElectricNozzle
            end,
            onSelect = function()
                SetElectricNozzle("putback")
            end
        }
    })
    
    -- Add vehicle target for electric charging
    exports.ox_target:addGlobalVehicle({
        {
            name = 'charge_electric_vehicle',
            icon = 'fas fa-bolt',
            label = 'Charge Vehicle',
            distance = 2.0,
            canInteract = function()
                local vehicle = Utils.GetClosestVehicle()
                return HoldingElectricNozzle and 
                       IsVehicleElectric(vehicle) and
                       Utils.IsPlayerNearVehicle()
            end,
            onSelect = function()
                TriggerEvent('cdn-fuel:client:electric:showMenu')
            end
        }
    })
end)

-- Resource cleanup
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    
    -- Remove electric chargers
    for i = 1, #Config.GasStations do
        if Config.GasStations[i].electriccharger then
            DeleteEntity(Config.GasStations[i].electriccharger)
        end
    end
    
    -- Remove electric nozzle
    if HoldingElectricNozzle and ElectricNozzle then
        DeleteEntity(ElectricNozzle)
    end
    
    -- Clean up rope
    if ElectricRope then
        RopeUnloadTextures()
        DeleteRope(ElectricRope)
    end
end)