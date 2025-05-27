Config = {}

-- Debug Settings
Config.FuelDebug = false
Config.ZoneDebug = false 

-- Core Settings
Config.LeaveEngineRunning = false
Config.VehicleBlowUp = true
Config.BlowUpChance = 5 
Config.CostMultiplier = 3 
Config.GlobalTax = 15.0
Config.FuelNozzleExplosion = false
Config.FuelDecor = "_FUEL_LEVEL"
Config.RefuelTime = 600
Config.ShowNearestGasStationOnly = true

-- Framework Selection
Config.CoreResource = 'qb-core'
Config.UseOxInventory = true
Config.FuelTargetExport = false

-- Fuel Pump Models
Config.FuelPumpModels = {
    'prop_gas_pump_1d',
    'prop_gas_pump_1a',
    'prop_gas_pump_1b',
    'prop_gas_pump_1c',
    'prop_vintage_pump',
    'prop_gas_pump_old2',
    'prop_gas_pump_old3',
    'denis3d_prop_gas_pump'
}

-- Rope Configuration
Config.PumpHose = true
Config.RopeType = {
    ['fuel'] = 1,
    ['electric'] = 1,
}

-- Vehicle Configuration
Config.FaceTowardsVehicle = true
Config.VehicleShutoffOnLowFuel = {
    ['shutOffLevel'] = 0,
    ['sounds'] = {
        ['enabled'] = true,
        ['audio_bank'] = "DLC_PILOT_ENGINE_FAILURE_SOUNDS",
        ['sound'] = "Landing_Tone",
    }
}

-- Payment System
Config.RenewedPhonePayment = false

-- Jerry Can Settings
Config.UseJerryCan = true
Config.JerryCanCap = 50
Config.JerryCanPrice = 200
Config.JerryCanGas = 25

-- Syphoning Settings
Config.UseSyphoning = true
Config.SyphonDebug = false
Config.SyphonKitCap = 50
Config.SyphonPoliceCallChance = 25

-- Animation Dictionaries
Config.StealAnimDict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@'
Config.StealAnim = 'machinic_loop_mechandplayer'
Config.JerryCanAnimDict = 'weapon@w_sp_jerrycan'
Config.JerryCanAnim = 'fire'
Config.RefuelAnimation = "gar_ig_5_filling_can"
Config.RefuelAnimationDictionary = "timetable@gardener@filling_can"

-- Player Owned Gas Stations
Config.PlayerOwnedGasStationsEnabled = true
Config.StationFuelSalePercentage = 0.65
Config.EmergencyShutOff = true
Config.UnlimitedFuel = false
Config.MaxFuelReserves = 100000
Config.FuelReservesPrice = 2.0
Config.GasStationSellPercentage = 50
Config.MinimumFuelPrice = 2
Config.MaxFuelPrice = 8
Config.PlayerControlledFuelPrices = true
Config.GasStationNameChanges = true
Config.NameChangeMinChar = 10
Config.NameChangeMaxChar = 25
Config.WaitTime = 400
Config.OneStationPerPerson = true

-- Fuel Pickup Configuration
Config.OwnersPickupFuel = true
Config.PossibleDeliveryTrucks = {
    "hauler",
    "phantom",
    "packer",
}
Config.DeliveryTruckSpawns = {
    ['trailer'] = vector4(1724.0, -1649.7, 112.57, 194.24),
    ['truck'] = vector4(1727.08, -1664.01, 112.62, 189.62),
    ['PolyZone'] = {
        ['coords'] = {
            vector2(1724.62, -1672.36),
            vector2(1719.01, -1648.33),
            vector2(1730.99, -1645.62),
            vector2(1734.42, -1673.32),
        },
        ['minz'] = 110.0,
        ['maxz'] = 115.0,
    }
}

-- Electric Vehicle Settings
Config.ElectricVehicleCharging = true
Config.ElectricChargingPrice = 4
Config.ElectricSprite = 620
Config.ElectricChargerModel = true
Config.ElectricVehicles = {
    ["surge"] = { isElectric = true },
    ["iwagen"] = { isElectric = true },
    ["voltic"] = { isElectric = true },
    ["voltic2"] = { isElectric = true },
    ["raiden"] = { isElectric = true },
    ["cyclone"] = { isElectric = true },
    ["tezeract"] = { isElectric = true },
    ["neon"] = { isElectric = true },
    ["omnisegt"] = { isElectric = true },
    ["caddy"] = { isElectric = true },
    ["caddy2"] = { isElectric = true },
    ["caddy3"] = { isElectric = true },
    ["airtug"] = { isElectric = true },
    ["rcbandito"] = { isElectric = true },
    ["imorgon"] = { isElectric = true },
    ["dilettante"] = { isElectric = true },
    ["khamelion"] = { isElectric = true },
}

