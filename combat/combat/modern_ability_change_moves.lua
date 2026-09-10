-- Ability-changing/suppressing moves -- Skill Swap, Worry Seed,
-- Entrainment, Gastro Acid -- a standing TODO this mod's own PROGRESS.md
-- named explicitly ("no mechanism exists at all") until abilities/
-- ability_dispatch.lua's own mod.exports.setAbility closed it this same
-- pass. Every real change goes through that one primitive -- combat-only
-- (restores each mon's own natural ability on switch-out/battle-end) and
-- boss-immune (refuses outright against battle.enemy), both already
-- enforced there, not duplicated here.
--
-- UNCHANGEABLE: MULTITYPE is the one ability actually built in this
-- engine today that real Showdown also protects from every one of these
-- four moves (Skill Swap/Worry Seed/Entrainment/Gastro Acid all refuse
-- against it). Real Showdown's own broader exclusion lists (As One,
-- Comatose, Disguise, Illusion, Imposter, RKS System, Schooling, Stance
-- Change...) target exotic form-changing abilities this engine's ability
-- system doesn't build anywhere -- moot here, not silently dropped.
return function(mod)
  local normalize = mod.exports.normalize
  local romText = require("src.core.RomText")
  local Strings = require("src.core.Strings")
  local abilityIdOf = mod.exports.abilityIdOf
  local setAbility = mod.exports.setAbility
  local displayNameFor = mod.exports.displayNameFor
  assert(normalize and abilityIdOf and setAbility and displayNameFor,
    "modern_ability_change_moves: combat/modern_combat.lua and abilities/ability_dispatch.lua must load first")

  local UNCHANGEABLE = { MULTITYPE = true }
  local function fail(n)
    return { romText(n.battle.data, "_ButItFailedText", "But, it failed!") }
  end

  ------------------------------------------------------------------
  -- Skill Swap -- mutual, both ways.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_SKILLSWAP_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user, target = n.user, n.target
      local userId, targetId = abilityIdOf(user), abilityIdOf(target)
      if not (userId and targetId) or userId == targetId
          or UNCHANGEABLE[userId] or UNCHANGEABLE[targetId] then
        return fail(n)
      end
      -- Second half gated on the first's own real success -- see
      -- abilities/engine/ability_copy.lua's own Wandering Spirit note for
      -- why (boss-immunity must refuse the WHOLE swap, never a half one).
      local userChanged = setAbility(n.battle, user, targetId)
      if userChanged == false then return fail(n) end
      setAbility(n.battle, target, userId)
      return { Strings("%s and %s swapped\nabilities!",
        displayNameFor(n.battle, user, n.gen2), displayNameFor(n.battle, target, n.gen2)) }
    end,
  })

  ------------------------------------------------------------------
  -- Worry Seed -- target's ability becomes Insomnia. Real, confirmed
  -- refusal: target's ability is already Insomnia, or is Truant (a real,
  -- specifically-named exception even though Truant itself has no other
  -- effect built in this engine).
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_WORRYSEED_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local target = n.target
      local targetId = abilityIdOf(target)
      if targetId == "INSOMNIA" or targetId == "TRUANT" or UNCHANGEABLE[targetId] then
        return fail(n)
      end
      local changed = setAbility(n.battle, target, "INSOMNIA")
      if changed == false then return fail(n) end
      return { Strings("%s's ability\nbecame Insomnia!", displayNameFor(n.battle, target, n.gen2)) }
    end,
  })

  ------------------------------------------------------------------
  -- Entrainment -- one-way, user's current ability copied onto target.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_ENTRAINMENT_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local user, target = n.user, n.target
      local userId, targetId = abilityIdOf(user), abilityIdOf(target)
      if not userId or userId == targetId or UNCHANGEABLE[userId] or UNCHANGEABLE[targetId] then
        return fail(n)
      end
      local changed = setAbility(n.battle, target, userId)
      if changed == false then return fail(n) end
      return { Strings("%s's ability\nbecame the same as\nthe opponent's!",
        displayNameFor(n.battle, target, n.gen2)) }
    end,
  })

  ------------------------------------------------------------------
  -- Gastro Acid -- suppresses the target's ability outright (setAbility
  -- with a nil id) for the rest of its time on the field. Closes the
  -- exact "g9 ability-suppression TODO" this mod's own memory named as
  -- deferred pending a real ability-execution system -- that system has
  -- existed since Phase 0 of this roadmap; only setAbility itself was
  -- still missing.
  ------------------------------------------------------------------
  mod.content.move_effects:register("GALAR_GASTROACID_EFFECT", {
    kind = "primary",
    accuracyChecked = true,
    run = function(a, b, c)
      local n = normalize(a, b, c)
      local target = n.target
      local targetId = abilityIdOf(target)
      if not targetId or UNCHANGEABLE[targetId] then return fail(n) end
      local changed = setAbility(n.battle, target, nil)
      if changed == false then return fail(n) end
      return { Strings("%s's ability\nwas suppressed!", displayNameFor(n.battle, target, n.gen2)) }
    end,
  })

  mod.log:info("g9-battle-engine-beta: modern_ability_change_moves installed (SKILLSWAP, WORRYSEED, ENTRAINMENT, GASTROACID)")
end
