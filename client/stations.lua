-- Imports and variables
local Utils = require 'client.utils'
local SharedUtils = require 'shared.utils'
local Core = exports[Config.CoreResource]:GetCoreObject()

-- Station variables
local StationPeds = {}
local CurrentLocation = nil
local StationFuelPrice = nil
local StationBalance = nil
local ReserveLevels = nil
local ReservesNotBuyable = false
local ReservePickupData = {}
local FuelDeliveryVehicle = nil
local FuelDeliveryTrailer = nil

-- Check if player owns the current station
local function IsPlayerStationOwner(location)
    if not Config.PlayerOwnedGasStationsEnabled or not location then
        return false
    end
    
    return lib.callback.await('cdn-fuel:server:isStationOwner', false, location)
end

-- Update station information from server
local function UpdateStationInfo(location, infoType)
    if not Config.PlayerOwnedGasStationsEnabled or not location then
        -- Set default values for non-owned stations
        ReserveLevels = 1000
        StationFuelPrice = Config.CostMultiplier
        StationBalance = 0
        return
    end
    
    local stationData = lib.callback.await('cdn-fuel:server:fetchStationInfo', false, location, infoType or "all")
    
    if stationData then
        if infoType == "all" or infoType == "reserves" then
            ReserveLevels = stationData.fuel
            ReservesNotBuyable = ReserveLevels >= Config.MaxFuelReserves
            
            if Config.UnlimitedFuel then
                ReservesNotBuyable = true
            end
        end
        
        if infoType == "all" or infoType == "fuelprice" then
            StationFuelPrice = stationData.fuelPrice
        end
        
        if infoType == "all" or infoType == "balance" then
            StationBalance = stationData.balance
        end
    else
        if Config.FuelDebug then
            print("Failed to fetch station information for location:", location)
        end
    end
end

-- Spawn station management peds
local function SpawnStationPeds()
    for locationId, station in pairs(Config.GasStations) do
        -- Load ped model
        local model = type(station.pedmodel) == 'string' and joaat(station.pedmodel) or station.pedmodel
        
        lib.requestModel(model)
        
        -- Create ped
        local ped = CreatePed(
            0, model,
            station.pedcoords.x, station.pedcoords.y, station.pedcoords.z, station.pedcoords.h,
            false, false
        )
        
        -- Set ped properties
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        
        -- Add to tracking table
        StationPeds[locationId] = ped
        
        -- Add interaction with ox_target
        exports.ox_target:addLocalEntity(ped, {
            {
                name = 'talk_to_station_attendant',
                icon = 'fas fa-building',
                label = 'Talk to Attendant',
                distance = 2.0,
                onSelect = function()
                    TriggerEvent('cdn-fuel:stations:openMenu', locationId)
                end
            }
        })
    end
end

