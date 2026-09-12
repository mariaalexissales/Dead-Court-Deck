----------
--ESTRAL--
----------

require "DCD_Core"
require "DCD_Json"

if not DCD.isAuthority() then return end

DCD = DCD or {}
DCD_Rewards = DCD_Rewards or {}

-- the admin's copy wins over the one shipped in the mod, and survives workshop updates. it is
-- written on first run, so there is always a file to edit.
local OVERRIDE = DCD.DIR .. "/rewards.json"

-- getFileWriter is not documented to create a missing subfolder, so this sits beside it in
-- Zomboid/Lua/ as the fallback.
local FLAT = "DeadCourtDeck_rewards.json"

-- seeded verbatim. kept here rather than read out of the mod folder so the reward table never
-- depends on getModFileReader resolving a b42 mod path.
local TEMPLATE = [==[
{
  "_readme": "Dummy rewards for testing - replace them with your own. Trading in a full suit pays the items listed under that set's race, each count multiplied by the set's tier (rounded down, at least 1). Keys starting with _ are ignored. This file is also written to Zomboid/Lua/DeadCourtDeck/rewards.json on first run, and that copy wins.",
  "_example": { "item": "Base.Axe", "count": 1 },

  "rarityMultiplier": {
    "Standard": 1,
    "Bronze": 2,
    "Silver": 3,
    "Gold": 5
  },

  "races": {
    "Human": {
      "items": [
        { "item": "Base.MetalPipe", "count": 2 }
      ]
    },

    "Goblin": {
      "items": [
        { "item": "Base.Money", "count": 5 }
      ]
    },

    "Elf": {
      "items": [
        { "item": "Base.BookForaging2", "count": 1 }
      ]
    },

    "Dwarf": {
      "items": [
        { "item": "Base.HandAxeForged", "count": 1 },
        { "item": "Base.MetalBar", "count": 2 }
      ]
    }
  }
}
]==]

-- b42 moved mod content under a version folder; which root getModFileReader resolves against
-- is not documented, so every layout is tried.
local BUNDLED = {
    "media/DeadCourtDeck/rewards.json",
    "42/media/DeadCourtDeck/rewards.json",
    "common/media/DeadCourtDeck/rewards.json",
}

local DEFAULT_MULTIPLIER = { Standard = 1, Bronze = 2, Silver = 3, Gold = 5 }

DCD_Rewards.data = DCD_Rewards.data or { rarityMultiplier = DEFAULT_MULTIPLIER, races = {} }
DCD_Rewards.source = DCD_Rewards.source or "none"

