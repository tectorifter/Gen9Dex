-- Turn order: Generation 9 / Pokemon Showdown-accurate action sequencing,
-- owned entirely by this mod -- "we are the bible and process of combat"
-- applies here the same as everywhere else in combat/. Replaces
-- gen2/Battle.lua's own native comparator (priority from a small Gen-2
-- effect table with no Trick Room concept, then Quick Claw, then raw
-- Speed, then a coin-flip tie) through the engine's own sanctioned
-- extension point.
--
-- SOURCES, for the mechanic itself (verified 2026-08-20 against primary
-- sources, not assumed or taken from a single search summary -- the
-- first search this session returned the WRONG, outdated rule):
-- - https://github.com/smogon/pokemon-showdown/pull/6100 -- "Dynamic
--   speed updates for Gen 8," the actual Pokemon Showdown PR that
--   introduced re-sorting the remaining action queue by CURRENT speed
--   after each action resolves. Standing behavior through Gen 9.
--   Confirms Gen 7 and earlier computed order once at turn start and
--   never revisited it -- the older rule most casual sources describe.
-- - https://pokemondb.net/pokebase/250090/what-happens-if-there-is-speed-change-in-the-middle-of-a-turn
--   -- the pre-Gen-8 rule, for contrast; this is what a naive search
--   turns up first and is easy to mistake for the current rule.
-- - https://bulbapedia.bulbagarden.net/wiki/User:FIQ/Turn_sequence --
--   the exact Speed calculation formula (stat-stage multiplier,
--   paralysis's 2048/4096 factor as of Gen 7+).
-- - https://bulbapedia.bulbagarden.net/wiki/Priority -- priority
--   bracket / Speed-tiebreak general reference.
--
-- SCOPE, stated plainly: this file owns the STRUCTURAL comparator --
-- priority bracket, Trick-Room-aware Speed compare, random tie-break --
-- generically over an arbitrary list of actors. It does NOT compute
-- effective Speed itself (stat stages, paralysis, item/ability speed
-- multipliers like Choice Scarf or Swift Swim, or ability-based priority
-- like Prankster) -- that is a separate, much larger body of work
-- (dozens of items/abilities), out of scope here. Callers pass in
-- already-resolved speed/priority numbers; this file only decides ORDER
-- given those numbers. Today's one real caller (the battle.turn_order
-- wrap below) reuses the engine's own native Battle:effectiveSpeed and
-- Battle:movePriority. Battle:movePriority itself was a real, confirmed
-- bug -- it read ONLY a small legacy table keyed by native effect id
-- (Quick Attack/Protect/Counter/etc.), completely ignoring def.priority,
-- the real schema field every modern move (and every mod patch, Trick
-- Room's own -7 included) actually sets, silently treating every move
-- outside that legacy list as priority 0. This mod stays self-contained --
-- gen1recomp-dev's own source is never edited -- so the fix is a
-- monkeypatch of Battle.movePriority itself, right below, not an engine
-- change: def.priority now read first, the legacy table kept only as a
-- fallback for a record with no priority field of its own. effectiveSpeed's
-- own accuracy (item/ability speed multipliers, Prankster-style ability
-- priority) remains genuinely out of scope, per the paragraph above.
--
-- Trick Room is accepted as an input flag (opts.trickRoom), not
-- something this file activates or tracks -- combat/trick_room.lua owns
-- the real move effect (a real 5-turn activation, -7 priority, toggle-off
-- on reuse, confirmed against Bulbapedia) and writes the
-- battle.trickRoomActive field the wiring below reads. Kept as two
-- separate files on purpose: this one only ever needs to know the
-- CURRENT value of that flag, never how or when it gets set.
--
-- MULTI-BATTLER READINESS: see combat/MULTI_BATTLE_HOOKS.md for the real
-- contract. computeTurnOrder below is an INTERNAL PRIMITIVE, not the
-- integration point -- a future multi-battler mod should not call it
-- directly, since that would mean it derives priority/Speed/Trick-Room/
-- RNG itself, exactly the caller-side computation that doc's contract
-- exists to avoid. The actual seam is mod.exports.resolveTurnActions
-- (not yet built, spec'd in that doc) -- hand it battler identity only,
-- it derives everything else the same way this file's own
-- battle.turn_order wiring already does below. computeTurnOrder itself
-- IS already generic over N actors on either side, including asymmetric
-- formats (4v1, 1v5, 4vN) -- a flat list, no concept of "sides" anywhere
-- in it -- which is what makes it the right primitive for
-- resolveTurnActions to be built on. What is NOT yet possible is calling
-- it more than once per turn (a genuine mid-turn re-sort, matching PR
-- #6100 exactly) -- gen2/Battle.lua's own turn-resolution loop is a
-- hard-coded two-branch call with no second extension point between the
-- two actions, and nothing beyond 2 actors exists in this engine's data
-- model at all. Both are real engine-level gaps, not something reachable
-- from mod code as it stands -- see MULTI_BATTLE_HOOKS.md for the full
-- explanation and what a future multi-battler mod would need to bring.
return function(mod)
  local Damage = require("src.battle.gen2.Damage")
  local Battle = require("src.battle.gen2.Battle")

  -- Real bug fix, monkeypatched rather than edited into the engine (see
  -- this file's own header): def.priority is the real, direct move-record
  -- field (src/mods/Schemas.lua's own moves schema, `priority = f.opt(
  -- f.int(-7, 7))`) every modern move -- and every mod patch onto an
  -- existing move, Trick Room's own -7 included -- actually sets;
  -- Battle.PRIORITY is an older, narrower table keyed by a handful of
  -- legacy native EFFECT ids (EFFECT_PRIORITY_HIT etc.) that predates that
  -- field. def.priority wins when a record carries one at all (explicit 0
  -- included, checked with `~= nil` rather than truthiness) so it is read
  -- FIRST; Battle.PRIORITY is kept only as the fallback for a record that
  -- somehow has no priority field of its own.
  --
  -- Phase 5 (abilities/engine/priority_change.lua): registerPriorityModifier
  -- -- the same composable-chain shape registerDamageModifier already is
  -- (combat/modern_combat.lua), just for priority instead of damage.
  -- `caster` is a NEW, OPTIONAL 2nd param -- every existing call site
  -- (this file's own resolveTurnActions/battle.turn_order wrap below, plus
  -- combat/modern_terrain.lua's Psychic Terrain block) now passes it, but
  -- it defaults to nil for any other caller (e.g. tests/
  -- gen2_battle_ui_test.lua's own direct calls), which simply skips every
  -- modifier -- an ability can never change priority without knowing WHO
  -- is using the move, so "no caster given" correctly means "base priority
  -- only," identical to this function's pre-existing behavior.
  local priorityModifiers = {} -- { {id=, fn=fn(battle,moveId,caster,def)->delta}, ... }
  local function registerPriorityModifier(id, fn)
    assert(type(id) == "string" and id ~= "", "priority modifier id is required")
    assert(type(fn) == "function", "priority modifier must be a function")
    for i, entry in ipairs(priorityModifiers) do
      if entry.id == id then table.remove(priorityModifiers, i) break end
    end
    table.insert(priorityModifiers, { id = id, fn = fn })
  end
  mod.exports.registerPriorityModifier = registerPriorityModifier

  function Battle:movePriority(moveId, caster)
    local def = self:moveDef(moveId)
    local base
    if not def then
      base = 0
    elseif def.priority ~= nil then
      base = def.priority
    else
      base = Battle.PRIORITY[def.effect] or 0
    end
    if caster then
      for _, entry in ipairs(priorityModifiers) do
        base = base + (entry.fn(self, moveId, caster, def) or 0)
      end
    end
    return base
  end

  -- A never-nil 0..n-1 roller, the same convention Battle:roller() uses
  -- (gen2/Battle.lua) -- accepted as an explicit parameter rather than
  -- reached for globally, so this stays a pure function callable outside
  -- a live battle (e.g. a future test suite) with any roller handed in,
  -- including a stubbed one.
  local function fisherYatesShuffle(list, roller)
    for i = #list, 2, -1 do
      local j = roller(i) + 1 -- roller gives 0..i-1; Lua arrays are 1-indexed
      list[i], list[j] = list[j], list[i]
    end
  end

  -- Computes the real turn order for an arbitrary list of actors --
  -- generic over how many there are or how they split between sides, so
  -- 1v1, 2v2, 3v3, and asymmetric formats (4v1, 1v5, 4vN) all go through
  -- the identical code path with no special-casing anywhere. See
  -- combat/MULTI_BATTLE_HOOKS.md for the full contract and worked
  -- examples.
  --
  -- actors: array of { id = <opaque, anything>, priority = <integer>,
  --   speed = <number>, ... } -- any extra fields are preserved on the
  --   returned entries untouched, so a caller can carry its own metadata
  --   (which mon, which action, which side) through the sort for free.
  -- opts.trickRoom: boolean, default false. Reverses the SPEED
  --   comparison direction within a priority bracket only -- priority
  --   itself always resolves high-to-low regardless of Trick Room, the
  --   one rule that has never changed across every generation Trick
  --   Room has existed in.
  -- opts.roller: function(n) -> 0..n-1, REQUIRED whenever the actor list
  --   can contain a genuine tie (same priority AND same speed) --
  --   asserted rather than silently defaulted, since a silent fallback
  --   RNG would make tie-break outcomes depend on which Lua happens to
  --   be running rather than the battle's own seeded stream.
  --
  -- Returns a NEW array (the same actor tables, in resolved order) --
  -- never mutates the input array or its entries.
  local function computeTurnOrder(actors, opts)
    opts = opts or {}
    local trickRoom = opts.trickRoom == true
    assert(type(actors) == "table", "computeTurnOrder: actors must be a table")

    local list = {}
    for i, actor in ipairs(actors) do
      assert(type(actor) == "table", "computeTurnOrder: actor #" .. i .. " must be a table")
      assert(type(actor.priority) == "number", "computeTurnOrder: actor #" .. i .. " needs a numeric priority")
      assert(type(actor.speed) == "number", "computeTurnOrder: actor #" .. i .. " needs a numeric speed")
      list[i] = actor
    end
    if #list <= 1 then return list end

    -- Coarse sort: priority always high-to-low; speed high-to-low
    -- normally, low-to-high under Trick Room. A genuine tie (equal
    -- priority AND equal speed) is left unordered by this pass on
    -- purpose -- table.sort's comparator has to be a strict, transitive
    -- "less than," and one that randomly answers differently for the
    -- same pair on different calls is not one (it can corrupt the sort
    -- or throw "invalid order function for sorting"). Ties are resolved
    -- properly afterward instead.
    table.sort(list, function(a, b)
      if a.priority ~= b.priority then return a.priority > b.priority end
      if a.speed == b.speed then return false end
      if trickRoom then return a.speed < b.speed end
      return a.speed > b.speed
    end)

    -- Group consecutive equal (priority, speed) runs and shuffle each
    -- group with the battle's own RNG -- the real rule, confirmed this
    -- session against the actual PS source and the GitHub issue
    -- discussing it: a genuine tie is broken randomly through the
    -- battle's own RNG, not by side, turn count, or array position.
    local result = {}
    local i = 1
    while i <= #list do
      local j = i
      while j < #list and list[j + 1].priority == list[i].priority
          and list[j + 1].speed == list[i].speed do
        j = j + 1
      end
      if j > i then
        assert(type(opts.roller) == "function",
          "computeTurnOrder: a tie exists (priority=" .. tostring(list[i].priority) ..
          ", speed=" .. tostring(list[i].speed) .. ") and opts.roller was not provided")
        local bucket = {}
        for k = i, j do bucket[#bucket + 1] = list[k] end
        fisherYatesShuffle(bucket, opts.roller)
        for _, actor in ipairs(bucket) do result[#result + 1] = actor end
      else
        result[#result + 1] = list[i]
      end
      i = j + 1
    end
    return result
  end
  mod.exports.computeTurnOrder = computeTurnOrder

  ------------------------------------------------------------------
  -- mod.exports.orderSwitchInMons(battle, monA, monB) -- speed order for
  -- SIMULTANEOUS switch-in triggers (explicit user rule, this session's
  -- Phase 1.5 follow-up). The one case this engine's own event model
  -- batches two mons into a single handler call is battle.started (both
  -- leads entering together) -- every switch-in ability engine in
  -- abilities/engine/ processes that pair in ONE call, and until now all
  -- of them used a fixed player-then-enemy order regardless of Speed.
  --
  -- Real rule: simultaneous switch-in effects resolve FASTEST first. Every
  -- switch-in ability engine in this mod applies its own effect by
  -- unconditionally overwriting shared field state (weather, terrain) --
  -- so whichever one applies SECOND is the one left standing afterward,
  -- meaning the SLOWER of the two Pokemon's own trigger is what actually
  -- persists on a speed mismatch. This function returns the two mons in
  -- that fastest-first APPLICATION order; the second one returned is the
  -- one a caller should expect to "win" any exclusive, overwrite-shaped
  -- state.
  --
  -- Deliberately passes trickRoom=false unconditionally rather than
  -- reading battle.trickRoomActive: Trick Room (combat/trick_room.lua,
  -- a real, already-working system -- see this file's own header)
  -- reorders MOVE speed only, confirmed real-game behavior, and never
  -- touches switch-in/ability activation order, so this stays correct
  -- regardless of whether Trick Room happens to be up. Reuses this same
  -- file's own
  -- computeTurnOrder for its already-correct RNG tie-break (a genuine
  -- speed tie is broken by the battle's own roller, never by argument
  -- order) instead of a second, parallel comparator.
  ------------------------------------------------------------------
  mod.exports.orderSwitchInMons = function(battle, monA, monB)
    if not (battle and monA and monB) then return monA, monB end
    local actors = {
      { id = 1, priority = 0, speed = battle:effectiveSpeed(monA) },
      { id = 2, priority = 0, speed = battle:effectiveSpeed(monB) },
    }
    local ordered = computeTurnOrder(actors, { trickRoom = false, roller = battle:roller() })
    if ordered[1].id == 1 then return monA, monB end
    return monB, monA
  end

  ------------------------------------------------------------------
  -- mod.exports.orderActiveBattlers(battle, battlers) -> orderedBattlers
  -- The real N-way generalization of orderSwitchInMons above, explicit
  -- user request (2026-08-28): the fixed player-then-enemy switch-in
  -- ordering pattern every switch-in ability engine in this mod used
  -- (`local first, second = battle.player, battle.enemy; if order then
  -- ... end`) only ever covered exactly two simultaneous switch-ins --
  -- real Showdown doubles/triples resolves a whole LEAD of 4-6
  -- simultaneously-entering Pokemon in fastest-first application order,
  -- same rule, just more than two actors. Reuses computeTurnOrder
  -- directly (already asymmetric-ready by construction, this file's own
  -- header) rather than a parallel N-way comparator -- same fastest-
  -- first APPLICATION order convention orderSwitchInMons already
  -- established (the LAST battler returned is the one that "wins" any
  -- exclusive, overwrite-shaped shared state, e.g. weather/terrain).
  ------------------------------------------------------------------
  mod.exports.orderActiveBattlers = function(battle, battlers)
    if not (battle and type(battlers) == "table") then return battlers or {} end
    local actors, byId = {}, {}
    for i, mon in ipairs(battlers) do
      if mon then
        local actor = { id = i, priority = 0, speed = battle:effectiveSpeed(mon) }
        actors[#actors + 1] = actor
        byId[i] = mon
      end
    end
    local ordered = computeTurnOrder(actors, { trickRoom = false, roller = battle:roller() })
    local result = {}
    for i, entry in ipairs(ordered) do
      result[i] = byId[entry.id]
    end
    return result
  end

  ------------------------------------------------------------------
  -- mod.exports.resolveTurnActions(battle, actingBattlers) -- the real
  -- multi-battler integration seam MULTI_BATTLE_HOOKS.md specs and this
  -- was, until now, "not yet built." A caller (a multi-battler combat
  -- scene) hands us battler identity ONLY -- who's acting, on what
  -- target, with what move -- and we derive priority/Speed/Trick-Room/
  -- RNG order ourselves and drive battle:useMove(...) directly, per
  -- battler, in our own correctly-derived order. This deliberately never
  -- touches battle:takeTurn/runTurn (confirmed unexported, unwrappable,
  -- hard-coded to battle.player/battle.enemy) -- useMove itself is
  -- confirmed generic over attacker/defender (Battle.lua:1337 reads
  -- self:findMove(attacker,...)/self:volatile(attacker)/
  -- self:sideOf(attacker), never battle.player/battle.enemy directly),
  -- so any battler this caller controls flows through the real pipeline
  -- (STAB/Tera/Protect/Max Guard/every registerDamageModifier) exactly
  -- like today's player-vs-enemy fights, with zero new wiring needed on
  -- the damage side.
  --
  -- actingBattlers: a flat list, any length, either side --
  --   { { mon = <real mon table>, move = <moveId>, target = <real mon> },
  --     ... }
  -- `target` is the single chosen mon as of QUEUE time. If an earlier
  -- action this turn faints it, THIS function redirects/fails that action
  -- itself (see the ROUND 26 note below) -- the caller never has to
  -- pre-check aliveness, exactly the mid-turn knowledge update
  -- MULTI_BATTLE_HOOKS.md's own contract puts on this side of the seam.
  --
  -- SPEED, deliberately NOT read via battle:effectiveSpeed(mon): that
  -- method computes self.stages[self:sideOf(mon)] (Battle.lua:845-848),
  -- and sideOf is a hard binary -- `(mon == self.player) and "player" or
  -- "enemy"` (Battle.lua:434-436) -- so every battler that isn't
  -- literally battle.player or battle.enemy would silently share ONE
  -- stage bucket with whichever side it falls through to, corrupting
  -- stat-stage boosts across unrelated battlers the instant a real
  -- (3+ total battlers) format is used. Confirmed by direct read, not
  -- assumed -- this is exactly the class of gap MULTI_BATTLE_HOOKS.md's
  -- own "no real N-way sideOf" section warns about, one level deeper
  -- than the event-tagging case that doc calls out by name. Speed here
  -- instead composes battle:battleStat(mon,"speed") (genuinely per-mon,
  -- confirmed safe -- Battle.lua:762-764's only mon-identity check is a
  -- `mon == self.player` badge-boost gate, which is real Gen 2 behavior:
  -- badges only ever boost the human player's own team, correct for any
  -- battler either way) against g9-battle-engine-beta's OWN per-mon
  -- stage store (mod.exports.ShowdownPrimitives.stageOf(mon, "spe"),
  -- combat/showdown_primitives.lua's mon.volatile.boosts table -- built
  -- for exactly this reason), through the same Damage.applyStage/
  -- Battle.statusPenaltyFor (paralysis halving) native's own
  -- effectiveSpeed composes, just keyed per-mon instead of per-side.
  ------------------------------------------------------------------
  local function effectiveSpeedFor(battle, mon)
    local Primitives = mod.exports.ShowdownPrimitives
    local raw = battle:battleStat(mon, "speed")
    local stage = Primitives and Primitives.stageOf(mon, "spe") or 0
    local boosted = Damage.applyStage(raw, stage)
    return Battle.statusPenaltyFor(battle.data, mon, "speed", boosted)
  end

  ------------------------------------------------------------------
  -- ROUND 26 (2026-09-10): mid-turn faint redirection for SINGLE-TARGET
  -- actions. Two actions in one multi-battler turn can name the SAME
  -- target, and whichever resolves first can faint it before the later
  -- one is delivered -- which, before this, left the later action applying
  -- its move to a 0-HP corpse: a second attack landing on an already-
  -- fainted mon, or Heal Pulse "reviving" it just to have it re-faint.
  -- The real rule (the user's own explicit spec) is decided by the fainted
  -- target's SIDE at resolution time:
  --   * an ENEMY-directed move still has legal recipients, so it redirects
  --     to a random live adjacent foe (combat/move_targeting.lua's own
  --     pickAdjacentEnemy), and fails outright when none is left standing;
  --   * an ALLY-directed move (Heal Pulse aimed at an ally, plus the
  --     inherently ally-only Helping Hand / Aromatic Mist / Acupressure)
  --     has no alternate recipient at all -- it simply FAILS, spending its
  --     PP and announcing itself exactly like any other failed move, and
  --     never touching the fainted ally.
  -- Spread moves are deliberately untouched: resolveMoveTargets already
  -- re-expands them over the LIVE roster just below, which is the same
  -- redirection for free. This path only ever runs for a single-target
  -- action whose chosen target was alive when queued and is not anymore.
  ------------------------------------------------------------------

  local function findMoveSlot(mon, moveId)
    if not (mon and mon.moves) then return nil end
    for _, ms in ipairs(mon.moves) do
      if ms and ms.id == moveId then return ms end
    end
    return nil
  end

  -- The move was chosen and used, but has no valid recipient left: spend
  -- its PP, announce "X used Y!" (the same kind="move" event native
  -- useMove emits, kept as battle.moveEvent), mark it missed so the screen
  -- plays no attack animation, then the engine's own failuretext line.
  -- Mirrors Battle:useMove's own failed-move tail (Battle.lua:1470-1478,
  -- :1656-1660): the PP is charged because the move WAS used, and the
  -- announcement is kept so the player sees "used Heal Pulse!" followed by
  -- "But it failed!" rather than the action silently vanishing.
  local function failAction(battle, caster, moveId)
    local moveSlot = findMoveSlot(caster, moveId)
    if moveSlot and (moveSlot.pp or 0) > 0 then
      moveSlot.pp = moveSlot.pp - 1
    end
    local def = battle.moveDef and battle:moveDef(moveId)
    local name = battle.monName and battle:monName(caster)
    if battle.emit then
      battle.moveEvent = battle:emit({ kind = "move",
        side = battle.sideOf and battle:sideOf(caster),
        move = moveId,
        text = (name or "?") .. "\nused " .. ((def and def.name) or moveId) .. "!" })
      if battle.markMissed then battle:markMissed() end
      battle:emit({ kind = "message", text = "But it failed!" })
    end
  end

  -- resolveSingleTarget(battle, caster, moveId, chosen) -> targets, failed
  -- targets is the list to deliver to (empty when nothing is left); failed
  -- is true when the move has no valid recipient at all and must announce
  -- its failure instead. A chosen target still standing resolves exactly as
  -- it did before this round.
  local function resolveSingleTarget(battle, caster, moveId, chosen)
    if not chosen then return {}, false end
    if (chosen.hp or 0) > 0 then return { chosen }, false end
    local targeting = mod.exports
    if targeting.isAllyDirectedMove and targeting.isAllyDirectedMove(moveId) then
      return {}, true
    end
    if battle.sideOf and battle:sideOf(chosen) == battle:sideOf(caster) then
      return {}, true
    end
    local redirect = targeting.pickAdjacentEnemy
      and targeting.pickAdjacentEnemy(battle, caster, moveId)
    if redirect then return { redirect }, false end
    return {}, true
  end

  -- A self-switch effect (combat/switch_primitives.lua's own
  -- requestSwitch, U-turn/Volt Switch/Baton Pass-shaped) sets the real,
  -- public battle.forcedSwitch field -- the SAME one native runTurn
  -- already checks (after a faint, or a Roar/Whirlwind drag-out) to end a
  -- round early and skip residual. Honored here too, after each action:
  -- whoever hasn't acted yet this round simply doesn't, matching vanilla's
  -- own real behavior for the identical case (see switch_primitives.lua's
  -- own header for why "resume the rest of this same round afterward"
  -- isn't achievable from mod code at all -- runTurn is an unexported
  -- local closure no mod can reach into).
  mod.exports.resolveTurnActions = function(battle, actingBattlers)
    if not (battle and type(actingBattlers) == "table") then return end
    local actors = {}
    for i, entry in ipairs(actingBattlers) do
      if entry.mon and (entry.mon.hp or 0) > 0 and entry.move then
        actors[#actors + 1] = {
          id = entry, -- the battler entry itself, not an index -- identity
          priority = battle:movePriority(entry.move, entry.mon),
          speed = effectiveSpeedFor(battle, entry.mon),
        }
      end
    end
    local ordered = computeTurnOrder(actors, {
      trickRoom = battle.trickRoomActive == true, -- combat/trick_room.lua sets this for real; see this file's own header
      roller = battle:roller(),
    })
    for _, actor in ipairs(ordered) do
      local entry = actor.id
      -- Mid-turn faint check: an earlier action in this same order may
      -- have dropped the actor or its own chosen target below 0 HP.
      -- Skipping here (rather than trusting the order computed before
      -- any of this turn's damage landed) is what MULTI_BATTLE_HOOKS.md's
      -- own contract promises -- "that knowledge updates who still
      -- counts as a valid remaining actor before we decide who's next."
      if (entry.mon.hp or 0) > 0 then
        -- Spread moves (all-opponents/all-other-pokemon: LEER, Muddy
        -- Water, Earthquake, Surf, ...) expand to EVERY adjacent target
        -- here, not the single placeholder target the caller queued --
        -- that is the entire point of combat/move_targeting.lua's
        -- resolveMoveTargets, and the reason a battle scene can queue one
        -- placeholder target for an AoE move and be correct. Each real
        -- target gets its own useMove; the count rides to the damage
        -- formula on a transient battle.__spreadTargetCount field
        -- (consumed by modern_combat.lua's spread_reduction modifier),
        -- and a mid-turn faint of the caster or a later target just skips
        -- whatever remains, lazily, same as single-target actions.
        local targets
        local failed = false
        if mod.exports.isSpreadMove and mod.exports.isSpreadMove(entry.move) then
          targets = mod.exports.resolveMoveTargets(battle, entry.mon, entry.move, entry.target)
        else
          -- Single-target: redirect to a live adjacent foe (or fail, for
          -- an ally-directed move) when this action's chosen target fainted
          -- to an earlier action this turn -- see resolveSingleTarget above.
          targets, failed = resolveSingleTarget(battle, entry.mon, entry.move, entry.target)
        end
        local live = {}
        for _, t in ipairs(targets) do
          if t and (t.hp or 0) > 0 then live[#live + 1] = t end
        end
        if #live == 0 and failed then
          -- No valid recipient and no redirect available: the move is used
          -- (announced, PP spent) and fails.
          failAction(battle, entry.mon, entry.move)
        elseif #live > 0 then
          if #live > 1 then battle.__spreadTargetCount = #live end
          -- Native Battle:useMove is single-target: it re-runs the full
          -- per-use pipeline (PP decrement, the kind="move" announce
          -- event the screen animates off, and the move effect) once per
          -- call. A spread action expanding to N targets must therefore
          -- cost exactly ONE use, not N -- this is where LEER used to
          -- fire its animation twice and burn 2 PP per action in every
          -- multi-battler battle. Two re-normalizations:
          --   * PP: locate the move's slot on the caster, remember its
          --     value after the first call, top it back to 1 before each
          --     later call (so native's no-PP bail never trips on the
          --     last-PP case), then restore the first-call value after
          --     the loop -- net cost is always exactly 1 PP.
          --   * announce: drain the event queue and keep only the FIRST
          --     kind="move" event (which already carries the user's "used
          --     %s!" text and the first target's scene stamp). The
          --     per-target effect messages (each enemy's "defense fell!")
          --     are separate kind="message" events and survive unchanged
          --     -- one per target is exactly right for a spread move.
          --     The dedup must be scoped to THIS spread action's own
          --     events only: battle.events already holds every earlier
          --     actor's events from this same resolveTurnActions pass
          --     (tail-whip.lua reported a boss's Tail Whip announcing
          --     nothing while its targets' "defense fell!" lines still
          --     showed -- the drain had been keeping the FIRST move event
          --     in the whole queue, i.e. some earlier actor's "used X!",
          --     and silently dropping the spread caster's own). priorEvents
          --     is the queue length before this action's useMove loop, so
          --     events at or below it pass through untouched and only the
          --     NEW events are deduped -- the caster's own announce
          --     survives no matter how many actors already went this turn.
          local moveSlot
          if entry.mon.moves then
            for _, ms in ipairs(entry.mon.moves) do
              if ms and ms.id == entry.move then moveSlot = ms break end
            end
          end
          local priorEvents = battle.events and #battle.events or 0
          local ppAfterFirst
          local forced = false
          for i, t in ipairs(live) do
            if (entry.mon.hp or 0) > 0 then
              if i > 1 and moveSlot and (moveSlot.pp or 0) < 1 then
                moveSlot.pp = 1
              end
              battle:useMove(entry.mon, t, entry.move)
              if i == 1 and moveSlot then ppAfterFirst = moveSlot.pp end
              if battle.forcedSwitch then
                forced = true
                break
              end
            end
          end
          if moveSlot and ppAfterFirst ~= nil then
            moveSlot.pp = ppAfterFirst
          end
          if #live > 1 and battle.takeEvents and battle.emit then
            local allEvents = battle:takeEvents() or {}
            local keptMove
            for i, ev in ipairs(allEvents) do
              if i <= priorEvents then
                battle:emit(ev)
              elseif ev and ev.kind == "move" then
                if not keptMove then
                  keptMove = true
                  battle:emit(ev)
                end
              else
                battle:emit(ev)
              end
            end
          end
          battle.__spreadTargetCount = nil
          if forced then
            battle.forcedSwitch = nil
            break
          end
        end
      end
    end
  end

  ------------------------------------------------------------------
  -- Today's one real caller: the native battle.turn_order hook
  -- (gen2/Battle.lua:4085-4098), which decides the whole turn's order
  -- once, before either action runs -- the only extension point this
  -- 2-battler engine currently exposes (see MULTI_BATTLE_HOOKS.md for
  -- why a real mid-turn re-sort needs more than this and doesn't exist
  -- yet). Replaces the native comparator with the SAME computeTurnOrder
  -- any future multi-battler caller will use, so the 2-actor case today
  -- and any future N-actor case are provably one algorithm, not two.
  ------------------------------------------------------------------
  -- CONFIRMED CRASH, this session (2026-08-27): "battle.turn_order" is
  -- NOT a Gen-2-exclusive hook name -- Gen 1's own BattleState:resolveTurn
  -- (src/battle/BattleState.lua:2736-2739) calls the identical hook name,
  -- and Runtime.wantsHook only checks whether ANYTHING is registered for
  -- that name, not which engine registered it -- so this wrap fires for
  -- Gen 1 battles too the instant it's installed. Gen 1's own call passes
  -- a completely different ctx shape (`{ rng = self.rng }`, confirmed by
  -- direct read -- no .battle field at all), so `local battle = ctx.battle`
  -- silently evaluated to nil and every following battle: call crashed
  -- (attempt to index a nil value) on the first turn of any Gen 1 battle.
  -- Gen 1 does not get Gen-9-accurate turn order from this file at all
  -- yet (that's real, separate work, not yet built) -- this guard only
  -- stops the crash by falling through to Gen 1's own native comparator
  -- (nextFn) whenever ctx doesn't look like Gen 2's own shape.
  mod.hooks:wrap("battle.turn_order",
    function(nextFn, playerBattler, playerMoveDef, enemyBattler, enemyMoveDef, ctx)
      local battle = ctx and ctx.battle
      if not battle then
        return nextFn(playerBattler, playerMoveDef, enemyBattler, enemyMoveDef, ctx)
      end
      local actors = {
        { id = "player", priority = battle:movePriority(ctx.playerMove, battle.player),
          speed = battle:effectiveSpeed(battle.player) },
        { id = "enemy", priority = battle:movePriority(ctx.enemyMove, battle.enemy),
          speed = battle:effectiveSpeed(battle.enemy) },
      }
      local ordered = computeTurnOrder(actors, {
        trickRoom = battle.trickRoomActive == true, -- combat/trick_room.lua sets this for real; see this file's own header
        roller = battle:roller(),
      })
      return ordered[1].id == "player"
    end, 0)

  mod.log:info("galar_gmax_dex: turn_order installed (Gen 9 priority/Trick-Room-aware/random-tie comparator)")
end
