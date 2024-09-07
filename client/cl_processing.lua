local QBCore = exports['qb-core']:GetCoreObject()
-- Charger la langue depuis le fichier config
local lang = Config.Locale or 'en'  -- Utilise la langue configurée
local Translations = LoadResourceFile(GetCurrentResourceName(), 'local/'..lang..'.lua')
local Locale = load(Translations)()
-- Opening Menu for Ordering Ingredients for Multiple Restaurants
Citizen.CreateThread(function()
    for id, restaurant in pairs(Config.Restaurants) do
        if Config.Target == 'qb' then
            exports['qb-target']:AddBoxZone("restaurant_computer_" .. id, restaurant.position, 1.5, 1.5, {
                name = "restaurant_computer_" .. id,
                heading = restaurant.heading,
                debugPoly = false,
                minZ = restaurant.position.z - 1.0,
                maxZ = restaurant.position.z + 1.0,
            }, {
                options = {
                    {
                        type = "client",
                        event = "restaurant:openOrderMenu",
                        icon = 'fas fa-laptop',
                        label = Locale.order_ingredients,
                        restaurantId = id,
                        job = restaurant.job
                    }
                },
                distance = 2.5
            })
        elseif Config.Target == 'ox' then
            exports.ox_target:addBoxZone({
                coords = restaurant.position,
                size = vec3(1.5, 1.5, 1.0),
                rotation = restaurant.heading,
                debug = false,
                options = {
                    {
                        name = "restaurant_computer_" .. id,
                        icon = 'fas fa-laptop',
                        label = Locale.order_ingredients,
                        onSelect = function()
                            TriggerEvent('restaurant:openOrderMenu', {restaurantId = id})
                        end,
                        groups = restaurant.job
                    }
                }
            })
        end
    end
end)

-- Open Order Menu
RegisterNetEvent('restaurant:openOrderMenu')
AddEventHandler('restaurant:openOrderMenu', function(data)
    -- Get the player's job data
    local PlayerData = QBCore.Functions.GetPlayerData()
    local PlayerJob = PlayerData.job

    -- Check if the player is the boss
    if not PlayerJob or not PlayerJob.name or not PlayerJob.isboss then
        lib.notify({
            title = Locale.error_title,
            description = Locale.no_permission,
            type = 'error',
            showDuration = true,
            duration = 10000
        })
        return
    end

    local restaurantId = data.restaurantId or nil

    if type(restaurantId) ~= 'number' and type(restaurantId) ~= 'string' then
        --print("Error: restaurantId is not a number or string.")
        return
    end

    local restaurantJob = Config.Restaurants[restaurantId].job
    local items = Config.Items[restaurantJob] or {}

    -- Function to filter items based on search query
    local function filterItems(query)
        local filteredItems = {}
        for ingredient, details in pairs(items) do
            if details.name and string.find(string.lower(details.name), string.lower(query)) then
                table.insert(filteredItems, {ingredient = ingredient, details = details})
            end
        end
        return filteredItems
    end

    -- Function to create the menu with the option to search
    local function createMenu(searchQuery)
        local options = {}

        -- Add the "View Stock" option
        table.insert(options, {
            title = Locale.view_stock,
            description = Locale.check_stock,
            onSelect = function()
                TriggerServerEvent('restaurant:requestStock', restaurantId)
            end
        })

        -- Add the search button below "View Stock"
        table.insert(options, {
            title = Locale.search_button,
            description = Locale.search_description,
            icon = 'fas fa-search',
            onSelect = function()
                -- Show the input dialog for search
                local input = lib.inputDialog(Locale.search_ingredients_title, {
                    { type = 'input', label = Locale.enter_ingredient_label }
                })

                -- If input is not canceled, filter and re-open the menu
                if input and input[1] then
                    createMenu(input[1])
                end
            end
        })

        -- Filter and sort items based on the current search query
        local filteredItems = filterItems(searchQuery or '')
        table.sort(filteredItems, function(a, b)
            return a.details.name < b.details.name
        end)

        for _, item in ipairs(filteredItems) do
            local ingredient = item.ingredient
            local details = item.details

            table.insert(options, {
                title = details.name,
                description = Locale.price_label .. ": $" .. details.price,  -- Utilisation de la traduction
                onSelect = function()
                    local input = lib.inputDialog(Locale.order_ingredients_title, {  -- Utilisation de la traduction
                        {type = 'number', label = Locale.enter_quantity_label, placeholder = Locale.quantity_placeholder, min = 1, max = 250, required = true}  -- Utilisation de la traduction
                    })

                    if input and input[1] and tonumber(input[1]) > 0 then
                        local quantity = tonumber(input[1])
                        --print("Sending order to server:", ingredient, quantity, restaurantId)
                        TriggerServerEvent('restaurant:orderIngredients', ingredient, quantity, restaurantId)
                    else
                        lib.notify({
                            title = Locale.error_title,  -- Utilisation de la traduction
                            description = Locale.invalid_quantity,  -- Utilisation de la traduction
                            type = 'error',
                            showDuration = true,
                            duration = 10000
                        })
                    end
                end
            })
        end

        lib.registerContext({
            id = 'order_menu',
            title = Locale.order_ingredients_title,  -- Utilisation de la traduction
            options = options
        })

        lib.showContext('order_menu')
    end

    -- Create and show the menu initially without any search query
    createMenu()
end)

