-- Handles items that modify stats on switch-in or via specific triggers
local stat_modifiers = {}

local switch_in_boosts = {
    -- Example: Life Orb (Damage boost, but takes damage)
    LIFEORB = function(pokemon, damage, move)
        return damage * 1.3
    end,
    -- Example: Choice Band/Specs
    CHOICEBAND = function(pokemon, damage, move)
        if move.category == "PHYSICAL" then return damage * 1.33 end
        return damage
    end,
}

stat_modifiers.apply_switch_in = function(pokemon)
    local item = pokemon.heldItem
    -- Logic for items that trigger a stat change immediately upon entering battle
    -- e.g., certain G9 items that set a stat stage
    if item == "SASH_BELT" then
        -- Specific logic for switch-in effects
    end
end

stat_modifiers.modify_damage = function(pokemon, damage, move)
    local item = pokemon.heldItem
    if item and switch_in_boosts[item] then
        return switch_in_boosts[item](pokemon, damage, move)
    end
    return damage
end

return stat_modifiers
