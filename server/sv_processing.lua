local QBCore = exports['qb-core']:GetCoreObject()
local lang = Config.Locale or 'en'  -- Utilise la langue configurée
local Translations = LoadResourceFile(GetCurrentResourceName(), 'locales/'..lang..'.lua')
local Locale = load(Translations)()

-- Handle Order Submission
RegisterNetEvent('restaurant:orderIngredients')
AddEventHandler('restaurant:orderIngredients', function(ingredient, quantity, restaurantId)
    local playerId = source

    -- Ensure quantity is a number and playerId is valid
    quantity = tonumber(quantity)
    if not quantity or quantity <= 0 then
        TriggerClientEvent('ox_lib:notify', playerId, {
            title = Locale.order_error,  -- Utilisation de la traduction
            description = Locale.invalid_quantity_provided,  -- Utilisation de la traduction
            type = 'error',
            showDuration = true,
            duration = 10000
        })
        return
    end

    -- Fetch restaurant-specific items based on the restaurantId
    local restaurantJob = Config.Restaurants[restaurantId] and Config.Restaurants[restaurantId].job
    if not restaurantJob then
        TriggerClientEvent('ox_lib:notify', playerId, {
            title = Locale.order_error,  -- Utilisation de la traduction
            description = Locale.invalid_restaurant_id,  -- Utilisation de la traduction
            type = 'error',
            showDuration = true,
            duration = 10000
        })
        return
    end

    local restaurantItems = Config.Items[restaurantJob] or {}
    local item = restaurantItems[ingredient]

    if item then
        local totalCost = item.price * quantity

        -- Fetch the player object
        local xPlayer = QBCore.Functions.GetPlayer(playerId)
        if xPlayer then
            -- Check if player has enough money in their bank
            if xPlayer.PlayerData.money.bank >= totalCost then
                -- Deduct the amount from the player's bank account
                xPlayer.Functions.RemoveMoney('bank', totalCost, "Ordered ingredients for restaurant")

                MySQL.Async.execute('INSERT INTO orders (owner_id, ingredient, quantity, status, restaurant_id, total_cost) VALUES (@owner_id, @ingredient, @quantity, @status, @restaurant_id, @total_cost)', {
                    ['@owner_id'] = playerId,
                    ['@ingredient'] = item.name,
                    ['@quantity'] = quantity,
                    ['@status'] = 'pending',
                    ['@restaurant_id'] = restaurantId,
                    ['@total_cost'] = totalCost
                }, function(rowsChanged)
                    -- Notify the player about the order status
                    if rowsChanged > 0 then
                        TriggerClientEvent('ox_lib:notify', playerId, {
                            title = Locale.order_submitted,  -- Utilisation de la traduction
                            description = string.format(Locale.order_successful, quantity, item.name, totalCost),
                            type = 'success',
                            showDuration = true,
                            duration = 10000
                        })
                        -- Also trigger showing order details on the client side
                        TriggerClientEvent('restaurant:showOrderDetails', playerId, item.name, quantity, totalCost)
                    else
                        TriggerClientEvent('ox_lib:notify', playerId, {
                            title = Locale.order_error,  -- Utilisation de la traduction
                            description = Locale.order_processing_error,  -- Utilisation de la traduction
                            type = 'error',
                            showDuration = true,
                            duration = 10000
                        })
                    end
                end)
            else
                TriggerClientEvent('ox_lib:notify', playerId, {
                    title = Locale.insufficient_funds,  -- Utilisation de la traduction
                    description = Locale.not_enough_money,  -- Utilisation de la traduction
                    type = 'error',
                    showDuration = true,
                    duration = 10000
                })
            end
        else
            TriggerClientEvent('ox_lib:notify', playerId, {
                title = Locale.order_error,  -- Utilisation de la traduction
                description = Locale.order_processing_error,  -- Utilisation de la traduction
                type = 'error',
                showDuration = true,
                duration = 10000
            })
        end
    else
        TriggerClientEvent('ox_lib:notify', playerId, {
            title = Locale.order_error,  -- Utilisation de la traduction
            description = Locale.ingredient_not_found,  -- Utilisation de la traduction
            type = 'error',
            showDuration = true,
            duration = 10000
        })
    end
end)