-- Display stock details
RegisterNetEvent('restaurant:showResturantStock')
AddEventHandler('restaurant:showResturantStock', function(stock, restaurantId)
    local options = {}

    for ingredient, quantity in pairs(stock) do
        table.insert(options, {
            title = ingredient,
            description = Locale.quantity_label .. ": " .. quantity,  -- Utilisation de la traduction
            onSelect = function()
                local input = lib.inputDialog(Locale.withdraw_stock_title, {  -- Utilisation de la traduction
                    {type = 'number', label = Locale.enter_amount_label, placeholder = Locale.amount_placeholder, min = 1, max = quantity, required = true}  -- Utilisation de la traduction
                })

                if input and input[1] and tonumber(input[1]) > 0 then
                    local amount = tonumber(input[1])
                    TriggerServerEvent('restaurant:withdrawStock', restaurantId, ingredient, amount)
                else
                    lib.notify({
                        title = Locale.error_title,  -- Utilisation de la traduction
                        description = Locale.invalid_amount,  -- Utilisation de la traduction
                        type = 'error',
                        showDuration = true,
                        duration = 10000
                    })
                end
            end
        })
    end

    lib.registerContext({
        id = 'stock_menu',
        title = Locale.current_stock_title,  -- Utilisation de la traduction
        options = options
    })
    lib.showContext('stock_menu')
end)


-- Warehouse Job Handling
Citizen.CreateThread(function()
    for index, warehouse in ipairs(Config.WarehousesLocation) do
        -- Conditional check for the target system (qb-target or ox_target)
        if Config.Target == 'qb' then
            exports['qb-target']:AddBoxZone("warehouse_processing_" .. tostring(index), warehouse.position, 1.5, 1.5, {
                name = "warehouse_processing_" .. tostring(index),
                heading = warehouse.heading,
                debugPoly = false,
                minZ = warehouse.position.z - 1.0,
                maxZ = warehouse.position.z + 1.0,
            }, {
                options = {
                    {
                        type = "client",
                        event = "warehouse:openProcessingMenu",
                        icon = 'fas fa-box',
                        label = Locale.process_orders,
                    }
                },
                distance = 2.5
            })
        elseif Config.Target == 'ox' then
            -- Using ox_target
            exports.ox_target:addBoxZone({
                coords = warehouse.position,
                size = vec3(1.0, 0.5, 3.5),
                rotation = warehouse.heading,
                debug = false,
                options = {
                    {
                        name = "warehouse_processing_" .. tostring(index),
                        icon = 'fas fa-box',
                        label = Locale.process_orders,
                        onSelect = function()
                            TriggerEvent('warehouse:openProcessingMenu')
                        end
                    }
                }
            })
        end

        -- Spawn the ped at each warehouse
        local pedModel = GetHashKey(warehouse.pedhash)
        RequestModel(pedModel)
        while not HasModelLoaded(pedModel) do
            Wait(500) -- Wait until the model is loaded
        end

        local ped = CreatePed(4, pedModel, warehouse.position.x, warehouse.position.y, warehouse.position.z, warehouse.heading, false, true)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetModelAsNoLongerNeeded(pedModel)

        -- Add a blip for the warehouse location
        local blip = AddBlipForCoord(warehouse.position.x, warehouse.position.y, warehouse.position.z)
        SetBlipSprite(blip, 473) -- Choose an appropriate blip sprite (473 for warehouse icon)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.9) -- Adjust size of the blip
        SetBlipColour(blip, 16) -- Set the color of the blip (16 is light blue)
        SetBlipAsShortRange(blip, true) -- Blip only visible at short range

        -- Add a label to the blip
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString('Warehouse')
        EndTextCommandSetBlipName(blip)
    end
end)

-- Open Processing Menu
RegisterNetEvent('warehouse:openProcessingMenu')
AddEventHandler('warehouse:openProcessingMenu', function()
   -- print("Opening main menu")

    local options = {
        {
            title = Locale.view_stock,  -- Utilisation de la traduction
            onSelect = function()
                TriggerServerEvent('warehouse:getStocks')
            end
        },
        {
            title = Locale.view_orders,  -- Utilisation de la traduction
            onSelect = function()
                TriggerServerEvent('warehouse:getPendingOrders')
            end
        }
    }

    -- Register and show the main menu
    lib.registerContext({
        id = 'main_menu',
        title = Locale.warehouse_menu_title,  -- Utilisation de la traduction
        options = options
    })
    lib.showContext('main_menu')
end)

RegisterNetEvent('warehouse:showOrderDetails')
AddEventHandler('warehouse:showOrderDetails', function(orders)
    --print("Orders received:", json.encode(orders))  -- Debug print

    if not orders or #orders == 0 then
        --print("No active orders found.")  -- Debug print
        lib.notify({
            title = Locale.no_orders,  -- Utilisation de la traduction
            description = Locale.no_active_orders,  -- Utilisation de la traduction
            type = 'error',
            showDuration = true,
            duration = 10000
        })
        return
    end

    local options = {}
    for _, order in ipairs(orders) do
        local restaurantId = order.restaurantId
        local restaurantData = Config.Restaurants[restaurantId]
        local restaurantName = restaurantData and restaurantData.name or Locale.unknown_business  -- Utilisation de la traduction

        table.insert(options, {
            title = string.format(Locale.item_quantity, order.itemName, order.quantity),  -- Utilisation de la traduction
            description = string.format(Locale.business_total_cost, restaurantName, order.totalCost),  -- Utilisation de la traduction
            onSelect = function()
                openOrderActionMenu(order, restaurantId)
            end
        })
    end

    lib.registerContext({
        id = 'order_menu',
        title = Locale.active_orders,
        options = options
    })
    lib.showContext('order_menu')
end)

