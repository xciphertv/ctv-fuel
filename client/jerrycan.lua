local Core = exports[Config.CoreResource]:GetCoreObject()
local Utils = require('client.utils')
local SharedUtils = require('shared.utils')

-- Purchase jerry can
RegisterNetEvent('cdn-fuel:client:purchaseJerryCan', function()
    local price = Config.JerryCanPrice
    local tax = SharedUtils.GlobalTax(price)
    local finalPrice = math.ceil(price + tax)
    
    local confirm = lib.alertDialog({
        header = 'Purchase Jerry Can',
        content = 'Would you like to purchase a jerry can for $' .. finalPrice .. '?',
        centered = true,
        cancel = true
    })
    
    if confirm == 'confirm' then
        local input = lib.inputDialog('Payment Method', {
            {
                type = 'select',
                label = 'Select Payment Method',
                options = {
                    { value = 'cash', label = 'Cash' },
                    { value = 'bank', label = 'Bank' }
                }
            }
        })
        
        if input then
            TriggerServerEvent('cdn-fuel:server:purchaseJerryCan', input[1])
        end
    end
end)

-- Jerry can menu
RegisterNetEvent('cdn-fuel:client:jerryCanMenu', function(itemData)
    if IsPedInAnyVehicle(PlayerPedId(), false) then 
        lib.notify({
            title = 'Fuel System',
            description = 'You cannot refuel from inside a vehicle',
            type = 'error'
        })
        return 
    end
    
    local fuelAmount = Config.UseOxInventory and 
                      tonumber(itemData.metadata.fuel) or 
                      itemData.info.gasamount
    
    local options = {}
    
    -- Only show refuel vehicle option if jerry can has fuel
    if fuelAmount > 0 then
        table.insert(options, {
            title = 'Refuel Vehicle',
            description = 'Use jerry can to refuel a vehicle',
            icon = 'fas fa-gas-pump',
            onSelect = function()
                TriggerEvent('cdn-fuel:client:refuelWithJerryCan', itemData)
            end
        })
    else
        table.insert(options, {
            title = 'Jerry can is empty',
            description = 'Fill it at a gas station',
            icon = 'fas fa-gas-pump',
            disabled = true
        })
    end
    
    -- Only show refill jerry can option if in gas station
    if inGasStation then
        table.insert(options, {
            title = 'Refill Jerry Can',
            description = 'Fill up your jerry can',
            icon = 'fas fa-fill',
            onSelect = function()
                TriggerEvent('cdn-fuel:client:refillJerryCan', itemData)
            end,
            disabled = fuelAmount >= Config.JerryCanCap
        })
    end
    
    -- Show the menu
    lib.registerContext({
        id = 'jerry_can_menu',
        title = 'Jerry Can',
        options = options
    })
    
    lib.showContext('jerry_can_menu')
end)

-- Refuel vehicle with jerry can
RegisterNetEvent('cdn-fuel:client:refuelWithJerryCan', function(itemData)
    local vehicle = Utils.GetClosestVehicle()
    if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(vehicle)) > 2.5 then
        lib.notify({
            title = 'Fuel System',
            description = 'You are too far from the vehicle',
            type = 'error'
        })
        return
    end
    
    if Utils.IsVehicleBlacklisted(vehicle) then
        lib.notify({
            title = 'Fuel System',
            description = 'This vehicle cannot be refueled',
            type = 'error'
        })
        return
    end
    
    local curFuel = Utils.GetFuel(vehicle)
    if curFuel >= 95 then
        lib.notify({
            title = 'Fuel System',
            description = 'Vehicle is already full',
            type = 'error'
        })
        return
    end
    
    local jerryCanFuel = Config.UseOxInventory and 
                         tonumber(itemData.metadata.fuel) or 
                         itemData.info.gasamount
    
    local maxRefuel = math.min(jerryCanFuel, 100 - curFuel)
    
    local input = lib.inputDialog('Refuel with Jerry Can', {
        {
            type = 'slider',
            label = 'Amount to Refuel',
            default = maxRefuel,
            min = 1,
            max = maxRefuel,
            step = 1
        }
    })
    
    if input then
        local amount = input[1]
        
        -- Create jerry can prop
        local jerryCanProp = CreateObject(joaat('w_am_jerrycan'), 1.0, 1.0, 1.0, true, true, false)
        local leftHand = GetPedBoneIndex(PlayerPedId(), 18905)
        AttachEntityToEntity(jerryCanProp, PlayerPedId(), leftHand, 0.11, 0.0, 0.25, 15.0, 170.0, 90.42, 0, 1, 0, 1, 0, 1)
        
        -- Start refueling
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
                dict = Config.JerryCanAnimDict,
                clip = Config.JerryCanAnim
            }
        })
        
        DeleteObject(jerryCanProp)
        
        if success then
            -- Update fuel in vehicle
            Utils.SetFuel(vehicle, curFuel + amount)
            
            -- Update jerry can fuel level
            TriggerServerEvent('cdn-fuel:server:updateJerryCan', "remove", amount, itemData)
            
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
end)

