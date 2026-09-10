-- Showdown-accurate combat item registry
-- These are read by combat_items_handler.lua to apply modifiers to the damage pipeline
return {
    damage_reduction = {
        -- Format: [ITEM_ID] = multiplier
        LEFTOVERS = 1.0, -- Handled by heal logic, not raw damage reduction
        ASSAULT_VEST = { special_def_mult = 1.5, damage_mult = 1.0 },
        EVOLVITE = 0.9, 
    },
    stat_modifiers = {
        -- Applied at start of turn or on specific triggers
        CHOICE_BAND = { attack = 1.5, type = "multiplier" },
        CHOICE_SCARF = { speed = 1.5, type = "multiplier" },
        LIFE_ORB = { damage_mult = 1.3, hp_drain = 0.125 },
    },
    berry_triggers = {
        -- Triggered when HP drops below threshold
        SITRUS = { threshold = 0.5, heal_amount = 0.25, trigger = "on_damage" },
        PINAP = { threshold = 0.5, heal_amount = 0.1, trigger = "on_damage" },
        LAMON = { threshold = 0.5, heal_amount = 0.25, trigger = "on_damage" },
    }
}
