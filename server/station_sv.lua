if Config.PlayerOwnedGasStationsEnabled then
    -- Variables
    local QBCore = exports[Config.Core]:GetCoreObject()
    local FuelPickupSent = {}
    
    -- Security tracking
    local stationAccessLog = {}
    local suspiciousStationActivity = {}
    
    -- Functions
    local function GlobalTax(value)
        local tax = (value / 100 * Config.GlobalTax)
        return tax
    end

    function math.percent(percent, maxvalue)
        if tonumber(percent) and tonumber(maxvalue) then
            return (maxvalue*percent)/100
        end
        return false
    end
    
    -- Security function: Sanitize inputs
    local function SanitizeInput(input)
        if type(input) == "string" then
            -- Remove potential SQL injection patterns
            local sanitized = input:gsub("'", ""):gsub(";", ""):gsub("-", ""):gsub("=", "")
            return sanitized
        elseif type(input) == "number" then
            return input
        else
            return nil
        end
    end
    
    -- Security function: Validate station location
    local function ValidateStationLocation(location)
        if type(location) ~= "number" then return false end
        if location < 1 or location > #Config.GasStations then return false end
        return true
    end
    
    -- Security function: Log station access
    local function LogStationAccess(playerId, location, action, details)
        if not stationAccessLog[playerId] then
            stationAccessLog[playerId] = {}
        end
        
        table.insert(stationAccessLog[playerId], {
            location = location,
            action = action,
            details = details,
            timestamp = os.time()
        })
        
        print(string.format("[STATION ACCESS] Player: %s | Station: %d | Action: %s | Details: %s", 
            GetPlayerName(playerId), location, action, details or "none"))
    end
    
    -- Security function: Flag suspicious station activity
    local function FlagSuspiciousStationActivity(playerId, stationId, activityType, details)
        if not suspiciousStationActivity[playerId] then
            suspiciousStationActivity[playerId] = {}
        end
        
        table.insert(suspiciousStationActivity[playerId], {
            stationId = stationId,
            type = activityType,
            details = details,
            timestamp = os.time()
        })
        
        -- If multiple suspicious activities in short time, take action
        if #suspiciousStationActivity[playerId] >= 3 then
            local recentCount = 0
            local currentTime = os.time()
            
            for _, activity in ipairs(suspiciousStationActivity[playerId]) do
                if (currentTime - activity.timestamp) < 300 then -- Within last 5 minutes
                    recentCount = recentCount + 1
                end
            end
            
            if recentCount >= 3 then
                -- Log for admin review
                print("ALERT: Player ID " .. playerId .. " has triggered multiple suspicious station activities")
                
                -- Optional: Take immediate action
                -- TriggerEvent('qb-log:server:CreateLog', 'anticheat', 'Possible Station Exploitation', 'red', GetPlayerName(playerId) .. ' has triggered multiple suspicious activities')
                
                -- Clear the record after logging
                suspiciousStationActivity[playerId] = {}
            end
        end
    end
    
    -- Security function: Verify station ownership
    local function VerifyStationOwnership(src, location, callback)
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then
            callback(false)
            return
        end
        
        local citizenid = Player.PlayerData.citizenid
        
        MySQL.Async.fetchAll('SELECT * FROM fuel_stations WHERE `owner` = ? AND location = ?', {citizenid, location}, function(result)
            if result and #result > 0 then
                local stationData = result[1]
                if stationData.owner == citizenid and stationData.owned == 1 then
                    callback(true, stationData)
                else
                    callback(false)
                end
            else
                callback(false)
            end
        end)
    end
    
    -- Security function: Rate limit checks for station operations
    local function CheckStationRateLimit(src, actionType, cooldownSeconds)
        if not playerLastActivity then playerLastActivity = {} end
        if not playerLastActivity[src] then
            playerLastActivity[src] = {}
        end
        
        local currentTime = os.time()
        local lastTime = playerLastActivity[src][actionType] or 0
        
        if currentTime - lastTime < cooldownSeconds then
            -- Rate limit exceeded
            return false
        end
        
        -- Update last activity time
        playerLastActivity[src][actionType] = currentTime
        return true
    end
    
    -- Event: Update station labels
    RegisterNetEvent('cdn-fuel:server:updatelocationlabels', function()
        local src = source
        if src <= 0 then return end -- Block non-player triggers
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "update_labels", 10) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before updating labels again", "error")
            return
        end
        
        for i = 1, #Config.GasStations do
            UpdateStationLabel(i, nil, src)
        end
    end)
    
    -- Event: Buy Gas Station
    RegisterNetEvent('cdn-fuel:server:buyStation', function(location, CitizenID)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to buy invalid location: " .. tostring(location))
            return
        end
        
        -- Validate CitizenID matches player
        if Player.PlayerData.citizenid ~= CitizenID then
            FlagSuspiciousStationActivity(src, location, "id_mismatch", "CitizenID mismatch during purchase")
            return
        end
        
        -- Check if station is already owned
        MySQL.Async.fetchAll('SELECT owned FROM fuel_stations WHERE location = ?', {location}, function(result)
            if result and #result > 0 then
                if result[1].owned == 1 then
                    TriggerClientEvent('QBCore:Notify', src, "This station is already owned", "error")
                    return
                else
                    -- Check if player already owns a station (if OneStationPerPerson is enabled)
                    if Config.OneStationPerPerson then
                        MySQL.Async.fetchAll('SELECT * FROM fuel_stations WHERE owner = ? AND owned = 1', {CitizenID}, function(ownedResults)
                            if ownedResults and #ownedResults > 0 then
                                TriggerClientEvent('QBCore:Notify', src, "You already own a gas station", "error")
                                return
                            else
                                -- Process purchase
                                CompletePurchase(src, Player, location, CitizenID)
                            end
                        end)
                    else
                        -- Process purchase
                        CompletePurchase(src, Player, location, CitizenID)
                    end
                end
            else
                FlagSuspiciousStationActivity(src, location, "missing_station", "Station data missing for location: " .. location)
            end
        end)
    end)
    
    -- Helper function for station purchase
    function CompletePurchase(src, Player, location, CitizenID)
        local CostOfStation = Config.GasStations[location].cost + GlobalTax(Config.GasStations[location].cost)
        
        -- Check if player can afford
        if Player.Functions.GetMoney("bank") < CostOfStation then
            TriggerClientEvent('QBCore:Notify', src, "You cannot afford this station", "error")
            return
        end
        
        -- Process payment
        if Player.Functions.RemoveMoney("bank", CostOfStation, Lang:t("station_purchased_location_payment_label")..Config.GasStations[location].label) then
            -- Update database
            MySQL.Async.execute('UPDATE fuel_stations SET owned = ? WHERE `location` = ?', {1, location})
            MySQL.Async.execute('UPDATE fuel_stations SET owner = ? WHERE `location` = ?', {CitizenID, location})
            
            -- Log transaction
            LogStationAccess(src, location, "purchase", "Purchased for $" .. CostOfStation)
            
            TriggerClientEvent('QBCore:Notify', src, "You have successfully purchased this gas station!", "success")
        else
            TriggerClientEvent('QBCore:Notify', src, "Transaction failed", "error")
        end
    end
    
    -- Event: Sell station
    RegisterNetEvent('cdn-fuel:stations:server:sellstation', function(location)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to sell invalid location: " .. tostring(location))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "sell_station", 30) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before attempting to sell again", "error")
            return
        end
        
        -- Verify ownership
        VerifyStationOwnership(src, location, function(isOwner, stationData)
            if not isOwner then
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_not_owner"), 'error')
                FlagSuspiciousStationActivity(src, location, "unauthorized_sell", "Attempted to sell without ownership")
                return
            end
            
            -- Calculate sale price
            local GasStationCost = Config.GasStations[location].cost + GlobalTax(Config.GasStations[location].cost)
            local SalePrice = math.percent(Config.GasStationSellPercentage, GasStationCost)
            
            -- Process sale
            if Player.Functions.AddMoney("bank", SalePrice, Lang:t("station_sold_location_payment_label")..Config.GasStations[location].label) then
                -- Update database
                MySQL.Async.execute('UPDATE fuel_stations SET owned = ? WHERE `location` = ?', {0, location})
                MySQL.Async.execute('UPDATE fuel_stations SET owner = ? WHERE `location` = ?', {0, location})
                
                -- Log transaction
                LogStationAccess(src, location, "sell", "Sold for $" .. SalePrice)
                
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_sold_success"), 'success')
            else
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_cannot_sell"), 'error')
            end
        end)
    end)
    
    -- Event: Withdraw funds
    RegisterNetEvent('cdn-fuel:station:server:Withdraw', function(amount, location, StationBalance)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        
        -- Validate inputs
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to withdraw from invalid location: " .. tostring(location))
            return
        end
        
        if type(amount) ~= "number" or amount <= 0 then
            FlagSuspiciousStationActivity(src, location, "invalid_amount", "Invalid withdrawal amount: " .. tostring(amount))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "withdraw", 5) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before making another withdrawal", "error")
            return
        end
        
        -- Verify ownership
        VerifyStationOwnership(src, location, function(isOwner, stationData)
            if not isOwner then
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_not_owner"), 'error')
                FlagSuspiciousStationActivity(src, location, "unauthorized_withdraw", "Attempted to withdraw without ownership")
                return
            end
            
            -- Verify station balance matches expected
            MySQL.Async.fetchAll('SELECT balance FROM fuel_stations WHERE location = ?', {location}, function(result)
                if result and #result > 0 then
                    local currentBalance = tonumber(result[1].balance)
                    
                    -- Verify balance
                    if math.abs(currentBalance - StationBalance) > 100 then
                        FlagSuspiciousStationActivity(src, location, "balance_mismatch", "Balance mismatch during withdrawal")
                        TriggerClientEvent('QBCore:Notify', src, "There was an issue with your balance. Please try again.", "error")
                        return
                    end
                    
                    -- Check if withdrawal amount is valid
                    if amount > currentBalance then
                        TriggerClientEvent('QBCore:Notify', src, Lang:t("station_withdraw_too_much"), 'error')
                        return
                    end
                    
                    -- Process withdrawal
                    local newBalance = currentBalance - amount
                    MySQL.Async.execute('UPDATE fuel_stations SET balance = ? WHERE `location` = ?', {newBalance, location})
                    
                    -- Add money to player
                    Player.Functions.AddMoney("bank", amount, Lang:t("station_withdraw_payment_label")..Config.GasStations[location].label)
                    
                    -- Log transaction
                    LogStationAccess(src, location, "withdraw", "Withdrew $" .. amount)
                    
                    TriggerClientEvent('QBCore:Notify', src, Lang:t("station_success_withdrew_1")..amount..Lang:t("station_success_withdrew_2"), 'success')
                else
                    FlagSuspiciousStationActivity(src, location, "missing_station", "Station data missing during withdrawal")
                end
            end)
        end)
    end)
    
    -- Event: Deposit funds
    RegisterNetEvent('cdn-fuel:station:server:Deposit', function(amount, location, StationBalance)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        
        -- Validate inputs
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to deposit to invalid location: " .. tostring(location))
            return
        end
        
        if type(amount) ~= "number" or amount <= 0 then
            FlagSuspiciousStationActivity(src, location, "invalid_amount", "Invalid deposit amount: " .. tostring(amount))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "deposit", 5) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before making another deposit", "error")
            return
        end
        
        -- Verify ownership
        VerifyStationOwnership(src, location, function(isOwner, stationData)
            if not isOwner then
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_not_owner"), 'error')
                FlagSuspiciousStationActivity(src, location, "unauthorized_deposit", "Attempted to deposit without ownership")
                return
            end
            
            -- Verify station balance
            MySQL.Async.fetchAll('SELECT balance FROM fuel_stations WHERE location = ?', {location}, function(result)
                if result and #result > 0 then
                    local currentBalance = tonumber(result[1].balance)
                    
                    -- Verify balance
                    if math.abs(currentBalance - StationBalance) > 100 then
                        FlagSuspiciousStationActivity(src, location, "balance_mismatch", "Balance mismatch during deposit")
                        TriggerClientEvent('QBCore:Notify', src, "There was an issue with your balance. Please try again.", "error")
                        return
                    end
                    
                    -- Check if player can afford
                    if Player.Functions.GetMoney("bank") < amount then
                        TriggerClientEvent('QBCore:Notify', src, Lang:t("station_cannot_afford_deposit")..amount.."!", 'error')
                        return
                    end
                    
                    -- Process deposit
                    if Player.Functions.RemoveMoney("bank", amount, Lang:t("station_deposit_payment_label")..Config.GasStations[location].label) then
                        local newBalance = currentBalance + amount
                        MySQL.Async.execute('UPDATE fuel_stations SET balance = ? WHERE `location` = ?', {newBalance, location})
                        
                        -- Log transaction
                        LogStationAccess(src, location, "deposit", "Deposited $" .. amount)
                        
                        TriggerClientEvent('QBCore:Notify', src, Lang:t("station_success_deposit_1")..amount..Lang:t("station_success_deposit_2"), 'success')
                    else
                        TriggerClientEvent('QBCore:Notify', src, Lang:t("station_cannot_afford_deposit")..amount.."!", 'error')
                    end
                else
                    FlagSuspiciousStationActivity(src, location, "missing_station", "Station data missing during deposit")
                end
            end)
        end)
    end)
    
    -- Event: Toggle emergency shutoff
    RegisterNetEvent('cdn-fuel:stations:server:Shutoff', function(location)
        local src = source
        if not src then return end
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to toggle shutoff for invalid location: " .. tostring(location))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "shutoff", 10) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before toggling shutoff again", "error")
            return
        end
        
        if Config.FuelDebug then print("Toggling Emergency Shutoff Valves for Location #"..location) end
        Config.GasStations[location].shutoff = not Config.GasStations[location].shutoff
        
        -- Log action
        LogStationAccess(src, location, "shutoff", "Changed shutoff state to: " .. tostring(Config.GasStations[location].shutoff))
        
        TriggerClientEvent('QBCore:Notify', src, Lang:t("station_shutoff_success"), 'success')
    end)
    
    -- Event: Update fuel price
    RegisterNetEvent('cdn-fuel:station:server:updatefuelprice', function(fuelprice, location)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        
        -- Validate inputs
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to update price for invalid location: " .. tostring(location))
            return
        end
        
        if type(fuelprice) ~= "number" or fuelprice < Config.MinimumFuelPrice or fuelprice > Config.MaxFuelPrice then
            FlagSuspiciousStationActivity(src, location, "invalid_price", "Invalid fuel price: " .. tostring(fuelprice))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "update_price", 5) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before updating price again", "error")
            return
        end
        
        -- Verify ownership
        VerifyStationOwnership(src, location, function(isOwner)
            if not isOwner then
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_not_owner"), 'error')
                FlagSuspiciousStationActivity(src, location, "unauthorized_price", "Attempted to change price without ownership")
                return
            end
            
            -- Update fuel price
            MySQL.Async.execute('UPDATE fuel_stations SET fuelprice = ? WHERE `location` = ?', {fuelprice, location})
            
            -- Log action
            LogStationAccess(src, location, "update_price", "Changed price to: $" .. fuelprice)
            
            TriggerClientEvent('QBCore:Notify', src, Lang:t("station_fuel_price_success")..fuelprice..Lang:t("station_per_liter"), 'success')
        end)
    end)
    
    -- Event: Update reserves
    RegisterNetEvent('cdn-fuel:station:server:updatereserves', function(reason, amount, currentlevel, location)
        local src = source
        
        -- Validate inputs
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to update reserves for invalid location: " .. tostring(location))
            return
        end
        
        if reason ~= "remove" and reason ~= "add" then
            FlagSuspiciousStationActivity(src, location, "invalid_reason", "Invalid reason for reserve update: " .. tostring(reason))
            return
        end
        
        if type(amount) ~= "number" or amount <= 0 then
            FlagSuspiciousStationActivity(src, location, "invalid_amount", "Invalid reserve amount: " .. tostring(amount))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "update_reserves", 2) then
            return
        end
        
        -- Verify current reserves
        MySQL.Async.fetchAll('SELECT fuel FROM fuel_stations WHERE location = ?', {location}, function(result)
            if result and #result > 0 then
                local currentReserves = tonumber(result[1].fuel)
                
                -- Validate current level
                if math.abs(currentReserves - currentlevel) > 50 then
                    FlagSuspiciousStationActivity(src, location, "reserves_mismatch", "Reserves mismatch: " .. currentlevel .. " vs actual " .. currentReserves)
                    return
                end
                
                -- Calculate new level
                local NewLevel
                if reason == "remove" then
                    NewLevel = math.max(0, currentReserves - amount)
                else
                    NewLevel = math.min(Config.MaxFuelReserves, currentReserves + amount)
                end
                
                -- Update reserves
                MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE `location` = ?', {NewLevel, location})
                
                -- Log action
                LogStationAccess(src, location, "update_reserves", reason .. " " .. amount .. "L, new level: " .. NewLevel)
            else
                FlagSuspiciousStationActivity(src, location, "missing_station", "Station data missing during reserves update")
            end
        end)
    end)
    
    -- Event: Update station balance
    RegisterNetEvent('cdn-fuel:station:server:updatebalance', function(reason, amount, StationBalance, location, FuelPrice)
        local src = source
        
        -- Validate inputs
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to update balance for invalid location: " .. tostring(location))
            return
        end
        
        if reason ~= "remove" and reason ~= "add" then
            FlagSuspiciousStationActivity(src, location, "invalid_reason", "Invalid reason for balance update: " .. tostring(reason))
            return
        end
        
        if type(amount) ~= "number" or amount <= 0 then
            FlagSuspiciousStationActivity(src, location, "invalid_amount", "Invalid balance amount: " .. tostring(amount))
            return
        end
        
        if type(FuelPrice) ~= "number" or FuelPrice < 0 then
            FlagSuspiciousStationActivity(src, location, "invalid_price", "Invalid fuel price in balance update: " .. tostring(FuelPrice))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "update_balance", 2) then
            return
        end
        
        -- Calculate amount to add or remove
        local Price = (FuelPrice * tonumber(amount))
        local StationGetAmount = math.floor(Config.StationFuelSalePercentage * Price)
        
        -- Verify current balance
        MySQL.Async.fetchAll('SELECT balance FROM fuel_stations WHERE location = ?', {location}, function(result)
            if result and #result > 0 then
                local currentBalance = tonumber(result[1].balance)
                
                -- Validate current balance
                if math.abs(currentBalance - StationBalance) > 100 then
                    FlagSuspiciousStationActivity(src, location, "balance_mismatch", "Balance mismatch in update: " .. StationBalance .. " vs actual " .. currentBalance)
                    return
                end
                
                -- Calculate new balance
                local NewBalance
                if reason == "remove" then
                    NewBalance = math.max(0, currentBalance - StationGetAmount)
                else
                    NewBalance = currentBalance + StationGetAmount
                end
                
                -- Update balance
                MySQL.Async.execute('UPDATE fuel_stations SET balance = ? WHERE `location` = ?', {NewBalance, location})
                
                -- Log action
                LogStationAccess(src, location, "update_balance", reason .. " $" .. StationGetAmount .. ", new balance: $" .. NewBalance)
            else
                FlagSuspiciousStationActivity(src, location, "missing_station", "Station data missing during balance update")
            end
        end)
    end)
    
    -- Event: Buy reserves
    RegisterNetEvent('cdn-fuel:stations:server:buyreserves', function(location, price, amount)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        
        -- Validate inputs
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to buy reserves for invalid location: " .. tostring(location))
            return
        end
        
        if type(price) ~= "number" or price <= 0 then
            FlagSuspiciousStationActivity(src, location, "invalid_price", "Invalid reserve price: " .. tostring(price))
            return
        end
        
        if type(amount) ~= "number" or amount <= 0 then
            FlagSuspiciousStationActivity(src, location, "invalid_amount", "Invalid reserve amount: " .. tostring(amount))
            return
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "buy_reserves", 10) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before buying reserves again", "error")
            return
        end
        
        -- Verify ownership
        VerifyStationOwnership(src, location, function(isOwner)
            if not isOwner then
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_not_owner"), 'error')
                FlagSuspiciousStationActivity(src, location, "unauthorized_reserve", "Attempted to buy reserves without ownership")
                return
            end
            
            -- Check current reserves
            MySQL.Async.fetchAll('SELECT fuel FROM fuel_stations WHERE location = ?', {location}, function(result)
                if result and #result > 0 then
                    local currentReserves = tonumber(result[1].fuel)
                    
                    -- Check if purchase would exceed capacity
                    if currentReserves + amount > Config.MaxFuelReserves then
                        TriggerClientEvent('QBCore:Notify', src, Lang:t("station_reserves_over_max"), 'error')
                        return
                    end
                    
                    -- Verify the cost
                    local expectedPrice = math.ceil(GlobalTax(amount * Config.FuelReservesPrice) + (amount * Config.FuelReservesPrice))
                    if math.abs(price - expectedPrice) > 10 then
                        FlagSuspiciousStationActivity(src, location, "price_mismatch", "Reserve price mismatch: " .. price .. " vs expected " .. expectedPrice)
                        return
                    end
                    
                    -- Check if player can afford
                    if Player.Functions.GetMoney("bank") < price then
                        TriggerClientEvent('QBCore:Notify', src, Lang:t("not_enough_money"), 'error')
                        return
                    end
                    
                    -- Process purchase
                    local ReserveBuyPossible = true
                    if ReserveBuyPossible and Player.Functions.RemoveMoney("bank", price, "Purchased "..amount.."L of Reserves for: "..Config.GasStations[location].label.." @ $"..Config.FuelReservesPrice.." / L!") then
                        if not Config.OwnersPickupFuel then
                            -- Direct update
                            local NewAmount = currentReserves + amount
                            MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE `location` = ?', {NewAmount, location})
                            
                            -- Log transaction
                            LogStationAccess(src, location, "buy_reserves", "Purchased " .. amount .. "L for $" .. price)
                        else
                            -- Initiate pickup
                            FuelPickupSent[location] = {
                                ['src'] = src,
                                ['refuelAmount'] = currentReserves + amount,
                                ['amountBought'] = amount,
                            }
                            
                            TriggerClientEvent('cdn-fuel:station:client:initiatefuelpickup', src, amount, currentReserves + amount, location)
                            
                            -- Log transaction
                            LogStationAccess(src, location, "buy_reserves_pickup", "Initiated pickup for " .. amount .. "L for $" .. price)
                        end
                    else
                        TriggerClientEvent('QBCore:Notify', src, Lang:t("not_enough_money"), 'error')
                    end
                else
                    FlagSuspiciousStationActivity(src, location, "missing_station", "Station data missing during reserve purchase")
                end
            end)
        end)
    end)
    
    -- Event: Fuel pickup failed
    RegisterNetEvent('cdn-fuel:station:server:fuelpickup:failed', function(location)
        local src = source
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to handle failed pickup for invalid location: " .. tostring(location))
            return
        end
        
        -- Verify this is a valid pickup
        if not FuelPickupSent[location] or FuelPickupSent[location]['src'] ~= src then
            FlagSuspiciousStationActivity(src, location, "invalid_pickup", "Attempted to handle nonexistent pickup")
            return
        end
        
        -- Process failed pickup
        local cid = QBCore.Functions.GetPlayer(src).PlayerData.citizenid
        MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE `location` = ?', {FuelPickupSent[location]['refuelAmount'], location})
        TriggerClientEvent('QBCore:Notify', src, Lang:t("fuel_pickup_failed"), 'success')
        
        -- Log action
        LogStationAccess(src, location, "failed_pickup", "Fuel delivery failed, updating fuel level: " .. FuelPickupSent[location].refuelAmount)
        
        -- Clean up
        FuelPickupSent[location] = nil
    end)
    
    -- Event: Fuel pickup finished
    RegisterNetEvent('cdn-fuel:station:server:fuelpickup:finished', function(location)
        local src = source
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to handle finished pickup for invalid location: " .. tostring(location))
            return
        end
        
        -- Verify this is a valid pickup
        if not FuelPickupSent[location] or FuelPickupSent[location]['src'] ~= src then
            FlagSuspiciousStationActivity(src, location, "invalid_pickup", "Attempted to handle nonexistent pickup")
            return
        end
        
        -- Process successful pickup
        local cid = QBCore.Functions.GetPlayer(src).PlayerData.citizenid
        MySQL.Async.execute('UPDATE fuel_stations SET fuel = ? WHERE `location` = ?', {FuelPickupSent[location].refuelAmount, location})
        TriggerClientEvent('QBCore:Notify', src, string.format(Lang:t("fuel_pickup_success"), tostring(FuelPickupSent[location].refuelAmount)), 'success')
        
        -- Log action
        LogStationAccess(src, location, "successful_pickup", "Fuel delivery completed, updating fuel level: " .. FuelPickupSent[location].refuelAmount)
        
        -- Clean up
        FuelPickupSent[location] = nil
    end)
    
    -- Event: Update location name
    RegisterNetEvent('cdn-fuel:station:server:updatelocationname', function(newName, location)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        if not Player then return end
        
        -- Validate inputs
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to update name for invalid location: " .. tostring(location))
            return
        end
        
        if type(newName) ~= "string" then
            FlagSuspiciousStationActivity(src, location, "invalid_name", "Invalid station name type: " .. type(newName))
            return
        end
        
        -- Sanitize name
        newName = SanitizeInput(newName)
        
        -- Check name length
        if string.len(newName) < Config.NameChangeMinChar or string.len(newName) > Config.NameChangeMaxChar then
            TriggerClientEvent('QBCore:Notify', src, Lang:t("station_name_invalid"), 'error')
            return
        end
        
        -- Check for profanity
        for _, word in ipairs(Config.ProfanityList) do
            if string.find(string.lower(newName), string.lower(word)) then
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_name_invalid"), 'error')
                return
            end
        end
        
        -- Rate limiting
        if not CheckStationRateLimit(src, "update_name", 30) then
            TriggerClientEvent('QBCore:Notify', src, "Please wait before changing the name again", "error")
            return
        end
        
        -- Verify ownership
        VerifyStationOwnership(src, location, function(isOwner)
            if not isOwner then
                TriggerClientEvent('QBCore:Notify', src, Lang:t("station_not_owner"), 'error')
                FlagSuspiciousStationActivity(src, location, "unauthorized_rename", "Attempted to rename without ownership")
                return
            end
            
            -- Update name
            MySQL.Async.execute('UPDATE fuel_stations SET label = ? WHERE `location` = ?', {newName, location})
            
            -- Log action
            LogStationAccess(src, location, "rename", "Changed name to: " .. newName)
            
            TriggerClientEvent('QBCore:Notify', src, Lang:t("station_name_change_success")..newName.."!", 'success')
            TriggerClientEvent('cdn-fuel:client:updatestationlabels', -1, location, newName)
        end)
    end)
    
    -- Callback: Check if location is purchased
    QBCore.Functions.CreateCallback('cdn-fuel:server:locationpurchased', function(source, cb, location)
        local src = source
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to check ownership of invalid location: " .. tostring(location))
            cb(false)
            return
        end
        
        -- Query database
        MySQL.Async.fetchAll('SELECT * FROM fuel_stations WHERE `location` = ?', {location}, function(result)
            if result and #result > 0 then
                local owned = (result[1].owned == 1)
                cb(owned)
            else
                cb(false)
            end
        end)
    end)
    
    -- Callback: Check if player owns any station
    QBCore.Functions.CreateCallback('cdn-fuel:server:doesPlayerOwnStation', function(source, cb)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        local citizenid = Player.PlayerData.citizenid
        
        -- Query database
        MySQL.Async.fetchAll('SELECT * FROM fuel_stations WHERE `owner` = ?', {citizenid}, function(result)
            local tableEmpty = next(result) == nil
            cb(not tableEmpty)
        end)
    end)
    
    -- Callback: Check if player owns specific station
    QBCore.Functions.CreateCallback('cdn-fuel:server:isowner', function(source, cb, location)
        local src = source
        local Player = QBCore.Functions.GetPlayer(src)
        local citizenid = Player.PlayerData.citizenid
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to check ownership of invalid location: " .. tostring(location))
            cb(false)
            return
        end
        
        -- Query database
        MySQL.Async.fetchAll('SELECT * FROM fuel_stations WHERE `owner` = ? AND location = ?', {citizenid, location}, function(result)
            if result and #result > 0 then
                local isOwner = (result[1].owner == citizenid and result[1].owned == 1)
                cb(isOwner)
            else
                cb(false)
            end
        end)
    end)
    
    -- Callback: Fetch station info
    QBCore.Functions.CreateCallback('cdn-fuel:server:fetchinfo', function(source, cb, location)
        local src = source
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to fetch info for invalid location: " .. tostring(location))
            cb(false)
            return
        end
        
        -- Query database
        MySQL.Async.fetchAll('SELECT * FROM fuel_stations WHERE location = ?', {location}, function(result)
            cb(result)
        end)
    end)
    
    -- Callback: Check shutoff state
    QBCore.Functions.CreateCallback('cdn-fuel:server:checkshutoff', function(source, cb, location)
        local src = source
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to check shutoff for invalid location: " .. tostring(location))
            cb(false)
            return
        end
        
        -- Return shutoff state
        cb(Config.GasStations[location].shutoff)
    end)
    
    -- Callback: Fetch station label
    QBCore.Functions.CreateCallback('cdn-fuel:server:fetchlabel', function(source, cb, location)
        local src = source
        
        -- Validate location
        if not ValidateStationLocation(location) then
            FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to fetch label for invalid location: " .. tostring(location))
            cb(false)
            return
        end
        
        -- Query database
        MySQL.Async.fetchAll('SELECT label FROM fuel_stations WHERE location = ?', {location}, function(result)
            cb(result)
        end)
    end)
    
    -- Update function for station labels
    function UpdateStationLabel(location, newLabel, src)
        if not ValidateStationLocation(location) then
            if src then
                FlagSuspiciousStationActivity(src, location, "invalid_location", "Attempted to update label for invalid location: " .. tostring(location))
            end
            return
        end
        
        if not newLabel or newLabel == nil then
            -- Fetch current label
            MySQL.Async.fetchAll('SELECT label FROM fuel_stations WHERE location = ?', {location}, function(result)
                if result and #result > 0 then
                    local newLabel = result[1].label
                    TriggerClientEvent('cdn-fuel:client:updatestationlabels', -1, location, newLabel)
                else
                    if src then
                        cb(false)
                    end
                end
            end)
        else
            -- Update label
            MySQL.Async.execute('UPDATE fuel_stations SET label = ? WHERE `location` = ?', {newLabel, location})
            TriggerClientEvent('cdn-fuel:client:updatestationlabels', -1, location, newLabel)
        end
    end
    
    -- Startup function
    local function Startup()
        if Config.FuelDebug then print("Starting up gas station system...") end
        local location = 0
        for _ in pairs(Config.GasStations) do
            location = location + 1
            UpdateStationLabel(location)
        end
    end
    
    -- Resource start handler
    AddEventHandler('onResourceStart', function(resource)
        if resource == GetCurrentResourceName() then
            Startup()
        end
    end)
end