-- Function to open action menu for a selected order
function openOrderActionMenu(order, restaurantId)
    --print(string.format("Opening action menu for Order ID: %d, Restaurant ID: %d", order.id, restaurantId))  -- Debug print
    lib.registerContext({
        id = 'order_action_menu',
        title = Locale.order_actions,  -- Utilisation de la traduction
        options = {
            {
                title = Locale.accept_order,  -- Utilisation de la traduction
                onSelect = function()
                    -- Trigger server event to accept the order
                    TriggerServerEvent('warehouse:acceptOrder', order.id, restaurantId)
                end
            },
            {
                title = Locale.deny_order,  -- Utilisation de la traduction
                onSelect = function()
                    -- Trigger server event to deny the order
                    TriggerServerEvent('warehouse:denyOrder', order.id, restaurantId)
                end
            }
        }
    })
    lib.showContext('order_action_menu')
end

-- Display Stock Details
RegisterNetEvent('restaurant:showStockDetails')
AddEventHandler('restaurant:showStockDetails', function(stock, restaurantId)
    --print("Stock details received:", json.encode(stock))  -- Debug print

    if not stock or next(stock) == nil then
        --print("No stock available.")  -- Debug print
        lib.notify({
            title = Locale.no_stock,  -- Utilisation de la traduction
            description = Locale.no_stock_available,  -- Utilisation de la traduction
            type = 'error',
            showDuration = true,
            duration = 10000
        })
        return
    end

    -- Function to filter stock based on search query and player's inventory
    local function filterStock(query)
        local filteredStock = {}
        local itemNames = exports.ox_inventory:Items()

        for ingredient, quantity in pairs(stock) do
            -- Check if the ingredient matches the query
            if string.find(string.lower(ingredient), string.lower(query)) then
                -- Search player's inventory for the item
                local itemData = itemNames[ingredient]
                if itemData then
                    table.insert(filteredStock, {
                        title = string.format(Locale.ingredient_quantity, itemData.label, quantity)
                    })
                end
            end
        end

        return filteredStock
    end

-- Function to create the menu with the option to search
local function createMenu(searchQuery)
    local options = {}

    -- Add the search button at the top
    table.insert(options, {
        title = Locale.search_button,  -- Utilisation de la traduction
        description = Locale.search_description,  -- Utilisation de la traduction
        icon = 'fas fa-search',
        onSelect = function()
            -- Show the input dialog for search
            local input = lib.inputDialog(Locale.search_stock_title, {  -- Utilisation de la traduction
                { type = 'input', label = Locale.enter_ingredient_label }  -- Utilisation de la traduction
            })

            -- If input is not canceled, filter and re-open the menu
            if input and input[1] then
                createMenu(input[1])
            end
        end
    })

    -- Add the stock items based on the current search query
    local filteredStock = filterStock(searchQuery or '')
    for _, item in ipairs(filteredStock) do
        table.insert(options, item)
    end

    -- Register and show the context menu for stock
    lib.registerContext({
        id = 'stock_menu',
        title = Locale.warehouse_stock_title,  -- Utilisation de la traduction
        options = options
    })
    lib.showContext('stock_menu')
end

-- Create and show the menu initially without any search query
createMenu()
end)

-- Helper function for vector subtraction and distance calculation
function vectorSubtract(v1, v2)
    return vector3(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z)
end

