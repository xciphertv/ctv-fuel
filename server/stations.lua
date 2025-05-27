local Core = exports[Config.CoreResource]:GetCoreObject()
local SharedUtils = require('shared.utils')
local FuelPickupData = {} -- Tracks fuel pickups in progress

-- Initialize stations
local function InitializeStations()
    if not Config.PlayerOwnedGasStationsEnabled then return end
    
    MySQL.Async.execute([[
        CREATE TABLE IF NOT EXISTS `fuel_stations` (
            `location` int(11) NOT NULL,
            `owned` int(11) DEFAULT 0,
            `owner` varchar(50) DEFAULT '0',
            `fuel` int(11) DEFAULT 100000,
            `fuelprice` float DEFAULT 3.0,
            `balance` int(255) DEFAULT 0,
            `label` varchar(255) DEFAULT NULL,
            PRIMARY KEY (`location`)
        )
    ]], {})
    
    -- Check for existing records
    MySQL.Async.fetchAll('SELECT location FROM fuel_stations', {}, function(result)
        if not result or #result == 0 then
            -- Initialize all gas stations in the database
            for i = 1, #Config.GasStations do
                MySQL.Async.execute([[
                    INSERT INTO fuel_stations (location, owned, owner, fuel, fuelprice, balance, label)
                    VALUES (?, 0, '0', 100000, 3, 0, ?)
                ]], {i, Config.GasStations[i].label})
            end
            
            print("CDN-Fuel: Initialized all gas stations in the database")
        end
    end)
end

-- Fetch station information callback
lib.callback.register('cdn-fuel:server:fetchStationInfo', function(source, location, infoType, forceFresh)
    if not Config.PlayerOwnedGasStationsEnabled or not location then
        return nil
    end
    
    -- Always use Sync when we need fresh data
    local queryFunction = forceFresh and MySQL.Sync.fetchAll or MySQL.Async.fetchAll
    local result = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE location = ?', {location})
    
    if not result or #result == 0 then
        print("No station data found for location #" .. location)
        return nil
    end
    
    local stationData = result[1]
    local returnData = {
        fuel = stationData.fuel,
        fuelPrice = stationData.fuelprice,
        balance = stationData.balance,
        owner = stationData.owner,
        owned = stationData.owned
    }
    
    if Config.FuelDebug then
        print("Fetched station data for location #" .. location .. ":")
        print("  Fuel: " .. (returnData.fuel or "nil"))
        print("  Fuel Price: " .. (returnData.fuelPrice or "nil"))
        print("  Balance: " .. (returnData.balance or "nil"))
    end
    
    return returnData
end)

-- Check if station is purchased
lib.callback.register('cdn-fuel:server:locationPurchased', function(source, location)
    if not location then
        return false
    end
    
    local result = MySQL.Sync.fetchAll('SELECT owned FROM fuel_stations WHERE location = ?', {location})
    
    if not result or #result == 0 then
        return false
    end
    
    return result[1].owned == 1
end)

-- Check if player is station owner
lib.callback.register('cdn-fuel:server:isStationOwner', function(source, location)
    local Player = Core.Functions.GetPlayer(source)
    
    if not Player or not location then
        return false
    end
    
    local citizenId = Player.PlayerData.citizenid
    local result = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE location = ? AND owner = ? AND owned = 1', 
                                      {location, citizenId})
    
    return result and #result > 0
end)

-- Check if player owns any station
lib.callback.register('cdn-fuel:server:doesPlayerOwnStation', function(source)
    local Player = Core.Functions.GetPlayer(source)
    
    if not Player then
        return false
    end
    
    local citizenId = Player.PlayerData.citizenid
    local result = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE owner = ? AND owned = 1', {citizenId})
    
    return result and #result > 0
end)

-- Check station shutoff status
lib.callback.register('cdn-fuel:server:checkShutoff', function(source, location)
    if not location or not Config.EmergencyShutOff then
        return false
    end
    
    return Config.GasStations[location].shutoff or false
end)

