-- Handles held items that modify stats (Choice Band, Life Orb, etc.)
-- Logic is applied during damage calculation or move selection
local stat_modifiers = {}

local MODIFIERS = {
    ["CHOICE_BAND"] = { stat = "attack", multiplier = 1.5, trigger = "damage_calc" },
    ["CHOICE_SCARF"] = { stat = "speed", multiplier = 1.5, trigger = "init" },
    ["LIFE_ORB"] = { stat = "all", multiplier = 1.3, trigger = "damage_calc", recoil = 0.10 },
}

function stat_modifiers.apply_to_damage(event, current_damage)
    local attacker = event.attacker
    local item = attacker.held_item

    if not item or not MODIFIERS[item] then
        return current_damage
    end

    local data = MODIFIERS[item]
    if data.trigger == "damage_calc" then
        current_damage = current_damage * data.multiplier
    end

    return current_damage
end

return stat_modifiers