-- Refill jerry can
RegisterNetEvent('cdn-fuel:client:refillJerryCan', function(itemData)
    if not inGasStation then return end
    
    local jerryCanFuel = Config.UseOxInventory and 
                         tonumber(itemData.metadata.fuel) or 
                         itemData.info.gasamount
    
    local maxRefill = Config.JerryCanCap - jerryCanFuel
    if maxRefill <= 0 then
        lib.notify({
            title = 'Fuel System',
            description = 'Jerry can is already full',
            type = 'error'
        })
        return
    end
    
    local fuelPrice = Config.PlayerOwnedGasStationsEnabled and StationFuelPrice or Config.CostMultiplier
    local totalCost = (maxRefill * fuelPrice) + SharedUtils.GlobalTax(maxRefill * fuelPrice)
    
    local input = lib.inputDialog('Refill Jerry Can', {
        {
            type = 'input',
            label = 'Fuel Price',
            default = '$' .. fuelPrice .. ' per liter',
            disabled = true
        },
        {
            type = 'slider',
            label = 'Amount to Refill',
            default = maxRefill,
            min = 1,
            max = maxRefill,
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
        local amount = input[2]
        local paymentType = input[3]
        local finalCost = (amount * fuelPrice) + SharedUtils.GlobalTax(amount * fuelPrice)
        
        -- Check if player can afford
        local playerMoney
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
        
        -- Create jerry can prop
        local jerryCanProp = CreateObject(joaat('w_am_jerrycan'), 1.0, 1.0, 1.0, true, true, false)
        local leftHand = GetPedBoneIndex(PlayerPedId(), 18905)
        AttachEntityToEntity(jerryCanProp, PlayerPedId(), leftHand, 0.11, 0.05, 0.27, -15.0, 170.0, -90.42, 0, 1, 0, 1, 0, 1)
        
        -- Start refilling
        local success = lib.progressBar({
            duration = amount * Config.RefuelTime,
            label = 'Refilling Jerry Can',
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = true,
                move = true,
                combat = true
            },
            anim = {
                dict = Config.JerryCanAnimDict,
                clip = Config.JerryCanAnim
            }
        })
        
        DeleteObject(jerryCanProp)
        
        if success then
            -- Pay for fuel
            TriggerServerEvent('cdn-fuel:server:payForFuel', finalCost, paymentType, fuelPrice)
            
            -- Update jerry can fuel level
            TriggerServerEvent('cdn-fuel:server:updateJerryCan', "add", amount, itemData)
            
            -- Update station reserves if player-owned
            if Config.PlayerOwnedGasStationsEnabled and not Config.UnlimitedFuel then
                TriggerServerEvent('cdn-fuel:station:server:updateReserves', "remove", amount, ReserveLevels, CurrentLocation)
                TriggerServerEvent('cdn-fuel:station:server:updateBalance', "add", amount, StationBalance, CurrentLocation, fuelPrice)
            end
            
            lib.notify({
                title = 'Fuel System',
                description = 'Jerry can refilled successfully',
                type = 'success'
            })
        else
            lib.notify({
                title = 'Fuel System',
                description = 'Refilling cancelled',
                type = 'error'
            })
        end
    end
end)