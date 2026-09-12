----------
--ESTRAL--
----------

DCD = DCD or {}

DCD.MODULE = "DCD"
DCD.MOD_ID = "DeadCourtDeck"
DCD.ITEM_MODULE = "DeadCourtDeck"
DCD.PACK = "DeadCourtDeck.CardPack"
DCD.PACK_SIZE = 5

-- under Zomboid/Lua/, not the mod folder: Steam overwrites that on every workshop update.
DCD.DIR = "DeadCourtDeck"

-- these lists and tools/gen_cards.ps1 describe the same 352 cards. change one, change both.
DCD.SUITS = { "Hearts", "Diamonds", "Clubs", "Spades" }
DCD.RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }
-- the art has no race version of the Ace, so it sits with the plain ranks and only the
-- Jack, Queen and King carry a race.
DCD.PLAIN_RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10" }
DCD.COURT_RANKS = { "J", "Q", "K" }
DCD.RACES = { "Human", "Goblin", "Elf", "Dwarf" }
DCD.TIERS = { "Standard", "Bronze", "Silver", "Gold" }

DCD.RANK_NAMES = { A = "Ace", J = "Jack", Q = "Queen", K = "King" }

DCD.TIER_COLORS = {
    Bronze = { 205, 127, 50 },
    Silver = { 200, 200, 210 },
    Gold   = { 255, 215, 0 },
}

-- the common tier is printed in its suit's colour. clubs are black on the card, which would
-- be unreadable as halo text, so they read as a light grey instead.
DCD.SUIT_COLORS = {
    Hearts   = { 220, 60, 60 },
    Spades   = { 90, 200, 220 },
    Clubs    = { 175, 175, 185 },
    Diamonds = { 80, 200, 110 },
}

function DCD.cardColor(suit, tier)
    if tier == "Standard" then return DCD.SUIT_COLORS[suit] end
    return DCD.TIER_COLORS[tier]
end

local function DCD_lookup(list)
    local out = {}
    for i, value in ipairs(list) do out[value] = i end
    return out
end

DCD.IS_SUIT = DCD_lookup(DCD.SUITS)
DCD.IS_COURT = DCD_lookup(DCD.COURT_RANKS)
DCD.IS_RACE = DCD_lookup(DCD.RACES)
DCD.IS_TIER = DCD_lookup(DCD.TIERS)

-- server/ lua loads on multiplayer clients too, and isServer() is false in singleplayer.
function DCD.isAuthority()
    return not (isClient() and not isServer())
end

function DCD.hasRemoteServer()
    return isClient() and not isServer()
end

function DCD.log(message)
    print("[DCD] " .. tostring(message))
end

function DCD.warn(message)
    print("[DCD] WARN: " .. tostring(message))
end

-- only for the fallback string. the game stores a loaded translation with java's %1$s
-- placeholders, so both spellings are filled here.
local function DCD_fill(text, ...)
    local args = { ... }

    for i = 1, select("#", ...) do
        local arg = tostring(args[i]):gsub("%%", "%%%%")
        text = text:gsub("%%" .. i .. "%$s", arg)
        text = text:gsub("%%" .. i, arg)
    end

    return text
end

-- getText does the substitution itself, and hands back the key when there is no such key.
-- pcall because a translation whose placeholder count does not match the arguments throws
-- out of java rather than returning anything.
function DCD.text(key, fallback, ...)
    local ok, value = pcall(getText, key, ...)
    if ok and value and value ~= "" and value ~= key then return value end

    return DCD_fill(fallback or key, ...)
end

-- SandboxVars.DeadCourtDeck is nil until the sandbox loads, so every read has a default.
function DCD.sandbox(name, default)
    local vars = SandboxVars and SandboxVars.DeadCourtDeck
    local value = vars and vars[name]
    if value == nil then return default end
    return value
end

-- ---------------------------------------------------------------------------------------
-- card table
-- ---------------------------------------------------------------------------------------

function DCD.cardType(suit, rank, race, tier)
    if DCD.IS_COURT[rank] then
        return DCD.ITEM_MODULE .. ".Card_" .. suit .. "_" .. rank .. "_" .. race .. "_" .. tier
    end
    return DCD.ITEM_MODULE .. ".Card_" .. suit .. "_" .. rank .. "_" .. tier
end

function DCD.setKey(suit, race, tier)
    return suit .. "|" .. race .. "|" .. tier
end

