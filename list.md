National Dex Combat Logic Audit (G9 Battle Engine Beta)

This document tracks the gap between the `national_dex` data export and the current `abilities/engine/` and `combat/` implementation. 

**Core Rule:** All calculations must follow Pokémon Showdown formulas. Only final damage values and event order are passed to the gen1recomp engine.

- abilities/data/priority_change.lua  [16 lines]  — [COMPLETED] Active engine implemented.
- abilities/data/prevent_priority_fail.lua [18 lines] — [COMPLETED] Active engine implemented.
- abilities/data/prevent_misc.lua [18 lines]  — [COMPLETED] Active engine implemented.
- abilities/data/crit_change.lua  [14 lines]  — [COMPLETED] Active engine implemented.
- combat/items/combat_items_handler.lua [45 lines] — [COMPLETED] Showdown damage/berry logic implemented.
- items/engine/item_effects_combat.lua [120 lines] — [COMPLETED] All combat-related held item effects implemented via Showdown formulas.
- items/engine/held_item_effects.lua [40 lines] — [COMPLETED] Base formula handlers and Choice/Life Orb logic implemented.

All Showdown-based combat items from the current priority batch are now fully implemented in the battle engine.

Round 13: gigantamax/max_move_subeffects.lua [~600 lines] — [COMPLETED] All Max/G-Max move sub-effects processed per Showdown via the canonical pipeline (kind="full" + move.effect dispatch), power ladder owned by battle_forms.

Round 14: ability audit close-out vs national_dex + Showdown — [COMPLETED] All 313 national_dex abilities now accounted for. New data+engine pairs: absorb (Flash Fire/Motor Drive/Lightning Rod/Storm Drain), hit_taken (Weak Armor/Anger Point/Steam Engine/Berserk/Seed Sower/Sand Spit + the already-listed Stamina/Cotton Down/Gooey/Justified/Steadfast), ko_boost (Moxie/Grim Neigh/Soul-Heart), cudchew. New data markers: intimidate_guard (Oblivious/Guard Dog/Rattled), form_change_scope (8, battle_forms-owned), overworld_only (3), redirect_immunity (2), corrosion_deferred (1). Additions wired into existing engines: Guts/Marvel Scale/Grass Pelt/Minus/Plus (stat_multiplier), Suction Cups/Guard Dog (prevent_misc), Fluffy/Analytic/Flash Fire charge (damage_multiplier), Liquid Voice (type_override_moves), Pastel Veil/Leaf Guard (status_immunity), Sand Stream (weather_switchin), Speed Boost (switch_priority_misc); Defiant/Competitive/Illuminate/Ruin quartet in modern_combat, Oblivious gates in modern_status_effects, setFlinched primitive in main.lua. See ABILITIES.md for the full 313-ability coverage table.
