WhoCanDo = {Database = {}}

SLASH_WCD1 = '/wcd'

WCDData = {}
WCDMetaData = {}
WCDPreferences = {debug = false}

local tradeSkillShown = false
local onlineGuildies = {}
WhoCanDo.Guildies = {}

local gameIdToProfessionName = {
    ['171'] = 'Alchemy',
    ['164'] = 'Blacksmithing',
    ['185'] = 'Cooking',
    ['333'] = 'Enchanting',
    ['202'] = 'Engineering',
    ['773'] = 'Inscription',
    ['755'] = 'Jewelcrafting',
    ['165'] = 'Leatherworking',
    ['197'] = 'Tailoring'
}

local function capitalize(text) return strupper(strsub(text, 1, 1)) .. strlower(strsub(text, 2)) end

local function debugLog(...) if WCDPreferences.debug then print("|cffff6633[|cffffffffWCD|cffff6633]|r", ...) end end

local function log(...) print("|cff66aa33[|cffffffffWCD|cff66aa33]|r", ...) end

function WhoCanDo:Log(...) log(...) end

function WhoCanDo:DebugLog(...) debugLog(...) end

local function initialize()
    log('WhoCanDo is ready! Type "/wcd" for help')
    WhoCanDo:InitializeSync()
    GuildRoster()
    C_Timer.NewTicker(2 * 60, function() GuildRoster() end)

end

function WhoCanDo:AddRecipe(professionName, spellId, name)
    local database = WhoCanDo.Database[professionName]
    if database then
        if database[spellId] then
            WCDData[spellId] = WCDData[spellId] or {}
            local spellDb = WCDData[spellId]
            if not tContains(spellDb, name) then
                table.insert(spellDb, name)
                WCDMetaData[professionName] = WCDMetaData[professionName] or {}
                WCDMetaData[professionName][name] = WCDMetaData[professionName][name] or 0
                WCDMetaData[professionName][name] = WCDMetaData[professionName][name] + 1
                return true
            end
        end
    else
        debugLog('Unkown profession ' .. professionName)
    end
    return false
end

local function onTradeSkillUpdate()
    local isLinked, name = IsTradeSkillLinked()
    if not name then name = UnitName('player') end
    if not tContains(WhoCanDo.Guildies, name) then
        debugLog(name, 'is not in the same guild, skipping')
        return
    end
    local numSkills = GetNumTradeSkills()
    debugLog(numSkills .. ' skills')
    local listLink = GetTradeSkillListLink()
    if not listLink then return end
    local _, _, _, idAndStuff = strsplit(':', listLink)
    local gameProfId = strsub(idAndStuff, 1, 3)

    local professionName = gameIdToProfessionName[gameProfId]
    if not professionName then
        debugLog('Unknown profession id ', gameProfId)
        return
    end
    if not WhoCanDo.Database[professionName] then
        debugLog(professionName .. ' not supported')
        return
    end
    debugLog('Scanning ' .. name .. "'s " .. professionName)
    local added = 0
    for i = 1, numSkills do
        local spellLink = GetTradeSkillRecipeLink(i)
        local skillName, skillType = GetTradeSkillInfo(i)
        if skillType ~= 'header' then
            local spellId = tonumber(strsub(spellLink, 21, 25))
            if not spellId then spellId = strsub(spellLink, 21, 24) end
            local isNew = WhoCanDo:AddRecipe(professionName, spellId, name)
            if isNew then added = added + 1 end
        end
    end
    if added > 0 then
        log('Added ' .. added .. ' new recipes for ' .. name .. '.. (' .. WCDMetaData[professionName][name] .. ' total)')
        WhoCanDo:AnnounceNewData(professionName, name)
    else
        debugLog('Nothing new here')
    end
end

local tsUpdateId = 0
local function debounceSkillUpdate()
    tsUpdateId = tsUpdateId + 1
    local currentId = tsUpdateId
    C_Timer.After(0.5, function() if currentId == tsUpdateId then onTradeSkillUpdate() end end)
end

local function exportCSV(professionName)
    professionName = capitalize(professionName)
    if not WhoCanDo.Database[professionName] then
        log('Unsupported profession ' .. professionName)
        return
    end

    for spellId, _ in pairs(WhoCanDo.Database[professionName]) do GetSpellInfo(spellId) end

    C_Timer.After(1, function()
        local spellList = {}
        for spellId, _ in pairs(WhoCanDo.Database[professionName]) do
            local name = GetSpellInfo(spellId)
            tinsert(spellList, {name = name, spellId = spellId})
        end
        table.sort(spellList, function(a, b) return a.name < b.name end)

        local result = {}
        for _, spell in ipairs(spellList) do
            tinsert(result, spell.name .. ',' .. table.concat(WCDData[spell.spellId] or {}, ','))
        end

        local text = table.concat(result, '\n')

        WhoCanDo_ExportFrame:Show()
        WhoCanDo_EditBox:SetText(text)
        WhoCanDo_EditBox:HighlightText(0, string.len(text))
    end)
