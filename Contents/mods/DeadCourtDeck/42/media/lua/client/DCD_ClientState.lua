----------
--ESTRAL--
----------

require "DCD_Core"

DCD = DCD or {}
DCD_ClientState = DCD_ClientState or {}

-- a single pack always shows every card. past this, open all only calls out the rare pulls.
local MAX_LINES = 8

local function DCD_player(args)
    local player = args and args.playerNum and getSpecificPlayer(args.playerNum)
    return player or getPlayer()
end

local function DCD_halo(player, text, color)
    if color then
        local ok = pcall(function()
            HaloTextHelper.addText(player, text, "[br/]", color[1], color[2], color[3])
        end)
        if ok then return end
    end
    HaloTextHelper.addText(player, text)
end

local function DCD_refreshInventory()
    pcall(function() ISInventoryPage.dirtyUI() end)
end

local function DCD_isRare(info)
    return info and (info.race ~= nil or info.tier == "Gold")
end

local function DCD_showCard(player, fullType)
    local info = DCD.cards[fullType]
    local color = info and DCD.cardColor(info.suit, info.tier)
    local name = getItemNameFromFullType(fullType) or fullType
    -- a court pull gets a marker on top of its tier colour, so it reads from across the screen.
    if info and info.race then name = "* " .. name .. " *" end
    DCD_halo(player, name, color)
end

local handlers = {}

function handlers.opened(player, args)
    local cards = args.cards or {}

    if #cards <= MAX_LINES then
        for _, fullType in ipairs(cards) do DCD_showCard(player, fullType) end
        return
    end

    DCD_halo(player, DCD.text("IGUI_DCD_OpenedPacks", "Opened %1 packs: %2 cards", args.packs or 0, #cards))

    local rare = {}
    for _, fullType in ipairs(cards) do
        if DCD_isRare(DCD.cards[fullType]) then rare[#rare + 1] = fullType end
    end

    for i = 1, math.min(#rare, MAX_LINES - 1) do DCD_showCard(player, rare[i]) end

    if #rare > MAX_LINES - 1 then
        DCD_halo(player, DCD.text("IGUI_DCD_MoreRare", "+%1 more rare pulls", #rare - (MAX_LINES - 1)))
    end
end

function handlers.traded(player, args)
    local name = DCD.setName(args.suit, args.race, args.tier)
    DCD_halo(player, DCD.text("IGUI_DCD_Traded", "Traded in %1", name), DCD.cardColor(args.suit, args.tier))

    local rewards = args.rewards or {}
    if #rewards == 0 then
        HaloTextHelper.addBadText(player, DCD.text("IGUI_DCD_NoRewards",
            "The %1 court has nothing to give yet", DCD.raceName(args.race)))
        return
    end

    for _, entry in ipairs(rewards) do
        local itemName = getItemNameFromFullType(entry.item) or entry.item
        HaloTextHelper.addGoodText(player, "+" .. tostring(entry.count) .. " " .. itemName)
    end
end

function handlers.refused(player, args)
    local key = "IGUI_DCD_Refused_" .. tostring(args.reason)
    HaloTextHelper.addBadText(player, DCD.text(key, "Can't do that right now"))
end

-- MP: OnServerCommand. SP: DCD_Net.toClient calls this directly.
function DCD_ClientState.onCommand(module, command, args)
    if module ~= DCD.MODULE then return end

    local handler = handlers[command]
    if not handler then return end

    args = args or {}
    local player = DCD_player(args)
    if not player then return end

    handler(player, args)
    DCD_refreshInventory()
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= DCD.MODULE then return end

    local ok, err = pcall(DCD_ClientState.onCommand, module, command, args)
    if not ok then DCD.warn("client command " .. tostring(command) .. " failed: " .. tostring(err)) end
end)
