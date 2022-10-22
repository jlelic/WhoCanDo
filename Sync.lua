local meta

local PROTOCOL_VERSION = '0'
local PREFIX = 'WCD'
local PREFIX_META = 'WCDM'
local UPDATE_INTERVAL = 5
local DELIMITER = ';'
local COMPRESSION_LEVEL = 5
local MSG_HELLO = 'HELLO'
local MSG_IM_BOSS = 'IMBOSS'
local MSG_HELLOBACK = 'HELLOBACK'
local MSG_REQUEST = 'REQUEST'
local MSG_RECIPES = 'R'
local MSG_BYE = 'BYE'
local BOSS_TTL = 5

local aceComm

local imBoss = true
local waitingForBoss = true

local outOfDatMentioned = false

local playerName = UnitName('player')
local addonUsers = {playerName}
local bossName

local b64toNum = {}
local chars = {}
for b64code, char in pairs {
    [0] = 'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'q',
    'r',
    's',
    't',
    'u',
    'v',
    'w',
    'x',
    'y',
    'z',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '+',
    '/',
    '='
} do
    b64toNum[strbyte(char, 1)] = b64code
    chars[b64code] = char
end

local professionIdToName = {
    A = 'Alchemy',
    B = 'Blacksmithing',
    C = 'Cooking',
    E = 'Enchanting',
    G = 'Engineering',
    H = 'Herbalism',
    I = 'Inscription',
    J = 'Jewelcrafting',
    L = 'Leatherworking',
    M = 'Mining',
    S = 'Skinning',
    T = 'Tailoring'
}

local firstEvent
local lastEvent

local function enqueueEvent(data)
    local event = {data = data}
    if not firstEvent then
        firstEvent = event
    else
        lastEvent.next = event
    end
    lastEvent = event
end

local function popNextEvent()
    if not firstEvent then return nil end
    local result = firstEvent
    firstEvent = firstEvent.next
    return result.data
end

local function professionNameToId(professionName)
    local id = strsub(professionName, 1, 1)
    if professionName == 'Engineering' then id = 'G' end
    return id
end

local function getSortedKeys(professionName)
    local keys = {}
    for key, _ in pairs(WhoCanDo.Database[professionName]) do tinsert(keys, key) end
    sort(keys)
    return keys
end

local function buildMessage(type, data) return PROTOCOL_VERSION .. DELIMITER .. type .. DELIMITER .. data end

local function compressGuildMetaData()
    local result = {}
    for professionName, profsData in pairs(WCDMetaData) do
        local subresult = {}
        if WhoCanDo.Database[professionName] then
            for name, total in pairs(profsData) do
                if tContains(WhoCanDo.Guildies, name) then tinsert(subresult, name .. '-' .. total) end
            end
            local profString = professionNameToId(professionName) .. ':' .. table.concat(subresult, ',')
            tinsert(result, profString)
        end
    end
    local rawData = table.concat(result, '*')
    local compressed = deflate:CompressDeflate(rawData, {level = COMPRESSION_LEVEL})
    local encoded = deflate:EncodeForWoWAddonChannel(compressed)
    return encoded
end

local function sendHello()
    local msg = buildMessage(MSG_HELLO, playerName)
    aceComm:SendCommMessage(PREFIX, msg, 'GUILD', nil, 'NORMAL')
end

local function sendHelloBack(target)
    local msg = buildMessage(MSG_HELLOBACK, playerName)
    aceComm:SendCommMessage(PREFIX, msg, 'WHISPER', target, 'NORMAL')
end

local function sendMetaData(channel, target)
    msg = compressGuildMetaData()
    aceComm:SendCommMessage(PREFIX_META, msg, channel, target, 'BULK')
end

local function sendImBoss()
    imBoss = true
    waitingForBoss = false
    bossName = playerName
    local msg = buildMessage(MSG_IM_BOSS, playerName)
    aceComm:SendCommMessage(PREFIX, msg, 'GUILD', nil, 'ALERT')
end

