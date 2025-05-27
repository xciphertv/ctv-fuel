local Utils = require 'client.utils'
local SharedUtils = require 'shared.utils'
local Core = exports[Config.CoreResource]:GetCoreObject()

-- AirWater fueling zones and props
local AirWaterFuelingZones = {}
local AirWaterFuelingProps = {}

-- Function to spawn air/water refueling props
local function SpawnAirWaterFuelingProp(locationId)
    if not Config.AirAndWaterVehicleFueling or not Config.AirAndWaterVehicleFueling.enabled then
        return
    end
    
    local location = Config.AirAndWaterVehicleFueling.locations[locationId]
    if not location or not location.prop or AirWaterFuelingProps[locationId] then
        return
    end
    
    local propData = location.prop
    local modelHash = type(propData.model) == 'string' and joaat(propData.model) or propData.model
    
    RequestModel(modelHash)
    
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Wait(10)
        timeout = timeout + 1
    end
    
    if HasModelLoaded(modelHash) then
        local prop = CreateObject(
            modelHash,
            propData.coords.x, propData.coords.y, propData.coords.z,
            false, false, false
        )
        
        SetEntityHeading(prop, propData.coords.w)
        FreezeEntityPosition(prop, true)
        SetEntityAsMissionEntity(prop, true, true)
        
        AirWaterFuelingProps[locationId] = prop
        
        -- Debug output
        if Config.FuelDebug then
            print("Spawned air/water fueling prop for location #" .. locationId .. ", entity ID: " .. prop)
            print("Prop coordinates: " .. propData.coords.x .. ", " .. propData.coords.y .. ", " .. propData.coords.z)
        end
        
        -- Add target option - simplified for debugging
        if Config.AirAndWaterVehicleFueling.interaction_type == 'target' or Config.AirAndWaterVehicleFueling.interaction_type == 'both' then
            Wait(500) -- Wait for entity to fully spawn
            
            -- Use addLocalEntity with debug info
            if Config.FuelDebug then
                print("Adding target to prop for location #" .. locationId)
            end
            
            exports.ox_target:addLocalEntity(prop, {
                {
                    name = 'refuel_airwater_' .. locationId,
                    icon = 'fas fa-gas-pump',
                    label = 'Refuel ' .. (location.type == 'air' and 'Aircraft' or 'Boat'),
                    distance = 5.0, -- Increased for easier targeting
                    canInteract = function()
                        local ped = PlayerPedId()
                        local vehicle = GetVehiclePedIsIn(ped, false)
                        
                        -- Simplified check - any vehicle for debugging
                        return true
                    end,
                    onSelect = function()
                        TriggerEvent('cdn-fuel:client:airwater:startRefuel', locationId, location.type)
                    end
                }
            })
        end
        
        -- Remove model from memory
        SetModelAsNoLongerNeeded(modelHash)
        return prop
    else
        if Config.FuelDebug then
            print("Failed to load model for air/water fueling prop at location #" .. locationId)
        end
        return nil
    end
end

-- Function to despawn air/water refueling props
local function DespawnAirWaterFuelingProp(locationId)
    if not AirWaterFuelingProps[locationId] then
        return
    end
    
    -- Remove target option if it was added
    if Config.AirAndWaterVehicleFueling.interaction_type == 'target' or Config.AirAndWaterVehicleFueling.interaction_type == 'both' then
        exports.ox_target:removeLocalEntity(AirWaterFuelingProps[locationId])
    end
    
    if DoesEntityExist(AirWaterFuelingProps[locationId]) then
        DeleteEntity(AirWaterFuelingProps[locationId])
    end
    
    AirWaterFuelingProps[locationId] = nil
    
    if Config.FuelDebug then
        print("Despawned air/water fueling prop for location #" .. locationId)
    end
end

