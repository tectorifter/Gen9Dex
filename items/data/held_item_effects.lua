-- Registry of items that trigger specific held-item effects
-- Following the pattern: { item_id = "effect_type", value = X }
return {
    effects = {
        -- Healing items
        LEFTOVERS = { type = "healing_regen", value = 13 },
        ORANGE_BERRY = { type = "healing_berry", value = 10 },
        PINAP_BERRY = { type = "healing_berry", value = 10 },
        W_PEPPITA_BERRY = { type = "healing_berry", value = 10 },
        -- More items to be added as engine dispatchers are created
    }
}
