local pma_voice = exports["pma-voice"]
local Framework = {}
local customPlayerNames = {}
local customRadioNames = {}

local function isPlayerAllowedToChangeName(_, _)
    return Config.LetPlayersSetTheirOwnNameInRadio
end
if Config.UseRPName then
    if GetResourceState("es_extended"):find("start") then
        Framework.Object = exports["es_extended"]:getSharedObject()
        Framework.Initial = "esx"
        Framework.GetPlayer = Framework.Object.GetPlayerFromId
        Framework.GetPlayerName = function(source)
            local xPlayer = Framework.GetPlayer(source)
            return xPlayer and xPlayer.getName() or nil
        end
    elseif GetResourceState("qb-core"):find("start") then
        Framework.Object = exports["qb-core"]:GetCoreObject()
        Framework.Initial = "qb"
        Framework.GetPlayer = Framework.Object.Functions.GetPlayer
        Framework.GetPlayerName = function(source)
            local xPlayer = Framework.GetPlayer(source)
            return xPlayer and ("%s %s"):format(xPlayer.PlayerData.charinfo.firstname, xPlayer.PlayerData.charinfo.lastname) or nil
        end
        isPlayerAllowedToChangeName = function(source, notify) -- override isPlayerAllowedToChangeName
            local response = Config.LetPlayersSetTheirOwnNameInRadio
            local xPlayer = Framework.GetPlayer(source)
            if xPlayer then
                if Config.JobsWithCallsign[xPlayer.PlayerData?.job?.name] and xPlayer.PlayerData?.job?.onduty then
                    response = false
                    if notify then
                        Config.Notification(source, "You cannot change your name on radio while on duty!", "error")
                    end
                end
            end
            return response
        end
    end
    Framework.Object = nil -- free up the memory
end

-- local function getPlayerIdentifier(source)
    -- local identifier
    -- for _, v in ipairs(GetPlayerIdentifiers(source)) do
        -- if string.match(v, "license:") then
            -- identifier = string.gsub(v, "license:", "")
            -- break
        -- end
    -- end
    -- return identifier
-- end

function GetPlayerIdentifierFromType(type, source)
	local identifiers = {}
	local identifierCount = GetNumPlayerIdentifiers(source)

	for a = 0, identifierCount do
		table.insert(identifiers, GetPlayerIdentifier(source, a))
	end

	for b = 1, #identifiers do
		if string.find(identifiers[b], type, 1) then
			return identifiers[b]
		end
	end
	return nil
end

--GetPlayerIdentifierFromType("license", playersource)
   
local function refreshRadioForPlayer(source)
    local currentRadioChannel = Player(source).state.radioChannel
    if not currentRadioChannel or not (currentRadioChannel > 0) then return end
    pma_voice:setPlayerRadio(source, 0)
    Wait(100)
    pma_voice:setPlayerRadio(source, currentRadioChannel)
end

local function setPlayerName(source, newName)
    local currentName = Player(source).state[Shared.State.nameInRadio]
    if currentName and currentName == newName then return end
    customPlayerNames[GetPlayerIdentifierFromType("license", source)] = newName
    Player(source).state:set(Shared.State.nameInRadio, newName, true)
    refreshRadioForPlayer(source)
    Config.Notification(source, ("Your name on radio changed to %s"):format(newName))
end

local function getPlayerName(source)
    local playerName = Player(source).state[Shared.State.nameInRadio]
    if not playerName then
        playerName = customPlayerNames[GetPlayerIdentifierFromType("license", source)] or (Config.UseRPName and Framework.GetPlayerName(source)) or GetPlayerName(source)
        setPlayerName(source, playerName)
    end
    return playerName
end

local function resetPlayerName(source)
    Player(source).state:set(Shared.State.nameInRadio, nil, true)
    getPlayerName(source)
    refreshRadioForPlayer(source)
end

local function getRadioChannelName(radioChannel)
    return customRadioNames[tostring(radioChannel)] or Config.RadioChannelsWithName[tostring(math.floor(radioChannel))] or radioChannel
end

local function modifyPermissionToSeeRadioList(source, state)
    Player(source).state:set(Shared.State.allowedToSeeRadioList, state, true)
end

callback.register(Shared.Callback.getPlayersInRadio, function(source, radioChannel)
    local playersInRadio = {}
    if not source then return playersInRadio end
    radioChannel = radioChannel or Player(source).state.radioChannel
    if not radioChannel then return playersInRadio end
    for player in pairs(pma_voice:getPlayersInRadioChannel(radioChannel)) do
        playersInRadio[player] = getPlayerName(player)
    end
    local radioChannelName = getRadioChannelName(radioChannel)
    return playersInRadio, radioChannel, radioChannelName
end)

callback.register(Shared.Callback.getPlayerName, function(_, player)
    return getPlayerName(player)
end)