end

local function forgetPlayer(name)
    local removed = 0
    name = capitalize(name)
    for _, data in pairs(WCDData) do
        if tContains(data, name) then
            for i = 1, #data do
                if data[i] == name then
                    tremove(data, i)
                    removed = removed + 1
                end
            end
        end
    end
    WhoCanDo:RecalculateMetaData()
    if removed > 0 then
        log('Removed ' .. removed .. ' recipes of ' .. name)
    else
        log('Found no recipes for player named ' .. name)
    end
end

local function forgetPlayerProfession(name, professionName)
    local removed = 0
    name = capitalize(name)
    professionName = capitalize(professionName)
    if not WhoCanDo.Database[professionName] then
        log('Unsupported profession ' .. professionName)
        return
    end
    for spellId, _ in pairs(WhoCanDo.Database[professionName]) do
        local data = WCDData[spellId] or {}
        if tContains(data, name) then
            for i = 1, #data do
                if data[i] == name then
                    tremove(data, i)
                    removed = removed + 1
                end
            end
        end
    end
    WhoCanDo:RecalculateMetaData()
    if removed > 0 then
        log('Removed ' .. removed .. ' recipes of ' .. name .. "'s " .. professionName)
    else
        log('Found no ' .. professionName .. ' recipes for player named ' .. name)
    end
end

local function findSpellIdByItemId(itemId)
    debugLog('Looking for item ' .. itemId)
    for profession, db in pairs(WhoCanDo.Database) do
        debugLog('Looking in ' .. profession)
        for spellId, spellData in pairs(db) do if spellData.item == itemId then return spellId end end
    end
    return nil
end

local function findSpellIdByItemName(name)
    name = strlower(name)
    debugLog('Looking for item named ' .. name)
    for profession, db in pairs(WhoCanDo.Database) do
        debugLog('Looking in ' .. profession)
        for spellId, spellData in pairs(db) do
            local first, last = strfind(spellData.name, name)
            if first and last then return spellId end
        end
    end
    return nil
end

local function sendGuildMessage(msg) SendChatMessage('WhoCanDo ' .. msg, "GUILD") end

function WhoCanDo:ProcessGuildMsg(...)
    local msg, sender = ...

    if not WhoCanDo:AmBoss() and strsub(msg, 1, 8) == 'WhoCanDo' then WhoCanDo:OnWCDMessageDetected(sender) end

    if strsub(msg, 1, 4) == 'wcd ' then
        if not WhoCanDo:AmBoss() then
            debugLog("I'm not boss")
            WhoCanDo:CheckOnBossReply(msg)
            return
        end
        local query = strsub(msg, 5, 500)

        if strlower(query) == 'copium' then
            sendGuildMessage('Copium©? ♥Alice♥')
            return
        end

        local spellId = tonumber(strsub(query, 21, 25)) or tonumber(strsub(query, 21, 24))

        local itemId = tonumber(strsub(query, 18, 22)) or tonumber(strsub(query, 18, 23))
        if itemId then
            debugLog('Is ItemId')
            spellId = findSpellIdByItemId(itemId)
        elseif not spellId then
            spellId = findSpellIdByItemName(query)
        end

        if not spellId then
            sendGuildMessage("couldn't find " .. query .. ' :(')
            return
        end

        local spellLink = GetSpellLink(spellId)

        local crafters = WCDData[spellId]

        if not crafters then
            sendGuildMessage(spellLink .. '? No one in the guild :(')
            return
        end

        local onlineCrafters = {}
        local offlineCrafters = {}

        for _, name in ipairs(crafters) do
            if tContains(onlineGuildies, name) then
                table.insert(onlineCrafters, name)
            else
                table.insert(offlineCrafters, name)
            end
        end

        sendGuildMessage(spellLink .. '? ♥' .. table.concat(onlineCrafters, ' ') .. ' • ' ..
                             table.concat(offlineCrafters, ' '))
    end
end

local function processGuildPlayers()
    if not GetGuildInfo('player') then return end

    local membersNum = GetNumGuildMembers()

    if membersNum == nil or membersNum == 0 then return end

    newOnlineGuildies = {}
    WhoCanDo.Guildies = {}

    for i = 1, membersNum do
        local fullName, rank, rankIndex, level, class, zone, note, officernote, online = GetGuildRosterInfo(i)
        local name = strsplit('-', fullName)
        table.insert(WhoCanDo.Guildies, name)
        if online then
            table.insert(newOnlineGuildies, name)
        elseif tContains(onlineGuildies, name) then
            WhoCanDo:OnGuildMemberLoggedOff(name)
        end
    end

    onlineGuildies = newOnlineGuildies