-- Generate random delivery truck model
local function GetRandomDeliveryTruck()
    local truckModels = Config.PossibleDeliveryTrucks
    return truckModels[math.random(#truckModels)]
end

-- Spawn fuel delivery vehicles
local function SpawnDeliveryVehicles()
    -- Load models
    local trailerModel = joaat('tanker')
    local truckModel = joaat(GetRandomDeliveryTruck())
    
    lib.requestModel(trailerModel)
    lib.requestModel(truckModel)
    
    -- Create vehicles
    FuelDeliveryVehicle = CreateVehicle(
        truckModel,
        Config.DeliveryTruckSpawns.truck.x, Config.DeliveryTruckSpawns.truck.y, Config.DeliveryTruckSpawns.truck.z,
        Config.DeliveryTruckSpawns.truck.w,
        true, false
    )
    
    FuelDeliveryTrailer = CreateVehicle(
        trailerModel,
        Config.DeliveryTruckSpawns.trailer.x, Config.DeliveryTruckSpawns.trailer.y, Config.DeliveryTruckSpawns.trailer.z,
        Config.DeliveryTruckSpawns.trailer.w,
        true, false
    )
    
    -- Set as mission entities
    SetEntityAsMissionEntity(FuelDeliveryVehicle, true, true)
    SetEntityAsMissionEntity(FuelDeliveryTrailer, true, true)
    
    -- Attach trailer to truck
    AttachVehicleToTrailer(FuelDeliveryVehicle, FuelDeliveryTrailer, 15.0)
    
    -- Give vehicle keys to player
    TriggerEvent("vehiclekeys:client:SetOwner", Core.Functions.GetPlate(FuelDeliveryVehicle))
    
    return FuelDeliveryVehicle ~= 0 and FuelDeliveryTrailer ~= 0
end

-- Station location update event
RegisterNetEvent('cdn-fuel:stations:updateLocation', function(location)
    CurrentLocation = location
    
    if location then
        UpdateStationInfo(location)
    end
end)

-- Purchase fuel reserves event
RegisterNetEvent('cdn-fuel:stations:purchaseReserves', function(data)
    local location = data.location
    
    if not IsPlayerStationOwner(location) then
        lib.notify({
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Update station info
    UpdateStationInfo(location, "reserves")
    
    -- Check if station can accept more fuel
    if ReserveLevels >= Config.MaxFuelReserves then
        lib.notify({
            title = 'Gas Station',
            description = 'Station fuel reserves are full',
            type = 'error'
        })
        return
    end
    
    local maxPurchase = Config.MaxFuelReserves - ReserveLevels
    local reservesPrice = Config.FuelReservesPrice
    
    -- Input dialog for fuel purchase
    local input = lib.inputDialog('Purchase Fuel Reserves', {
        {
            type = 'input',
            label = 'Current Reserves',
            default = ReserveLevels .. ' / ' .. Config.MaxFuelReserves .. ' liters',
            disabled = true
        },
        {
            type = 'input',
            label = 'Price per Liter',
            default = '$' .. reservesPrice,
            disabled = true
        },
        {
            type = 'slider',
            label = 'Amount to Purchase',
            default = maxPurchase,
            min = 1,
            max = maxPurchase,
            step = 100
        }
    })
    
    if not input then return end
    
    local amount = input[3]
    local cost = amount * reservesPrice
    local tax = SharedUtils.GlobalTax(cost)
    local totalCost = cost + tax
    
    -- Confirm purchase
    local confirm = lib.alertDialog({
        header = 'Confirm Purchase',
        content = 'Purchase ' .. amount .. ' liters of fuel for $' .. math.ceil(totalCost) .. '?',
        centered = true,
        cancel = true
    })
    
    if confirm == 'confirm' then
        -- Check if player can afford
        if Core.Functions.GetPlayerData().money['bank'] < totalCost then
            lib.notify({
                title = 'Gas Station',
                description = 'Not enough money in bank',
                type = 'error'
            })
            return
        end
        
        -- Process purchase
        TriggerServerEvent('cdn-fuel:stations:server:buyReserves', location, amount)
    end
end)

-- Change fuel price event
RegisterNetEvent('cdn-fuel:stations:changeFuelPrice', function(data)
    local location = data.location
    
    if not IsPlayerStationOwner(location) then
        lib.notify({
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Update station info
    UpdateStationInfo(location, "fuelprice")
    
    -- Input dialog for price change
    local input = lib.inputDialog('Change Fuel Price', {
        {
            type = 'input',
            label = 'Current Price',
            default = '$' .. StationFuelPrice .. ' per liter',
            disabled = true
        },
        {
            type = 'number',
            label = 'New Price per Liter',
            default = StationFuelPrice,
            min = Config.MinimumFuelPrice,
            max = Config.MaxFuelPrice,
            step = 0.1
        }
    })
    
    if not input then return end
    
    local newPrice = input[2]
    
    -- Validate price
    if newPrice < Config.MinimumFuelPrice or newPrice > Config.MaxFuelPrice then
        lib.notify({
            title = 'Gas Station',
            description = 'Price must be between $' .. Config.MinimumFuelPrice .. ' and $' .. Config.MaxFuelPrice,
            type = 'error'
        })
        return
    end
    
    -- Update price
    TriggerServerEvent('cdn-fuel:station:server:updateFuelPrice', newPrice, location)
    
    lib.notify({
        title = 'Gas Station',
        description = 'Fuel price updated to $' .. newPrice,
        type = 'success'
    })
end)

-- Manage station funds event
RegisterNetEvent('cdn-fuel:stations:manageFunds', function()
    if not IsPlayerStationOwner(CurrentLocation) then
        lib.notify({
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Update station info
    UpdateStationInfo(CurrentLocation, "balance")
    
    -- Create management menu
    lib.registerContext({
        id = 'station_funds_menu',
        title = 'Station Funds Management',
        options = {
            {
                title = 'Current Balance',
                description = '$' .. StationBalance,
                icon = 'fas fa-money-bill',
                disabled = true
            },
            {
                title = 'Withdraw Funds',
                description = 'Transfer money from station to your bank',
                icon = 'fas fa-arrow-left',
                onSelect = function()
                    TriggerEvent('cdn-fuel:stations:withdrawFunds')
                end,
                disabled = StationBalance <= 0
            },
            {
                title = 'Deposit Funds',
                description = 'Transfer money from your bank to station',
                icon = 'fas fa-arrow-right',
                onSelect = function()
                    TriggerEvent('cdn-fuel:stations:depositFunds')
                end
            }
        }
    })
    
    lib.showContext('station_funds_menu')
end)

-- Withdraw funds event
RegisterNetEvent('cdn-fuel:stations:withdrawFunds', function()
    if not IsPlayerStationOwner(CurrentLocation) then return end
    
    -- Update station info
    UpdateStationInfo(CurrentLocation, "balance")
    
    if StationBalance <= 0 then
        lib.notify({
            title = 'Gas Station',
            description = 'No funds to withdraw',
            type = 'error'
        })
        return
    end
    
    -- Input dialog for withdrawal
    local input = lib.inputDialog('Withdraw Funds', {
        {
            type = 'input',
            label = 'Station Balance',
            default = '$' .. StationBalance,
            disabled = true
        },
        {
            type = 'number',
            label = 'Amount to Withdraw',
            default = StationBalance,
            min = 1,
            max = StationBalance
        }
    })
    
    if not input then return end
    
    local amount = input[2]
    
    -- Validate amount
    if amount <= 0 then
        lib.notify({
            title = 'Gas Station',
            description = 'Amount must be greater than 0',
            type = 'error'
        })
        return
    end
    
    if amount > StationBalance then
        lib.notify({
            title = 'Gas Station',
            description = 'Cannot withdraw more than the balance',
            type = 'error'
        })
        return
    end
    
    -- Process withdrawal
    TriggerServerEvent('cdn-fuel:station:server:withdrawFunds', amount, CurrentLocation, StationBalance)
end)

-- Deposit funds event
RegisterNetEvent('cdn-fuel:stations:depositFunds', function()
    if not IsPlayerStationOwner(CurrentLocation) then return end
    
    -- Update station info
    UpdateStationInfo(CurrentLocation, "balance")
    
    local playerBank = Core.Functions.GetPlayerData().money['bank']
    
    -- Input dialog for deposit
    local input = lib.inputDialog('Deposit Funds', {
        {
            type = 'input',
            label = 'Station Balance',
            default = '$' .. StationBalance,
            disabled = true
        },
        {
            type = 'input',
            label = 'Your Bank Balance',
            default = '$' .. playerBank,
            disabled = true
        },
        {
            type = 'number',
            label = 'Amount to Deposit',
            min = 1,
            max = playerBank
        }
    })
    
    if not input then return end
    
    local amount = input[3]
    
    -- Validate amount
    if amount <= 0 then
        lib.notify({
            title = 'Gas Station',
            description = 'Amount must be greater than 0',
            type = 'error'
        })
        return
    end
    
    if amount > playerBank then
        lib.notify({
            title = 'Gas Station',
            description = 'Cannot deposit more than you have',
            type = 'error'
        })
        return
    end
    
    -- Process deposit
    TriggerServerEvent('cdn-fuel:station:server:depositFunds', amount, CurrentLocation, StationBalance)
end)

-- Change station name event
RegisterNetEvent('cdn-fuel:stations:changeName', function()
    if not IsPlayerStationOwner(CurrentLocation) then return end
    
    if not Config.GasStationNameChanges then
        lib.notify({
            title = 'Gas Station',
            description = 'Name changes are disabled',
            type = 'error'
        })
        return
    end
    
    local currentName = Config.GasStations[CurrentLocation].label
    
    -- Input dialog for name change
    local input = lib.inputDialog('Change Station Name', {
        {
            type = 'input',
            label = 'Current Name',
            default = currentName,
            disabled = true
        },
        {
            type = 'input',
            label = 'New Name',
            placeholder = 'Enter new station name',
            min = Config.NameChangeMinChar,
            max = Config.NameChangeMaxChar
        }
    })
    
    if not input then return end
    
    local newName = input[2]
    
    -- Validate name
    if #newName < Config.NameChangeMinChar then
        lib.notify({
            title = 'Gas Station',
            description = 'Name too short (min ' .. Config.NameChangeMinChar .. ' characters)',
            type = 'error'
        })
        return
    end
    
    if #newName > Config.NameChangeMaxChar then
        lib.notify({
            title = 'Gas Station',
            description = 'Name too long (max ' .. Config.NameChangeMaxChar .. ' characters)',
            type = 'error'
        })
        return
    end
    
    -- Check for profanity
    for badWord, _ in pairs(Config.ProfanityList) do
        if string.find(string.lower(newName), string.lower(badWord)) then
            lib.notify({
                title = 'Gas Station',
                description = 'Inappropriate station name',
                type = 'error'
            })
            return
        end
    end
    
    -- Update name
    TriggerServerEvent('cdn-fuel:station:server:updateLocationName', newName, CurrentLocation)
end)

-- Sell station event
RegisterNetEvent('cdn-fuel:stations:sellStation', function()
    if not IsPlayerStationOwner(CurrentLocation) then return end
    
    local stationCost = Config.GasStations[CurrentLocation].cost
    local tax = SharedUtils.GlobalTax(stationCost)
    local totalValue = stationCost + tax
    local sellPrice = math.floor(SharedUtils.PercentOf(Config.GasStationSellPercentage, totalValue))
    
    -- Confirm dialog for selling
    local confirm = lib.alertDialog({
        header = 'Sell Gas Station',
        content = 'Are you sure you want to sell this station for $' .. sellPrice .. '? This action cannot be undone.',
        centered = true,
        cancel = true
    })
    
    if confirm ~= 'confirm' then return end
    
    -- Process sale
    TriggerServerEvent('cdn-fuel:server:sellStation', CurrentLocation)
end)

-- Toggle emergency shutoff event
RegisterNetEvent('cdn-fuel:stations:toggleShutoff', function()
    if not Config.EmergencyShutOff then return end
    
    TriggerServerEvent('cdn-fuel:stations:server:toggleShutoff', CurrentLocation)
    
    lib.notify({
        title = 'Gas Station',
        description = 'Emergency shutoff toggled',
        type = 'success'
    })
end)

-- Main station management menu
RegisterNetEvent('cdn-fuel:stations:openMenu', function(location)
    CurrentLocation = location
    
    -- Check if station is owned
    local isOwned = lib.callback.await('cdn-fuel:server:locationPurchased', false, location)
    local isOwner = IsPlayerStationOwner(location)
    local shutoffState = lib.callback.await('cdn-fuel:server:checkShutoff', false, location)
    
    -- Create menu options
    local options = {}
    
    -- Station information
    table.insert(options, {
        title = Config.GasStations[location].label,
        description = 'Gas Station Management',
        icon = 'fas fa-gas-pump',
        disabled = true
    })
    
    -- Owner management options
    if isOwner then
        -- Update station info
        UpdateStationInfo(location)
        
        -- Management option
        table.insert(options, {
            title = 'Manage Station',
            description = 'Access management options',
            icon = 'fas fa-cogs',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:manageMenu')
            }
        })
    end
    
    -- Purchase option (if not owned)
    if not isOwned then
        table.insert(options, {
            title = 'Purchase Station',
            description = 'Buy this gas station',
            icon = 'fas fa-shopping-cart',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:purchaseMenu', location)
            }
        })
    end
    
    -- Emergency shutoff option
    if Config.EmergencyShutOff then
        local shutoffText = shutoffState and "Pumps are currently disabled" or "Pumps are currently enabled"
        
        table.insert(options, {
            title = 'Emergency Shutoff',
            description = shutoffText,
            icon = 'fas fa-power-off',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:toggleShutoff')
            }
        })
    end
    
    -- Create and show menu
    lib.registerContext({
        id = 'gas_station_menu',
        title = 'Gas Station',
        options = options
    })
    
    lib.showContext('gas_station_menu')
end)

-- Station management menu
RegisterNetEvent('cdn-fuel:stations:manageMenu', function()
    if not IsPlayerStationOwner(CurrentLocation) then return end
    
    -- Update station info
    UpdateStationInfo(CurrentLocation)
    
    -- Create menu options
    local options = {
        {
            title = 'Fuel Reserves',
            description = ReserveLevels .. ' / ' .. Config.MaxFuelReserves .. ' liters',
            icon = 'fas fa-oil-can',
            disabled = true
        },
        {
            title = 'Purchase Fuel',
            description = 'Buy more fuel for your station',
            icon = 'fas fa-truck-loading',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:purchaseReserves', {location = CurrentLocation})
            },
            disabled = ReservesNotBuyable
        }
    }
    
    -- Price management (if enabled)
    if Config.PlayerControlledFuelPrices then
        table.insert(options, {
            title = 'Change Fuel Price',
            description = 'Current price: $' .. StationFuelPrice .. ' per liter',
            icon = 'fas fa-tags',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:changeFuelPrice', {location = CurrentLocation})
            }
        })
    end
    
    -- Funds management
    table.insert(options, {
        title = 'Manage Funds',
        description = 'Current balance: $' .. StationBalance,
        icon = 'fas fa-money-bill',
        onSelect = function()
            TriggerEvent('cdn-fuel:stations:manageFunds')
        }
    })
    
    -- Station name change (if enabled)
    if Config.GasStationNameChanges then
        table.insert(options, {
            title = 'Change Station Name',
            description = 'Current name: ' .. Config.GasStations[CurrentLocation].label,
            icon = 'fas fa-pencil-alt',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:changeName')
            }
        })
    end
    
    -- Sell station option
    table.insert(options, {
        title = 'Sell Station',
        description = 'Sell for $' .. math.floor(SharedUtils.PercentOf(Config.GasStationSellPercentage, Config.GasStations[CurrentLocation].cost)),
        icon = 'fas fa-dollar-sign',
        onSelect = function()
            TriggerEvent('cdn-fuel:stations:sellStation')
        }
    })
    
    -- Create and show menu
    lib.registerContext({
        id = 'station_management_menu',
        title = 'Station Management',
        options = options
    })
    
    lib.showContext('station_management_menu')
end)