function vectorLength(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Function to get a random inactive warehouse configuration
local function getRandomInactiveWarehouseConfig()
    local availableWarehouses = {}

    -- Collect all available warehouses that are not active
    for index, warehouse in ipairs(Config.Warehouses) do
        if not warehouse.active then
            table.insert(availableWarehouses, index)
        end
    end

    -- If no inactive warehouses are available, return nil
    if #availableWarehouses == 0 then
        print(Locale.no_inactive_warehouses_available)
        return nil
    end

    -- Select a random index from the available warehouses
    local randomIndex = math.random(1, #availableWarehouses)
    local warehouseIndex = availableWarehouses[randomIndex]

    -- Mark the warehouse as active
    Config.Warehouses[warehouseIndex].active = true

    return Config.Warehouses[warehouseIndex], warehouseIndex
end

RegisterNetEvent('warehouse:spawnVehicles')
AddEventHandler('warehouse:spawnVehicles', function(restaurantId, orders)
    -- Get a random inactive warehouse configuration
    local warehouseConfig, warehouseIndex = getRandomInactiveWarehouseConfig()

    if not warehouseConfig then
        print(Locale.no_inactive_warehouse_config)  -- Utilisation de la traduction
        return
    end

    lib.alertDialog({
        header = Locale.welcome_job,  -- Utilisation de la traduction
        content = Locale.delivery_instructions,  -- Utilisation de la traduction
        centered = true,
        cancel = true
    })

    DoScreenFadeOut(2500)
    Citizen.Wait(2500)

    local playerPed = PlayerPedId()
    local notificationShown = false
    local trailerInZoneNotificationShown = false
    local blip
    local markerDrawn = false

    -- Load models
    RequestModel(warehouseConfig.truck.model)
    while not HasModelLoaded(warehouseConfig.truck.model) do
        Citizen.Wait(100)
    end

    RequestModel(warehouseConfig.trailer.model)
    while not HasModelLoaded(warehouseConfig.trailer.model) do
        Citizen.Wait(100)
    end

    -- Spawn truck and trailer
    local truck = CreateVehicle(warehouseConfig.truck.model, warehouseConfig.truck.position.x, warehouseConfig.truck.position.y, warehouseConfig.truck.position.z, warehouseConfig.truck.position.w, true, false)
    local trailer = CreateVehicle(warehouseConfig.trailer.model, warehouseConfig.trailer.position.x, warehouseConfig.trailer.position.y, warehouseConfig.trailer.position.z, warehouseConfig.trailer.position.w, true, false)

    -- Retrieve plates for the vehicles
    local truckPlate = GetVehicleNumberPlateText(truck)
    local trailerPlate = GetVehicleNumberPlateText(trailer)

    -- Set the owner for the vehicles
    TriggerEvent("vehiclekeys:client:SetOwner", truckPlate)
    TriggerEvent("vehiclekeys:client:SetOwner", trailerPlate)

    -- Attach trailer to truck
    AttachVehicleToTrailer(truck, trailer, 50)

    DoScreenFadeIn(2500)

    -- Create Blip for Delivery Marker
    blip = AddBlipForCoord(warehouseConfig.deliveryMarker.position.x, warehouseConfig.deliveryMarker.position.y, warehouseConfig.deliveryMarker.position.z)
    SetBlipSprite(blip, 1)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(Locale.delivery_area)  -- Utilisation de la traduction
    EndTextCommandSetBlipName(blip)

    lib.notify({
        title = Locale.vehicles_spawned,  -- Utilisation de la traduction
        description = Locale.spawned_description,  -- Utilisation de la traduction
        type = 'success',
        showDuration = true,
        duration = 10000
    })

    TaskWarpPedIntoVehicle(playerPed, truck, -1)

    -- Create a thread to manage the delivery process
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)  -- Adjust the wait time to 1000ms (1 second)

            local trailerCoords = GetEntityCoords(trailer)
            local trailerBack = GetOffsetFromEntityInWorldCoords(trailer, 0.0, -5.0, 0.0)
            local distToMarker = Vdist(trailerBack, warehouseConfig.deliveryMarker.position)

            DrawMarker(1, warehouseConfig.deliveryMarker.position.x, warehouseConfig.deliveryMarker.position.y, warehouseConfig.deliveryMarker.position.z, 0, 0, 0, 0, 0, 0, warehouseConfig.deliveryMarker.radius, warehouseConfig.deliveryMarker.radius, 1.0, 0, 255, 0, 100, false, true, 2, false, nil, nil, false)

            -- Check if trailer is stopped within the marker area
            if distToMarker < warehouseConfig.deliveryMarker.radius and GetEntitySpeed(trailer) < 0.1 then
                if not notificationShown then
                    lib.notify({
                        title = Locale.trailer_in_marker,  -- Utilisation de la traduction
                        description = Locale.trailer_stopped_description,  -- Utilisation de la traduction
                        type = 'success',
                        showDuration = true,
                        duration = 10000
                    })
                    notificationShown = true

                    -- Remove the marker by setting markerDrawn to false
                    markerDrawn = false

                    -- Trigger the loading with forklift event
                    TriggerEvent('warehouse:loadingWithForklift', warehouseConfig.trailer, warehouseConfig.deliveryMarker, truck, restaurantId, orders, trailer)
                    break
                end
            end

            -- Notify when the trailer is in the zone
            if not trailerInZoneNotificationShown and GetPedInVehicleSeat(truck, -1) == playerPed and distToMarker < warehouseConfig.deliveryMarker.radius then
                lib.notify({
                    title = Locale.trailer_in_zone,  -- Utilisation de la traduction
                    description = Locale.trailer_in_zone_description,  -- Utilisation de la traduction
                    type = 'success',
                    showDuration = true,
                    duration = 10000
                })
                trailerInZoneNotificationShown = true
            end

            -- Remove the blip when the player is close to the delivery zone
            if distToMarker < warehouseConfig.deliveryMarker.radius and blip then
                RemoveBlip(blip)
                blip = nil
            end
        end
    end)
end)

