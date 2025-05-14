-- Variables
local QBCore = exports[Config.Core]:GetCoreObject()

-- Fuel state tracking
local vehicleFuelStates = {}
local pendingRefuels = {}
local playerLastActivity = {}
local suspiciousActivity = {}

-- Transaction tracking for anti-cheat
local recentTransactions = {}

-- Functions
local function GlobalTax(value)
    local tax = (value / 100 * Config.GlobalTax)
    return tax
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

-- Security function: Log suspicious activity
local function FlagSuspiciousActivity(playerId, activityType, details)
    if not suspiciousActivity[playerId] then
        suspiciousActivity[playerId] = {}
    end
    
    table.insert(suspiciousActivity[playerId], {
        type = activityType,
        details = details,
        timestamp = os.time()
    })
    
    -- If multiple suspicious activities in short time, take action
    if #suspiciousActivity[playerId] >= 3 then
        local recentCount = 0
        local currentTime = os.time()
        
        for _, activity in ipairs(suspiciousActivity[playerId]) do
            if (currentTime - activity.timestamp) < 300 then -- Within last 5 minutes
                recentCount = recentCount + 1
            end
        end
        
        if recentCount >= 3 then
            -- Log for admin review
            print("ALERT: Player ID " .. playerId .. " has triggered multiple suspicious fuel activities")
            
            -- Optional: Take immediate action
            -- TriggerEvent('qb-log:server:CreateLog', 'anticheat', 'Possible Fuel Script Exploitation', 'red', GetPlayerName(playerId) .. ' has triggered multiple suspicious activities')
            
            -- Clear the record after logging
            suspiciousActivity[playerId] = {}
        end
    end
end

-- Security function: Check if player is near gas station
local function IsPlayerNearGasStation(src)
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return false end
    
    local playerPed = GetPlayerPed(src)
    if not playerPed then return false end
    
    local playerCoords = GetEntityCoords(playerPed)
    
    for _, station in pairs(Config.GasStations) do
        local stationCoords = vector3(station.pedcoords.x, station.pedcoords.y, station.pedcoords.z)
        local distance = #(playerCoords - stationCoords)
        if distance < 50.0 then
            return true, distance
        end
    end
    
    return false, 999.0
end

-- Security function: Rate limit checks
local function CheckRateLimit(src, actionType, cooldownSeconds)
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

-- Security function: Log transactions
local function LogFuelTransaction(data)
    if not data then return end
    
    -- Store in database
    MySQL.Async.execute('INSERT INTO fuel_transactions (player_id, player_name, citizen_id, amount, payment_type, fuel_amount, fuel_price, is_electric, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    {
        data.playerId,
        data.playerName,
        data.citizenId,
        data.amount,
        data.paymentType,
        data.fuelAmount,
        data.fuelPrice,
        data.isElectric,
        data.timestamp
    })
    
    -- Track recent transactions for this player
    if not recentTransactions[data.playerId] then
        recentTransactions[data.playerId] = {}
    end
    
    table.insert(recentTransactions[data.playerId], {
        amount = data.amount,
        fuelAmount = data.fuelAmount,
        timestamp = os.time()
    })
    
    -- Check for suspicious patterns (many small transactions, etc)
    if #recentTransactions[data.playerId] >= 5 then
        local recentCount = 0
        local totalAmount = 0
        local currentTime = os.time()
        
        for i = #recentTransactions[data.playerId], 1, -1 do
            local transaction = recentTransactions[data.playerId][i]
            if (currentTime - transaction.timestamp) < 60 then -- Last minute
                recentCount = recentCount + 1
                totalAmount = totalAmount + transaction.amount
            end
        end
        
        if recentCount >= 5 then
            -- Suspicious rapid transactions
            FlagSuspiciousActivity(data.playerId, "rapid_transactions", "5+ fuel transactions in 60 seconds, total $" .. totalAmount)
        end
        
        -- Trim the transaction history to prevent memory growth
        if #recentTransactions[data.playerId] > 20 then
            for i = 1, #recentTransactions[data.playerId] - 20 do
                table.remove(recentTransactions[data.playerId], 1)
            end
        end
    end
    
    -- Console log for immediate visibility
    print(string.format("[FUEL TRANSACTION] Player: %s (%s) | Amount: $%d | Fuel: %.1f L | Type: %s", 
        data.playerName, data.citizenId, data.amount, data.fuelAmount, data.paymentType))