-- Purchase station menu
RegisterNetEvent('cdn-fuel:stations:purchaseMenu', function(location)
    local stationCost = Config.GasStations[location].cost
    local tax = SharedUtils.GlobalTax(stationCost)
    local totalCost = stationCost + tax
    
    -- Check if player already owns a station (if limited to one)
    if Config.OneStationPerPerson then
        local ownsStation = lib.callback.await('cdn-fuel:server:doesPlayerOwnStation', false)
        
        if ownsStation then
            lib.notify({
                title = 'Gas Station',
                description = 'You already own a gas station',
                type = 'error'
            })
            return
        end
    end
    
    -- Check if player can afford
    if Core.Functions.GetPlayerData().money['bank'] < totalCost then
        lib.notify({
            title = 'Gas Station',
            description = 'Not enough money in bank',
            type = 'error'
        })
        return
    end
    
    -- Confirm purchase dialog
    local confirm = lib.alertDialog({
        header = 'Purchase Gas Station',
        content = 'Are you sure you want to purchase this station for $' .. totalCost .. '?',
        centered = true,
        cancel = true
    })
    
    if confirm == 'confirm' then
        TriggerServerEvent('cdn-fuel:server:buyStation', location, Core.Functions.GetPlayerData().citizenid)
    end
end)

