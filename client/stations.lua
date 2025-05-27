-- Imports and variables
local Utils = require 'client.utils'
local SharedUtils = require 'shared.utils'
local Core = exports[Config.CoreResource]:GetCoreObject()

-- Station variables
local StationPeds = {}
local CurrentLocation = nil
local StationFuelPrice = Config.CostMultiplier
local StationBalance = 0
local ReserveLevels = 0
local ReservesNotBuyable = false
local ReservePickupData = {}
local FuelDeliveryVehicle = nil
local FuelDeliveryTrailer = nil
local GasStationZones = {}

-- Update station information from server
local function UpdateStationInfo(location, infoType)
    if not Config.PlayerOwnedGasStationsEnabled or not location then
        -- Set default values for non-owned stations
        ReserveLevels = 1000
        StationFuelPrice = Config.CostMultiplier
        StationBalance = 0
        return
    end
    
    -- Always force a direct database lookup
    local stationData = lib.callback.await('cdn-fuel:server:fetchStationInfo', false, location, "all", true)
    
    if stationData then
        if Config.FuelDebug then
            print("Station data received for location #" .. location .. ":")
            print("  Fuel: " .. (stationData.fuel or "nil"))
            print("  Fuel Price: " .. (stationData.fuelPrice or "nil"))
            print("  Balance: " .. (stationData.balance or "nil"))
        end
        
        -- Update all variables regardless of infoType parameter
        ReserveLevels = stationData.fuel or 0
        ReservesNotBuyable = (ReserveLevels or 0) >= Config.MaxFuelReserves
        StationFuelPrice = stationData.fuelPrice or Config.CostMultiplier
        StationBalance = stationData.balance or 0
        
        if Config.UnlimitedFuel then
            ReservesNotBuyable = true
        end
    else
        -- Set default values if fetch failed
        ReserveLevels = 0
        StationFuelPrice = Config.CostMultiplier
        StationBalance = 0
        
        if Config.FuelDebug then
            print("Failed to fetch station information for location:", location)
        end
    end
end

-- Function to refresh station data and reopen the menu
local function refreshStationData(reopenMenu)
    -- Update all station data
    UpdateStationInfo(CurrentLocation)
    
    -- Reopen the management menu if requested
    if reopenMenu then
        Wait(100) -- Brief delay to ensure data is updated
        TriggerEvent('cdn-fuel:stations:manageMenu')
    end
end

-- Function to force refresh station data from database
local function forceRefreshStationData()
    if not CurrentLocation then return end
    
    -- Clear current values to show loading state
    StationFuelPrice = nil
    StationBalance = nil
    ReserveLevels = nil
    
    -- Force database lookup and update
    UpdateStationInfo(CurrentLocation, "all")
    
    -- Return current values after update
    return {
        fuelPrice = StationFuelPrice,
        balance = StationBalance,
        reserves = ReserveLevels
    }
end

-- Event to refresh station data
RegisterNetEvent('cdn-fuel:client:forceRefreshStationData', function()
    forceRefreshStationData()
end)

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
            ReserveLevels = stationData.fuel or 0
            ReservesNotBuyable = (ReserveLevels or 0) >= Config.MaxFuelReserves
            
            if Config.UnlimitedFuel then
                ReservesNotBuyable = true
            end
        end
        
        if infoType == "all" or infoType == "fuelprice" then
            StationFuelPrice = stationData.fuelPrice or Config.CostMultiplier
        end
        
        if infoType == "all" or infoType == "balance" then
            StationBalance = stationData.balance or 0
        end
    else
        -- Set default values if fetch failed
        ReserveLevels = 0
        StationFuelPrice = Config.CostMultiplier
        StationBalance = 0
        
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
        
        -- Wait for delivery or auto-completion
        Wait(1000)
        
        -- Refresh data and reopen menu if not using the delivery system
        if not Config.OwnersPickupFuel then
            refreshStationData(true)
        end
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
    TriggerClientEvent('cdn-fuel:client:forceRefreshStationData', src)
    
    lib.notify({
        title = 'Gas Station',
        description = 'Fuel price updated to $' .. newPrice,
        type = 'success'
    })
    
    -- Wait for server to process
    Wait(500)
    
    -- Refresh data and reopen menu
    refreshStationData(true)
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
    
    if (StationBalance or 0) <= 0 then
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
    
    -- Process withdrawal as cash item
    TriggerServerEvent('cdn-fuel:station:server:withdrawFunds', amount, CurrentLocation, StationBalance, true)
    TriggerClientEvent('cdn-fuel:client:forceRefreshStationData', src)

    
    -- Wait for server to process
    Wait(500)
    
    -- Refresh data and reopen menu
    refreshStationData(true)