if Config.LetPlayersSetTheirOwnNameInRadio then
    local commandLength = string.len(Config.RadioListChangeNameCommand)
    local argumentStartIndex = commandLength + 2
    RegisterCommand(Config.RadioListChangeNameCommand, function(source, _, rawCommand)
        if source and source > 0 then
            local customizedName = rawCommand:sub(argumentStartIndex)
            if customizedName ~= "" and customizedName ~= " " and customizedName ~= nil then
                if isPlayerAllowedToChangeName(source, true) then
                    setPlayerName(source, customizedName)
                end
            end
        end
    end, false)
end

if Config.LetPlayersChangeRadioChannelsName then
    local commandLength = string.len(Config.ModifyRadioChannelNameCommand)
    local argumentStartIndex = commandLength + 2
    RegisterCommand(Config.ModifyRadioChannelNameCommand, function(source, _, rawCommand)
        if source and source > 0 then
            local currentRadioChannel = Player(source).state.radioChannel
            if not currentRadioChannel or not (currentRadioChannel > 0) then
                return Config.Notification(source, "You must be in a radio channel to modify its name!", "error")
            end
            local customizedName = rawCommand:sub(argumentStartIndex)
            if customizedName ~= "" and customizedName ~= " " and customizedName ~= nil then
                if not Config.LetPlayersOverrideRadioChannelsWithName and Config.RadioChannelsWithName[tostring(math.floor(currentRadioChannel))] then
                    return Config.Notification(source, "You are not permitted to change this radio channel name!", "error")
                end
                customRadioNames[tostring(currentRadioChannel)] = customizedName
                for player in pairs(pma_voice:getPlayersInRadioChannel(currentRadioChannel)) do
                    refreshRadioForPlayer(player)
                    Config.Notification(player, ("Player %s changed the radio channel(%s)'s name to %s"):format(Player(source).state[Shared.State.nameInRadio], currentRadioChannel, customizedName))
                end
            end
        end
    end, false)
end

local function onPlayerDropped(source)
    if Config.ResetPlayersCustomizedNameOnExit then
        local playerIdentifier = GetPlayerIdentifierFromType("license", source)
        if customPlayerNames[playerIdentifier] then
            customPlayerNames[playerIdentifier] = nil
            Player(source).state:set(Shared.State.nameInRadio, nil, true)
        end
    end
    Player(source).state:set(Shared.State.callsignIsSet, nil)
end

local function onResourceStopped(resource)
    if resource ~= Shared.currentResourceName then return end
    for _, source in pairs(GetPlayers()) do
        onPlayerDropped(source)
    end
end

AddEventHandler("playerDropped", function()
    onPlayerDropped(source)
end)

AddEventHandler("onResourceStop", function(resource)
    onResourceStopped(resource)
end)

AddEventHandler("onServerResourceStop", function(resource)
    onResourceStopped(resource)
end)

if Framework.Initial == "esx" then
    AddEventHandler("esx:playerLoaded", function(playerId, xPlayer, _)
        if Config.RadioListOnlyShowsToGroupsWithAccess then
            local allowedToSeeRadioList = Config.GroupsWithAccessToTheRadioList[xPlayer?.getJob()?.name]
            modifyPermissionToSeeRadioList(playerId, allowedToSeeRadioList)
        end
    end)

    AddEventHandler("esx:setJob", function(source, job, _)
        if Config.RadioListOnlyShowsToGroupsWithAccess then
            local allowedToSeeRadioList = Config.GroupsWithAccessToTheRadioList[job?.name]
            modifyPermissionToSeeRadioList(source, allowedToSeeRadioList)
        end
    end)

    AddEventHandler("esx:playerDropped", function(source)
        onPlayerDropped(source)
    end)
elseif Framework.Initial == "qb" then
    AddEventHandler("QBCore:Player:SetPlayerData", function(playerData)
        local source = playerData.source
        if not source then return end
        local isAllowedToChangeName = isPlayerAllowedToChangeName(source, false)
        local hasCallsignSetAsName = Player(source).state[Shared.State.callsignIsSet]
        if not isAllowedToChangeName then
            setPlayerName(source, playerData.metadata?.callsign or Player(source).state[Shared.State.nameInRadio])
            Player(source).state:set(Shared.State.callsignIsSet, true)
        elseif isAllowedToChangeName and hasCallsignSetAsName then
            resetPlayerName(source)
            Player(source).state:set(Shared.State.callsignIsSet, false)
        end
        if Config.RadioListOnlyShowsToGroupsWithAccess then
            local allowedToSeeRadioList = (Config.GroupsWithAccessToTheRadioList[playerData.job?.name] and playerData.job?.onduty) or Config.GroupsWithAccessToTheRadioList[playerData.gang?.name]
            modifyPermissionToSeeRadioList(source, allowedToSeeRadioList)
        end
    end)

    AddEventHandler("QBCore:Server:OnPlayerUnload", function(source)
        onPlayerDropped(source)
    end)
end
