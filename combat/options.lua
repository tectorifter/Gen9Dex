-- Mod Manager option schema for g9-battle-engine-beta (combat-only fork:
-- see main.lua's own header for what this fork does and doesn't own).
--
-- Declared in manifest.json's "options_schema" field, same as Wilds of
-- Kanto's own options.lua, so the Mod Manager can lazy-load and render
-- this list even before/without the mod's own entry chunk running (a
-- disabled mod's options are still viewable/editable this way). main.lua
-- also calls mod.options:define() with this exact table at load time, so
-- both the static manifest path and the live mod.options:get() reads
-- share one source of truth instead of two schemas that could drift.
--
-- Visible labels stay short: the Mod Manager's row layout truncates long
-- labels (same constraint every other mod's options.lua documents).
--
-- mod.options:define() REPLACES the whole schema on every call -- it is
-- not additive across multiple calls within the same mod (confirmed from
-- Loader.lua: loader.optionSchemas[modId] = schema, a plain overwrite).
-- gmax_custom_art and animated_battle_sprites used to be defined by their
-- own separate mod.options:define() calls elsewhere in main.lua
-- (installGmaxAssetPacks, installSpriteAnimation) -- each call silently
-- discarded whatever schema came before it, which is exactly why only the
-- LAST-registered option ever showed up in the Mod Manager screen. Both
-- rows now live here instead, in this one shared schema, and those two
-- functions no longer call mod.options:define at all -- see main.lua.
-- Keys/types/choices/defaults are unchanged from their original
-- definitions, so every existing mod.options:get(...) read elsewhere in
-- this mod keeps working exactly as before.
-- [g9-battle-engine-beta] gmax_custom_art, animated_battle_sprites,
-- wild_spawns_enabled, use_base_area_tables, classic_encounters,
-- wild_max_per_map, follower_enabled, wild_contact_radius, and
-- national_dex_sprites removed -- all sprite/spawn/overworld/follower
-- toggles with nothing left in this fork to control. See
-- g9-battle-engine for those.
-- gimmicks and vanilla_enhanced_layout removed too (2026-08-20): both
-- custom battle scenes (Gen 1 overlay + Gen 2 full screen) that these
-- controlled are deleted outright, not just uncalled -- see main.lua's
-- own header. gigantamax_size/gigantamax_skip_animation stay, now LIVE
-- again (round 12): battle_forms owns Dynamax activation + mechanics end
-- to end (including Gen 2's size-up via its own gen2dynamaxgrow.lua), but
-- Gen 1's draw-time scaling seam is the flagship's -- gigantamax/
-- dynamax_battle.lua (the consume-only processor, see main.lua) reads
-- these two options for the Gen 1 size-up it wraps around battle_forms'
-- dynamax_applied/reverted trigger. gimmick_dynamax.lua (the full parallel
-- Dynamax engine with its own HP doubling) stays on disk, canonical-
-- disabled -- booting it next to battle_forms would double-count.
return {
  -- Not yet consulted anywhere -- explicit user request to leave this
  -- placeholder in place for a future pass that prints "X lost Y HP!"
  -- style messages using our own computed damage number (both gens).
  -- modern_combat.lua's damage formula itself is no longer toggleable
  -- (see that file's own header) -- this option is unrelated to that.
  {
    key = "show_hp_lost_messages",
    label = "SHOW HP LOST MESSAGES",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "Not yet implemented. Reserved for a future \"X lost Y HP!\" battle message using this mod's own computed damage number.",
  },
  {
    key = "gen2_wide_layout",
    label = "GEN 2 MOVE TYPE READOUT",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "Gen 2 only. Gen 2's real move-select screen has no equivalent to Gen 1's WIDE layout -- it's a single fixed 160x144 panel with no engine-level wider-canvas mechanism, confirmed against source. This adds the highlighted move's TYPE on the move box's own unused bottom row (native only fills 4 of the box's 6 rows during move select) -- the one piece of info Gen 2's native list doesn't show at all, without touching or resizing anything native draws.",
  },
  {
    key = "custom_menu_scene",
    label = "CUSTOM MENU SCREENS",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "Replaces native menu screens with GalarGmaxDex's own GUI. Covers: party overview + moves/relearn/IV-EV screens, the title screen menu, the in-game start menu (with a MOD MENUS hub for other mods' rows), the options menu, and the mod manager. Battle switch prompts and TM/HM teach mode still render natively; bag and Pokedex are not covered yet. OFF (default): menus are fully vanilla.",
  },
  {
    key = "gigantamax_size",
    label = "GIGANTAMAX SIZE",
    type = "choice",
    default = "1.4",
    choices = { { "x1.2", "1.2" }, { "x1.4", "1.4" }, { "x1.8", "1.8" }, { "x2.2", "2.2" }, { "x2.6", "2.6" } },
    description = "How much bigger the player's mon's battle sprite draws while Dynamaxed (Gen 1 only; battle_forms grows Gen 2 itself), on top of its normal resting size. Read by gigantamax/dynamax_battle.lua.",
  },
  {
    key = "gigantamax_skip_animation",
    label = "SKIP GIGANTAMAX GROW/SHRINK",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "ON: Dynamax's size-up and size-down happen instantly (0 seconds, no staged ramp/pause) instead of the eased animation -- Gen 1 only, read by gigantamax/dynamax_battle.lua (Gen 2 is battle_forms' own gen2dynamaxgrow.lua). OFF (default): the full animated sequence plays.",
  },
  {
    key = "gym_badge_buff",
    label = "GYM BADGE BUFF",
    type = "choice",
    default = "true",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "ON (default): owning certain badges boosts the player's WHOLE side's stats/move-type damage (real Gold/Silver mechanic, now correctly applied to every player-side battler in a doubles/triples fight, not just the lead -- native Gen 2 only ever checked the single primary battler). OFF: no badge stat/type boost for anyone.",
  },
  {
    key = "dev_tools",
    label = "DEV TOOLS",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "ON: adds a DEVSTATS entry to the party submenu (selected Pokemon) showing its ability/nature/Tera type/Dynamax level/Gigantamax Factor, real combat stats, and full EV/IV distribution across 3 pages. OFF (default): party submenu is unchanged.",
  },
  {
    key = "bf_tera_dev",
    label = "BATTLE FORMS TERA DEV",
    type = "choice",
    default = "false",
    choices = { { "ON", "true" }, { "OFF", "false" } },
    description = "OFF (default): this mod owns Tera entirely. battle_forms' own TERA TYPE manager choice is forced to AUTO and its DVs-derived fallback is never reached (every battler is pre-stamped with this mod's stored per-Pokemon Tera Type), so battle_forms only reports WHEN Terastallization triggers -- it never decides WHAT type deploys. ON: battle_forms' original dev/test tool is re-enabled -- its TERA TYPE choice overrides every Pokemon (and overrides per-Pokemon stored types, so the stats row may differ from what deploys while this is ON). Only turn it on to deliberately pin a matchup for testing.",
  },
}
