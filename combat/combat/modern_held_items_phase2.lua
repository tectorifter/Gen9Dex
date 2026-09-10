-- Held-item COMBAT effects, Phase 2: non-consumable items (explicit user
-- directive, 2026-08-28: "start with non consumables first"). None of
-- these have any real precedent on the Gold/Silver cartridge (confirmed
-- via `tools/rom_manifest_gold.json`'s own real itemOrder -- zero
-- matches for any id this file registers) except LIGHT_BALL, THICK_CLUB
-- and METAL_POWDER, which ARE real, already-holdable native items with
-- NO combat behavior wired anywhere in this engine at all (confirmed:
-- zero references to any of the three, or to the real native
-- `HELD_METAL_POWDER` effect string, anywhere in gen1recomp-dev's own
-- source) -- a real, confirmed gap, not assumed.
--
-- Every other item here is registered fresh via `mod.content.items
-- :register` (the same real, sanctioned mechanism species/
-- species_evolutions.lua's own evolution-item loop already uses in this
-- mod's own main.lua -- id/name/price/tossable is the whole real schema,
-- confirmed against src/mods/Schemas.lua's own R.items). This file owns
-- the COMBAT effect only -- how a player actually acquires one of these
-- in-game (shop, wild find, etc.) is a real, explicitly out-of-scope
-- concern, the same "we don't handle X, we handle combat effect"
-- boundary this whole session's ability work already established for
-- transformations.
--
-- REAL BUG FOUND AND FIXED IN THIS SAME PASS: Phase 1's own type-boost-
-- item fix (combat/modern_held_items.lua, Charcoal family) is confirmed
-- DEAD CODE under this mod -- `computeModernDamage` (combat/
-- modern_combat.lua, the real function that REPLACES native damage
-- computation once this mod's own "battle.damage" wrap is installed)
-- never reads `heldEffect`/`itemBoostPercent`/any `HELD_*` string
-- anywhere in its own body (confirmed, direct grep of the whole
-- function: zero matches) -- the exact same "registered somewhere real
-- code never reaches" bug class as Scope Lens, Wonder Guard's own scale
-- bug, and the Foresight/Scrappy negation dead code, all found earlier
-- this same day. Re-implemented here via a real `registerDamageModifier`
-- entry (the same live chain STAB/weather already use) instead --
-- covers BOTH the Phase 1 native family (Charcoal etc.) and this
-- phase's new species-locked orbs/Soul Dew in one place, since they're
-- the identical real mechanic.
--
-- Real values verified against Showdown's own actual `data/items.ts`
-- source (smogon/pokemon-showdown master branch, fetched and read this
-- same pass), not memory -- summary per item; see each section's own
-- comment for the literal source fields that grounded it.
return function(mod)
  local itemOf = mod.exports.itemOf
  local isGen2Battle = mod.exports.isGen2Battle
  local registerDamageModifier = mod.exports.registerDamageModifier
  local registerPostEffectivenessModifier = mod.exports.registerPostEffectivenessModifier
  local registerPriorityModifier = mod.exports.registerPriorityModifier
  local resolvedTypeMult = mod.exports.resolvedTypeMult
  assert(itemOf and isGen2Battle and registerDamageModifier and registerPostEffectivenessModifier
      and registerPriorityModifier and resolvedTypeMult,
    "modern_held_items_phase2: combat/modern_items.lua, combat/modern_combat.lua and "
      .. "combat/turn_order.lua must all load first")

  local Battle2 = require("src.battle.gen2.Battle")

  local function hpOf(mon) return (mon.mon or mon) end
  local function damageFraction(mon, fraction)
    local m = hpOf(mon)
    local maxHp = m.stats and m.stats.hp
    if not (maxHp and maxHp > 0) then return end
    m.hp = math.max(0, (m.hp or 0) - math.max(1, math.floor(maxHp * fraction)))
  end

  ------------------------------------------------------------------
  -- New item registrations. tossable=true matches the real evolution-
  -- item precedent (main.lua's own speciesEvolutions.items loop); price
  -- 0 since none of these have a real in-game shop presence yet (out of
  -- this file's own combat-effect scope). pcall-guarded per item and as
  -- a whole block, same defensive pattern Counter's own bulk patch
  -- (combat/legacy_move_takeover.lua) already established -- a name
  -- collision here should never take the whole mod down.
  ------------------------------------------------------------------
  local NEW_ITEMS = {
    { id = "CHOICE_BAND", name = "Choice Band" },
    { id = "CHOICE_SPECS", name = "Choice Specs" },
    { id = "CHOICE_SCARF", name = "Choice Scarf" },
    { id = "LIFE_ORB", name = "Life Orb" },
    { id = "ASSAULT_VEST", name = "Assault Vest" },
    { id = "EVIOLITE", name = "Eviolite" },
    { id = "EXPERT_BELT", name = "Expert Belt" },
    { id = "ROCKY_HELMET", name = "Rocky Helmet" },
    { id = "BLACK_SLUDGE", name = "Black Sludge" },
    { id = "LIGHT_CLAY", name = "Light Clay" },
    { id = "QUICK_POWDER", name = "Quick Powder" },
    { id = "IRON_BALL", name = "Iron Ball" },
    { id = "LAGGING_TAIL", name = "Lagging Tail" },
    { id = "FULL_INCENSE", name = "Full Incense" },
    { id = "DEEP_SEA_TOOTH", name = "Deep Sea Tooth" },
    { id = "DEEP_SEA_SCALE", name = "Deep Sea Scale" },
    { id = "SOUL_DEW", name = "Soul Dew" },
    { id = "ADAMANT_ORB", name = "Adamant Orb" },
    { id = "LUSTROUS_ORB", name = "Lustrous Orb" },
    { id = "GRISEOUS_ORB", name = "Griseous Orb" },
  }
  do
    local registered = 0
    for _, def in ipairs(NEW_ITEMS) do
      local ok, err = pcall(function()
        mod.content.items:register(def.id, {
          id = def.id, name = def.name, price = 0, tossable = true,
        })
      end)
      if ok then registered = registered + 1
      else mod.log:warn("g9-battle-engine-beta: modern_held_items_phase2: "
        .. "item registration failed for %s (%s)", def.id, tostring(err)) end
    end
    mod.log:info("g9-battle-engine-beta: modern_held_items_phase2: %d/%d new items registered",
      registered, #NEW_ITEMS)
  end

  ------------------------------------------------------------------
  -- Type-boost family (Charcoal etc., Phase 1's own real item family --
  -- see this file's own header for why that fix had to move here) plus
  -- the four species-locked orbs. Real Gen 9 value for every entry:
  -- +20% (`chainModify([4915,4096])`, confirmed via Charcoal/Adamant
  -- Orb/Soul Dew's own real source entries). Registered at the same
  -- real chain STAB/weather already use, priority 90 (below both --
  -- order among registerDamageModifier entries doesn't change the final
  -- product, this just keeps it grouped near the other flat real-item/
  -- ability multipliers).
  ------------------------------------------------------------------
  local TYPE_BOOST_ITEMS = {
    CHARCOAL = "FIRE", MYSTIC_WATER = "WATER", MIRACLE_SEED = "GRASS",
    MAGNET = "ELECTRIC", NEVERMELTICE = "ICE", BLACKBELT_I = "FIGHTING",
    POISON_BARB = "POISON", SOFT_SAND = "GROUND", SHARP_BEAK = "FLYING",
    TWISTEDSPOON = "PSYCHIC", BLACKGLASSES = "DARK", HARD_STONE = "ROCK",
    METAL_COAT = "STEEL", DRAGON_FANG = "DRAGON", SILVERPOWDER = "BUG",
  }
  -- Species-locked: item id -> { species = real Gen2 species id, types = {a,b} }
  local SPECIES_TYPE_BOOST_ITEMS = {
    ADAMANT_ORB = { species = "DIALGA", types = { STEEL = true, DRAGON = true } },
    LUSTROUS_ORB = { species = "PALKIA", types = { WATER = true, DRAGON = true } },
    GRISEOUS_ORB = { species = "GIRATINA", types = { GHOST = true, DRAGON = true } },
    -- Real Gen 9 Soul Dew (Bulbapedia, verified): a move-power boost, NOT
    -- the old Gen 3-6 stat-boost version -- the mechanic changed in Gen 7
    -- specifically to make the item tournament-legal, and this project's
    -- own standing rule is always the highest generation's real version.
    SOUL_DEW = { species = "LATIOS", altSpecies = "LATIAS", types = { PSYCHIC = true, DRAGON = true } },
  }
  registerDamageModifier("held_item_type_boost", 90, function(ctx)
    if not ctx.gen2 then return 1.0 end
    local item = itemOf(ctx.user, true)
    if not item then return 1.0 end
    local plainType = TYPE_BOOST_ITEMS[item]
    if plainType and ctx.move.type == plainType then return 4915 / 4096 end
    local locked = SPECIES_TYPE_BOOST_ITEMS[item]
    if locked and locked.types[ctx.move.type]
        and (ctx.user.species == locked.species or (locked.altSpecies and ctx.user.species == locked.altSpecies)) then
      return 4915 / 4096
    end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- LIFE_ORB -- real 1.3x damage on every hit (`chainModify([5324,4096])`)
  -- plus 1/10 max HP recoil on any landed, non-Status hit, self-inflicted
  -- regardless of whether the hit was blocked/immune-to-zero (real
  -- Showdown: `onAfterMoveSecondarySelf`, fires once per move use, not
  -- gated on damage actually landing) -- checked via `battle.damage_dealt`
  -- instead (this mod's own real "landed, non-zero hit" event), a
  -- narrower real condition than Showdown's own (a hit that whiffs
  -- outright or is fully immune won't trigger recoil here, where real
  -- Showdown's recoil is independent of that) -- an honest, small,
  -- flagged divergence rather than building a new move-use-level hook
  -- for one item.
  ------------------------------------------------------------------
  registerDamageModifier("life_orb", 85, function(ctx)
    if not ctx.gen2 then return 1.0 end
    if itemOf(ctx.user, true) ~= "LIFE_ORB" then return 1.0 end
    return 5324 / 4096
  end)
  mod.events:on("battle.damage_dealt", function(ev)
    local user = ev and ev.user
    local move = ev and ev.move
    if not (user and move and ev.battle and isGen2Battle(ev.battle) and (ev.damage or 0) > 0) then return end
    if itemOf(user, true) ~= "LIFE_ORB" then return end
    local nationalDex = mod.find and mod.find("national_dex")
    local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
    local ok, info = moveById and pcall(moveById, move.id)
    if ok and info and info.damageClass == "status" then return end
    damageFraction(user, 1 / 10)
  end)

  ------------------------------------------------------------------
  -- EXPERT_BELT -- real 1.2x on a super-effective hit only
  -- (`chainModify([4915,4096])`, gated on `typeMod > 0`). The REAL
  -- resolved type multiplier only exists after computeModernDamage's own
  -- per-row TypeChart.rows() scaling -- the same reason Wonder Guard/
  -- Filter/Tinted Lens live on registerPostEffectivenessModifier instead
  -- of registerDamageModifier (see that primitive's own header,
  -- modern_combat.lua) -- registered here on the same real chain.
  ------------------------------------------------------------------
  registerPostEffectivenessModifier("expertbelt", 0, function(ctx)
    if not (ctx.gen2 and ctx.user) then return 1.0 end
    if itemOf(ctx.user, true) ~= "EXPERT_BELT" then return 1.0 end
    if ctx.mult and ctx.mult > 10 then return 4915 / 4096 end
    return 1.0
  end)

  ------------------------------------------------------------------
  -- ROCKY_HELMET -- real 1/6 max HP contact damage back to a PHYSICAL
  -- attacker, same real primitive/pattern Iron Barbs already established
  -- (abilities/engine/contact_retaliation.lua's own real makesContact
  -- check).
  ------------------------------------------------------------------
  mod.events:on("battle.damage_dealt", function(ev)
    local target = ev and ev.target
    local user = ev and ev.user
    local move = ev and ev.move
    if not (target and user and move and ev.battle and isGen2Battle(ev.battle) and (ev.damage or 0) > 0) then return end
    if itemOf(target, true) ~= "ROCKY_HELMET" then return end
    local nationalDex = mod.find and mod.find("national_dex")
    local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
    local ok, info = moveById and pcall(moveById, move.id)
    if not (ok and info and info.damageClass == "physical") then return end
    local makesContact = mod.exports.makesContact
    if makesContact and makesContact(move.id, user) then damageFraction(user, 1 / 6) end
  end)

  ------------------------------------------------------------------
  -- BLACK_SLUDGE -- real: heals 1/16 max HP per turn for a Poison-type
  -- holder, damages 1/8 max HP per turn for anyone else
  -- (`pokemon.hasType('Poison')`). No native precedent (unlike
  -- Leftovers) -- built fresh on the real `battle.turn_ended` event
  -- every other end-of-turn residual in this mod already uses
  -- (combat/modern_status_volatiles.lua's own Leech Seed tick, for one).
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not (battle and isGen2Battle(battle)) then return end
    local curTypesOf = mod.exports.curTypesOf
    for _, mon in ipairs({ battle.player, battle.enemy }) do
      if mon and (mon.hp or 0) > 0 and itemOf(mon, true) == "BLACK_SLUDGE" then
        local maxHp = mon.stats and mon.stats.hp
        if maxHp and maxHp > 0 then
          local isPoison = false
          for _, t in ipairs(curTypesOf and curTypesOf(mon, true) or {}) do
            if t == "POISON" then isPoison = true end
          end
          if isPoison then
            mon.hp = math.min(maxHp, mon.hp + math.max(1, math.floor(maxHp / 16)))
          else
            mon.hp = math.max(0, mon.hp - math.max(1, math.floor(maxHp / 8)))
          end
        end
      end
    end
  end)

  ------------------------------------------------------------------
  -- LIGHT_CLAY -- real: extends Reflect/Light Screen (and Aurora Veil,
  -- not modeled in this engine at all yet -- a real, pre-existing gap,
  -- not introduced here) from the real base 5 turns
  -- (`Battle.SCREEN_TURNS`, gen2/Battle.lua, confirmed unchanged from
  -- Gen 2's own real native value) to 8. Monkeypatched onto the two real
  -- native `Battle.MOVE_EFFECTS` entries directly (a plain table-field
  -- override, the same sanctioned runtime-override technique combat/
  -- legacy_move_takeover.lua's own Battle2:dealDamage patch already
  -- established -- not an edit to gen1recomp-dev's own source file).
  ------------------------------------------------------------------
  local nativeLightScreen = Battle2.MOVE_EFFECTS.EFFECT_LIGHT_SCREEN
  Battle2.MOVE_EFFECTS.EFFECT_LIGHT_SCREEN = function(self, attacker)
    local result = nativeLightScreen(self, attacker)
    local side = self.screens[self:sideOf(attacker)]
    if (side.lightScreen or 0) > 0 and itemOf(attacker, true) == "LIGHT_CLAY" then
      side.lightScreen = 8
    end
    return result
  end
  local nativeReflect = Battle2.MOVE_EFFECTS.EFFECT_REFLECT
  Battle2.MOVE_EFFECTS.EFFECT_REFLECT = function(self, attacker)
    local result = nativeReflect(self, attacker)
    local side = self.screens[self:sideOf(attacker)]
    if (side.reflect or 0) > 0 and itemOf(attacker, true) == "LIGHT_CLAY" then
      side.reflect = 8
    end
    return result
  end

  ------------------------------------------------------------------
  -- Stat multipliers -- Choice Band/Specs (1.5x Atk/SpA), Assault Vest
  -- (1.5x SpD), Eviolite (1.5x Def AND SpD for a real NFE species,
  -- checked live via national_dex's own evolutionsOf -- a species with
  -- at least one real evolvesInto entry), Light Ball (2x Atk/SpA,
  -- Pikachu only -- real, confirmed, previously-unwired native item),
  -- Thick Club (2x Atk, Cubone/Marowak only -- same), Deep Sea Tooth
  -- (2x SpA, Clamperl only), Deep Sea Scale (2x SpD, Clamperl only),
  -- Metal Powder (2x Def, untransformed Ditto only -- real, confirmed,
  -- previously-unwired native item, native effect string
  -- HELD_METAL_POWDER exists in the ROM's own item name table but was
  -- never actually dispatched anywhere in gen1recomp-dev's own source).
  -- Inserted directly into computeModernDamage's own atk/dfn
  -- computation, same real insertion point Snow's own Ice-type Defense
  -- boost and burn's own Attack halving already use (both a few lines
  -- below this same real spot).
  ------------------------------------------------------------------
  local function nfe(speciesId)
    local nationalDex = mod.find and mod.find("national_dex")
    local evolutionsOf = nationalDex and nationalDex.exports and nationalDex.exports.evolutionsOf
    local evo = evolutionsOf and speciesId and evolutionsOf(speciesId)
    return evo and evo.evolvesInto and #evo.evolvesInto > 0
  end
  mod.exports.applyHeldItemStatMultiplier = function(ctx, user, target, atkStat, defStat, atk, dfn)
    if not ctx.gen2 then return atk, dfn end
    local userItem = itemOf(user, true)
    local targetItem = itemOf(target, true)
    if userItem == "CHOICE_BAND" and atkStat == "attack" then
      atk = math.floor(atk * 1.5)
    elseif userItem == "CHOICE_SPECS" and atkStat == "spa" then
      atk = math.floor(atk * 1.5)
    elseif userItem == "LIGHT_BALL" and user.species == "PIKACHU"
        and (atkStat == "attack" or atkStat == "spa") then
      atk = math.floor(atk * 2)
    elseif userItem == "THICK_CLUB" and atkStat == "attack"
        and (user.species == "CUBONE" or user.species == "MAROWAK") then
      atk = math.floor(atk * 2)
    elseif userItem == "DEEP_SEA_TOOTH" and atkStat == "spa" and user.species == "CLAMPERL" then
      atk = math.floor(atk * 2)
    end
    if targetItem == "ASSAULT_VEST" and defStat == "spd" then
      dfn = math.floor(dfn * 1.5)
    elseif targetItem == "EVIOLITE" and (defStat == "defense" or defStat == "spd")
        and nfe(target.species) then
      dfn = math.floor(dfn * 1.5)
    elseif targetItem == "DEEP_SEA_SCALE" and defStat == "spd" and target.species == "CLAMPERL" then
      dfn = math.floor(dfn * 2)
    elseif targetItem == "METAL_POWDER" and defStat == "defense" and target.species == "DITTO"
        and not target.transformed then
      dfn = math.floor(dfn * 2)
    end
    return atk, dfn
  end

  ------------------------------------------------------------------
  -- Speed -- Choice Scarf (1.5x), Quick Powder (2x, untransformed Ditto
  -- only), Iron Ball (0.5x, unconditional). Monkeypatched onto the real
  -- native `Battle:battleStat` (gen2/Battle.lua) -- the ONE real, shared
  -- choke point both combat/turn_order.lua's own effectiveSpeedFor AND
  -- native code everywhere else read "speed" through -- keyed strictly
  -- on `key == "speed"` so this never touches the "attack"/
  -- "specialAttack"/etc. reads the same method also serves (those go
  -- through this file's own applyHeldItemStatMultiplier above instead,
  -- a completely separate real code path).
  ------------------------------------------------------------------
  local nativeBattleStat = Battle2.battleStat
  function Battle2:battleStat(mon, key)
    local value = nativeBattleStat(self, mon, key)
    if key ~= "speed" or not mon then return value end
    local item = itemOf(mon, true)
    if item == "CHOICE_SCARF" then
      return math.floor(value * 1.5)
    elseif item == "QUICK_POWDER" and mon.species == "DITTO" and not mon.transformed then
      return math.floor(value * 2)
    elseif item == "IRON_BALL" then
      return math.floor(value * 0.5)
    end
    return value
  end

  ------------------------------------------------------------------
  -- IRON_BALL -- real second half: grounds the holder (negates a
  -- natural Flying-type immunity to Ground-type moves), via the same
  -- real `resolvedTypeMult` negation primitive Smack Down/Telekinesis
  -- already use (combat/modern_combat.lua) -- Iron Ball is just one more
  -- real way to become "grounded," alongside that move's own volatile
  -- flag. Honest narrower scope, same shape as Smack Down's own: real
  -- Iron Ball also grounds the holder against Spikes/Toxic Spikes/Arena
  -- Trap, none of which check this same signal yet -- not built here,
  -- flagged rather than silently claimed complete.
  ------------------------------------------------------------------
  mod.exports.ironBallGrounds = function(mon)
    return itemOf(mon, true) == "IRON_BALL"
  end

  ------------------------------------------------------------------
  -- LAGGING_TAIL / FULL_INCENSE -- real -0.1 fractional priority
  -- (`onFractionalPriority: -0.1`, confirmed both items share the
  -- identical real value/shape). Registered on the same real
  -- registerPriorityModifier chain Stall/Quick Draw's own fractional
  -- offset already uses (abilities/engine/switch_priority_misc.lua) --
  -- the one real, live mechanism that actually intercepts BEFORE the
  -- whole-number priority/Speed compare, not just the final coinflip
  -- tiebreak.
  ------------------------------------------------------------------
  registerPriorityModifier("lagging_tail", function(battle, moveId, caster, def)
    if not caster then return 0 end
    local item = itemOf(caster, true)
    if item == "LAGGING_TAIL" or item == "FULL_INCENSE" then return -0.1 end
    return 0
  end)

  ------------------------------------------------------------------
  -- CHOICE_BAND / CHOICE_SPECS / CHOICE_SCARF -- real move-lock: once
  -- the holder uses a move, it can only select that same move again
  -- until it switches out (or the move runs out of PP, at which point
  -- real Showdown frees the lock -- see the forcedMove patch below for
  -- why that falls out for free). Monkeypatched onto the real native
  -- `Battle:forcedMove` (gen2/Battle.lua) -- the SAME real function
  -- Encore/Bide/Rollout-lock already answer through, and the one
  -- `Battle:usableMoves` (the real move-menu filter) already consults,
  -- so patching just this one function correctly restricts BOTH actual
  -- move execution AND the move menu, with no separate menu-side patch
  -- needed. A brand-new own field (`ggdChoiceLockedMove`), NOT the
  -- native `state.encore` field -- aliasing onto Encore's own real
  -- field would corrupt its own separate duration/messaging semantics
  -- if the two ever overlapped on the same mon.
  ------------------------------------------------------------------
  local nativeForcedMove = Battle2.forcedMove
  function Battle2:forcedMove(mon)
    local native = nativeForcedMove(self, mon)
    if native then return native end
    local locked = mon.ggdChoiceLockedMove
    if not locked then return nil end
    for _, move in ipairs(mon.moves or {}) do
      if move.id == locked and (move.pp or 0) > 0 then return locked end
    end
    mon.ggdChoiceLockedMove = nil
    return nil
  end

  -- Direct monkeypatch of the real native `Battle:useMove(attacker,
  -- defender, moveId)` -- confirmed the real, whole-move entry point
  -- (NOT a named "battle.useMove" Runtime hook -- no such hook exists,
  -- confirmed by direct grep of every real Runtime.call("battle....")
  -- site in gen2/Battle.lua), the exact same real function combat/
  -- interaction_memory.lua's own recorder already wraps this same way
  -- earlier this session. `self.copyDepth` guard matches that file's
  -- own real established precedent for "don't let a called/copied move
  -- (Metronome, Mirror Move, Sleep Talk) overwrite state meant for the
  -- TOP-LEVEL move the player actually selected" -- the same real guard
  -- native `lastMove` tracking uses for an identical problem.
  local nativeUseMove = Battle2.useMove
  function Battle2:useMove(attacker, defender, moveId)
    local result = nativeUseMove(self, attacker, defender, moveId)
    if attacker and moveId and (self.copyDepth or 0) == 0 then
      local item = itemOf(attacker, true)
      if item == "CHOICE_BAND" or item == "CHOICE_SPECS" or item == "CHOICE_SCARF" then
        attacker.ggdChoiceLockedMove = moveId
      end
    end
    return result
  end

  mod.events:on("battle.battler_switched", function(ev)
    local mon = ev and ev.previous
    if mon then mon.ggdChoiceLockedMove = nil end
  end)

  ------------------------------------------------------------------
  -- ASSAULT_VEST -- real second half: bans selecting a Status move
  -- outright (real exception, Me First, checked by id -- `move.id !==
  -- 'mefirst'`). Monkeypatched onto the real native `Battle:usableMoves`
  -- (gen2/Battle.lua) -- the same real move-menu filter Choice's own
  -- lock above already flows through for free via forcedMove, but this
  -- ban isn't a "locked to one move," it's "some moves are never
  -- selectable," which forcedMove's own shape can't express -- needs
  -- its own, separate filter pass over the returned list.
  ------------------------------------------------------------------
  local nativeUsableMoves = Battle2.usableMoves
  function Battle2:usableMoves(mon)
    local out = nativeUsableMoves(self, mon)
    if itemOf(mon, true) ~= "ASSAULT_VEST" then return out end
    local nationalDex = mod.find and mod.find("national_dex")
    local moveById = nationalDex and nationalDex.exports and nationalDex.exports.moveById
    if not moveById then return out end
    local filtered = {}
    for _, move in ipairs(out) do
      local ok, info = pcall(moveById, move.id)
      if move.id == "MEFIRST" or not (ok and info and info.damageClass == "status") then
        filtered[#filtered + 1] = move
      end
    end
    return filtered
  end

  mod.log:info("g9-battle-engine-beta: modern_held_items_phase2 installed (non-consumable "
    .. "combat items: Choice Band/Specs/Scarf, Life Orb, Assault Vest, Eviolite, Expert Belt, "
    .. "Rocky Helmet, Black Sludge, Light Clay, Quick Powder, Iron Ball, Lagging Tail, "
    .. "Full Incense, Deep Sea Tooth/Scale, Soul Dew, the three Sinnoh orbs; Light Ball/"
    .. "Thick Club/Metal Powder's own previously-unwired native combat effect; Phase 1's "
    .. "dead-code type-boost-item fix corrected. Big Root explicitly deferred -- needs a "
    .. "real drain-heal interception point this engine doesn't expose yet, see PROGRESS.md)")
end