-- fullType -> { suit, rank, race, tier }. race is nil on the Ace and the number cards.
DCD.cards = {}

-- setKey -> the 13 full types that make that set, in rank order.
DCD.sets = {}

for _, suit in ipairs(DCD.SUITS) do
    for _, tier in ipairs(DCD.TIERS) do
        for _, race in ipairs(DCD.RACES) do
            local members = {}

            for _, rank in ipairs(DCD.RANKS) do
                local fullType = DCD.cardType(suit, rank, race, tier)
                members[#members + 1] = fullType

                -- raceless cards land here once per race; the info is identical each time.
                DCD.cards[fullType] = {
                    suit = suit,
                    rank = rank,
                    race = DCD.IS_COURT[rank] and race or nil,
                    tier = tier,
                }
            end

            DCD.sets[DCD.setKey(suit, race, tier)] = members
        end
    end
end

function DCD.cardInfo(item)
    if not item then return nil end
    return DCD.cards[item:getFullType()]
end

function DCD.isPack(item)
    return item ~= nil and item:getFullType() == DCD.PACK
end

function DCD.rankName(rank)
    return DCD.text("IGUI_DCD_Rank_" .. rank, DCD.RANK_NAMES[rank] or rank)
end

function DCD.raceName(race)
    return DCD.text("IGUI_DCD_Race_" .. race, race)
end

function DCD.tierName(tier)
    return DCD.text("IGUI_DCD_Tier_" .. tier, tier)
end

function DCD.suitName(suit)
    return DCD.text("IGUI_DCD_Suit_" .. suit, suit)
end

-- "Gold Goblin Hearts"
function DCD.setName(suit, race, tier)
    return DCD.text("IGUI_DCD_SetName", "%1 %2 %3", DCD.tierName(tier), DCD.raceName(race), DCD.suitName(suit))
end

-- ---------------------------------------------------------------------------------------
-- inventory scan. the client menu and the server check both call these, so the menu can
-- only offer what the server will accept.
-- ---------------------------------------------------------------------------------------

-- fullType -> list of card items, carried bags included.
function DCD.scan(inventory)
    local held = {}
    if not inventory then return held end

    local found = inventory:getAllEvalRecurse(function(item)
        return DCD.cards[item:getFullType()] ~= nil
    end, ArrayList.new())

    for i = 0, found:size() - 1 do
        local item = found:get(i)
        local fullType = item:getFullType()
        local list = held[fullType]
        if not list then
            list = {}
            held[fullType] = list
        end
        list[#list + 1] = item
    end

    return held
end

-- how many full copies of this set the scan holds. 0 means incomplete.
function DCD.copiesOf(held, suit, race, tier)
    local members = DCD.sets[DCD.setKey(suit, race, tier)]
    if not members then return 0 end

    local copies = nil
    for _, fullType in ipairs(members) do
        local count = held[fullType] and #held[fullType] or 0
        if copies == nil or count < copies then copies = count end
    end

    return copies or 0
end

function DCD.missing(held, suit, race, tier)
    local out = {}
    local members = DCD.sets[DCD.setKey(suit, race, tier)]
    if not members then return out end

    for _, fullType in ipairs(members) do
        if not held[fullType] or #held[fullType] == 0 then out[#out + 1] = fullType end
    end

    return out
end

-- every complete set held, in suit / race / tier order so the menu does not reshuffle.
-- a raceless card counts toward every race's set, so two sets can share a 7 of Hearts. copies is
-- per set; trading one set in can drop another set's count.
function DCD.completeSets(held)
    local out = {}

    for _, suit in ipairs(DCD.SUITS) do
        for _, race in ipairs(DCD.RACES) do
            for _, tier in ipairs(DCD.TIERS) do
                local copies = DCD.copiesOf(held, suit, race, tier)
                if copies > 0 then
                    out[#out + 1] = { suit = suit, race = race, tier = tier, copies = copies }
                end
            end
        end
    end

    return out
end

-- the set a clicked card is closest to finishing. a court card only belongs to its own race's
-- set; a raceless card is weighed against all four and the fewest-missing race wins.
function DCD.closestSet(held, info)
    if not info then return nil end

    local races = info.race and { info.race } or DCD.RACES
    local best = nil

    for _, race in ipairs(races) do
        local missing = DCD.missing(held, info.suit, race, info.tier)
        if not best or #missing < #best.missing then
            best = { suit = info.suit, race = race, tier = info.tier, missing = missing }
        end
    end

    return best
end