-- Buy station event
-- Buy station event
RegisterNetEvent('cdn-fuel:server:buyStation', function(location, citizenId)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player or not location then
        return
    end
    
    -- Check if station is already owned - direct DB query
    local isOwnedResult = MySQL.Sync.fetchAll('SELECT owned FROM fuel_stations WHERE location = ?', {location})
    local isOwned = isOwnedResult and #isOwnedResult > 0 and isOwnedResult[1].owned == 1
    
    if isOwned then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'This station is already owned',
            type = 'error'
        })
        return
    end
    
    -- Check if player already owns a station (if limited to one)
    if Config.OneStationPerPerson then
        local ownsStationResult = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE owner = ? AND owned = 1', {citizenId})
        local ownsStation = ownsStationResult and #ownsStationResult > 0
        
        if ownsStation then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Gas Station',
                description = 'You already own a gas station',
                type = 'error'
            })
            return
        end
    end
    
    -- Calculate price
    local stationCost = Config.GasStations[location].cost
    local tax = SharedUtils.GlobalTax(stationCost)
    local totalCost = stationCost + tax
    
    -- Check if player can afford
    if Player.PlayerData.money['bank'] < totalCost then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Not enough money in bank',
            type = 'error'
        })
        return
    end
    
    -- Process purchase
    Player.Functions.RemoveMoney('bank', totalCost, 'Gas Station Purchase')
    
    MySQL.Async.execute('UPDATE fuel_stations SET owned = 1, owner = ? WHERE location = ?', {citizenId, location})
    
    if Config.FuelDebug then
        print("Player " .. Player.PlayerData.citizenid .. " purchased gas station at location " .. location)
    end
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Gas Station',
        description = 'You now own this gas station',
        type = 'success'
    })
    
    -- Update station labels for all players
    TriggerClientEvent('cdn-fuel:client:updateStationLabels', -1, location, Config.GasStations[location].label)
end)

-- Sell station event
RegisterNetEvent('cdn-fuel:server:sellStation', function(location, sellPrice)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player or not location then
        print("Error: Invalid player or location data for station sale")
        return
    end
    
    if not sellPrice or sellPrice <= 0 then
        print("Error: Invalid sell price for station sale")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Invalid sell price',
            type = 'error'
        })
        return
    end
    
    -- Directly check ownership from database
    local result = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE location = ? AND owner = ? AND owned = 1', 
                                  {location, Player.PlayerData.citizenid})
    
    if not result or #result == 0 then
        print("Error: Player is not the owner of this station")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Begin transaction to sell the station
    print("Processing sale of station #" .. location .. " for $" .. sellPrice .. " by " .. Player.PlayerData.citizenid)
    
    -- First, update the station record
    MySQL.Async.execute('UPDATE fuel_stations SET owned = 0, owner = ?, balance = 0, fuelprice = ? WHERE location = ?', 
                      {'0', Config.CostMultiplier, location},
        function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                print("Successfully reset station #" .. location .. " (Rows changed: " .. rowsChanged .. ")")
                
                -- Add money to player as cash item
                local success = false
                
                if Config.UseOxInventory then
                    -- For ox_inventory
                    success = exports.ox_inventory:AddItem(src, 'money', sellPrice)
                else
                    -- For qb-inventory
                    success = Player.Functions.AddItem('money', sellPrice)
                    if success then
                        TriggerClientEvent('inventory:client:ItemBox', src, Core.Shared.Items['money'], "add")
                    end
                end
                
                if success then
                    print("Successfully paid $" .. sellPrice .. " to " .. Player.PlayerData.citizenid .. " for station sale")
                    
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Gas Station',
                        description = 'You sold the gas station for $' .. sellPrice,
                        type = 'success'
                    })
                    
                    -- Reset the station label to default if needed
                    local defaultLabel = "Gas Station " .. location
                    if Config.GasStations[location] and Config.GasStations[location].originalLabel then
                        defaultLabel = Config.GasStations[location].originalLabel
                    end
                    
                    -- Update station labels for all players
                    TriggerClientEvent('cdn-fuel:client:updateStationLabels', -1, location, defaultLabel)
                else
                    print("Error: Failed to add money to player for station sale - inventory might be full!")
                    
                    -- Try to revert the station ownership
                    MySQL.Async.execute('UPDATE fuel_stations SET owned = 1, owner = ? WHERE location = ?', 
                                      {Player.PlayerData.citizenid, location})
                    
                    TriggerClientEvent('ox_lib:notify', src, {
                        title = 'Gas Station',
                        description = 'Sale failed - inventory might be full',
                        type = 'error'
                    })
                end
            else
                print("Failed to reset station #" .. location .. " (No rows changed)")
                
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Failed to sell gas station',
                    type = 'error'
                })
            end
        end
    )
end)

