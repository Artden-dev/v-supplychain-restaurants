local QBCore = exports['qb-core']:GetCoreObject()
local lang = Config.Locale or 'en'  -- Utilise la langue configurée
local Translations = LoadResourceFile(GetCurrentResourceName(), 'locales/'..lang..'.lua')
local Locale = load(Translations)()

Citizen.CreateThread(function()
    if not Businesses.Businesses or type(Businesses.Businesses) ~= "table" then
        print(Locale.error_invalid_business_table)  -- Utilisation de la traduction
        return
    end

    for job, details in pairs(Businesses.Businesses) do
        if not details.trays or type(details.trays) ~= "table" then
            print(string.format(Locale.warning_invalid_trays_table, job))  -- Utilisation de la traduction
            details.trays = {}
        end

        if not details.storage or type(details.storage) ~= "table" then
            print(string.format(Locale.warning_invalid_storage_table, job))  -- Utilisation de la traduction
            details.storage = {}
        end

        for trayIndex, _ in pairs(details.trays) do
            local trayId = "order-tray-" .. job .. '-' .. trayIndex
            local trayLabel = string.format(Locale.order_tray_label, details.jobDisplay, trayIndex)  -- Utilisation de la traduction
            exports["ox_inventory"]:RegisterStash(trayId, trayLabel, 10, 50000)
        end

        for storageIndex, storageDetails in pairs(details.storage) do
            local storageId = "storage-" .. job .. '-' .. storageIndex
            local storageLabel = string.format(Locale.storage_label, details.jobDisplay, storageIndex)  -- Utilisation de la traduction
            local slots = storageDetails.inventory.slots or 6
            local weight = (storageDetails.inventory.weight or 10) * 1000
            exports["ox_inventory"]:RegisterStash(storageId, storageLabel, slots, weight)
        end
    end
end)

RegisterServerEvent('v-businesses:GiveItem', function(info)
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    local iteminfo = info.iteminfo
    local quantity = info.quantity or 1

    if not iteminfo or not iteminfo.requiredItems then
        TriggerClientEvent('ox_lib:notify', src, {
            title = Locale.invalid_item_info,  -- Utilisation de la traduction
            type = "error",
            duration = 3000,
            position = "top-right"
        })
        return
    end

    if type(iteminfo.requiredItems) ~= "table" then
        TriggerClientEvent('ox_lib:notify', src, {
            title = Locale.invalid_required_items_table,  -- Utilisation de la traduction
            type = "error",
            duration = 3000,
            position = "top-right"
        })
        return
    end

    for _, reqItem in pairs(iteminfo.requiredItems) do
        local playerItem = player.Functions.GetItemByName(reqItem.item)
        if not playerItem or playerItem.amount < reqItem.amount * quantity then
            TriggerClientEvent('ox_lib:notify', src, {
                title = Locale.insufficient_required_items,  -- Utilisation de la traduction
                type = "error",
                duration = 3000,
                position = "top-right"
            })
            return
        end
    end

    for _, reqItem in pairs(iteminfo.requiredItems) do
        player.Functions.RemoveItem(reqItem.item, reqItem.amount * quantity)
    end

    player.Functions.AddItem(iteminfo.item, quantity)

    TriggerClientEvent('ox_lib:notify', src, {
        title = Locale.item_crafted_success,  -- Utilisation de la traduction
        type = "success",
        duration = 3000,
        position = "top-right"
    })
end)
