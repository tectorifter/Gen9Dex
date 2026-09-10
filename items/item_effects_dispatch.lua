local healing = require("items/engine/healing_items")
local damage_reduction = require("items/engine/damage_reduction")
local stat_modifiers = require("items/engine/stat_modifiers")

local dispatcher = {}

-- Hook into the damage pipeline
function dispatcher.on_damage_calculate(event, current_damage)
    -- 1. Apply Stat Modifiers first (Attacker)
    current_damage = stat_modifiers.apply_to_damage(event, current_damage)

    -- 2. Apply Damage Reduction (Defender)
    current_damage = damage_reduction.apply(event, current_damage)

    return current_damage
end

-- Hook into turn-start or move-selection
function dispatcher.on_item_trigger(event)
    -- Existing healing logic (Leftovers/Berries)
    if healing.should_trigger(event) then
        return healing.apply(event)
    end
end

return dispatcher
