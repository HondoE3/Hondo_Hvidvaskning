local npcModel = 'a_m_o_ktown_01' -- NPC Model (change this to the NPC you want)
local npcCoords = vector3(188.7, -1680.63, -1.53) -- Coordinates of the NPC
local npcHeading = 272.61 -- Direction the NPC will face

-- Opret NPC og brug ox_target til interaktion
CreateThread(function()
    -- Indlæs NPC modellen
    RequestModel(npcModel)
    while not HasModelLoaded(npcModel) do
        Wait(100)
    end

    -- Opret NPC
    local npc = CreatePed(4, npcModel, npcCoords.x, npcCoords.y, npcCoords.z, npcHeading, false, true)
    SetEntityInvincible(npc, true) -- NPC'en kan ikke dø
    SetBlockingOfNonTemporaryEvents(npc, true) -- NPC'en reagerer ikke på omgivelserne
    FreezeEntityPosition(npc, true) -- NPC'en kan ikke bevæge sig

    -- Brug ox_target til at kunne interagere med NPC'en
    exports.ox_target:addLocalEntity(npc, {
        {
            name = 'interact_npc',
            label = 'Snak Med Jan',
            icon = 'fa-solid fa-user',
            onSelect = function()
                -- Tjek for igangværende proces, før menuen åbnes
                TriggerServerEvent('Hondo_laundering:checkForActiveProcess')
            end
        }
    })
end)

-- Event til at modtage status om igangværende hvidvaskningsproces og opdatere menuen
RegisterNetEvent('Hondo_laundering:receiveProcessStatus', function(hasActiveProcess)
    -- Opret context-menuen og deaktiver "Igangsæt Hvidvaskning", hvis der er en aktiv proces
    lib.registerContext({
        id = 'laundering_menu',
        title = 'Hvidvaskningsmenu',
        options = {
            {
                title = '⏳ Tjek Status ⏳',
                description = 'Se status på hvidvaskning',
                event = 'Hondo_laundering:checkStatus'
            },
            {
                title = '💷 Igangsæt Hvidvaskning 💷',
                description = hasActiveProcess and 'Kun en af gangen' or 'Start hvidvaskning af penge', -- Tilføjer beskrivelsen, hvis der er en aktiv proces
                event = 'Hondo_laundering:requestDateTime',
                disabled = hasActiveProcess -- Lås valgmuligheden, hvis der er en aktiv proces
            }
        }
    })

    -- Åbn menuen
    lib.showContext('laundering_menu')
end)

-- Event for at modtage statusinformationer og vise dem
RegisterNetEvent('Hondo_laundering:receiveStatus', function(laundering)

    -- Formatér pengebeløb som tal
    local blackMoney = laundering.black_money and string.format('%d', laundering.black_money) or "Ikke tilgængelig"
    local cleanMoney = laundering.clean_money and string.format('%d', laundering.clean_money) or "Ikke tilgængelig"

    -- Opret en context menu med statusinformationerne
    local elements = {
        {
            title = '📆 Startdato 📆',
            description = laundering.start_time_formatted, -- Viser den allerede formaterede startdato
        },
        {
            title = '📅 Slutdato 📅',
            description = laundering.ready_time_formatted, -- Viser den allerede formaterede slutdato
        },
        {
            title = '💷 Sorte penge indsat 💷',
            description = blackMoney .. ' DKK', -- Viser sorte penge, eller "Ikke tilgængelig" hvis den er nil
        },
        {
            title = '💵 Rene penge modtages 💵',
            description = cleanMoney .. ' DKK', -- Viser rene penge, eller "Ikke tilgængelig" hvis den er nil
        },
        {
            title = '🧮 Gebyrprocent 🧮',
            description = '30%',
        },
        {
            title = '⏳ Status ⏳',
            description = math.floor(laundering.progress) .. '% færdig', -- Progressen vises her
            progress = laundering.progress, -- Vis progressbaren med den beregnede progress
            colorScheme = 'green'
        }
    }

    -- Hvis pengene kan afhentes (progress er 100%)
    if laundering.canCollect then
        table.insert(elements, {
            title = '💰 Udbetal 💰',
            event = 'Hondo_laundering:collectLaunderedMoney',
            onSelect = function()
                TriggerServerEvent('Hondo_laundering:collectLaunderedMoney') -- Send eventet til serveren
            end
        })
    else
        table.insert(elements, {
            title = '🔒 Udbetal (Ikke klar) 🔒',
            disabled = true
        })
    end

    -- Registrer context menuen
    lib.registerContext({
        id = 'laundering_status_menu',
        title = '📝 Hvidvasknings status 📝',
        options = elements
    })

    -- Vis context menuen
    lib.showContext('laundering_status_menu')
end)

-- Event for at anmode om status
RegisterNetEvent('Hondo_laundering:checkStatus', function()
    TriggerServerEvent('Hondo_laundering:checkStatus')
end)

-- Event for at modtage dato og tid fra serveren og åbne dialog
RegisterNetEvent('Hondo_laundering:receiveDateTime', function(currentDateTime)
    local input = lib.inputDialog('Hvidvaskning', {
        { type = 'input', label = '💷 Antal Sorte Penge Der Skal Vaskes:', placeholder = 'Indtast beløb' },
        { type = 'input', label = '🧮 Procenter', default = '30%', disabled = true }, -- Låst input felt
        { type = 'input', label = '🕖 Dato/Tid:', default = currentDateTime, disabled = true } -- Låst input med tid modtaget fra serveren
    })

    -- Tjek om spilleren indtastede noget
    if input then
        local amount = tonumber(input[1]) -- Antal sorte penge som spilleren indtastede
        if amount and amount > 0 then
            -- Send beløbet til serveren for at starte processen
            TriggerServerEvent('Hondo_laundering:startLaunderingProcess', amount)
        else
            exports.qbx_core:Notify('Ugyldigt beløb', 'error', 5000)
        end
    else
        exports.qbx_core:Notify('Du afbrød handlingen', 'error', 5000)
    end
end)

-- Event for at anmode om dato og tid fra serveren
RegisterNetEvent('Hondo_laundering:requestDateTime', function()
    TriggerServerEvent('Hondo_laundering:getDateTime')
end)