end)

-- Deposit funds event
RegisterNetEvent('cdn-fuel:stations:depositFunds', function()
    if not IsPlayerStationOwner(CurrentLocation) then return end
    
    -- Update station info
    UpdateStationInfo(CurrentLocation, "balance")
    
    -- Check if player has cash item
    local cash = 0
    if Config.UseOxInventory then
        -- For ox_inventory
        local inventory = exports.ox_inventory:GetPlayerItems()
        for _, item in pairs(inventory) do
            if item.name == 'money' then
                cash = item.count
                break
            end
        end
    else
        -- For qb-inventory
        cash = Core.Functions.GetPlayerData().items.money or 0
    end
    
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
            label = 'Your Cash',
            default = '$' .. cash,
            disabled = true
        },
        {
            type = 'number',
            label = 'Amount to Deposit',
            min = 1,
            max = cash
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
    
    if amount > cash then
        lib.notify({
            title = 'Gas Station',
            description = 'Cannot deposit more than you have',
            type = 'error'
        })
        return
    end
    
    -- Process deposit as cash item
    TriggerServerEvent('cdn-fuel:station:server:depositFunds', amount, CurrentLocation, StationBalance, true)
    TriggerClientEvent('cdn-fuel:client:forceRefreshStationData', src)
    
    -- Wait for server to process
    Wait(500)
    
    -- Refresh data and reopen menu
    refreshStationData(true)
end)

-- Update station labels event
RegisterNetEvent('cdn-fuel:client:updateStationLabels', function(location, newLabel)
    if Config.FuelDebug then
        print("Updating station label for location #" .. location .. " to: " .. newLabel)
    end
    
    if Config.GasStations[location] then
        Config.GasStations[location].label = newLabel
        
        if Config.FuelDebug then
            print("Station label updated successfully")
        end
        
        -- If this is our current location, force a refresh
        if CurrentLocation == location then
            forceRefreshStationData()
        end
    else
        if Config.FuelDebug then
            print("Failed to update station label - location not found in config")
        end
    end
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
    
    local currentName = Config.GasStations[CurrentLocation] and Config.GasStations[CurrentLocation].label or "Unknown"
    
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
    
    -- Skip if name is unchanged
    if newName == currentName then
        lib.notify({
            title = 'Gas Station',
            description = 'The name is unchanged',
            type = 'info'
        })
        return
    end
    
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
    
    -- Update name
    TriggerServerEvent('cdn-fuel:station:server:updateLocationName', newName, CurrentLocation)
    
    -- Wait for server to process
    Wait(1000)
    
    -- Refresh data
    forceRefreshStationData()
    
    -- Reopen menu to show updated name
    Wait(200)
    TriggerEvent('cdn-fuel:stations:manageMenu')
end)

