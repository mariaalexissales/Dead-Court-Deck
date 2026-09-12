----------
--ESTRAL--
----------

require "DCD_Core"

if not DCD.isAuthority() then return end

DCD = DCD or {}
DCD_Packs = DCD_Packs or {}

-- ZombRand is integer-only. a million steps is fine enough for a 0.01% court chance.
local STEPS = 1000000

function DCD_Packs.rollPercent(chance)
    if not chance or chance <= 0 then return false end
    if chance >= 100 then return true end
    return ZombRand(STEPS) < chance * (STEPS / 100)
end

local function DCD_pickUniform(list)
    return list[ZombRand(#list) + 1]
end

-- weights come off the sandbox, so all-zero is a real input. it falls back to uniform rather
-- than handing out nothing.
local function DCD_pickWeighted(list, weights)
    local total = 0
    for i = 1, #list do total = total + math.max(0, weights[i] or 0) end
    if total <= 0 then return DCD_pickUniform(list) end

    local roll = ZombRand(STEPS) / STEPS * total
    for i = 1, #list do
        roll = roll - math.max(0, weights[i] or 0)
        if roll < 0 then return list[i] end
    end

    return list[#list]
end

local function DCD_raceWeights()
    local out = {}
    for i, race in ipairs(DCD.RACES) do
        out[i] = DCD.sandbox("RaceWeight" .. race, 25)
    end
    return out
end

-- in DCD.TIERS order: Standard, Bronze, Silver, Gold.
local function DCD_tierWeights()
    return {
        DCD.sandbox("StandardWeight", 70),
        DCD.sandbox("BronzeWeight", 20),
        DCD.sandbox("SilverWeight", 8),
        DCD.sandbox("GoldWeight", 2),
    }
end

-- each card rolls on its own, so a pack can hold several courts or none. duplicates allowed.
function DCD_Packs.rollCard()
    local suit = DCD_pickUniform(DCD.SUITS)
    local tier = DCD_pickWeighted(DCD.TIERS, DCD_tierWeights())

    if DCD_Packs.rollPercent(DCD.sandbox("CourtChance", 10)) then
        local rank = DCD_pickUniform(DCD.COURT_RANKS)
        local race = DCD_pickWeighted(DCD.RACES, DCD_raceWeights())
        return DCD.cardType(suit, rank, race, tier)
    end

    return DCD.cardType(suit, DCD_pickUniform(DCD.PLAIN_RANKS), nil, tier)
end

function DCD_Packs.roll()
    local out = {}
    for i = 1, DCD.PACK_SIZE do out[i] = DCD_Packs.rollCard() end
    return out
end