-- Warehouse loading event
RegisterNetEvent('warehouse:loadingWithForklift')
AddEventHandler('warehouse:loadingWithForklift', function(trailerConfig, deliveryMarkerConfig, truck, restaurantId, orders, trailer)

    --print('Trailer:'.. trailer)
    lib.alertDialog({
        header = Locale.nice_job,  -- Utilisation de la traduction
        content = Locale.truck_ready_content,  -- Utilisation de la traduction
        centered = true,
        cancel = true
    })
    DoScreenFadeOut(2500)
    Citizen.Wait(2500)

    local playerPed = PlayerPedId()
    local forklift
    local pallets = {}
    local palletIndex = 1
    local allPalletsLoaded = false
    local warehouseConfig = nil
    local playerPos = GetEntityCoords(playerPed)

    -- Find the nearest warehouse based on the player's position
    for _, warehouse in ipairs(Config.Warehouses) do
        local warehousePos = warehouse.forkliftPosition
        local distance = vectorLength(vectorSubtract(playerPos, warehousePos))
        if distance < 50.0 then
            warehouseConfig = warehouse
            break
        end
    end

    if not warehouseConfig then
        lib.notify({
            title = Locale.error_title,  -- Utilisation de la traduction
            description = Locale.no_warehouse_found,  -- Utilisation de la traduction
            type = 'error',
            showDuration = true,
            duration = 10000
        })
        return
    end

    -- Spawn the forklift
    RequestModel('forklift')
    while not HasModelLoaded('forklift') do
        Citizen.Wait(100)
    end

    forklift = CreateVehicle('forklift', warehouseConfig.forkliftPosition.x, warehouseConfig.forkliftPosition.y, warehouseConfig.forkliftPosition.z, warehouseConfig.heading, true, false)
    TaskWarpPedIntoVehicle(playerPed, forklift, -1)
    DoScreenFadeIn(2500)

    lib.notify({
        title = Locale.forklift_spawned,  -- Utilisation de la traduction
        description = Locale.forklift_spawned_description,  -- Utilisation de la traduction
        type = 'success',
        showDuration = true,
        duration = 10000
    })

    -- Blip for forklift return position
    local forkliftReturnBlip = AddBlipForCoord(warehouseConfig.forkliftPosition.x, warehouseConfig.forkliftPosition.y, warehouseConfig.forkliftPosition.z)
    SetBlipSprite(forkliftReturnBlip, 2)
    SetBlipDisplay(forkliftReturnBlip, 4)
    SetBlipScale(forkliftReturnBlip, 1.0)
    SetBlipColour(forkliftReturnBlip, 1)
    SetBlipAsShortRange(forkliftReturnBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Forklift Return")
    EndTextCommandSetBlipName(forkliftReturnBlip)

    -- Blip for truck location
    local truckBlip = AddBlipForCoord(deliveryMarkerConfig.position.x, deliveryMarkerConfig.position.y, deliveryMarkerConfig.position.z)
    SetBlipSprite(truckBlip, 1)
    SetBlipDisplay(truckBlip, 4)
    SetBlipScale(truckBlip, 1.0)
    SetBlipColour(truckBlip, 3)
    SetBlipAsShortRange(truckBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Truck Location")
    EndTextCommandSetBlipName(truckBlip)

    -- Blips for pallet locations
    local palletBlips = {}
    for _, pos in ipairs(warehouseConfig.pallets) do
        local palletBlip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(palletBlip, 1)
        SetBlipDisplay(palletBlip, 4)
        SetBlipScale(palletBlip, 0.7)
        SetBlipColour(palletBlip, 4)
        SetBlipAsShortRange(palletBlip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Pallet Location")
        EndTextCommandSetBlipName(palletBlip)
        table.insert(palletBlips, palletBlip)
    end

    lib.notify({
        title = Locale.pallets_spawned,  -- Utilisation de la traduction
        description = Locale.pallets_spawned_description,  -- Utilisation de la traduction
        type = 'success',
        showDuration = true,
        duration = 10000
    })

    -- Spawn the pallets
    for _, pos in ipairs(warehouseConfig.pallets) do
        local palletModel = GetHashKey('prop_boxpile_06b')
        RequestModel(palletModel)
        while not HasModelLoaded(palletModel) do
            Citizen.Wait(100)
        end

        local pallet = CreateObject(palletModel, pos.x, pos.y, pos.z, true, true, true)
        if pallet then
            table.insert(pallets, pallet)
        else
            print(string.format(Locale.failed_to_spawn_pallet, pos.x, pos.y, pos.z))  -- Utilisation de la traduction
        end
    end

    -- Main loop for pallet loading
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)

            -- Draw markers for forklift return and delivery zones
            DrawMarker(1, warehouseConfig.forkliftPosition.x, warehouseConfig.forkliftPosition.y, warehouseConfig.forkliftPosition.z - 1.0, 0, 0, 0, 0, 0, 0, 2.0, 2.0, 1.0, 255, 0, 0, 100, false, true, 2, false, nil, nil, false)
            DrawMarker(1, deliveryMarkerConfig.position.x, deliveryMarkerConfig.position.y, deliveryMarkerConfig.position.z, 0, 0, 0, 0, 0, 0, deliveryMarkerConfig.radius, deliveryMarkerConfig.radius, 1.0, 0, 255, 0, 100, false, true, 2, false, nil, nil, false)

            -- Handle pallet loading
            if allPalletsLoaded then
                -- Forklift return handling
                local forkliftPos = GetEntityCoords(forklift)
                local forkliftZoneDist = vectorLength(vectorSubtract(forkliftPos, warehouseConfig.forkliftPosition))
                if forkliftZoneDist < 3.0 then
                    lib.showTextUI('[E] ' .. Locale.return_forklift)  -- Utilisation de la traduction
                    if IsControlJustReleased(0, 38) then
                        lib.hideTextUI()
                        if lib.progressCircle({
                            duration = 5000,
                            position = 'bottom',
                            label = Locale.returning_forklift,  -- Utilisation de la traduction
                            canCancel = false,
                            disable = { move = true, car = true, combat = true, sprint = true },
                            anim = { dict = 'anim@scripted@heist@ig3_button_press@male@', clip = 'button_press' }
                        }) then
                            if DoesEntityExist(forklift) then
                                DeleteVehicle(forklift)
                                if not DoesEntityExist(forklift) then
                                    lib.notify({
                                        title = Locale.forklift_returned_title,  -- Utilisation de la traduction
                                        description = Locale.forklift_returned_description,  -- Utilisation de la traduction
                                        type = 'success',
                                        showDuration = true,
                                        duration = 10000
                                    })
                                    TriggerEvent('warehouse:startDelivery', restaurantId, truck, orders, trailer)
                                    RemoveBlip(forkliftReturnBlip)
                                    RemoveBlip(truckBlip)
                                    for _, blip in ipairs(palletBlips) do
                                        RemoveBlip(blip)
                                    end
                                    return
                                end
                            end
                        end
                    end
                else
                    lib.hideTextUI()
                end
            end

            -- Check for pallet loading
            if #pallets > 0 then
                for _, pallet in ipairs(pallets) do
                    local palletPos = GetEntityCoords(pallet)
                    local dist = vectorLength(vectorSubtract(palletPos, GetEntityCoords(forklift)))
                    local deliveryZoneDist = vectorLength(vectorSubtract(GetEntityCoords(forklift), deliveryMarkerConfig.position))

                    if dist < 3.0 and deliveryZoneDist < deliveryMarkerConfig.radius then
                        lib.showTextUI('[E] ' .. Locale.load_pallet)  -- Utilisation de la traduction
                        if IsControlJustReleased(0, 38) then
                            lib.hideTextUI()
                            if lib.progressCircle({
                                duration = 5000,
                                position = 'bottom',
                                label = Locale.loading_pallet,  -- Utilisation de la traduction
                                canCancel = false,
                                disable = { move = true, car = true, combat = true, sprint = true },
                                anim = { dict = 'anim@scripted@heist@ig3_button_press@male@', clip = 'button_press' }
                            }) then
                                DeleteEntity(pallet)
                                palletIndex = palletIndex + 1
                                if palletIndex > #pallets then
                                    allPalletsLoaded = true
                                    lib.notify({
                                        title = Locale.all_pallets_loaded_title,  -- Utilisation de la traduction
                                        description = Locale.all_pallets_loaded_description,  -- Utilisation de la traduction
                                        type = 'success',
                                        showDuration = true,
                                        duration = 10000
                                    })
                                else
                                    lib.notify({
                                        title = Locale.pallet_loaded_title,  -- Utilisation de la traduction
                                        description = Locale.pallet_loaded_description,  -- Utilisation de la traduction
                                        type = 'success',
                                        showDuration = true,
                                        duration = 10000
                                    })
                                end
                            end
                        end
                    else
                        lib.hideTextUI()
                    end
                end
            end
        end
    end)
end)

-- If you're reading my code, fuck off thank you
RegisterNetEvent('warehouse:startDelivery')
AddEventHandler('warehouse:startDelivery', function(restaurantId, truck, orders, trailer)
    lib.alertDialog({
        header = Locale.amazing_work,  -- Utilisation de la traduction
        content = Locale.truck_loaded_content,  -- Utilisation de la traduction
        centered = true,
        cancel = true
    })

    --print("Received orders:", json.encode(orders))
    --print(restaurantId)

    local deliveryPosition = Config.Restaurants[restaurantId].delivery

    -- Notify the player to start the delivery
    lib.notify({
        title = Locale.delivery_started_title,  -- Utilisation de la traduction
        description = Locale.delivery_started_description,  -- Utilisation de la traduction
        type = 'success',
        showDuration = true,
        duration = 10000
    })

    -- Set GPS route to the delivery location
    SetNewWaypoint(deliveryPosition.x, deliveryPosition.y)

    -- Add a blip to the delivery location
    local blip = AddBlipForCoord(deliveryPosition.x, deliveryPosition.y, deliveryPosition.z)
    SetBlipSprite(blip, 1) -- Choose a blip sprite ID as needed
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 3) -- Choose a blip color as needed
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Delivery Location")
    EndTextCommandSetBlipName(blip)

    -- Monitor the truck's location and trigger the delivery process when the destination is reached
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            local truckPos = GetEntityCoords(truck)
            local distToDelivery = #(truckPos - vector3(deliveryPosition.x, deliveryPosition.y, deliveryPosition.z))

            -- Check if the truck is within 10 meters of the delivery position
            if distToDelivery < 10.0 then
                -- Draw a marker at the delivery position
                DrawMarker(
                    1, -- Type of the marker (1 = Cylinder)
                    deliveryPosition.x, deliveryPosition.y, deliveryPosition.z - 1.0,
                    0, 0, 0, -- Rotation (not used)
                    0, 0, 0, -- Direction (not used)
                    4.0, 4.0, 1.0, -- Width, Height, and Depth
                    255, 0, 0, 150, -- Color and Alpha (increased transparency for better visibility)
                    false, true, 2, -- Upwards, face camera, draw on entities
                    false, nil, nil, false
                )
                -- Trigger the event to deliver boxes
                TriggerEvent('warehouse:deliverBoxes', restaurantId, truck, orders, trailer)
                -- Remove the blip as delivery is completed
                RemoveBlip(blip)
                break
            else
                -- Draw a marker at the delivery position even if not close
                DrawMarker(
                    1, -- Type of the marker (1 = Cylinder)
                    deliveryPosition.x, deliveryPosition.y, deliveryPosition.z - 1.0,
                    0, 0, 0, -- Rotation (not used)
                    0, 0, 0, -- Direction (not used)
                    4.0, 4.0, 1.0, -- Width, Height, and Depth
                    0, 255, 0, 150, -- Color (green) and Alpha (increased transparency for better visibility)
                    false, true, 2, -- Upwards, face camera, draw on entities
                    false, nil, nil, false
                )
            end
        end
    end)