-- Fuel pickup initiation event
RegisterNetEvent('cdn-fuel:station:client:initiateFuelPickup', function(amount, finalAmount, location)
    ReservePickupData = {
        amountBought = amount,
        finalAmount = finalAmount,
        location = location
    }
    
    -- Spawn delivery vehicles
    if SpawnDeliveryVehicles() then
        -- Set waypoint to pickup location
        SetNewWaypoint(Config.DeliveryTruckSpawns.truck.x, Config.DeliveryTruckSpawns.truck.y)
        
        -- Create blip for pickup
        ReservePickupData.blip = Utils.CreateBlip(
            vec3(Config.DeliveryTruckSpawns.truck.x, Config.DeliveryTruckSpawns.truck.y, Config.DeliveryTruckSpawns.truck.z),
            "Fuel Pickup",
            361,
            5
        )
        
        -- Create pickup zone
        ReservePickupData.zone = lib.zones.box({
            coords = vec3(
                Config.DeliveryTruckSpawns.PolyZone.coords[1].x,
                Config.DeliveryTruckSpawns.PolyZone.coords[1].y,
                (Config.DeliveryTruckSpawns.PolyZone.minz + Config.DeliveryTruckSpawns.PolyZone.maxz) / 2
            ),
            size = vec3(
                20.0, 20.0,
                Config.DeliveryTruckSpawns.PolyZone.maxz - Config.DeliveryTruckSpawns.PolyZone.minz
            ),
            rotation = 0,
            debug = Config.ZoneDebug,
            onEnter = function()
                -- Start pickup process
                lib.showTextUI('[E] Drop Off Truck')
                
                CreateThread(function()
                    while true do
                        Wait(0)
                        
                        if IsControlJustReleased(0, 38) then -- E key
                            -- Check if truck and trailer are still connected
                            local truckCoords = GetEntityCoords(FuelDeliveryVehicle)
                            local trailerCoords = GetEntityCoords(FuelDeliveryTrailer)
                            
                            if #(truckCoords - trailerCoords) > 10.0 then
                                lib.notify({
                                    title = 'Fuel Delivery',
                                    description = 'Trailer is not connected to the truck',
                                    type = 'error'
                                })
                            else
                                -- Complete delivery
                                lib.hideTextUI()
                                
                                -- Remove blip
                                if ReservePickupData.blip then
                                    RemoveBlip(ReservePickupData.blip)
                                    ReservePickupData.blip = nil
                                end
                                
                                -- Remove zone
                                ReservePickupData.zone:remove()
                                ReservePickupData.zone = nil
                                
                                -- Get player out of vehicle if needed
                                local ped = PlayerPedId()
                                if IsPedInVehicle(ped, FuelDeliveryVehicle, false) then
                                    TaskLeaveVehicle(ped, FuelDeliveryVehicle, 0)
                                    Wait(2000)
                                end
                                
                                -- Delete vehicles
                                DeleteEntity(FuelDeliveryVehicle)
                                DeleteEntity(FuelDeliveryTrailer)
                                FuelDeliveryVehicle = nil
                                FuelDeliveryTrailer = nil
                                
                                -- Complete delivery server-side
                                TriggerServerEvent('cdn-fuel:station:server:completeFuelPickup', ReservePickupData.location)
                                
                                -- Notify success
                                lib.notify({
                                    title = 'Fuel Delivery',
                                    description = 'Delivery completed successfully',
                                    type = 'success'
                                })
                                
                                -- Reset data
                                ReservePickupData = {}
                                break
                            end
                        end
                    end
                end)
            end,
            onExit = function()
                lib.hideTextUI()
            end
        })
        
        lib.notify({
            title = 'Fuel Delivery',
            description = 'Your fuel order is ready for pickup. Check your GPS.',
            type = 'success'
        })
    else
        -- Failed to spawn vehicles
        TriggerServerEvent('cdn-fuel:station:server:failedFuelPickup', location)
        
        lib.notify({
            title = 'Fuel Delivery',
            description = 'There was an issue with your delivery. The fuel has been delivered automatically.',
            type = 'info'
        })
    end
end)

-- Initialize station management
CreateThread(function()
    Wait(1000) -- Wait for core to initialize
    
    if Config.PlayerOwnedGasStationsEnabled then
        -- Spawn station management peds
        SpawnStationPeds()
        
        -- Request updated station labels
        TriggerServerEvent('cdn-fuel:server:updateLocationLabels')
    end
end)

-- Resource cleanup
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    
    -- Delete peds
    for _, ped in pairs(StationPeds) do
        DeleteEntity(ped)
    end
    
    -- Delete delivery vehicles
    if FuelDeliveryVehicle then DeleteEntity(FuelDeliveryVehicle) end
    if FuelDeliveryTrailer then DeleteEntity(FuelDeliveryTrailer) end
    
    -- Remove pickup zone
    if ReservePickupData.zone then
        ReservePickupData.zone:remove()
    end
    
    -- Remove blip
    if ReservePickupData.blip then
        RemoveBlip(ReservePickupData.blip)
    end
end)