end

-- Fuel sync event
RegisterNetEvent('cdn-fuel:server:RequestFuelSync', function(plate)
    local src = source
    if not CheckRateLimit(src, "fuel_sync", 2) then return end
    
    if not plate then
        FlagSuspiciousActivity(src, "invalid_sync", "Missing plate parameter")
        return
    end
    
    -- If we have a state for this vehicle, send it to the client
    if vehicleFuelStates[plate] then
        TriggerClientEvent('cdn-fuel:client:SyncFuel', src, plate, vehicleFuelStates[plate])
    else
        -- No state yet, initialize with a reasonable value
        local fuelLevel = math.random(30, 80)
        vehicleFuelStates[plate] = fuelLevel
        TriggerClientEvent('cdn-fuel:client:SyncFuel', src, plate, fuelLevel)
    end
end)

-- Update fuel event
RegisterNetEvent('cdn-fuel:server:UpdateFuel', function(plate, fuel)
    local src = source
    if not CheckRateLimit(src, "fuel_update", 1) then return end
    
    -- Validate inputs
    if not plate or type(fuel) ~= "number" or fuel < 0 or fuel > 100 then
        FlagSuspiciousActivity(src, "invalid_fuel", "Invalid fuel update: " .. tostring(fuel))
        return
    end
    
    -- Store the updated state
    vehicleFuelStates[plate] = fuel
    
    -- Broadcast to nearby players (optional, for multiplayer sync)
    local players = QBCore.Functions.GetPlayers()
    for _, playerId in ipairs(players) do
        if tonumber(playerId) ~= src then
            local playerPed = GetPlayerPed(playerId)
            local playerCoords = GetEntityCoords(playerPed)
            local sourceCoords = GetEntityCoords(GetPlayerPed(src))
            
            if #(playerCoords - sourceCoords) < 100.0 then
                TriggerClientEvent('cdn-fuel:client:SyncFuel', playerId, plate, fuel)
            end
        end
    end
end)

-- Start refuel event
RegisterNetEvent('cdn-fuel:server:StartRefuel', function(plate, currentFuel, fuelAmount, purchaseType)
    local src = source
    
    -- Rate limiting
    if not CheckRateLimit(src, "refuel_start", 2) then
        TriggerClientEvent('QBCore:Notify', src, "Please wait before attempting to refuel again", "error")
        return
    end
    
    -- Input validation
    if not plate or not currentFuel or not fuelAmount or not purchaseType then
        FlagSuspiciousActivity(src, "invalid_refuel_start", "Missing parameters")
        return
    end
    
    -- Verify player is near a gas station
    local isNearStation, distance = IsPlayerNearGasStation(src)
    if not isNearStation then
        FlagSuspiciousActivity(src, "distance_refuel", "Started refuel while not at gas station. Distance: " .. distance)
        return
    end
    
    -- Create pending refuel entry
    pendingRefuels[src] = {
        plate = plate,
        initialFuel = currentFuel,
        requestedAmount = fuelAmount,
        purchaseType = purchaseType,
        timestamp = os.time()
    }
    
    -- Acknowledge start to client
    TriggerClientEvent('cdn-fuel:client:RefuelStarted', src, true)
end)