-- Toggle station shutoff
RegisterNetEvent('cdn-fuel:stations:server:toggleShutoff', function(location)
    local src = source
    
    if not location or not Config.EmergencyShutOff then
        return
    end
    
    -- Toggle shutoff state
    Config.GasStations[location].shutoff = not Config.GasStations[location].shutoff
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Gas Station',
        description = 'Emergency shutoff toggled',
        type = 'success'
    })
end)

-- Update fuel reserves
RegisterNetEvent('cdn-fuel:station:server:updateReserves', function(operation, amount, currentLevel, location)
    if not Config.PlayerOwnedGasStationsEnabled or not location then
        return
    end
    
    local newLevel
    
    if operation == "remove" then
        newLevel = math.max(currentLevel - amount, 0)
    elseif operation == "add" then
        newLevel = math.min(currentLevel + amount, Config.MaxFuelReserves)
    else
        return
    end
    
    MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE location = ?', {newLevel, location})
    
    if Config.FuelDebug then
        print("Updated fuel reserves for location #" .. location .. " to " .. newLevel)
    end
end)

-- Update station balance
RegisterNetEvent('cdn-fuel:station:server:updateBalance', function(operation, amount, currentBalance, location, fuelPrice)
    if not Config.PlayerOwnedGasStationsEnabled or not location then
        return
    end
    
    local revenue = amount * fuelPrice * Config.StationFuelSalePercentage
    local newBalance
    
    if operation == "remove" then
        newBalance = math.max(currentBalance - revenue, 0)
    elseif operation == "add" then
        newBalance = currentBalance + revenue
    else
        return
    end
    
    MySQL.Async.execute('UPDATE fuel_stations SET balance = ? WHERE location = ?', {newBalance, location})
    
    if Config.FuelDebug then
        print("Updated balance for location #" .. location .. " to $" .. newBalance)
    end
end)

-- Buy fuel reserves
RegisterNetEvent('cdn-fuel:stations:server:buyReserves', function(location, amount)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player or not location then
        return
    end
    
    -- Check if player owns the station
    local isOwner = lib.callback.await('cdn-fuel:server:isStationOwner', src, location)
    
    if not isOwner then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Get current reserves
    local stationData = lib.callback.await('cdn-fuel:server:fetchStationInfo', src, location, "reserves")
    
    if not stationData then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Failed to fetch station data',
            type = 'error'
        })
        return
    end
    
    local currentFuel = stationData.fuel
    
    -- Check if station can hold more fuel
    if currentFuel + amount > Config.MaxFuelReserves then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Station cannot hold that much fuel',
            type = 'error'
        })
        return
    end
    
    -- Calculate cost
    local cost = amount * Config.FuelReservesPrice
    local tax = SharedUtils.GlobalTax(cost)
    local totalCost = cost + tax
    
    -- Check if player can afford
    if Player.PlayerData.money['bank'] < totalCost then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Not enough money in bank',
            type = 'error'
        })
        return
    end
    
    -- Process purchase
    Player.Functions.RemoveMoney('bank', totalCost, 'Fuel Reserves Purchase')
    
    if Config.OwnersPickupFuel then
        -- Register pickup data
        FuelPickupData[location] = {
            src = src,
            amount = amount,
            finalAmount = currentFuel + amount
        }
        
        -- Initiate pickup process
        TriggerClientEvent('cdn-fuel:station:client:initiateFuelPickup', src, amount, currentFuel + amount, location)
    else
        -- Directly add fuel to station
        MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE location = ?', {currentFuel + amount, location})
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Purchased ' .. amount .. ' liters of fuel',
            type = 'success'
        })
    end
end)

-- Complete fuel pickup
RegisterNetEvent('cdn-fuel:station:server:completeFuelPickup', function(location)
    local src = source
    
    if not location or not FuelPickupData[location] then
        return
    end
    
    -- Update station fuel level
    MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE location = ?', 
                       {FuelPickupData[location].finalAmount, location})
    
    -- Notify player
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Fuel Delivery',
        description = 'Fuel delivery completed',
        type = 'success'
    })
    
    -- Clear pickup data
    FuelPickupData[location] = nil
end)

-- Failed fuel pickup
RegisterNetEvent('cdn-fuel:station:server:failedFuelPickup', function(location)
    local src = source
    
    if not location or not FuelPickupData[location] then
        return
    end
    
    -- Update station fuel level (auto-delivery fallback)
    MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE location = ?', 
                       {FuelPickupData[location].finalAmount, location})
    
    -- Notify player
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Fuel Delivery',
        description = 'Fuel delivered automatically',
        type = 'info'
    })
    
    -- Clear pickup data
    FuelPickupData[location] = nil