end)

RegisterNetEvent('warehouse:deliverBoxes')
AddEventHandler('warehouse:deliverBoxes', function(restaurantId, truck, orders, trailer)
    lib.alertDialog({
        header = Locale.wow,  -- Utilisation de la traduction
        content = Locale.arrived_grab_boxes,  -- Utilisation de la traduction
        centered = true,
        cancel = true
    })

    local playerPed = PlayerPedId()
    local deliveryFootPosition = Config.Restaurants[restaurantId].deliveryFoot
    local trailerCoords = GetEntityCoords(trailer)
    local trailerHeading = GetEntityHeading(trailer)

    -- Calculate the position at the back of the trailer based on its heading
    local trailerBackPosition = vector3(
        trailerCoords.x - math.sin(math.rad(trailerHeading)) * 5.0,
        trailerCoords.y + math.cos(math.rad(trailerHeading)) * 5.0,
        trailerCoords.z - 1.0  -- Move slightly down
    )

    local boxCount = 0
    local maxBoxes = Config.maxBoxes
    local hasBox = false
    local boxProp = nil
    local palletProp = nil

    -- Notify the player that they can start delivering boxes
    lib.notify({
        title = Locale.delivery_location_reached,  -- Utilisation de la traduction
        description = Locale.pick_up_boxes,  -- Utilisation de la traduction
        type = 'success',
        showDuration = true,
        duration = 10000
    })

    -- Draw markers and handle pickup and delivery
    Citizen.CreateThread(function()
        -- Create a pallet prop at the trailer back position
        local palletModel = GetHashKey('prop_boxpile_06b')  -- Change to appropriate pallet model
        RequestModel(palletModel)
        while not HasModelLoaded(palletModel) do
            Citizen.Wait(0)
        end

        palletProp = CreateObject(palletModel, trailerBackPosition.x, trailerBackPosition.y, trailerBackPosition.z, true, true, true)
        PlaceObjectOnGroundProperly(palletProp)

        while true do
            Citizen.Wait(0)

            -- Draw marker for trailer back location
            DrawMarker(
                1,
                trailerBackPosition.x, trailerBackPosition.y, trailerBackPosition.z - 1.0,
                0, 0, 0,
                0, 0, 0,
                0.8, 0.8, 1.0,
                255, 0, 0, 100,
                false, true, 2,
                false, nil, nil, false
            )

            -- Draw marker for delivery spot
            DrawMarker(
                1,
                deliveryFootPosition.x, deliveryFootPosition.y, deliveryFootPosition.z - 0.1,
                0, 0, 0,
                0, 0, 0,
                0.8, 0.8, 1.0,
                0, 255, 0, 100,
                false, true, 2,
                false, nil, nil, false
            )

            local playerCoords = GetEntityCoords(playerPed)

            -- Check if player is near the box pickup location
            if #(playerCoords - trailerBackPosition) < 2.0 then
                if not hasBox then
                    -- Show the text UI for picking up the box
                    lib.showTextUI('[E] ' .. Locale.pick_up_box)  -- Utilisation de la traduction
                end

                if IsControlJustReleased(0, 38) then -- E key
                    -- Hide the text UI when the action starts
                    lib.hideTextUI()

                    -- Start progress circle for picking up the box
                    if lib.progressCircle({
                        duration = 3000, -- 3 seconds to pick up a box
                        position = 'bottom',
                        label = Locale.unloading_box,  -- Utilisation de la traduction
                        canCancel = false,
                        disable = {
                            move = true,
                            car = true,
                            combat = true,
                            sprint = true,
                        },
                        anim = {
                            dict = 'mini@repair',
                            clip = 'fixing_a_ped'
                        }
                    }) then
                        -- Create a box prop and attach it to the player
                        local model = GetHashKey(Config.CarryBoxProp)
                        RequestModel(model)
                        while not HasModelLoaded(model) do
                            Citizen.Wait(0)
                        end

                        local coords = GetEntityCoords(playerPed)
                        boxProp = CreateObject(model, coords.x, coords.y, coords.z, true, true, true)

                        -- Attach the box to the player's hand (bone index 60309)
                        AttachEntityToEntity(boxProp, playerPed, GetPedBoneIndex(playerPed, 60309),
                            0.1, 0.2, 0.25,  -- Position offsets
                            -90.0, 0.0, 0.0,  -- Rotation
                            true, true, false, true, 1, true
                        )

                        -- Set flag indicating the player has a box
                        hasBox = true

                        -- Play the carrying animation
                        local animDict = "anim@heists@box_carry@"
                        local animName = "idle"
                        RequestAnimDict(animDict)
                        while not HasAnimDictLoaded(animDict) do
                            Citizen.Wait(0)
                        end

                        TaskPlayAnim(playerPed, animDict, animName, 8.0, -8.0, -1, 50, 0, false, false, false)

                        -- Notify player to deliver the box
                        lib.notify({
                            title = Locale.box_picked_up,  -- Utilisation de la traduction
                            description = Locale.deliver_box_description,  -- Utilisation de la traduction
                            type = 'info',
                            showDuration = true,
                            duration = 10000
                        })
                    end
                end
            elseif hasBox then
                -- Hide the text UI if the player is not in range and has a box
                lib.hideTextUI()
            end

            -- Check if player is near the delivery location
            if #(playerCoords - deliveryFootPosition) < 2.0 and hasBox then
                -- Show the text UI for delivering the box
                lib.showTextUI('[E] ' .. Locale.deliver_box)  -- Utilisation de la traduction

                if IsControlJustReleased(0, 38) then -- E key
                    -- Hide the text UI when the action starts
                    lib.hideTextUI()

                    -- Start progress circle for delivering the box
                    if lib.progressCircle({
                        duration = 3000, -- 3 seconds to deliver the box
                        position = 'bottom',
                        label = Locale.delivering_package,  -- Utilisation de la traduction
                        canCancel = false,
                        disable = {
                            move = true,
                            car = true,
                            combat = true,
                            sprint = true,
                        },
                        anim = {
                            dict = 'mini@repair',
                            clip = 'fixing_a_ped'
                        }
                    }) then
                        -- Remove the box prop and reset the state
                        if boxProp then
                            DeleteObject(boxProp)
                            boxProp = nil
                        end
                        hasBox = false
                        boxCount = boxCount + 1

                        -- Clear animation
                        ClearPedTasks(playerPed)

                        -- Notify player to return and pick up the next box
                        lib.notify({
                            title = Locale.box_delivered,  -- Utilisation de la traduction
                            description = Locale.return_to_truck,  -- Utilisation de la traduction
                            type = 'success',
                            showDuration = true,
                            duration = 10000
                        })

                        -- Check if all boxes are delivered
                        if boxCount >= maxBoxes then
                            -- Notify player that delivery is complete
                            lib.notify({
                                title = Locale.delivery_complete,  -- Utilisation de la traduction
                                description = Locale.return_truck_to_warehouse,  -- Utilisation de la traduction
                                type = 'success',
                                showDuration = true,
                                duration = 10000
                            })

                            -- Remove the pallet prop
                            if palletProp then
                                DeleteObject(palletProp)
                                palletProp = nil
                            end

                            -- Trigger the event to return the truck
                            TriggerEvent('warehouse:returnTruck', truck, restaurantId, orders)

                            -- Break out of the loop once the delivery is complete
                            break
                        end
                    end
                end
            elseif hasBox then
                -- Hide the text UI if the player is not in range and has a box
                lib.hideTextUI()
            end
        end
    end)
end)

