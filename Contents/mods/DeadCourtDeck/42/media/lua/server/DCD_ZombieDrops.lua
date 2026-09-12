----------
--ESTRAL--
----------

require "DCD_Core"
require "DCD_Packs"

if not DCD.isAuthority() then return end

-- the zombie's inventory becomes the corpse's, so a pack added here is found by searching
-- the body like any other loot.
local function DCD_onZombieDead(zombie)
    if not zombie then return end

    local chance = DCD.sandbox("ZombieDropChance", 1.0)
    if not DCD_Packs.rollPercent(chance) then return end

    local inventory = zombie:getInventory()
    if inventory then inventory:AddItem(DCD.PACK) end
end

Events.OnZombieDead.Add(DCD_onZombieDead)