-- Server-side: Update stock and pay driver
RegisterNetEvent('update:stock')
AddEventHandler('update:stock', function(restaurantId)
    local src = source

    if not restaurantId then
        TriggerClientEvent('ox_lib:notify', source, {
            title = Locale.error,  -- Utilisation de la traduction
            description = Locale.invalid_restaurant_id_stock_update,  -- Utilisation de la traduction
            type = 'error',
            position = 'top-right',
            showDuration = true,
            duration = 10000
        })
        return
    end

    MySQL.Async.fetchAll('SELECT * FROM orders WHERE restaurant_id = @restaurant_id AND status IN ("pending", "accepted")', {
        ['@restaurant_id'] = restaurantId
    }, function(orders)
        local queries = {}
        local totalCost = 0

        for _, order in ipairs(orders) do
            local orderId = order.id
            local ingredient = order.ingredient:lower()
            local quantity = tonumber(order.quantity)
            local orderCost = order.total_cost or 0

            if ingredient and quantity then
                table.insert(queries, string.format(
                    'UPDATE orders SET status = "completed" WHERE id = %d',
                    orderId
                ))

                table.insert(queries, string.format(
                    'INSERT INTO stock (restaurant_id, ingredient, quantity) VALUES (%d, "%s", %d) ON DUPLICATE KEY UPDATE quantity = quantity + %d',
                    restaurantId,
                    ingredient,
                    quantity,
                    quantity
                ))

                totalCost = totalCost + orderCost

            else
                print(Locale.error_invalid_order_data)  -- Utilisation de la traduction
            end
        end

        -- Execute transaction
        MySQL.Async.transaction(queries, function(success)
            if success then
                TriggerClientEvent('ox_lib:notify', src, {
                    title = Locale.stock_updated,  -- Utilisation de la traduction
                    description = Locale.orders_complete_stock_updated,  -- Utilisation de la traduction
                    type = 'success',
                    position = 'top-right',
                    showDuration = true,
                    duration = 10000
                })

                -- Calculate driver payment based on total cost
                local driverPayment = totalCost * Config.DriverPayPrec
                TriggerEvent('pay:driver', src, driverPayment)
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title = Locale.error,  -- Utilisation de la traduction
                    description = Locale.failed_update_stock,  -- Utilisation de la traduction
                    type = 'error',
                    position = 'top-right',
                    showDuration = true,
                    duration = 10000
                })
            end
        end)
    end)
end)

RegisterNetEvent('pay:driver')
AddEventHandler('pay:driver', function(driverId, amount)
    local src = source
    local xPlayer = QBCore.Functions.GetPlayer(driverId)

    if xPlayer then
        xPlayer.Functions.AddMoney('bank', amount, Locale.payment_for_delivery)  -- Utilisation de la traduction

        TriggerClientEvent('ox_lib:notify', driverId, {
            title = Locale.payment_received,  -- Utilisation de la traduction
            description = string.format(Locale.paid_for_delivery, amount),  -- Utilisation de la traduction
            type = 'success',
            position = 'top-right',
            showDuration = true,
            duration = 10000
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = Locale.error,  -- Utilisation de la traduction
            description = Locale.unable_to_find_player,  -- Utilisation de la traduction
            type = 'error',
            position = 'top-right',
            showDuration = true,
            duration = 10000
        })
    end
end)

