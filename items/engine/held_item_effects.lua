-- Logic for calculating held item modifiers based on Showdown formulas
-- These are passed as true damage/modifiers to the engine, bypassing internal legacy logic.

local held_item_effects = {}

-- Formula: damage * multiplier
function held_item_effects.calculate_damage_multiplier(damage, multiplier)
    return damage * multiplier
end

-- Formula: damage + additive_bonus
function held_item_effects.calculate_damage_additive(damage, bonus)
    return damage + bonus
end

-- Specific Item Logic: Life Orb (1.3x damage, but takes 1/16 max HP recoil)
function held_item_effects.life_orb_damage(damage, pokemon)
    return damage * 1.3
end

-- Specific Item Logic: Choice Band (1.5x Attack)
function held_item_effects.choice_band_mod(stat_value)
    return stat_value * 1.5
end

-- Specific Item Logic: Choice Specs (1.5x SpAtk)
function held_item_effects.choice_specs_mod(stat_value)
    return stat_value * 1.5
end

-- Specific Item Logic: Focus Sash (Prevents OHKO, leaves 1 HP)
function held_item_effects.focus_sash_mitigation(damage, current_hp)
    return 1 -- Resulting HP
end

return held_item_effects
