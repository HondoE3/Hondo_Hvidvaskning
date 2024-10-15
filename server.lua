-- Event til at starte hvidvaskning
RegisterNetEvent('Hondo_laundering:startLaunderingProcess', function(amount)
    local source = source

    -- Få spillerens identitet
    local playerIdentifier = GetPlayerIdentifiers(source)[1] -- License ID
    local playerName = GetPlayerName(source) -- Spillerens navn

    -- Få "black_money" item direkte fra spillerens inventory
    local blackMoney = exports.ox_inventory:GetItem(source, 'black_money', nil)

    -- Tjek om spilleren har nok sorte penge
    if blackMoney and blackMoney.count >= amount then
        -- Fjern de sorte penge fra spillerens inventory
        exports.ox_inventory:RemoveItem(source, 'black_money', amount)

        -- Beregn rene penge efter 30% gebyr
        local cleanMoney = amount * 0.7

        -- Få den nuværende tid som timestamp
        local currentTime = os.time()

        -- Beregn ventetiden baseret på mængden af sorte penge
        -- 1 minut pr. 40.000 sorte penge
        local timePerAmount = 60 -- 1 minut i sekunder pr. 40.000 sorte penge
        local readyTimeInSeconds = (amount / 40000) * timePerAmount
        local readyTime = currentTime + readyTimeInSeconds

        -- Gem hvidvaskningsprocessen i databasen som datetime-værdier
        exports.oxmysql:insert('INSERT INTO laundering_processes (license_id, name, black_money, clean_money, start_time, ready_time, collected) VALUES (?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?)', {
            playerIdentifier,
            playerName,
            amount, -- Sorte penge
            cleanMoney, -- Rene penge efter gebyr
            currentTime, -- Starttidspunkt
            readyTime, -- Tidspunkt for hvornår pengene er klar
            0 -- Ikke afhentet endnu
        })

        -- Beregn ventetid i minutter og sørg for, at det er minimum 1 minut
        local minutesToWait = math.max(1, math.floor(readyTimeInSeconds / 60))

        -- Send en besked til spilleren om, at hvidvaskningsprocessen er startet
        TriggerClientEvent('ox_lib:notify', source, { type = 'success', description = 'Hvidvaskning påbegyndt. Kom tilbage om '..minutesToWait..' minutter for at hente dine penge.' })
    else
        -- Hvis spilleren ikke har nok sorte penge
        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Du har ikke nok sorte penge' })
    end
end)

-- Event til at sende dato og tid til klienten
RegisterNetEvent('Hondo_laundering:getDateTime', function()
    local source = source
    -- Få den nuværende dato og tid
    local currentDateTime = os.date('%Y-%m-%d %H:%M:%S')
    -- Send dato og tid tilbage til klienten
    TriggerClientEvent('Hondo_laundering:receiveDateTime', source, currentDateTime)
end)

-- Event til at sende statusinformationer til klienten
RegisterNetEvent('Hondo_laundering:checkStatus', function()
    local source = source
    local playerIdentifier = GetPlayerIdentifiers(source)[1]

    -- Hent den igangværende proces for spilleren
    exports.oxmysql:fetch('SELECT * FROM laundering_processes WHERE license_id = ? AND collected = 0', {playerIdentifier}, function(result)
        if result and #result > 0 then
            local laundering = result[1] -- Der vil kun være én aktiv proces per spiller

            -- Konverter start_time og ready_time til et læsbart format kun til visning
            local startDateFormatted = os.date('%Y-%m-%d %H:%M:%S', laundering.start_time / 1000)
            local readyDateFormatted = os.date('%Y-%m-%d %H:%M:%S', laundering.ready_time / 1000)

            -- Beregn progressen som procent
            local currentTime = os.time()
            local progress = math.min(((currentTime - (laundering.start_time / 1000)) / ((laundering.ready_time / 1000) - (laundering.start_time / 1000))) * 100, 100)

            -- Kontroller, om processen er klar til afhentning
            local canCollect = currentTime >= (laundering.ready_time / 1000)

            -- Send informationerne til klienten
            TriggerClientEvent('Hondo_laundering:receiveStatus', source, {
                start_time_formatted = startDateFormatted,
                ready_time_formatted = readyDateFormatted,
                black_money = laundering.black_money,
                clean_money = laundering.clean_money,
                progress = progress,
                canCollect = canCollect
            })
        else
            -- Hvis ingen igangværende hvidvaskning findes
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Ingen igangværende hvidvaskning.' })
            return -- Stop funktionen her, så der ikke sendes flere beskeder
        end
    end)
end)

--- Event til at tjekke om spilleren allerede har en igangværende hvidvaskningsproces
RegisterNetEvent('Hondo_laundering:checkForActiveProcess', function()
    local source = source
    local playerIdentifier = GetPlayerIdentifiers(source)[1]

    -- Tjek om spilleren allerede har en igangværende hvidvaskningsproces
    exports.oxmysql:fetch('SELECT * FROM laundering_processes WHERE license_id = ? AND collected = 0', {playerIdentifier}, function(results)
        if results and #results > 0 then
            -- Spilleren har en aktiv hvidvaskningsproces, send besked til klienten
            TriggerClientEvent('Hondo_laundering:receiveProcessStatus', source, true)
        else
            -- Spilleren har ingen aktiv proces, send besked til klienten
            TriggerClientEvent('Hondo_laundering:receiveProcessStatus', source, false)
        end
    end)
end)

-- Event til at hente rene penge efter hvidvaskning
RegisterNetEvent('Hondo_laundering:collectLaunderedMoney', function()
    local source = source
    local playerIdentifier = GetPlayerIdentifiers(source)[1]

    -- Hent den igangværende proces for spilleren baseret på license_id
    exports.oxmysql:fetch('SELECT * FROM laundering_processes WHERE license_id = ? AND collected = 0', {playerIdentifier}, function(result)
        if result and #result > 0 then
            local laundering = result[1]

            -- Tilføj de rene penge til spillerens konto eller inventory
            local success = exports.ox_inventory:AddItem(source, 'money', laundering.clean_money)

            -- Tjek, om penge blev tilføjet korrekt
            if success then

                -- Marker processen som afhentet i databasen
                exports.oxmysql:update('UPDATE laundering_processes SET collected = 1 WHERE id = ?', {laundering.id}, function(rowsChanged)
                    if rowsChanged > 0 then
                        -- Send besked til spilleren
                        TriggerClientEvent('ox_lib:notify', source, { type = 'success', description = 'Du har hentet dine '..laundering.clean_money..' rene penge.' })
                    else
                        TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Der opstod en fejl ved at markere processen som afhentet.' })
                    end
                end)
            else
                TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Der opstod en fejl, og pengene blev ikke tilføjet.' })
            end
        else
            TriggerClientEvent('ox_lib:notify', source, { type = 'error', description = 'Ingen penge er klar til afhentning endnu.' })
        end
    end)
end)