RegisterNetEvent('warehouse:getPendingOrders')
AddEventHandler('warehouse:getPendingOrders', function()
    local playerId = source

    MySQL.Async.fetchAll('SELECT * FROM orders WHERE status = @status', {
        ['@status'] = 'pending',
    }, function(results)
        if not results then
            print(Locale.error_no_results_db)  -- Utilisation de la traduction
            return
        end

        local orders = {}

        for _, order in ipairs(results) do
            -- Get the restaurant job from Config.Restaurants
            local restaurantData = Config.Restaurants[order.restaurant_id]
            local restaurantJob = restaurantData and restaurantData.job

            -- Print the item list for the current restaurant job
            if Config.Items[restaurantJob] then

            else
                print(string.format(Locale.error_items_not_exist, restaurantJob))  -- Utilisation de la traduction
            end

            -- Get item details from Config.Items based on the restaurant's job
            local itemKey = order.ingredient:lower()
            local item = Config.Items[restaurantJob] and Config.Items[restaurantJob][itemKey]

            if item then
                table.insert(orders, {
                    id = order.id,
                    ownerId = order.owner_id,
                    itemName = item.name,
                    quantity = order.quantity,
                    totalCost = item.price * order.quantity,
                    restaurantId = order.restaurant_id
                })
            else
                print(string.format(Locale.error_item_not_found, order.ingredient, restaurantJob))  -- Utilisation de la traduction
            end
        end

        TriggerClientEvent('warehouse:showOrderDetails', playerId, orders)
    end)
end)

-- Fetch and show stock details
RegisterNetEvent('restaurant:requestStock')
AddEventHandler('restaurant:requestStock', function(restaurantId)
    local playerId = source
    MySQL.Async.fetchAll('SELECT * FROM stock WHERE restaurant_id = @restaurant_id', {
        ['@restaurant_id'] = restaurantId
    }, function(results)
        local stock = {}
        local itemsToDelete = {}

        -- Collect items to delete and build the stock table
        for _, item in ipairs(results) do
            if item.quantity <= 0 then
                table.insert(itemsToDelete, item.id)  -- Collect item IDs to delete
            else
                stock[item.ingredient] = item.quantity
            end
        end

        -- Delete items with quantity <= 0
        for _, itemId in ipairs(itemsToDelete) do
            MySQL.Async.execute('DELETE FROM stock WHERE id = @id', {
                ['@id'] = itemId
            })
        end

        -- Pass the cleaned stock table to the client
        TriggerClientEvent('restaurant:showResturantStock', playerId, stock, restaurantId)
    end)
end)

RegisterNetEvent('warehouse:getStocks')
AddEventHandler('warehouse:getStocks', function()
    local playerId = source
    MySQL.Async.fetchAll('SELECT * FROM warehouse_stock', {}, function(results)
        local stock = {}

        for _, item in ipairs(results) do
            stock[item.ingredient] = item.quantity
        end
        TriggerClientEvent('restaurant:showStockDetails', playerId, stock, restaurantId)
    end)
end)