end

local function processEvent(event, type, ...)
    if type == 'VARIABLES_LOADED' then
        initialize()
    elseif type == 'TRADE_SKILL_SHOW' then
        tradeSkillShown = true
    elseif type == 'TRADE_SKILL_CLOSE' then
        tradeSkillShown = false
    elseif type == 'TRADE_SKILL_UPDATE' then
        debounceSkillUpdate()
    elseif type == 'CHAT_MSG_GUILD' then
        WhoCanDo:ProcessGuildMsg(...)
    elseif type == 'CHAT_MSG_SYSTEM' then
        WhoCanDo:ProcessSystemMsg(...)
    elseif type == 'GUILD_ROSTER_UPDATE' then
        processGuildPlayers()
    elseif type == 'PLAYER_LOGOUT' then
        WhoCanDo:OnLogout()
    end
end

function WhoCanDo:Start()
    WhoCanDoEventFrame:RegisterEvent('VARIABLES_LOADED')
    WhoCanDoEventFrame:RegisterEvent('TRADE_SKILL_SHOW')
    WhoCanDoEventFrame:RegisterEvent('TRADE_SKILL_UPDATE')
    WhoCanDoEventFrame:RegisterEvent('TRADE_SKILL_CLOSE')
    WhoCanDoEventFrame:RegisterEvent('CHAT_MSG_GUILD')
    WhoCanDoEventFrame:RegisterEvent('CHAT_MSG_ADDON')
    WhoCanDoEventFrame:RegisterEvent('CHAT_MSG_SYSTEM')
    WhoCanDoEventFrame:RegisterEvent('GUILD_ROSTER_UPDATE')
    WhoCanDoEventFrame:RegisterEvent('PLAYER_LOGOUT')
    WhoCanDoEventFrame:SetScript('OnEvent', processEvent)
end

function WhoCanDo:RecalculateMetaData(loud)
    local logFunc = loud and log or debugLog
    logFunc('Recalculating meta data...')
    WCDMetaData = {}
    for professionName, db in pairs(WhoCanDo.Database) do
        local newMeta = {}
        for spellId, _ in pairs(db) do
            if WCDData[spellId] then
                for i, name in ipairs(WCDData[spellId]) do newMeta[name] = (newMeta[name] or 0) + 1 end
            end
        end
        WCDMetaData[professionName] = newMeta
    end
    logFunc('Meta data recalculated!')
end

function SlashCmdList.WCD(rawCmd)
    local cmd, arg1, arg2 = strsplit(' ', rawCmd)
    cmd = strlower(cmd)
    if cmd == 'forget' then
        if arg1 == 'all' then
            WCDData = {}
            WCDMetaData = {}
            log('All stored data has been reset')
        elseif arg1 then
            if arg2 then
                forgetPlayerProfession(arg1, arg2)
            else
                forgetPlayer(arg1)
            end
        else
            log('Forget what?')
            print('Examples:')
            local guildies = WhoCanDo.Guildies
            local gIndex1 = fastrandom(1, #guildies)
            local gIndex2 = fastrandom(1, #guildies)
            print('/wcd forget ' .. guildies[gIndex1])
            print('/wcd forget ' .. guildies[gIndex2] .. ' tailoring')
            print('/wcd forget all')
        end
    elseif cmd == 'recalculate' then
        WhoCanDo:RecalculateMetaData(true)
    elseif cmd == 'who' then
        log('Current users: ' .. table.concat(WhoCanDo:GetAddonUsers(), ', '))
    elseif cmd == 'export' then
        if not arg1 then
            log('Usage: /wcd export [profession name], e.g.: /wcd export jewelcrafting')
            return
        end
        exportCSV(arg1)
    elseif not cmd or cmd == '' or cmd == 'help' then
        log('Ask a question in /guild chat in format: "wcd glyph of bladestorm"')
        print('Other supported commands:')
        print(' To export into csv/sheet:')
        print('|cffcccccc    /wcd export |cff999999[profession name]')
        print(' To remove data:')
        print('|cffcccccc    /wcd forget |cff999999[player name]')
        print('|cffcccccc    /wcd forget |cff999999[player name] [profession name]')
        print('|cffcccccc    /wcd forget all')
        print(' To show who is using the addon:')
        print('|cffcccccc    /wcd who')
    else
        log('Unknown command /wcd ' .. cmd .. ', try /wcd help')
    end
end

WhoCanDo:Start()