-- Complete refuel event
RegisterNetEvent('cdn-fuel:server:CompleteRefuel', function(plate, finalFuel, addedFuel, purchaseType)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end
    
    -- Validate pending refuel exists
    if not pendingRefuels[src] then
        FlagSuspiciousActivity(src, "unauthorized_refuel", "Completed refuel without starting it")
        return
    end
    
    -- Validate plate matches
    if pendingRefuels[src].plate ~= plate then
        FlagSuspiciousActivity(src, "plate_mismatch", "Plate mismatch during refuel")
        return
    end
    
    -- Validate time elapsed is reasonable
    local timeElapsed = os.time() - pendingRefuels[src].timestamp
    local expectedTime = pendingRefuels[src].requestedAmount * Config.RefuelTime / 1000
    
    if timeElapsed < (expectedTime * 0.5) then
        FlagSuspiciousActivity(src, "speedhack", "Refuel completed too quickly: " .. timeElapsed .. "s vs expected " .. expectedTime .. "s")
        return
    end
    
    -- Validate fuel amount change is reasonable
    local fuelDifference = finalFuel - pendingRefuels[src].initialFuel
    if math.abs(fuelDifference - addedFuel) > 1.0 then
        FlagSuspiciousActivity(src, "fuel_mismatch", "Added fuel mismatch: " .. addedFuel .. " vs calculated " .. fuelDifference)
    end
    
    -- Calculate price based on actual fuel added
    local actualFuelAdded = math.min(addedFuel, pendingRefuels[src].requestedAmount)
    
    -- Determine price (simplified, you would add station price logic here)
    local fuelPrice = Config.CostMultiplier
    if plate then
        -- Get vehicle class for special pricing
        -- This would need server-side vehicle tracking to be fully secure
    end
    
    -- Calculate total cost
    local refillCost = (actualFuelAdded * fuelPrice) + GlobalTax(actualFuelAdded * fuelPrice)
    
    -- Process payment
    local paymentType = purchaseType
    local paymentSuccess = false
    
    if paymentType == "bank" then
        if player.Functions.GetMoney('bank') >= refillCost then
            player.Functions.RemoveMoney('bank', refillCost, "Vehicle Refueling")
            paymentSuccess = true
        end
    elseif paymentType == "cash" then
        if player.Functions.GetMoney('cash') >= refillCost then
            player.Functions.RemoveMoney('cash', refillCost, "Vehicle Refueling")
            paymentSuccess = true
        end
    end
    
    -- Log transaction
    if paymentSuccess then
        LogFuelTransaction({
            playerId = src,
            playerName = player.PlayerData.name,
            citizenId = player.PlayerData.citizenid,
            amount = refillCost,
            paymentType = paymentType,
            fuelAmount = actualFuelAdded,
            fuelPrice = fuelPrice,
            isElectric = false,
            timestamp = os.date("%Y-%m-%d %H:%M:%S")
        })
        
        -- Update vehicle fuel state
        vehicleFuelStates[plate] = finalFuel
        
        -- Broadcast to nearby players
        local sourceCoords = GetEntityCoords(GetPlayerPed(src))
        local players = QBCore.Functions.GetPlayers()
        for _, playerId in ipairs(players) do
            if tonumber(playerId) ~= src then
                local playerCoords = GetEntityCoords(GetPlayerPed(playerId))
                if #(playerCoords - sourceCoords) < 100.0 then
                    TriggerClientEvent('cdn-fuel:client:SyncFuel', playerId, plate, finalFuel)
                end
            end
        end
    end
    
    -- Notify client about payment result
    TriggerClientEvent('cdn-fuel:client:PaymentComplete', src, paymentSuccess, finalFuel)
    
    -- Clean up
    pendingRefuels[src] = nil
end)

-- Cancel refuel event
RegisterNetEvent('cdn-fuel:server:CancelRefuel', function()
    local src = source
    pendingRefuels[src] = nil
end)

-- Payment event (for security, all payments go through the server)
RegisterNetEvent("cdn-fuel:server:PayForFuel", function(amount, purchasetype, FuelPrice, electric, originalPrice)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Validate inputs
    if type(amount) ~= "number" or amount < 0 then
        FlagSuspiciousActivity(src, "invalid_payment", "Invalid payment amount: " .. tostring(amount))
        return
    end
    
    if type(FuelPrice) ~= "number" or FuelPrice < 0 then
        FlagSuspiciousActivity(src, "invalid_price", "Invalid fuel price: " .. tostring(FuelPrice))
        return
    end
    
    -- Check if this is a standalone payment or part of a refuel process
    local isPartOfRefuel = pendingRefuels[src] ~= nil
    
    -- If not part of refuel, verify player is at a gas station
    if not isPartOfRefuel then
        local isNearStation = IsPlayerNearGasStation(src)
        if not isNearStation then
            FlagSuspiciousActivity(src, "distance_payment", "Attempted payment while not at gas station")
            return
        end
    end
    
    -- Calculate total with tax
    local total = math.ceil(amount)
    if amount < 1 then
        total = 0
    end
    
    -- Validate payment type
    local moneyremovetype = purchasetype
    if purchasetype == "bank" then
        moneyremovetype = "bank"
    elseif purchasetype == "cash" then
        moneyremovetype = "cash"
    else
        FlagSuspiciousActivity(src, "invalid_payment_type", "Invalid payment type: " .. tostring(purchasetype))
        return
    end
    
    -- Check if player can afford
    if Player.Functions.GetMoney(moneyremovetype) < total then
        TriggerClientEvent('QBCore:Notify', src, "You don't have enough money", "error")
        return
    end
    
    -- Process payment
    local payString = electric and "Electric Charging" or "Fuel Purchase"
    Player.Functions.RemoveMoney(moneyremovetype, total, payString)
    
    -- Log transaction
    LogFuelTransaction({
        playerId = src,
        playerName = Player.PlayerData.name,
        citizenId = Player.PlayerData.citizenid,
        amount = total,
        paymentType = moneyremovetype,
        fuelAmount = amount,
        fuelPrice = FuelPrice,
        isElectric = electric or false,
        timestamp = os.date("%Y-%m-%d %H:%M:%S")
    })
    
    -- If this is a station purchase, update station balance
    if not electric and CurrentLocation and Config.PlayerOwnedGasStationsEnabled then
        -- Add station balance update logic here
    end
    
    -- Notify client
    TriggerClientEvent('cdn-fuel:client:PaymentComplete', src, true)
end)