RegisterNetEvent('restaurant:withdrawStock')
AddEventHandler('restaurant:withdrawStock', function(restaurantId, ingredient, amount)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)

    if player then
        for job, items in pairs(Config.Items) do
            for item, data in pairs(items) do
                print("Job: " .. job .. ", Item: " .. item .. ", Item Name: " .. data.name)
            end
        end

        ingredient = trim(ingredient)

        local restaurantJob = Config.Restaurants[restaurantId].job

        local itemData = Config.Items[restaurantJob] and Config.Items[restaurantJob][ingredient]

        if itemData then
            local amountNum = tonumber(amount)
            if amountNum and amountNum > 0 then
                player.Functions.AddItem(itemData.name, amountNum)

                MySQL.Async.execute('UPDATE stock SET quantity = quantity - @amount WHERE restaurant_id = @restaurant_id AND ingredient = @ingredient', {
                    ['@restaurant_id'] = restaurantId,
                    ['@ingredient'] = ingredient,
                    ['@amount'] = amountNum
                }, function(rowsChanged)
                    if rowsChanged > 0 then
                        TriggerClientEvent('ox_lib:notify', src, {
                            title = Locale.stock_withdrawn,  -- Utilisation de la traduction
                            description = string.format(Locale.stock_withdraw_success, amountNum, itemData.name),  -- Utilisation de la traduction
                            type = 'success',
                            showDuration = true,
                            duration = 10000
                        })
                    else
                        TriggerClientEvent('ox_lib:notify', src, {
                            title = Locale.error,  -- Utilisation de la traduction
                            description = Locale.unable_to_withdraw_stock,  -- Utilisation de la traduction
                            type = 'error',
                            showDuration = true,
                            duration = 10000
                        })
                    end
                end)
            else
                TriggerClientEvent('ox_lib:notify', src, {
                    title = Locale.error,  -- Utilisation de la traduction
                    description = Locale.invalid_stock_withdrawal_amount,  -- Utilisation de la traduction
                    type = 'error',
                    showDuration = true,
                    duration = 10000
                })
            end
        else
            TriggerClientEvent('ox_lib:notify', src, {
                title = Locale.error,  -- Utilisation de la traduction
                description = string.format(Locale.item_data_not_found, ingredient),  -- Utilisation de la traduction
                type = 'error',
                showDuration = true,
                duration = 10000
            })
        end
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = Locale.error,  -- Utilisation de la traduction
            description = Locale.player_not_found,  -- Utilisation de la traduction
            type = 'error',
            showDuration = true,
            duration = 10000
        })
    end
end)

function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

RegisterNetEvent('warehouse:acceptOrder')
AddEventHandler('warehouse:acceptOrder', function(orderId, restaurantId)
    local workerId = source

    MySQL.Async.fetchAll('SELECT * FROM orders WHERE id = @id', {
        ['@id'] = orderId,
    }, function(orderResults)
        if not orderResults or #orderResults == 0 then
            print(string.format(Locale.error_no_order_found, orderId))  -- Utilisation de la traduction
            return
        end

        local order = orderResults[1]

        local restaurantJob = Config.Restaurants[restaurantId] and Config.Restaurants[restaurantId].job

        local itemData = Config.Items[restaurantJob] and Config.Items[restaurantJob][order.ingredient:lower()]

        if not itemData then
            print(string.format(Locale.error_item_not_found_ingredient, order.ingredient))  -- Utilisation de la traduction
            return
        end

        MySQL.Async.fetchAll('SELECT quantity FROM warehouse_stock WHERE ingredient = @ingredient', {
            ['@ingredient'] = order.ingredient:lower(),
        }, function(stockResults)
            if not stockResults or #stockResults == 0 then
                print(string.format(Locale.error_no_stock_info, order.ingredient))  -- Utilisation de la traduction
                TriggerClientEvent('ox_lib:notify', workerId, {
                    title = Locale.insufficient_stock,  -- Utilisation de la traduction
                    description = string.format(Locale.not_enough_stock, order.ingredient),  -- Utilisation de la traduction
                    type = 'error',
                    position = 'top-right',
                    showDuration = true,
                    duration = 10000
                })
                return
            end

            local stock = stockResults[1].quantity

            if stock < order.quantity then
                TriggerClientEvent('ox_lib:notify', workerId, {
                    title = Locale.insufficient_stock,  -- Utilisation de la traduction
                    description = string.format(Locale.not_enough_stock, order.ingredient),  -- Utilisation de la traduction
                    type = 'error',
                    position = 'top-right',
                    showDuration = true,
                    duration = 10000
                })
                return
            end

            local orders = {
                {
                    id = order.id,
                    ownerId = order.owner_id,
                    itemName = itemData.name,
                    quantity = order.quantity,
                    totalCost = itemData.price * order.quantity,
                    restaurantId = order.restaurant_id
                }
            }

            TriggerClientEvent('warehouse:spawnVehicles', workerId, restaurantId, orders)

            -- Update the warehouse stock
            MySQL.Async.execute('UPDATE warehouse_stock SET quantity = quantity - @quantity WHERE ingredient = @ingredient', {
                ['@quantity'] = order.quantity,
                ['@ingredient'] = order.ingredient:lower(),
            }, function(rowsChanged)

                -- Update the order status to 'accepted'
                MySQL.Async.execute('UPDATE orders SET status = @status WHERE id = @id', {
                    ['@status'] = 'accepted',
                    ['@id'] = orderId,
                }, function(statusUpdateResult)

                    -- Notify the client about successful stock update and order acceptance
                    TriggerClientEvent('ox_lib:notify', workerId, {
                        description = Locale.order_accepted,  -- Utilisation de la traduction
                        type = 'success',
                        position = 'top-right',
                        showDuration = true,
                        duration = 10000
                    })
                end)
            end)
        end)
    end)
end)

