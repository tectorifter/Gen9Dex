-- The curated set of switch_in abilities this generic engine safely
-- auto-derives via combat/modern_terrain.lua's own setTerrain primitive --
-- Electric/Grassy/Misty/Psychic Surge, plus Hadron Engine's terrain half.
-- This is ONLY an inclusion list: the actual terrain value is read LIVE
-- from national_dex's own abilityBehaviorOf at dispatch time (abilities/
-- engine/switchin_terrain.lua's own header) -- nothing about the effect
-- itself is duplicated here.
--
-- Hadron Engine's own second effect (a Sp. Atk stat_multiplier while
-- Electric Terrain is active) has no primitive yet -- Phase 4 -- and is a
-- real, flagged gap, not silently dropped.
--
-- Seed Sower is NOT here: its real trigger is on_hit_taken, not switch_in
-- -- a different phase, same reasoning as weather_switchin.lua's own Sand
-- Spit exclusion.
return {
  ELECTRICSURGE = true,
  GRASSYSURGE = true,
  MISTYSURGE = true,
  PSYCHICSURGE = true,
  HADRONENGINE = true,
}