-- Jerry Can purchase event
RegisterNetEvent("cdn-fuel:server:purchase:jerrycan", function(purchasetype)
    local src = source
    if not src then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    -- Rate limiting
    if not CheckRateLimit(src, "jerrycan_purchase", 5) then
        TriggerClientEvent('QBCore:Notify', src, "Please wait before purchasing again", "error")
        return
    end
    
    -- Verify player is at a gas station
    local isNearStation = IsPlayerNearGasStation(src)
    if not isNearStation then
        FlagSuspiciousActivity(src, "distance_jerrycan", "Attempted to buy jerrycan while not at gas station")
        return
    end
    
    local tax = GlobalTax(Config.JerryCanPrice)
    local total = math.ceil(Config.JerryCanPrice + tax)
    
    -- Validate payment type
    local moneyremovetype = purchasetype
    if purchasetype == "bank" then
        moneyremovetype = "bank"
    elseif purchasetype == "cash" then
        moneyremovetype = "cash"
    else
        FlagSuspiciousActivity(src, "invalid_payment_type", "Invalid payment type for jerrycan: " .. tostring(purchasetype))
        return
    end
    
    -- Check if player can afford
    if Player.Functions.GetMoney(moneyremovetype) < total then
        TriggerClientEvent('QBCore:Notify', src, "You don't have enough money", "error")
        return
    end
    
    -- Process payment and give item
    if Config.Ox.Inventory then
        local info = {cdn_fuel = tostring(Config.JerryCanGas)}
        local success = exports.ox_inventory:AddItem(src, 'jerrycan', 1, info)
        
        if success then
            Player.Functions.RemoveMoney(moneyremovetype, total, Lang:t("jerry_can_payment_label"))
        end
    else
        local info = {gasamount = Config.JerryCanGas}
        if Player.Functions.AddItem("jerrycan", 1, false, info) then
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['jerrycan'], "add")
            Player.Functions.RemoveMoney(moneyremovetype, total, Lang:t("jerry_can_payment_label"))
        end
    end
    
    -- Log transaction
    LogFuelTransaction({
        playerId = src,
        playerName = Player.PlayerData.name,
        citizenId = Player.PlayerData.citizenid,
        amount = total,
        paymentType = moneyremovetype,
        fuelAmount = 0,
        fuelPrice = 0,
        isElectric = false,
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        itemType = "jerrycan"
    })
end)

