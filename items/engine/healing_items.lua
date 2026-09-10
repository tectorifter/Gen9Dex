local data = require("items/data/held_item_effects")

-- Logic for items that provide healing or recovery
local healing_engine = {}

function healing_engine.apply(pokemon, item_id)
    local entry = data.effects[item_id]
    if not entry then return end

    if entry.type == "healing_regen" then
        -- Leftovers: Heals a small amount every turn
        -- In gen1recomp, we return the delta to be applied to HP
        return { hp_delta = entry.value, message = "Healed by Leftovers!" }
    elseif entry.type == "healing_berry" then
        -- Berry consumption logic
        -- Return healing and signal that the item is consumed
        return { hp_delta = entry.value, consume_item = true, message = "A berry was consumed!" }
    end

    return nil
end

return healing_engine
