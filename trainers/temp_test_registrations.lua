-- TEMPORARY, 2026-08-29: in-process trainer registrations used while
-- debugging the cross-mod registerTrainer path (Sample-Trainer-Registry
-- calling in via mod.find fails on a fresh boot; this same registration
-- called in-process, from inside g9-battle-engine-beta itself, works).
-- Isolated into its own file, out of main.lua's own install sequence,
-- purely for readability while this stays in place. Revert/delete once
-- the cross-mod investigation is resolved -- this does not belong in a
-- shipped build.
return function(mod)
  mod.exports.registerTrainer("YOUNGSTER:JOEY1", {
    {
      species = "EXCADRILL",
      level = 10,
      moves = { "EARTHQUAKE", "ROCKSLIDE", "PROTECT", "SWORDSDANCE" },
      ability = "MOLDBREAKER",
      nature = "JOLLY",
      ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
      evs = { hp = 252, atk = 252, def = 0, spa = 0, spd = 0, spe = 4 },
      teraType = "GROUND",
      dynamaxLvl = 10,
      gigantamax = false,
      heldItem = "CHOICE_BAND",
    },
    {
      species = "EXCADRILL",
      level = 10,
      moves = { "EARTHQUAKE", "ROCKSLIDE", "PROTECT", "SWORDSDANCE" },
      ability = "MOLDBREAKER",
      nature = "JOLLY",
      ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
      evs = { hp = 252, atk = 252, def = 0, spa = 0, spd = 0, spe = 4 },
      teraType = "GROUND",
      dynamaxLvl = 10,
      gigantamax = false,
      heldItem = "CHOICE_BAND",
    },
  }, { combatType = "doubles" })
end