-- Sell station event
RegisterNetEvent('cdn-fuel:stations:sellStation', function()
    if not IsPlayerStationOwner(CurrentLocation) then 
        lib.notify({
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return 
    end
    
    -- Get the station cost and calculate sell price
    local stationCost = Config.GasStations[CurrentLocation] and Config.GasStations[CurrentLocation].cost or 0
    if stationCost <= 0 then
        if Config.FuelDebug then
            print("Error: Invalid station cost for location #" .. CurrentLocation)
        end
        
        lib.notify({
            title = 'Gas Station',
            description = 'Station pricing error',
            type = 'error'
        })
        return
    end
    
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
    
    if Config.FuelDebug then
        print("Attempting to sell station #" .. CurrentLocation .. " for $" .. sellPrice)
    end
    
    -- Process sale
    TriggerServerEvent('cdn-fuel:server:sellStation', CurrentLocation, sellPrice)
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
            end
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
            end
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
            end
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
    if not IsPlayerStationOwner(CurrentLocation) then
        lib.notify({
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Force data refresh from database
    local freshData = forceRefreshStationData()

    -- Update station info to get latest data
    UpdateStationInfo(CurrentLocation)
    
    -- Ensure variables have values to avoid nil concatenation
    local reserves = ReserveLevels or 0
    local price = StationFuelPrice or Config.CostMultiplier
    local balance = StationBalance or 0
    
    Wait(200)
    -- Create menu options
    local options = {
        {
            title = 'Fuel Reserves',
            description = tostring(ReserveLevels) .. ' / ' .. tostring(Config.MaxFuelReserves) .. ' liters',
            icon = 'fas fa-oil-can',
            disabled = Config.UnlimitedFuel,
        },
        {
            title = 'Purchase Fuel',
            description = 'Buy more fuel for your station',
            icon = 'fas fa-truck-loading',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:purchaseReserves', {location = CurrentLocation})
            end,
            disabled = ReservesNotBuyable or Config.UnlimitedFuel,
        }
    }
    
    -- Price management (if enabled)
    if Config.PlayerControlledFuelPrices then
        table.insert(options, {
            title = 'Change Fuel Price',
            description = 'Current price: $' .. tostring(price) .. ' per liter',
            icon = 'fas fa-tags',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:changeFuelPrice', {location = CurrentLocation})
            end
        })
    end
    
    -- Funds management
    table.insert(options, {
        title = 'Manage Funds',
        description = 'Current balance: $' .. tostring(balance),
        icon = 'fas fa-money-bill',
        onSelect = function()
            TriggerEvent('cdn-fuel:stations:manageFunds')
        end
    })
    
    -- Station name change (if enabled)
    local stationLabel = Config.GasStations[CurrentLocation] and Config.GasStations[CurrentLocation].label or "Unknown"
    if Config.GasStationNameChanges then
        table.insert(options, {
            title = 'Change Station Name',
            description = 'Current name: ' .. stationLabel,
            icon = 'fas fa-pencil-alt',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:changeName')
            end
        })
    end
    
    -- Sell station option
    local stationCost = Config.GasStations[CurrentLocation] and Config.GasStations[CurrentLocation].cost or 0
    local sellPrice = math.floor(SharedUtils.PercentOf(Config.GasStationSellPercentage, stationCost))
    table.insert(options, {
        title = 'Sell Station',
        description = 'Sell for $' .. tostring(sellPrice),
        icon = 'fas fa-dollar-sign',
        onSelect = function()
            TriggerEvent('cdn-fuel:stations:sellStation')
        end
    })
    
    -- Emergency shutoff option (if enabled)
    if Config.EmergencyShutOff then
        local shutOffState = lib.callback.await('cdn-fuel:server:checkShutoff', false, CurrentLocation)
        local shutoffText = shutOffState and "Currently disabled" or "Currently enabled"
        
        table.insert(options, {
            title = 'Emergency Shutoff',
            description = 'Pumps: ' .. shutoffText,
            icon = 'fas fa-power-off',
            onSelect = function()
                TriggerEvent('cdn-fuel:stations:toggleShutoff')
            end
        })
    end
    
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
                    -- If we're selling our station, wait briefly before clearing location
                    Wait(1000)
                    TriggerEvent('cdn-fuel:stations:updateLocation', nil)
                    CurrentLocation = nil
                end
            end
        })
    end
end)

-- Initialize air and water vehicle fueling zones
CreateThread(function()
    if not Config.AirAndWaterVehicleFueling or not Config.AirAndWaterVehicleFueling.enabled then
        return
    end
    
    -- Wait for airwater.lua to define the global functions
    Wait(1000)
    -- Make sure GasStationZones exists
    if not GasStationZones then
        GasStationZones = {}
    end
    
    for locationId, location in pairs(Config.AirAndWaterVehicleFueling.locations) do
        -- Create the polygon zone directly using the points from config
        GasStationZones['air_water_' .. locationId] = lib.zones.poly({
            points = location.zone.points,
            thickness = location.zone.thickness,
            debug = Config.ZoneDebug,
            onEnter = function()
                -- Handle entering fueling zone
                if location.draw_text then
                    lib.showTextUI(location.draw_text)
                end
                
                -- Spawn prop when entering zone
                exports[GetCurrentResourceName()]:SpawnAirWaterFuelingProp(locationId)
            end,
            onExit = function()
                -- Handle exiting fueling zone
                lib.hideTextUI()
                
                -- Check if we should despawn the prop
                CreateThread(function()
                    Wait(5000)
                    if not exports[GetCurrentResourceName()]:IsAnyPlayerNearAirWaterFueling(locationId) then
                        exports[GetCurrentResourceName()]:DespawnAirWaterFuelingProp(locationId)
                    end
                end)
            end,
            inside = function()
                -- Handle interactions inside the zone
                if IsControlJustPressed(0, Config.AirAndWaterVehicleFueling.refuel_button) then
                    -- Trigger refueling for air/water vehicle
                    TriggerEvent('cdn-fuel:client:airwater:startRefuel', locationId, location.type)
                end
            end
        })
    end
end)

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
    
    -- Process refueling
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
    
    -- Remove gas station zones - Fix this section
    for id, zone in pairs(GasStationZones) do
        if zone and zone.remove then
            zone:remove()
        end
    end
    
    -- The air/water zones are now handled in airwater.lua's cleanup function
end)