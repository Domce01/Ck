ESX = nil
TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

-- Leidžiamos ESX grupės
local AllowedGroups = { owner = true, superadmin = true, admin = true }

-- Paprasta helper funkcija
local function isAdmin(xPlayer)
    if not xPlayer or not xPlayer.getGroup then return false end
    local g = xPlayer.getGroup()
    return g and AllowedGroups[g] == true
end

-- Saugus vykdymas: DELETE table WHERE column = @val (table/column validuojami prieš tai)
local function deleteBy(dbTable, dbColumn, value)
    -- Table/column negali būti parametrizuojami, todėl juos naudojame tik po tikrinimo schema'e
    local sql = string.format("DELETE FROM `%s` WHERE `%s` = @val", dbTable, dbColumn)
    MySQL.Async.execute(sql, { ['@val'] = value })
end

-- Surenka visas (table, column) poras, kuriose stulpelio pavadinimas yra vienas iš nurodytų
local function fetchTargetsByColumns(columnList, cb)
    local colIn = table.concat((function()
        local t = {}
        for i, c in ipairs(columnList) do t[i] = "'" .. c .. "'" end
        return t
    end)(), ",")
    MySQL.Async.fetchAll("SELECT DATABASE() AS db", {}, function(dbres)
        local dbName = dbres and dbres[1] and dbres[1].db or nil
        if not dbName then cb({}) return end

        local q = ([[
            SELECT TABLE_NAME, COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = @db
              AND COLUMN_NAME IN (]] .. colIn .. [[)
        ]])
        MySQL.Async.fetchAll(q, { ['@db'] = dbName }, function(rows)
            cb(rows or {})
        end)
    end)
end

-- Pabando paimti žaidėjo telefono numerį iš users (jei yra stulpelis)
local function fetchPhoneNumber(identifier, cb)
    MySQL.Async.fetchAll("SELECT DATABASE() AS db", {}, function(dbres)
        local dbName = dbres and dbres[1] and dbres[1].db or nil
        if not dbName then cb(nil) return end
        local probe = [[
            SELECT COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'users' AND COLUMN_NAME = 'phone_number'
            LIMIT 1
        ]]
        MySQL.Async.fetchAll(probe, { ['@db'] = dbName }, function(has)
            if not has or not has[1] then cb(nil) return end
            MySQL.Async.fetchAll("SELECT phone_number FROM `users` WHERE `identifier` = @id LIMIT 1", { ['@id'] = identifier }, function(r)
                if r and r[1] and r[1].phone_number and r[1].phone_number ~= "" then
                    cb(r[1].phone_number)
                else
                    cb(nil)
                end
            end)
        end)
    end)
end

-- Pagrindinis CK
RegisterCommand('ck', function(source, args)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end

    if not isAdmin(xPlayer) then
        TriggerClientEvent('chat:addMessage', source, { args = {"^1[CK]", "Neturi teisių CK!"} })
        return
    end

    local targetId = tonumber(args[1]) or source
    local tPlayer = ESX.GetPlayerFromId(targetId)
    if not tPlayer then
        TriggerClientEvent('chat:addMessage', source, { args = {"^1[CK]", "Žaidėjas nerastas!"} })
        return
    end

    local targetIdentifier = tPlayer.identifier

    -- 1) Visi identifikatoriaus stulpeliai, pagal kuriuos trinsime
    local idColumns = {
        'identifier',      -- ESX users, dauguma lentelių
        'owner',           -- owned_vehicles, licenses, datastore_data
        'citizenid',       -- kai kurios sistemos/portai
        'charid',          -- alternatyvūs multi-char pluginai
        'license',         -- kai kas naudoja license vietoj identifier
        'character_id',    -- kai kurie multi-char resursai
        'charidentifier'   -- retesni atvejai
    }

    -- 2) Telefono stulpeliai (lb-phone, gcphone, npwd, qs ir pan.)
    local phoneColumns = {
        'phone', 'phone_number', 'number',
        'caller', 'target', 'source_number', 'dest_number'
    }

    -- Prieš išmetant – užfiksuojam telefono numerį (jei yra)
    fetchPhoneNumber(targetIdentifier, function(phoneNumber)
        -- Surandame visas lenteles/kolonas su identifikatorių stulpeliais
        fetchTargetsByColumns(idColumns, function(idTargets)
            for _, row in ipairs(idTargets) do
                local tbl = row.TABLE_NAME
                local col = row.COLUMN_NAME
                -- Filtras: netrinam iš information_schema ir panašiai (jau filtruota per schema, bet vistiek…)
                if tbl ~= nil and col ~= nil then
                    deleteBy(tbl, col, targetIdentifier)
                end
            end

            -- Jei turime telefono numerį – pravalykime ir telefono duomenis
            if phoneNumber and phoneNumber ~= "" then
                fetchTargetsByColumns(phoneColumns, function(phTargets)
                    for _, row in ipairs(phTargets) do
                        local tbl = row.TABLE_NAME
                        local col = row.COLUMN_NAME
                        deleteBy(tbl, col, phoneNumber)
                    end
                end)
            end
        end)

        -- Galiausiai – išmetame žaidėją
        DropPlayer(targetId, "CK įvykdytas")

        -- Pranešimai
        TriggerClientEvent('chat:addMessage', source, { args = {"^2[CK]", "CK įvykdytas"} })
        print("[CK] Adminas ID " .. tostring(source) .. " įvykdė CK žaidėjui ID " .. tostring(targetId) .. " (autorius domce01)")
    end)
end, false)