-- Function to check if any player is near air/water fueling location
local function IsAnyPlayerNearAirWaterFueling(locationId)
    local location = Config.AirAndWaterVehicleFueling.locations[locationId]
    if not location then return false end
    
    -- Use the first point as a reference
    local firstPoint = location.zone.points[1]
    
    local players = GetActivePlayers()
    
    for _, playerId in ipairs(players) do
        local playerPed = GetPlayerPed(playerId)
        local playerCoords = GetEntityCoords(playerPed)
        
        if #(playerCoords - firstPoint) < 50.0 then
            return true
        end
    end
    
    return false
end

-- Initialize air and water vehicle fueling zones
CreateThread(function()
    if not Config.AirAndWaterVehicleFueling or not Config.AirAndWaterVehicleFueling.enabled then
        return
    end
    
    Wait(2000) -- Wait for resources to load
    
    if Config.FuelDebug then
        print("Air/Water Fueling initialization - Interaction type: " .. Config.AirAndWaterVehicleFueling.interaction_type)
    end
    
    for locationId, location in pairs(Config.AirAndWaterVehicleFueling.locations) do
        -- Create the polygon zone using ox_lib
        AirWaterFuelingZones[locationId] = lib.zones.poly({
            points = location.zone.points,
            thickness = location.zone.thickness,
            debug = Config.ZoneDebug,
            onEnter = function()
                -- Spawn prop when entering the zone
                SpawnAirWaterFuelingProp(locationId)
                
                -- Show UI if TextUI is enabled - ONLY if set to textui or both
                if Config.AirAndWaterVehicleFueling.interaction_type == 'textui' or Config.AirAndWaterVehicleFueling.interaction_type == 'both' then
                    if location.draw_text then
                        if Config.FuelDebug then
                            print("Showing TextUI - Interaction type: " .. Config.AirAndWaterVehicleFueling.interaction_type)
                        end
                        lib.showTextUI(location.draw_text)
                    end
                else
                    if Config.FuelDebug then
                        print("TextUI disabled - Interaction type: " .. Config.AirAndWaterVehicleFueling.interaction_type)
                    end
                end
            end,
            onExit = function()
                -- Hide TextUI ONLY if it was shown (interaction_type is textui or both)
                if Config.AirAndWaterVehicleFueling.interaction_type == 'textui' or Config.AirAndWaterVehicleFueling.interaction_type == 'both' then
                    lib.hideTextUI()
                    if Config.FuelDebug then
                        print("Hiding TextUI - Interaction type: " .. Config.AirAndWaterVehicleFueling.interaction_type)
                    end
                end
                
                -- Don't despawn props immediately, check if other players are in the area
                CreateThread(function()
                    Wait(5000) -- Wait to make sure the player has definitely left
                    
                    -- Only despawn if no players are in the area
                    if not IsAnyPlayerNearAirWaterFueling(locationId) then
                        DespawnAirWaterFuelingProp(locationId)
                    end
                end)
            end,
            inside = function()
                -- Handle key press interaction if TextUI is enabled (textui or both)
                if (Config.AirAndWaterVehicleFueling.interaction_type == 'textui' or Config.AirAndWaterVehicleFueling.interaction_type == 'both') and IsControlJustPressed(0, Config.AirAndWaterVehicleFueling.refuel_button) then
                    -- Check if player is in the correct type of vehicle
                    local ped = PlayerPedId()
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    
                    if vehicle == 0 then
                        lib.notify({
                            title = 'Fuel System',
                            description = 'You must be in a ' .. (location.type == 'air' and 'aircraft' or 'boat'),
                            type = 'error'
                        })
                        return
                    end
                    
                    local vehicleClass = GetVehicleClass(vehicle)
                    local isCorrectType = (location.type == 'air' and (vehicleClass == 15 or vehicleClass == 16)) or
                                         (location.type == 'water' and vehicleClass == 14)
                    
                    if isCorrectType then
                        TriggerEvent('cdn-fuel:client:airwater:startRefuel', locationId, location.type)
                    else
                        lib.notify({
                            title = 'Fuel System',
                            description = 'This is not a ' .. (location.type == 'air' and 'aircraft' or 'boat'),
                            type = 'error'
                        })
                    end
                end
            end
        })
    end
end)