end)

-- Update fuel price
RegisterNetEvent('cdn-fuel:station:server:updateFuelPrice', function(newPrice, location)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player or not location then
        print("Error: Invalid player or location data")
        return
    end
    
    -- Directly check ownership from database
    local result = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE location = ? AND owner = ? AND owned = 1', 
                                  {location, Player.PlayerData.citizenid})
    
    if not result or #result == 0 then
        print("Error: Player is not the owner of this station")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Validate price
    if newPrice < Config.MinimumFuelPrice or newPrice > Config.MaxFuelPrice then
        print("Error: Invalid price range")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Invalid price range',
            type = 'error'
        })
        return
    end
    
    -- Update price with logging
    print("Attempting to update fuel price for location #" .. location .. " to $" .. newPrice)
    
    MySQL.Async.execute('UPDATE fuel_stations SET fuelprice = ? WHERE location = ?', {newPrice, location}, 
        function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                print("Successfully updated fuel price for location #" .. location .. " to $" .. newPrice .. " (Rows changed: " .. rowsChanged .. ")")
                
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Fuel price updated to $' .. newPrice,
                    type = 'success'
                })
            else
                print("Failed to update fuel price for location #" .. location .. " (No rows changed)")
                
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Failed to update fuel price',
                    type = 'error'
                })
            end
        end
    )
end)

-- Station fund management - withdraw
RegisterNetEvent('cdn-fuel:station:server:withdrawFunds', function(amount, location, currentBalance, useCashItem)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player or not location then
        return
    end
    
    -- Check if player owns the station
    local isOwner = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE location = ? AND owner = ? AND owned = 1', 
                                  {location, Player.PlayerData.citizenid})
    
    if not isOwner or #isOwner == 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Get current balance from database to ensure accuracy
    local stationData = MySQL.Sync.fetchAll('SELECT balance FROM fuel_stations WHERE location = ?', {location})
    local actualBalance = stationData[1].balance
    
    if amount <= 0 or amount > actualBalance then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Invalid amount or insufficient station funds',
            type = 'error'
        })
        return
    end
    
    -- Update balance in database
    MySQL.Async.execute('UPDATE fuel_stations SET balance = balance - ? WHERE location = ?', {amount, location}, 
        function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                -- Add money as cash item to player
                if useCashItem then
                    if Config.UseOxInventory then
                        -- For ox_inventory
                        local success = exports.ox_inventory:AddItem(src, 'money', amount)
                        if not success then
                            -- Revert the database change if inventory is full
                            MySQL.Async.execute('UPDATE fuel_stations SET balance = balance + ? WHERE location = ?', {amount, location})
                            
                            TriggerClientEvent('ox_lib:notify', src, {
                                title = 'Gas Station',
                                description = 'Inventory is full - cannot withdraw cash',
                                type = 'error'
                            })
                            return
                        end
                    else
                        -- For qb-inventory
                        Player.Functions.AddItem('money', amount)
                        TriggerClientEvent('inventory:client:ItemBox', src, Core.Shared.Items['money'], "add")
                    end
                else
                    -- Legacy method - add to bank
                    Player.Functions.AddMoney('bank', amount, 'Gas Station Withdrawal')
                end
                
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Withdrew $' .. amount,
                    type = 'success'
                })
                
                -- Trigger refresh for client
                TriggerClientEvent('cdn-fuel:client:forceRefreshStationData', src)
                
                if Config.FuelDebug then
                    print("Player " .. Player.PlayerData.citizenid .. " withdrew $" .. amount .. " from station #" .. location)
                end
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Failed to withdraw funds',
                    type = 'error'
                })
            end
        end
    )
end)

