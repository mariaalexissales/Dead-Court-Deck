----------
--ESTRAL--
----------

require "DCD_Core"
require "DCD_Net"
require "DCD_Packs"
require "DCD_Rewards"

if not DCD.isAuthority() then return end

DCD = DCD or {}
DCD_Commands = DCD_Commands or {}

-- open all sends every id in one command. past this the player clicks again.
local MAX_PACKS_PER_COMMAND = 100
local OPEN_COOLDOWN_MS = 250
local TRADE_COOLDOWN_MS = 1000

-- runtime only. a rate limit has no business surviving a restart or sitting in the save.
local lastOpen = {}
local lastTrade = {}

local function DCD_cooledDown(ledger, player, window)
    local name = tostring(player:getUsername())
    local now = getTimestampMs()
    if now - (ledger[name] or 0) < window then return false end
    ledger[name] = now
    return true
end

-- the item's own container, not the main inventory: a card in a backpack lives in the backpack.
local function DCD_remove(player, item)
    local container = item:getContainer()
    if not container then return false end

    player:removeFromHands(item)

    if isServer() then
        sendRemoveItemFromContainer(container, item)
    end
    container:Remove(item)

    return true
end

local function DCD_add(inventory, fullType)
    local item = inventory:AddItem(fullType)
    if not item then return nil end

    if isServer() then
        sendAddItemToContainer(inventory, item)
    end

    return item
end

-- a favourited card is one the player meant to keep, so it goes last when there are spares.
local function DCD_pickCopy(copies)
    for _, item in ipairs(copies) do
        if not item:isFavorite() then return item end
    end
    return copies[1]
end

DCD_Commands.handlers = {}

-- ids only. the server finds the packs in its own copy of the inventory, so a crafted packet
-- cannot open a pack the player is not carrying.
function DCD_Commands.handlers.openPacks(player, args)
    if not player or not args or type(args.ids) ~= "table" then return end
    if not DCD_cooledDown(lastOpen, player, OPEN_COOLDOWN_MS) then return end

    local inventory = player:getInventory()
    local packs = {}

    local found = inventory:getAllEvalRecurse(function(item)
        return item:getFullType() == DCD.PACK
    end, ArrayList.new())

    for i = 0, found:size() - 1 do
        local item = found:get(i)
        packs[item:getID()] = item
    end

    local cards = {}
    local opened = 0

    for _, raw in ipairs(args.ids) do
        if opened >= MAX_PACKS_PER_COMMAND then break end

        local id = tonumber(raw)
        local pack = id and packs[id]

        if pack then
            -- the same id twice in one packet opens once.
            packs[id] = nil

            if DCD_remove(player, pack) then
                opened = opened + 1
                for _, fullType in ipairs(DCD_Packs.roll()) do
                    if DCD_add(inventory, fullType) then cards[#cards + 1] = fullType end
                end
            end
        end
    end

    if opened > 0 then
        DCD_Net.toClient(player, "opened", { packs = opened, cards = cards })
    end
end

-- the client names a set; which cards make it, and whether they are held, is decided here.
function DCD_Commands.handlers.tradeSuit(player, args)
    if not player or not args then return end

    local suit, race, tier = args.suit, args.race, args.tier
    if not (DCD.IS_SUIT[suit] and DCD.IS_RACE[race] and DCD.IS_TIER[tier]) then return end
    if not DCD_cooledDown(lastTrade, player, TRADE_COOLDOWN_MS) then return end

    local held = DCD.scan(player:getInventory())
    local missing = DCD.missing(held, suit, race, tier)

    if #missing > 0 then
        -- the menu only offers complete sets, so this is a stale menu or someone going around it.
        DCD_Net.toClient(player, "refused", { reason = "Incomplete", suit = suit, race = race, tier = tier })
        return
    end

    local chosen = {}
    for _, fullType in ipairs(DCD.sets[DCD.setKey(suit, race, tier)]) do
        local item = DCD_pickCopy(held[fullType])
        if not item:getContainer() then
            DCD_Net.toClient(player, "refused", { reason = "Incomplete", suit = suit, race = race, tier = tier })
            return
        end
        chosen[#chosen + 1] = item
    end

    -- every card is confirmed before any is taken, so a trade is all 13 or nothing.
    for _, item in ipairs(chosen) do DCD_remove(player, item) end

    local granted = DCD_Rewards.grant(player, race, tier)

    DCD.log(tostring(player:getUsername()) .. " traded in " .. suit .. "/" .. race .. "/" .. tier
        .. " for " .. #granted .. " reward lines")

    DCD_Net.toClient(player, "traded", { suit = suit, race = race, tier = tier, rewards = granted })
end

local function DCD_onClientCommand(module, command, player, args)
    if module ~= DCD.MODULE then return end

    local handler = DCD_Commands.handlers[command]
    if not handler then return end

    local ok, err = pcall(handler, player, args)
    if not ok then DCD.warn("command " .. tostring(command) .. " failed: " .. tostring(err)) end
end

Events.OnClientCommand.Add(DCD_onClientCommand)
