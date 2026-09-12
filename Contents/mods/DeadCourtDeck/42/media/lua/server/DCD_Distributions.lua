----------
--ESTRAL--
----------

require "Items/ProceduralDistributions"

local ProceduralDistributions_list = ProceduralDistributions.list
local table_insert = table.insert

-- the places vanilla already drops a deck of cards, plus a few a kid or an office would keep
-- a pack in. weights sit near vanilla CardDeck in the same tables.
local TABLES = {
    BedroomDresser        = 1,
    BedroomSidetable      = 1,
    BedroomDresserChild   = 3,
    BedroomSidetableChild = 3,
    WardrobeChild         = 2,
    LivingRoomShelf       = 1,
    LivingRoomSideTable   = 1,
    DeskGeneric           = 1,
    OfficeDeskHome        = 1,
    ClassroomDesk         = 1,
    SchoolLockers         = 1,
    PoliceDesk            = 1,
    SecurityDesk          = 1,
    RecRoomShelf          = 4,
    CrateRandomJunk       = 0.5,
    CrateToys             = 6,
    GigamartToys          = 6,
    GiftStoreToys         = 6,
    Hobbies               = 6,
    BookstoreHobbies      = 6,
}

-- SandboxVars.DeadCourtDeck is nil at file-load time, so packs go in at base weight now and
-- are recorded here to be rescaled once the sandbox exists.
local slots = {}

for tableName, weight in pairs(TABLES) do
    local distribution = ProceduralDistributions_list[tableName]
    local items = distribution and distribution.items

    if items then
        table_insert(items, "DeadCourtDeck.CardPack")
        table_insert(items, weight)
        slots[#slots + 1] = { items = items, index = #items, base = weight }
    else
        print("[DCD] WARN: loot table " .. tableName .. " not found, skipped")
    end
end

-- recomputed from the base weight each time, so running twice never compounds.
local function DCD_applyLootWeight()
    local vars = SandboxVars and SandboxVars.DeadCourtDeck
    if not vars then return end

    local multiplier = vars.PackLootWeight
    if type(multiplier) ~= "number" or multiplier < 0 then multiplier = 1.0 end

    for _, slot in ipairs(slots) do
        -- skip if another mod shifted our entry out from under the index.
        if slot.items[slot.index - 1] == "DeadCourtDeck.CardPack" then
            slot.items[slot.index] = slot.base * multiplier
        end
    end
end

-- whichever fires first with the sandbox loaded wins; the other is a harmless re-run.
if Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(DCD_applyLootWeight)
end
if Events.OnPreDistributionMerge then
    Events.OnPreDistributionMerge.Add(DCD_applyLootWeight)
end