local function sendRequest(target, professionName, name)
    local msg = buildMessage(MSG_REQUEST, professionNameToId(professionName) .. ',' .. name)
    aceComm:SendCommMessage(PREFIX, msg, 'WHISPER', target, 'NORMAL')
end

local function sendRecipes(target, professionName, name)
    local sortedKeys = getSortedKeys(professionName)
    local data = {}
    local modStep = 0
    local currentValue = 0

    -- Pad the list of keys to be divisible by 6
    -- so we can correctly decode last char
    while #sortedKeys % 6 ~= 0 do tinsert(sortedKeys, 0) end

    for _, key in ipairs(sortedKeys) do
        local knows = WCDData[key] and tContains(WCDData[key], name)
        if knows then currentValue = currentValue + 1 end
        modStep = modStep + 1
        if modStep == 6 then
            tinsert(data, chars[currentValue])
            currentValue = 0
            modStep = 0
        else
            currentValue = currentValue * 2
        end
    end
    local strData = table.concat(data, '')
    local profId = professionNameToId(professionName)
    msgData = profId .. ',' .. name .. ',' .. strData
    local msg = buildMessage(MSG_RECIPES, msgData)
    local channel = target == 'GUILD' and 'GUILD' or 'WHISPER'
    aceComm:SendCommMessage(PREFIX, msg, channel, target, 'NORMAL')
end

local function updateRecipesFromMessage(message)
    local profId, name, data = strsplit(',', message)
    local professionName = professionIdToName[profId]
    local sortedKeys = getSortedKeys(professionName)
    for i = 0, (strlen(data) - 1) do
        local num = b64toNum[strbyte(data, i + 1)]
        for j = 5, 0, -1 do
            local spellId = sortedKeys[i * 6 + j + 1]
            if num % 2 == 1 then
                WhoCanDo:AddRecipe(professionName, spellId, name)
                num = num - 1
            end
            num = num / 2
        end
    end
end

local function compareAndSync(sender, compressedMsg)
    WhoCanDo:DebugLog('Compare and sync with', sender)
    local unmentionedCrafters = {}
    if imBoss then
        for professionName, metaData in pairs(WCDMetaData) do
            for name, _ in pairs(metaData) do
                unmentionedCrafters[professionName] = unmentionedCrafters[professionName] or {}
                unmentionedCrafters[professionName][name] = true
            end
        end
    end

    local decoded = deflate:DecodeForWoWAddonChannel(compressedMsg)
    local data = deflate:DecompressDeflate(decoded, {level = COMPRESSION_LEVEL})
    local profsData = {strsplit('*', data)}
    for _, profData in ipairs(profsData) do
        local profId, charactersData = strsplit(':', profData)
        if charactersData then
            local professionName = professionIdToName[profId]
            local entries = {strsplit(',', charactersData)}
            for _, entry in ipairs(entries) do
                local name, strOtherTotal = strsplit('-', entry)
                local otherTotal = tonumber(strOtherTotal)
                local ownTotal = (WCDMetaData[professionName] or {[name] = 0})[name]

                if imBoss then unmentionedCrafters[professionName][name] = false end

                if ownTotal < otherTotal then
                    enqueueEvent({type = MSG_REQUEST, name = name, profession = professionName, target = sender})
                elseif ownTotal > otherTotal then
                    if imBoss then
                        enqueueEvent({type = MSG_RECIPES, name = name, profession = professionName, target = sender})
                    end
                else
                    WhoCanDo:DebugLog(ownTotal .. ' entries on both ends for ' .. name .. "'s " .. professionName)
                end
            end
        end
    end

    if imBoss then
        for professionName, professionCrafters in pairs(unmentionedCrafters) do
            for name, unmentioned in pairs(professionCrafters) do
                if unmentioned then
                    WhoCanDo:DebugLog(sender, 'does not have', professionName, 'data for', name)
                    enqueueEvent({type = MSG_RECIPES, name = name, profession = professionName, target = sender})
                end
            end
        end
    end
end

local function registerAddonUser(name)
    if tContains(addonUsers, name) then return end
    tinsert(addonUsers, name)
    sort(addonUsers)
    WhoCanDo:DebugLog('New addon user ' .. name)