-- returning the truck
RegisterNetEvent('warehouse:returnTruck')
AddEventHandler('warehouse:returnTruck', function(truck, restaurantId, orders)
    lib.alertDialog({
        header = Locale.delivery_complete_header,  -- Utilisation de la traduction
        content = Locale.drive_back_to_warehouse,  -- Utilisation de la traduction
        centered = true,
        cancel = true
    })
    --print("Received orders:", json.encode(orders))
    local playerPed = PlayerPedId()
    local truckReturnPosition = vector3(Config.Warehouses[1].truck.position.x, Config.Warehouses[1].truck.position.y, Config.Warehouses[1].truck.position.z)

    -- Set GPS route to the truck return location
    SetNewWaypoint(truckReturnPosition.x, truckReturnPosition.y)

    -- Add a blip to the truck return location
    local blip = AddBlipForCoord(truckReturnPosition.x, truckReturnPosition.y, truckReturnPosition.z)
    SetBlipSprite(blip, 1) -- Choose a blip sprite ID as needed
    SetBlipScale(blip, 1.0)
    SetBlipColour(blip, 3) -- Choose a blip color as needed
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Truck Return Location")
    EndTextCommandSetBlipName(blip)

    -- Draw marker and handle truck return
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)

            -- Draw marker for truck return location
            DrawMarker(
                1,
                truckReturnPosition.x, truckReturnPosition.y, truckReturnPosition.z - 1.0,
                0, 0, 0,
                0, 0, 0,
                1.5, 1.5, 1.0,
                0, 255, 255, 100,
                false, true, 2,
                false, nil, nil, false
            )

            -- Check if player is near the truck return location
            local playerPos = GetEntityCoords(playerPed)
            local distanceToReturnPos = #(playerPos - vector3(truckReturnPosition.x, truckReturnPosition.y, truckReturnPosition.z))

            if distanceToReturnPos < 2.0 and IsPedInVehicle(playerPed, truck, false) then
                -- Show the text UI for returning the truck
                lib.showTextUI(Locale.press_return_truck)  -- Utilisation de la traduction

                if IsControlJustReleased(0, 38) then -- E key
                    -- Hide the text UI when the action starts
                    lib.hideTextUI()

                    -- Start progress circle for returning the truck
                    if lib.progressCircle({
                        duration = 3000, -- 3 seconds to return the truck
                        position = 'bottom',
                        label = Locale.returning_truck_trailer,  -- Utilisation de la traduction
                        canCancel = false,
                        disable = {
                            move = true,
                            car = true,
                            combat = true,
                            sprint = true,
                        },
                        anim = {
                            dict = 'anim@scripted@heist@ig3_button_press@male@',
                            clip = 'button_press'
                        }
                    }) then

                        lib.alertDialog({
                            header = Locale.truck_returned_header,  -- Utilisation de la traduction
                            content = Locale.truck_returned_content,  -- Utilisation de la traduction
                            centered = true,
                            cancel = true
                        })

                        -- Remove blip and marker
                        RemoveBlip(blip)

                        -- Delete the truck
                        DeleteVehicle(truck)

                        -- Trigger server event to update stock
                        TriggerServerEvent('update:stock', restaurantId, orders) -- 'all' for all ingredients or specify ingredient

                        -- Break out of the loop once the truck is returned
                        break
                    end
                end
            else
                -- Hide the text UI if the player is not in range
                lib.hideTextUI()
            end
        end
    end)
end)

-- DrawText3D Function
function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(0)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end
