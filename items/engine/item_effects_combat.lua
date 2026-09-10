local mod = nil -- Injected via loader or global

-- Showdown-based Damage Multipliers
-- These are applied in a specific order: 
-- 1. Choice items (Band/Specs)
-- 2. Life Orb / Damage Boosting items
-- 3. Specific Ability-synergies
local DAMAGE_MODS = {
    -- Attack Boosters
    ["CHOICE_BAND"] = { multiplier = 1.33, target = "attack" },
    ["LIFE_ORB"] = { multiplier = 1.3, side_effect = "recoil", recoil_pct = 0.125 },
    ["EXP_SHARE"] = { multiplier = 1.0, target = "none" },
}

-- Showdown-based Status Inducers
local STATUS_ITEMS = {
    ["SERENE_GRACE_SASH"] = { chance = 0.1, status = "confused" },
    ["TOXIC_ORB"] = { trigger = "switch_in", status = "poisoned", chance = 1.0 },
    ["FLAMING_SASH"] = { trigger = "hit", status = "burned", chance = 0.3 },
}

-- Utility / Complex Logic Items
local UTILITY_ITEMS = {
    ["SITRUS_BERRY"] = { trigger = "hp_threshold", threshold = 0.5, heal_amount = 0.25 },
    ["CRIF_BERRY"] = { trigger = "status_inflict", status = "frozen", heal_amount = 0.25 },
}

local ItemCombat = {}

-- Processes damage modifiers before passing to engine
function ItemCombat.applyDamageModifiers(attacker, defender, baseDamage)
    local finalDamage = baseDamage
    local item = attacker.heldItem

    if item and DAMAGE_MODS[item.id] then
        local modData = DAMAGE_MODS[item.id]
        finalDamage = finalDamage * modData.multiplier
        
        -- Handle side effects (e.g. Life Orb recoil)
        if modData.side_effect == "recoil" then
            attacker:applyDamage(baseDamage * modData.recoil_pct, "recoil")
        end
    end

    return finalDamage
end

-- Handles status trigger items based on event
function ItemCombat.handleStatusTrigger(event, pokemon)
    local item = pokemon.heldItem
    if not item or not STATUS_ITEMS[item.id] then return end

    local statusData = STATUS_ITEMS[item.id]
    if event == "switch_in" and statusData.trigger == "switch_in" then
        if math.random() <= statusData.chance then
            pokemon:setStatus(statusData.status)
        end
    end
end

-- Logic for Berry consumption
function ItemCombat.handleBerryTrigger(pokemon, event)
    local item = pokemon.heldItem
    if not item or not UTILITY_ITEMS[item.id] then return end

    local berry = UTILITY_ITEMS[item.id]
    if event == "hp_threshold" and pokemon.hp / pokemon.maxHp <= berry.threshold then
        pokemon:heal(pokemon.maxHp * berry.heal_amount)
        pokemon:consumeItem() -- Remove item
    end
end

return ItemCombat