-- Handle Order Denial
RegisterNetEvent('warehouse:denyOrder')
AddEventHandler('warehouse:denyOrder', function(orderId)
    TriggerClientEvent('ox_lib:notify', workerId, {
        title = Locale.job_denied,  -- Utilisation de la traduction
        description = Locale.order_denied_description,  -- Utilisation de la traduction
        type = 'error',
        position = 'top-right',
        showDuration = true,
        duration = 10000
    })
end)

-- Event handler for resource start
AddEventHandler('onResourceStart', function(resourceName)
    -- Ensure this code runs only when the relevant resource starts
    if resourceName == GetCurrentResourceName() then

        -- Update orders with 'accepted' status to 'pending'
        MySQL.Async.execute('UPDATE orders SET status = @newStatus WHERE status = @oldStatus', {
            ['@newStatus'] = 'pending',
            ['@oldStatus'] = 'accepted'
        }, function(affectedRows)
        end)
    end
end)

RegisterServerEvent('farming:sellFruit')
AddEventHandler('farming:sellFruit', function(fruit, amount, targetCoords)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    local item = Player.Functions.GetItemByName(fruit)

    if item then
        if item.amount >= amount then
            local price = Config.ItemsFarming[fruit].price
            local total = amount * price

            Player.Functions.RemoveItem(fruit, amount)
            Player.Functions.AddMoney('cash', total)

            MySQL.Async.fetchAll('SELECT * FROM warehouse_stock WHERE ingredient = @ingredient', {
                ['@ingredient'] = fruit
            }, function(stockResults)
                if #stockResults > 0 then
                    MySQL.Async.execute('UPDATE warehouse_stock SET quantity = quantity + @quantity WHERE ingredient = @ingredient', {
                        ['@quantity'] = amount,
                        ['@ingredient'] = fruit
                    })
                else
                    MySQL.Async.execute('INSERT INTO warehouse_stock (ingredient, quantity) VALUES (@ingredient, @quantity)', {
                        ['@ingredient'] = fruit,
                        ['@quantity'] = amount
                    })
                end
            end)

            local data = {
                title = string.format(Locale.sold_fruit, amount, fruit),  -- Utilisation de la traduction
                description = string.format(Locale.for_dollars, total),  -- Utilisation de la traduction
                type = 'success',
                duration = 9000,
                position = 'top-right'
            }
            TriggerClientEvent('ox_lib:notify', src, data)
        else
            local data = {
                title = string.format(Locale.not_enough_fruit, fruit),  -- Utilisation de la traduction
                type = 'error',
                duration = 3000,
                position = 'top-right'
            }
            TriggerClientEvent('ox_lib:notify', src, data)
        end
    else
        local data = {
            title = string.format(Locale.no_fruit, fruit),  -- Utilisation de la traduction
            type = 'error',
            duration = 3000,
            position = 'top-right'
        }
        TriggerClientEvent('ox_lib:notify', src, data)
    end
end)