-- Make these functions global for other scripts to use
_G.SpawnAirWaterFuelingProp = SpawnAirWaterFuelingProp
_G.DespawnAirWaterFuelingProp = DespawnAirWaterFuelingProp
_G.IsAnyPlayerNearAirWaterFueling = IsAnyPlayerNearAirWaterFueling

-- Air/water vehicle refueling event
RegisterNetEvent('cdn-fuel:client:airwater:startRefuel', function(locationId, vehicleType)
    -- Get the current vehicle
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    if vehicle == 0 then
        lib.notify({
            title = 'Fuel System',
            description = 'You must be in a ' .. (vehicleType == 'air' and 'aircraft' or 'boat'),
            type = 'error'
        })
        return
    end
    
    -- Check if it's the correct type of vehicle
    local vehicleClass = GetVehicleClass(vehicle)
    local isCorrectType = (vehicleType == 'air' and (vehicleClass == 15 or vehicleClass == 16)) or
                          (vehicleType == 'water' and vehicleClass == 14)
    
    if not isCorrectType then
        lib.notify({
            title = 'Fuel System',
            description = 'This is not a ' .. (vehicleType == 'air' and 'aircraft' or 'boat'),
            type = 'error'
        })
        return
    end
    
    -- Get current fuel level
    local curFuel = Utils.GetFuel(vehicle)
    
    if curFuel >= 95 then
        lib.notify({
            title = 'Fuel System',
            description = 'The tank is already full',
            type = 'error'
        })
        return
    end
    
    -- Calculate refueling details
    local maxFuel = math.ceil(100 - curFuel)
    local fuelPrice = vehicleType == 'air' and Config.AirAndWaterVehicleFueling.air_fuel_price or Config.AirAndWaterVehicleFueling.water_fuel_price
    
    -- Show refueling menu
    local input = lib.inputDialog('Refuel ' .. (vehicleType == 'air' and 'Aircraft' or 'Boat'), {
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
    
    if not input then return end
    
    local amount = input[3]
    local paymentType = input[4]
    local finalCost = (amount * fuelPrice) + SharedUtils.GlobalTax(amount * fuelPrice)
    
    -- Process payment
    local success = lib.callback.await('cdn-fuel:server:payForFuel', false, finalCost, paymentType, fuelPrice)
    
    if success then
        -- Start refueling animation/progress bar
        lib.progressBar({
            duration = amount * Config.RefuelTime,
            label = 'Refueling ' .. (vehicleType == 'air' and 'Aircraft' or 'Boat'),
            useWhileDead = false,
            canCancel = true,
            disable = {
                car = true,
                move = true
            }
        })
        
        -- Update vehicle fuel
        local newFuel = curFuel + amount
        if newFuel > 100 then newFuel = 100 end
        Utils.SetFuel(vehicle, newFuel)
        
        lib.notify({
            title = 'Fuel System',
            description = 'Vehicle refueled successfully',
            type = 'success'
        })
    else
        lib.notify({
            title = 'Fuel System',
            description = 'Payment failed',
            type = 'error'
        })
    end
end)

-- Resource cleanup
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    
    -- Clean up air/water fueling zones
    for locationId, zone in pairs(AirWaterFuelingZones) do
        if zone and zone.remove then
            zone:remove()
        end
    end
    
    -- Clean up props
    for locationId, prop in pairs(AirWaterFuelingProps) do
        if DoesEntityExist(prop) then
            DeleteEntity(prop)
        end
    end
end)


-- Export functions for other files to use
exports('SpawnAirWaterFuelingProp', SpawnAirWaterFuelingProp)
exports('DespawnAirWaterFuelingProp', DespawnAirWaterFuelingProp)
exports('IsAnyPlayerNearAirWaterFueling', IsAnyPlayerNearAirWaterFueling)