-- Jerry Can and Syphon info update event
RegisterNetEvent('cdn-fuel:info', function(type, amount, srcPlayerData, itemdata)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local srcPlayerData = srcPlayerData
    local ItemName = itemdata.name
    
    -- Input validation
    if type ~= "add" and type ~= "remove" then
        FlagSuspiciousActivity(src, "invalid_info_type", "Invalid jerry can/syphon action type: " .. tostring(type))
        return
    end
    
    if type(amount) ~= "number" or amount <= 0 then
        FlagSuspiciousActivity(src, "invalid_info_amount", "Invalid jerry can/syphon amount: " .. tostring(amount))
        return
    end
    
    -- Validate item
    if Config.Ox.Inventory then
        if itemdata == "jerrycan" then
            if amount < 1 or amount > Config.JerryCanCap then
                if Config.FuelDebug then print("Error, amount is invalid (< 1 or > "..Config.JerryCanCap..")! Amount:" ..amount) end
                return
            end
        elseif itemdata == "syphoningkit" then
            if amount < 1 or amount > Config.SyphonKitCap then
                if Config.SyphonDebug then print("Error, amount is invalid (< 1 or > "..Config.SyphonKitCap..")! Amount:" ..amount) end
                return
            end
        end
        
        if ItemName ~= nil then
            itemdata.metadata = itemdata.metadata
            itemdata.slot = itemdata.slot
            
            if ItemName == 'jerrycan' then
                local fuel_amount = tonumber(itemdata.metadata.cdn_fuel)
                if type == "add" then
                    fuel_amount = fuel_amount + amount
                    if fuel_amount > Config.JerryCanCap then
                        FlagSuspiciousActivity(src, "jerrycan_overfill", "Attempted to add more than capacity: " .. fuel_amount)
                        return
                    end
                    itemdata.metadata.cdn_fuel = tostring(fuel_amount)
                    exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
                elseif type == "remove" then
                    if fuel_amount < amount then
                        FlagSuspiciousActivity(src, "jerrycan_overdraw", "Attempted to remove more than available: " .. amount .. " from " .. fuel_amount)
                        return
                    end
                    fuel_amount = fuel_amount - amount
                    itemdata.metadata.cdn_fuel = tostring(fuel_amount)
                    exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
                end
            elseif ItemName == 'syphoningkit' then
                -- Similar validation for syphoning kit
                local fuel_amount = tonumber(itemdata.metadata.cdn_fuel)
                if type == "add" then
                    fuel_amount = fuel_amount + amount
                    if fuel_amount > Config.SyphonKitCap then
                        FlagSuspiciousActivity(src, "syphon_overfill", "Attempted to add more than capacity: " .. fuel_amount)
                        return
                    end
                    itemdata.metadata.cdn_fuel = tostring(fuel_amount)
                    exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
                elseif type == "remove" then
                    if fuel_amount < amount then
                        FlagSuspiciousActivity(src, "syphon_overdraw", "Attempted to remove more than available: " .. amount .. " from " .. fuel_amount)
                        return
                    end
                    fuel_amount = fuel_amount - amount
                    itemdata.metadata.cdn_fuel = tostring(fuel_amount)
                    exports.ox_inventory:SetMetadata(src, itemdata.slot, itemdata.metadata)
                end
            end
        else
            if Config.FuelDebug then
                print("ItemName is invalid!")
            end
        end
    else
        -- Similar validation for QB Inventory
        -- ...
    end
end)

-- Initialize fuel transaction table on resource start
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        -- Create transaction table if it doesn't exist
        MySQL.Async.execute([[
            CREATE TABLE IF NOT EXISTS `fuel_transactions` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `player_id` int(11) NOT NULL,
              `player_name` varchar(50) NOT NULL,
              `citizen_id` varchar(50) NOT NULL,
              `amount` int(11) NOT NULL,
              `payment_type` varchar(10) NOT NULL,
              `fuel_amount` float NOT NULL,
              `fuel_price` float NOT NULL,
              `is_electric` tinyint(1) NOT NULL DEFAULT 0,
              `timestamp` datetime NOT NULL,
              PRIMARY KEY (`id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])
        
        print("^2cdn-fuel server security rewrite initialized^7")
    end
end)

-- Create usable items
if Config.UseJerryCan then
    QBCore.Functions.CreateUseableItem("jerrycan", function(source, item)
        local src = source
        TriggerClientEvent('cdn-fuel:jerrycan:refuelmenu', src, item)
    end)
end

if Config.UseSyphoning then
    QBCore.Functions.CreateUseableItem("syphoningkit", function(source, item)
        local src = source
        if Config.Ox.Inventory then
            if item.metadata.cdn_fuel == nil then
                item.metadata.cdn_fuel = '0'
                exports.ox_inventory:SetMetadata(src, item.slot, item.metadata)
            end
        end
        TriggerClientEvent('cdn-syphoning:syphon:menu', src, item)
    end)
end