-- Emergency Services Discount
Config.EmergencyServicesDiscount = {
    ['enabled'] = true,
    ['discount'] = 25,
    ['emergency_vehicles_only'] = true,
    ['ondutyonly'] = true,
    ['job'] = {
        "police",
        "sasp",
        "trooper",
        "ambulance",
    }
}

-- Air and Water Vehicle Fueling
Config.AirAndWaterVehicleFueling = {
    ['enabled'] = true,
    ['refuel_button'] = 47, -- G key
    ['nozzle_length'] = 20.0,
    ['air_fuel_price'] = 10,
    ['water_fuel_price'] = 4,
    ['interaction_type'] = 'target', -- 'textui', 'target', or 'both'
    ['locations'] = {
        -- MRPD Helipad
        [1] = {
            ['zone'] = {
                ['points'] = {
                    vec3(439.96, -973.0, 43.0),
                    vec3(458.09, -973.04, 43.0),
                    vec3(458.26, -989.47, 43.0),
                    vec3(439.58, -989.94, 43.0)
                },
                ['thickness'] = 10.0
            },
            ['draw_text'] = "[G] Refuel Helicopter",
            ['type'] = 'air',
            ['whitelist'] = {
                ['enabled'] = true,
                ['on_duty_only'] = true,
                ['whitelisted_jobs'] = {
                    'police', 'ambulance'
                },
            },
            ['prop'] = {
                ['model'] = 'prop_gas_pump_1d',
                ['coords'] = vector4(455.38, -977.15, 42.69, 269.52),
            }
        },
        -- Add more locations as needed
    }
}

-- Vehicle Blacklist
Config.NoFuelUsage = {
    ["bmx"] = { blacklisted = true }
}

-- Vehicle Class Configuration
Config.Classes = {
    [0] = 1.0, -- Compacts
    [1] = 1.0, -- Sedans
    [2] = 1.0, -- SUVs
    [3] = 1.0, -- Coupes
    [4] = 1.0, -- Muscle
    [5] = 1.0, -- Sports Classics
    [6] = 1.0, -- Sports
    [7] = 1.0, -- Super
    [8] = 1.0, -- Motorcycles
    [9] = 1.0, -- Off-road
    [10] = 1.0, -- Industrial
    [11] = 1.0, -- Utility
    [12] = 1.0, -- Vans
    [13] = 0.0, -- Cycles
    [14] = 1.0, -- Boats
    [15] = 1.0, -- Helicopters
    [16] = 1.0, -- Planes
    [17] = 1.0, -- Service
    [18] = 1.0, -- Emergency
    [19] = 1.0, -- Military
    [20] = 1.0, -- Commercial
    [21] = 1.0, -- Trains
}

-- Fuel Consumption Configuration
Config.FuelUsage = {
    [1.0] = 1.3,
    [0.9] = 1.1,
    [0.8] = 0.9,
    [0.7] = 0.8,
    [0.6] = 0.7,
    [0.5] = 0.5,
    [0.4] = 0.3,
    [0.3] = 0.2,
    [0.2] = 0.1,
    [0.1] = 0.1,
    [0.0] = 0.0,
}

-- Gas Station Configurations
Config.GasStations = {
    [1] = {
        zones = {
            vector2(176.89, -1538.26),
            vector2(151.52, -1560.98),
            vector2(168.56, -1577.65),
            vector2(196.97, -1563.64)
        },
        minz = 28.2,
        maxz = 30.3,
        pedmodel = "a_m_m_indian_01",
        cost = 100000,
        shutoff = false,
        pedcoords = {
            x = 167.06,
            y = -1553.56,
            z = 28.26,
            h = 220.44,
        },
        electricchargercoords = vector4(175.9, -1546.65, 28.26, 224.29),
        label = "Davis Avenue Ron",
    },
    -- Add more stations as needed
}

-- Profanity Filter
Config.ProfanityList = {
    "badword1",
    "badword2",
    -- add more as needed
}