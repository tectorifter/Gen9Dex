-- Inclusion list only -- factors are read LIVE from national_dex's own
-- abilityBehaviorOf; only Hustle's own move-category filter is
-- hardcoded, since accuracy_multiplier has no move-category field at all
-- (confirmed via its own notes: "Both multipliers apply only to
-- physical moves... the schema has no move-category filter"). Real,
-- confirmed accuracy_multiplier abilities (2026-08-27 audit, 3 total):
--   COMPOUNDEYES (x1.3, unconditional -- its own real OHKO-move
--     exception is NOT modeled, per its own notes, and not built here
--     either -- a genuine, flagged simplification, not silently
--     dropped),
--   HUSTLE (x0.8, physical moves only -- the damage half, x1.5 physical
--     power, was already built in Phase 2's damage_multiplier.lua; this
--     is its deferred accuracy half),
--   VICTORYSTAR (x1.1, applies to the holder's own moves AND its
--     allies' -- confirmed via its own notes, a self-inclusive ally
--     scope like Sweet Veil/Flower Gift's own family).
-- NOGUARD (Phase 8, "other" bucket -- not accuracy_multiplier at all in
-- national_dex's own kind taxonomy, but wired in the same file since it
-- shares the exact same "battle.accuracy" hook this file already owns):
-- a real, unconditional guaranteed hit for either side of the matchup,
-- not a multiplier -- see abilities/engine/accuracy_multiplier.lua's own
-- comment for why it can't be expressed as one.
return {
  COMPOUNDEYES = true, HUSTLE = true, VICTORYSTAR = true, NOGUARD = true,
}