-- Station fund management - deposit
RegisterNetEvent('cdn-fuel:station:server:depositFunds', function(amount, location, currentBalance, useCashItem)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player or not location then
        return
    end
    
    -- Check if player owns the station
    local isOwner = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE location = ? AND owner = ? AND owned = 1', 
                                  {location, Player.PlayerData.citizenid})
    
    if not isOwner or #isOwner == 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Validate amount
    if amount <= 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Invalid deposit amount',
            type = 'error'
        })
        return
    end
    
    local success = false
    
    -- Remove cash from player
    if useCashItem then
        if Config.UseOxInventory then
            -- For ox_inventory
            success = exports.ox_inventory:RemoveItem(src, 'money', amount)
        else
            -- For qb-inventory
            success = Player.Functions.RemoveItem('money', amount)
            if success then
                TriggerClientEvent('inventory:client:ItemBox', src, Core.Shared.Items['money'], "remove")
            end
        end
    else
        -- Legacy method - remove from bank
        success = Player.Functions.RemoveMoney('bank', amount, 'Gas Station Deposit')
    end
    
    if not success then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Insufficient funds',
            type = 'error'
        })
        return
    end
    
    -- Update balance in database
    MySQL.Async.execute('UPDATE fuel_stations SET balance = balance + ? WHERE location = ?', {amount, location}, 
        function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Deposited $' .. amount,
                    type = 'success'
                })
                
                -- Trigger refresh for client
                TriggerClientEvent('cdn-fuel:client:forceRefreshStationData', src)
                
                if Config.FuelDebug then
                    print("Player " .. Player.PlayerData.citizenid .. " deposited $" .. amount .. " to station #" .. location)
                end
            else
                -- Refund money if database update failed
                if useCashItem then
                    if Config.UseOxInventory then
                        exports.ox_inventory:AddItem(src, 'money', amount)
                    else
                        Player.Functions.AddItem('money', amount)
                        TriggerClientEvent('inventory:client:ItemBox', src, Core.Shared.Items['money'], "add")
                    end
                else
                    Player.Functions.AddMoney('bank', amount, 'Gas Station Deposit Refund')
                end
                
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Failed to deposit funds',
                    type = 'error'
                })
            end
        end
    )
end)

-- Update station name
RegisterNetEvent('cdn-fuel:station:server:updateLocationName', function(newName, location)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player or not location then
        print("Error: Invalid player or location data for name change")
        return
    end
    
    -- Directly check ownership from database
    local result = MySQL.Sync.fetchAll('SELECT * FROM fuel_stations WHERE location = ? AND owner = ? AND owned = 1', 
                                  {location, Player.PlayerData.citizenid})
    
    if not result or #result == 0 then
        print("Error: Player is not the owner of this station")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'You do not own this station',
            type = 'error'
        })
        return
    end
    
    -- Validate name length
    if #newName < Config.NameChangeMinChar or #newName > Config.NameChangeMaxChar then
        print("Error: Invalid name length")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Invalid name length',
            type = 'error'
        })
        return
    end
    
    -- Check for profanity
    local hasProfanity = false
    for badWord, _ in pairs(Config.ProfanityList) do
        if string.find(string.lower(newName), string.lower(badWord)) then
            hasProfanity = true
            break
        end
    end
    
    if hasProfanity then
        print("Error: Inappropriate station name")
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Gas Station',
            description = 'Inappropriate station name',
            type = 'error'
        })
        return
    end
    
    -- Update name with detailed logging
    print("Attempting to update station name for location #" .. location .. " to: " .. newName)
    
    MySQL.Async.execute('UPDATE fuel_stations SET label = ? WHERE location = ?', {newName, location}, 
        function(rowsChanged)
            if rowsChanged and rowsChanged > 0 then
                print("Successfully updated station name for location #" .. location .. " (Rows changed: " .. rowsChanged .. ")")
                
                -- Update config in memory
                Config.GasStations[location].label = newName
                
                -- Notify all players of the change
                TriggerClientEvent('cdn-fuel:client:updateStationLabels', -1, location, newName)
                
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Station name updated',
                    type = 'success'
                })
                
                -- Trigger refresh for the client
                TriggerClientEvent('cdn-fuel:client:forceRefreshStationData', src)
            else
                print("Failed to update station name for location #" .. location .. " (No rows changed)")
                
                TriggerClientEvent('ox_lib:notify', src, {
                    title = 'Gas Station',
                    description = 'Failed to update station name',
                    type = 'error'
                })
            end
        end
    )
end)

-- Update location labels for all players
RegisterNetEvent('cdn-fuel:server:updateLocationLabels', function()
    local src = source
    
    MySQL.Async.fetchAll('SELECT location, label FROM fuel_stations', {}, function(result)
        if result then
            for _, station in pairs(result) do
                local location = station.location
                local label = station.label
                
                if location and label then
                    TriggerClientEvent('cdn-fuel:client:updateStationLabels', src, location, label)
                end
            end
        end
    end)
end)

-- Initialize stations on resource start
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        InitializeStations()
    end
end)