-- a missing file is either a nil reader or one whose first line is nil, build depending.
local function DCD_drain(reader)
    if not reader then return nil end

    local lines = {}
    local ok = pcall(function()
        local line = reader:readLine()
        while line do
            lines[#lines + 1] = line
            line = reader:readLine()
        end
    end)

    pcall(function() reader:close() end)

    if not ok or #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

local function DCD_readOverride()
    for _, path in ipairs({ OVERRIDE, FLAT }) do
        local ok, reader = pcall(function() return getFileReader(path, false) end)
        if ok and reader then
            local text = DCD_drain(reader)
            if text then return text, path end
        end
    end

    return nil
end

local function DCD_exists(path)
    local ok, found = pcall(function() return fileExists(path) end)
    return ok and found == true
end

-- the write is read back rather than trusted: a missing subfolder fails quietly.
local function DCD_writeFile(path, text)
    local ok, writer = pcall(function() return getFileWriter(path, true, false) end)
    if not ok or not writer then return false end

    local wrote = pcall(function() writer:write(text) end)
    pcall(function() writer:close() end)

    return wrote and DCD_exists(path)
end

-- first run only. an admin's edits are never overwritten.
function DCD_Rewards.seed()
    if DCD_exists(OVERRIDE) or DCD_exists(FLAT) then return end

    if DCD_writeFile(OVERRIDE, TEMPLATE) then
        DCD.log("wrote a starting rewards file to Zomboid/Lua/" .. OVERRIDE)
        return
    end

    if DCD_writeFile(FLAT, TEMPLATE) then
        DCD.log("wrote a starting rewards file to Zomboid/Lua/" .. FLAT
            .. ", the " .. DCD.DIR .. " folder could not be created")
        return
    end

    DCD.warn("could not write a rewards file. create Zomboid/Lua/" .. OVERRIDE .. " by hand.")
end

local function DCD_readBundled()
    for _, path in ipairs(BUNDLED) do
        local ok, reader = pcall(function() return getModFileReader(DCD.MOD_ID, path, false) end)
        if ok and reader then
            local text = DCD_drain(reader)
            if text then return text, path end
        end
    end
    return nil
end

-- json keys are hand-typed, so "gold" and "Gold" both mean Gold.
local function DCD_canonical(list)
    local out = {}
    for _, value in ipairs(list) do out[value:lower()] = value end
    return out
end

local RACE_KEY = DCD_canonical(DCD.RACES)
local TIER_KEY = DCD_canonical(DCD.TIERS)

local function DCD_itemExists(fullType)
    local ok, script = pcall(function() return getScriptManager():FindItem(fullType) end)
    return ok and script ~= nil
end

local function DCD_normalise(decoded, source)
    local out = { rarityMultiplier = {}, races = {} }
    local warnings = {}

    local function warn(message) warnings[#warnings + 1] = source .. ": " .. message end

    for tier, value in pairs(DEFAULT_MULTIPLIER) do out.rarityMultiplier[tier] = value end

    if type(decoded) ~= "table" then
        warn("expected an object at the top level")
        return out, warnings
    end

    if decoded.rarityMultiplier ~= nil then
        if type(decoded.rarityMultiplier) ~= "table" then
            warn("rarityMultiplier should be an object like { \"Gold\": 3 }")
        else
            for key, value in pairs(decoded.rarityMultiplier) do
                local tier = TIER_KEY[tostring(key):lower()]
                if not tier then
                    warn("rarityMultiplier has unknown tier " .. tostring(key))
                elseif type(value) ~= "number" or value < 0 then
                    warn("rarityMultiplier." .. tier .. " should be a number of 0 or more")
                else
                    out.rarityMultiplier[tier] = value
                end
            end
        end
    end

    if decoded.races ~= nil and type(decoded.races) ~= "table" then
        warn("races should be an object keyed by race name")
        return out, warnings
    end

    for key, def in pairs(decoded.races or {}) do
        local race = RACE_KEY[tostring(key):lower()]

        if not race then
            warn("unknown race " .. tostring(key) .. ", expected one of " .. table.concat(DCD.RACES, ", "))
        elseif type(def) ~= "table" then
            warn(race .. " should be an object with an items list")
        else
            local items = {}
            local list = def.items

            if list ~= nil and type(list) ~= "table" then
                warn(race .. ".items should be a list")
                list = nil
            end

            for index, entry in ipairs(list or {}) do
                local where = race .. ".items[" .. index .. "]"
                local count = type(entry) == "table" and entry.count or nil
                if count == nil then count = 1 end

                if type(entry) ~= "table" or type(entry.item) ~= "string" then
                    warn(where .. " needs an \"item\" full type, like \"Base.Axe\"")
                elseif type(count) ~= "number" or count <= 0 then
                    warn(where .. " count should be a number above 0")
                elseif not DCD_itemExists(entry.item) then
                    -- kept, not dropped: the item may come from a mod that loads later.
                    warn(where .. " " .. entry.item .. " is not a known item (typo, or a mod not loaded?)")
                    items[#items + 1] = { item = entry.item, count = count }
                else
                    items[#items + 1] = { item = entry.item, count = count }
                end
            end

            out.races[race] = { items = items }
        end
    end

    return out, warnings
end

-- quiet is for the reload a trade-in does: the file was already reported at startup, and
-- a warning per trade would bury the log.
function DCD_Rewards.load(quiet)
    local text, path = DCD_readOverride()
    local source = path and ("Zomboid/Lua/" .. path) or nil

    if not text then
        local bundledPath
        text, bundledPath = DCD_readBundled()
        source = bundledPath and ("mod:" .. bundledPath) or nil
    end

    if not text then
        DCD_Rewards.data = { rarityMultiplier = DEFAULT_MULTIPLIER, races = {} }
        DCD_Rewards.source = "none"
        if not quiet then DCD.warn("no rewards.json found. trade-ins will consume cards and give nothing.") end
        return DCD_Rewards.data
    end

    local decoded, err = DCD_Json.decode(text)
    if not decoded then
        -- a broken edit keeps the last good table rather than zeroing everyone's payout.
        DCD.warn(source .. ": " .. tostring(err) .. " (keeping the previous reward table)")
        return DCD_Rewards.data
    end

    local data, warnings = DCD_normalise(decoded, source)

    if not quiet then
        for _, message in ipairs(warnings) do DCD.warn(message) end

        local counts = {}
        for _, race in ipairs(DCD.RACES) do
            local def = data.races[race]
            counts[#counts + 1] = race .. "=" .. (def and #def.items or 0)
        end
        DCD.log("rewards from " .. source .. ": " .. table.concat(counts, ", "))
    end

    DCD_Rewards.data = data
    DCD_Rewards.source = source
    return data
end

-- one at a time rather than AddItems, so a container that fills partway through reports
-- how far it got.
local function DCD_giveItem(player, fullType, count)
    local inventory = player:getInventory()
    local given = 0

    for _ = 1, count do
        local item = inventory:AddItem(fullType)
        if not item then break end

        if isServer() then
            sendAddItemToContainer(inventory, item)
        end

        given = given + 1
    end

    return given
end

function DCD_Rewards.multiplier(tier)
    return DCD_Rewards.data.rarityMultiplier[tier] or DEFAULT_MULTIPLIER[tier] or 1
end

-- returns { { item, count } } of what actually landed, for the client's halo text.
function DCD_Rewards.grant(player, race, tier)
    if not player then return {} end

    -- re-read so an edited rewards.json applies on the next trade, no restart.
    DCD_Rewards.load(true)

    local def = DCD_Rewards.data.races[race]
    if not def or #def.items == 0 then
        DCD.log("no rewards defined for " .. tostring(race) .. " in " .. DCD_Rewards.source)
        return {}
    end

    local multiplier = DCD_Rewards.multiplier(tier)
    local granted = {}

    for _, entry in ipairs(def.items) do
        local raw = entry.count * multiplier
        -- a fractional multiplier still pays at least one; a zero multiplier pays nothing.
        local count = raw > 0 and math.max(1, math.floor(raw)) or 0

        if count > 0 then
            local given = DCD_giveItem(player, entry.item, count)
            if given < count then
                DCD.warn(tostring(player:getUsername()) .. ": only " .. given .. " of " .. count
                    .. " " .. entry.item .. " could be given")
            end
            if given > 0 then granted[#granted + 1] = { item = entry.item, count = given } end
        end
    end

    return granted
end

Events.OnInitGlobalModData.Add(function()
    DCD_Rewards.seed()
    DCD_Rewards.load(false)
end)
