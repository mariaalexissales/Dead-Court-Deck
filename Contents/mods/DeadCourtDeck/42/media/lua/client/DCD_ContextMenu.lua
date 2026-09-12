----------
--ESTRAL--
----------

require "DCD_Core"
require "DCD_Net"

DCD = DCD or {}
DCD_ContextMenu = DCD_ContextMenu or {}

-- matches the server's per-command cap, so open all never sends ids that get ignored.
local MAX_OPEN = 100

-- the menu hands back bare items for singles and { items = {...} } for stacks, where the
-- first entry repeats the second.
local function DCD_flatten(items)
    local out = {}

    for _, entry in ipairs(items) do
        if instanceof(entry, "InventoryItem") then
            out[#out + 1] = entry
        elseif type(entry) == "table" and entry.items then
            local first = #entry.items > 1 and 2 or 1
            for i = first, #entry.items do out[#out + 1] = entry.items[i] end
        end
    end

    return out
end

-- the server only looks in the player's own inventory, so a pack or card in a crate or on
-- the floor would be offered and then silently refused.
local function DCD_isCarried(player, item)
    local ok, carried = pcall(function() return player:getInventory():containsRecursive(item) end)
    return ok and carried
end

local function DCD_idsOf(list)
    local ids = {}
    for i = 1, math.min(#list, MAX_OPEN) do ids[#ids + 1] = list[i]:getID() end
    return ids
end

function DCD_ContextMenu.onOpen(player, ids)
    DCD_Net.toServer(player, "openPacks", { ids = ids })
end

function DCD_ContextMenu.onTrade(player, set)
    DCD_Net.toServer(player, "tradeSuit", { suit = set.suit, race = set.race, tier = set.tier })
end

local function DCD_tooltip(description)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    tooltip.description = description
    return tooltip
end

-- ---------------------------------------------------------------------------------------

local function DCD_packOptions(player, context, selected)
    local carried, loose = {}, nil

    for _, item in ipairs(selected) do
        if DCD.isPack(item) then
            if DCD_isCarried(player, item) then
                carried[#carried + 1] = item
            else
                loose = loose or item
            end
        end
    end

    if #carried == 0 then
        if loose then
            local option = context:addOption(DCD.text("ContextMenu_DCD_OpenPack", "Open Card Pack"))
            option.notAvailable = true
            option.itemForTexture = loose
            option.toolTip = DCD_tooltip(DCD.text("ContextMenu_DCD_NotCarried", "Pick it up first."))
        end
        return
    end

    local label = #carried == 1
        and DCD.text("ContextMenu_DCD_OpenPack", "Open Card Pack")
        or DCD.text("ContextMenu_DCD_OpenPacks", "Open %1 Card Packs", math.min(#carried, MAX_OPEN))

    local option = context:addOption(label, player, DCD_ContextMenu.onOpen, DCD_idsOf(carried))
    option.itemForTexture = carried[1]

    local all = player:getInventory():getAllEvalRecurse(function(item)
        return item:getFullType() == DCD.PACK
    end, ArrayList.new())

    if all:size() > #carried then
        local list = {}
        for i = 0, all:size() - 1 do list[#list + 1] = all:get(i) end

        local allOption = context:addOption(
            DCD.text("ContextMenu_DCD_OpenAllPacks", "Open All Card Packs (%1)", math.min(#list, MAX_OPEN)),
            player, DCD_ContextMenu.onOpen, DCD_idsOf(list))
        allOption.itemForTexture = carried[1]
    end
end

-- "Ace, 7, Queen" for the tooltip. the set name above it already says suit, race and tier.
local function DCD_missingList(missing)
    local names = {}
    for _, fullType in ipairs(missing) do
        local info = DCD.cards[fullType]
        names[#names + 1] = info and DCD.rankName(info.rank) or fullType
    end
    return table.concat(names, ", ")
end

local function DCD_setContains(set, info)
    return set.suit == info.suit and set.tier == info.tier and (info.race == nil or set.race == info.race)
end

local function DCD_cardOptions(player, context, selected)
    local card, info = nil, nil

    for _, item in ipairs(selected) do
        local cardInfo = DCD.cardInfo(item)
        if cardInfo and DCD_isCarried(player, item) then
            card, info = item, cardInfo
            break
        end
    end

    if not card then return end

    local held = DCD.scan(player:getInventory())

    -- only the sets this card is part of. offering a Standard suit off a right-clicked Bronze
    -- card reads as trading the wrong cards away.
    local sets = {}
    for _, set in ipairs(DCD.completeSets(held)) do
        if DCD_setContains(set, info) then sets[#sets + 1] = set end
    end

    local label = DCD.text("ContextMenu_DCD_TradeIn", "Trade In Full Suit")

    if #sets == 0 then
        local closest = DCD.closestSet(held, info)
        local option = context:addOption(label)
        option.notAvailable = true
        option.itemForTexture = card

        local text = DCD.text("ContextMenu_DCD_NoSet",
            "Needs all 13 cards of one suit, one tier, with court cards of one race.")
        if closest then
            text = text .. " <LINE> <LINE> "
                .. DCD.text("ContextMenu_DCD_Closest", "Closest: %1",
                    DCD.setName(closest.suit, closest.race, closest.tier))
                .. " <LINE> <RGB:1,0.5,0.5> "
                .. DCD.text("ContextMenu_DCD_Missing", "Missing %1: %2",
                    #closest.missing, DCD_missingList(closest.missing))
        end
        option.toolTip = DCD_tooltip(text)
        return
    end

    local option = context:addOption(label)
    option.itemForTexture = card
    local sub = context:getNew(context)
    context:addSubMenu(option, sub)

    for _, set in ipairs(sets) do
        local name = DCD.setName(set.suit, set.race, set.tier)
        if set.copies > 1 then
            name = DCD.text("ContextMenu_DCD_TradeCopies", "%1 (x%2)", name, set.copies)
        end

        local entry = sub:addOption(name, player, DCD_ContextMenu.onTrade, set)
        entry.toolTip = DCD_tooltip(DCD.text("ContextMenu_DCD_TradeTooltip",
            "Hands over 13 cards for the %1 court's reward, at %2 rarity.",
            DCD.raceName(set.race), DCD.tierName(set.tier)))
    end
end

local function DCD_onFillInventoryObjectContextMenu(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() then return end

    local selected = DCD_flatten(items)
    if #selected == 0 then return end

    DCD_packOptions(player, context, selected)
    DCD_cardOptions(player, context, selected)
end

Events.OnFillInventoryObjectContextMenu.Add(DCD_onFillInventoryObjectContextMenu)