end

local function waitAndSnatchBoss(missedMsg)
    waitingForBoss = true
    local delay = 0
    for _, name in ipairs(addonUsers) do
        if name == playerName then break end
        delay = delay + 1.6 + fastrandom(30) / 10
    end
    C_Timer.After(delay, function()
        if waitingForBoss then
            sendImBoss()
            if missedMsg then WhoCanDo:ProcessGuildMsg(missedMsg, 'missed') end
        end
    end)
end

local function unregisterAddonUser(name)
    if not tContains(addonUsers, name) then return end
    for i = 1, #addonUsers do
        if addonUsers[i] == name then
            tremove(addonUsers, i)
            if bossName == name then waitAndSnatchBoss() end
            return
        end
    end
end

local function onCommReceived(prefix, msg, channel, sender)
    if sender == playerName then return end

    local proto, type, data = strsplit(DELIMITER, msg)

    if proto < PROTOCOL_VERSION then
        if not outOfDatMentioned then WhoCanDo:Log('You are using old version of WhoCanDo, consider updating') end
        outOfDatMentioned = true
        return
    end
    WhoCanDo:DebugLog(sender, 'sent', type, data)
    if type == MSG_HELLO then
        if imBoss then sendImBoss() end
        registerAddonUser(sender)
        sendHelloBack(sender)
    elseif type == MSG_HELLOBACK then
        registerAddonUser(sender)
    elseif type == MSG_IM_BOSS then
        imBoss = false
        waitingForBoss = false
        bossName = data
    elseif type == MSG_REQUEST then
        local profId, name = strsplit(',', data)
        local professionName = professionIdToName[profId]
        enqueueEvent({type = MSG_RECIPES, name = name, profession = professionName, target = sender})
    elseif type == MSG_RECIPES then
        updateRecipesFromMessage(data)
    elseif type == MSG_BYE then
        unregisterAddonUser(sender)
        if sender == bossName then waitAndSnatchBoss() end
    end
end

local function onMetaDataCommReceived(prefix, msg, channel, sender)
    if sender == playerName then return end
    WhoCanDo:DebugLog('Received meta data from', sender)
    compareAndSync(sender, msg)
end

local function processQueue()
    if InCombatLockdown() then return end
    local event = popNextEvent()
    if not event then return end
    if event.type == MSG_RECIPES then
        sendRecipes(event.target, event.profession, event.name)
    elseif event.type == MSG_REQUEST then
        sendRequest(event.target, event.profession, event.name)
    end
end

function WhoCanDo:AmBoss() return imBoss end

function WhoCanDo:InitializeSync()
    meta = WCDMetaData
    deflate = LibStub:GetLibrary("LibDeflate")
    aceComm = LibStub:GetLibrary("AceComm-3.0")
    aceComm:RegisterComm(PREFIX, onCommReceived)
    aceComm:RegisterComm(PREFIX_META, onMetaDataCommReceived)

    GuildRoster()
    C_Timer.After(3, function() sendHello() end)
    C_Timer.After(6, function() sendMetaData('GUILD') end)

    C_Timer.After(10, function() if waitingForBoss then waitAndSnatchBoss() end end)

    C_Timer.NewTicker(UPDATE_INTERVAL, processQueue)
end

function WhoCanDo:CheckOnBossReply(msg)
    waitingForBoss = true
    C_Timer.After(BOSS_TTL, function() if waitingForBoss then waitAndSnatchBoss(msg) end end)
end

function WhoCanDo:OnWCDMessageDetected() waitingForBoss = false end

function WhoCanDo:AnnounceNewData(professionName, name)
    enqueueEvent({type = MSG_RECIPES, name = name, profession = professionName, target = 'GUILD'})
end

function WhoCanDo:OnGuildMemberLoggedOff(name) unregisterAddonUser(name) end

function WhoCanDo:OnLogout()
    local msg = buildMessage(MSG_BYE, playerName)
    aceComm:SendCommMessage(PREFIX, msg, 'GUILD', nil, 'ALERT')
end

function WhoCanDo:GetAddonUsers() return addonUsers end
