-- Inclusion list -- Phase 14 (ability audit close-out). The form /
-- transformation family. These eight abilities exist in national_dex
-- and ARE correctly referenced by the engine's ability_dispatch
-- (so they are NOT "missing"), but their actual mechanic is a
-- battle-time transformation, which the battle_forms plugin owns
-- (the mod's base battle is single-form with no Mega/Dynamax/Zen/Mode
-- framework of its own). So there is NO combat effect to wire here.
--
-- This file exists so the audit's "every ability in national_dex is
-- accounted for" invariant has a home for them, and each entry notes
-- the real mechanic in prose:
--   STANCECHANGE  -- Aegislash alternates Shield/Blade form (attacking
--                  move -> Blade, King's Shield -> Shield).
--   SCHOOLING     -- Wishiwashi becomes School Form at Lv20+.
--   ZENMODE       -- Darmanitan changes to Zen Mode when HP <= half.
--   POWERCONSTRUCT -- Zygarde becomes Complete Forme when HP <= half.
--   TERASHIFT     -- Terapagos enters Stellar Form when HP <= half.
--   ILLUSION      -- Zorua disguises itself as the last party member.
--   IMPOSTER      -- Ditto transforms into the opposing Pokémon.
--   ZEROTOHERO    -- Palafin changes to Hero Form on switch-out.
--
-- battle_forms owns all of these transformations; no battle-combat
-- effect is expressible in the base engine for any of them.
return {
  STANCECHANGE = { transform = true },
  SCHOOLING = { transform = true },
  ZENMODE = { transform = true },
  POWERCONSTRUCT = { transform = true },
  TERASHIFT = { transform = true },
  ILLUSION = { transform = true },
  IMPOSTER = { transform = true },
  ZEROTOHERO = { transform = true },
}
