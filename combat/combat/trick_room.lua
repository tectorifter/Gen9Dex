-- Trick Room's real activation, owned here so combat/turn_order.lua's own
-- battle.trickRoomActive read (its header has said so since it was
-- written: "nothing in this engine implements Trick Room's own move
-- effect yet... the wiring below always passes false today") stops being
-- a permanent stub and becomes a real, tracked value.
--
-- MECHANIC, confirmed against Bulbapedia directly (2026-08-20, not
-- assumed -- this session already got one Speed-mechanic detail wrong by
-- trusting a first search result over a primary source, so this one was
-- checked properly first):
--   - Priority -7 (the lowest bracket; still subordinate to priority
--     itself the same way every other move is -- Trick Room reverses
--     SPEED order within a bracket, never priority order between them,
--     which combat/turn_order.lua's own computeTurnOrder already gets
--     right and needs no change here).
--   - Lasts 5 turns; using it counts as the first of those five.
--   - Using Trick Room again while it is already active ends it
--     immediately (a toggle, not a refresh) -- the same rule Magic Room/
--     Wonder Room share in the real games.
--
-- Gen 2 has NO native concept of Trick Room at all -- it is a Generation
-- IV move, and this engine recompiles Gold/Silver. Unlike weather
-- (combat/modern_weather.lua's own header: Gen 2's native tickWeather
-- already runs a real duration pass, so that file explicitly skips Gen 2
-- to avoid double-ticking), there is nothing native here to defer to or
-- collide with -- the duration countdown below is the only mechanism
-- that will ever run it, with no Gen2-skip guard needed.
--
-- Field state lives directly on the battle object (battle.trickRoomActive,
-- battle.trickRoomTurns) -- the same convention weather's own
-- battle.weather/battle.weatherTurns and Protect's own user.protected
-- already use throughout this mod, not a new pattern.
-- Boss-fight "dimension" protections (combat/boss_fight.lua), added this
-- session -- four independent flags, not one combined "dimension" flag:
--   dimensionLock -- bans all three room moves (Trick Room, Magic Room,
--     Wonder Room) from being used at all. Does NOT activate any of them
--     itself -- a pure "no room shenanigans" gate.
--   trickRoom -- the battle is permanently in Trick Room from the moment
--     this flag is set (battle.trickRoomActive/battle.trickRoomTurns set
--     directly in combat/boss_fight.lua's own setBossFightProtections,
--     since this is read as an immediate environmental fact, not
--     something contingent on the move actually being cast -- unlike
--     weather/terrain's boss-lock, which only takes effect once the boss
--     itself sets one through its own kit) -- and bans ONLY the
--     TRICKROOM move (using it again would otherwise toggle it off).
--   magicRoom / wonderRoom -- bans ONLY their own move. Honest gap, not
--     silently pretended complete: NEITHER Magic Room nor Wonder Room has
--     any real field-effect implementation anywhere in this mod (no
--     item-suppression, no Def/SpDef swap) -- these two flags today can
--     only ever enforce the move-ban half of their own description, never
--     "permanent Magic/Wonder Room," because there is no room mechanic
--     here for either to make permanent.
--
-- All four compose freely (checked together in the single Battle:useMove
-- wrap below): trickRoom alone leaves Magic/Wonder Room castable by
-- either side; trickRoom + dimensionLock together removes room-move
-- access entirely for the rest of the fight.
return function(mod)
  local Battle = require("src.battle.gen2.Battle")
  local EFFECT_ID = "GALAR_TRICKROOM_EFFECT"
  local START_TEXT = " twisted\nthe dimensions!"
  local END_TEXT = "The twisted\ndimensions returned\nto normal!"
  local resolveFieldDuration = mod.exports.resolveFieldDuration
  local FIELD_BASE_TURNS = mod.exports.FIELD_BASE_TURNS
  local FIELD_EXTENDED_TURNS = mod.exports.FIELD_EXTENDED_TURNS
  assert(resolveFieldDuration and FIELD_BASE_TURNS and FIELD_EXTENDED_TURNS,
    "trick_room: combat/field_duration.lua must load first")
  -- No real item extends Trick Room in any current generation -- this
  -- still runs through the SAME resolveFieldDuration primitive weather/
  -- terrain use, with extendingItem=nil, so it always resolves to
  -- FIELD_BASE_TURNS (5) today but needs no rewrite if a future id is ever
  -- assigned here. Explicit user decision: future-proofing only, not a
  -- guess at a real mechanic.
  local TRICKROOM_EXTEND_ITEM = nil

  ------------------------------------------------------------------
  -- The move's own effect: a real Gen 2 kind="primary" record (see this
  -- mod's own combat/SUBEFFECTS.md for why -- kind="full"+perform is
  -- Gen 1's shape and silently does nothing under Gen 2's real dispatch,
  -- the exact bug Protect/Max Guard shipped with once already this
  -- session). accuracyChecked left unset: Trick Room affects the whole
  -- field, not the opponent specifically, the same "self/field-only,
  -- never miss" reasoning modern_weather.lua's own starters already
  -- establish for this shape of move.
  ------------------------------------------------------------------
  mod.content.move_effects:register(EFFECT_ID, {
    kind = "primary",
    run = function(battle, attacker, defender, def, moveId, sureHit)
      if battle.trickRoomActive then
        battle.trickRoomActive = false
        battle.trickRoomTurns = nil
        battle:emit({ kind = "message", text = END_TEXT })
        return
      end
      battle.trickRoomActive = true
      battle.trickRoomTurns = resolveFieldDuration(attacker, FIELD_BASE_TURNS,
        FIELD_EXTENDED_TURNS, TRICKROOM_EXTEND_ITEM)
      battle:emit({ kind = "message", text = battle:monName(attacker) .. START_TEXT })
    end,
  })

  -- National Dex already owns TRICKROOM's real base stats (Psychic,
  -- status, 0 power, never-miss accuracy, 5 PP) -- patched, not
  -- re-registered, touching only what is actually this mod's domain:
  -- which sub-effect runs, and the priority tier that effect needs.
  -- priority is a real, direct move-record field (src/mods/Schemas.lua's
  -- own moves schema: `priority = f.opt(f.int(-7, 7))`), not something
  -- combat/turn_order.lua derives on its own -- patched explicitly here
  -- rather than trusted to whatever National Dex's own placeholder value
  -- was, the identical reasoning Max Guard's own explicit priority patch
  -- already used this session after a live symptom pointed straight at
  -- priority.
  mod.content.moves:patch("TRICKROOM", { effect = EFFECT_ID, priority = -7 })

  ------------------------------------------------------------------
  -- Duration: battle.turn_ended, the same real turn-boundary event
  -- modern_weather.lua's own decrement uses -- reused, not a new hook.
  -- No isGen2Battle guard: unlike weather, nothing native exists here to
  -- avoid double-ticking against.
  ------------------------------------------------------------------
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev and ev.battle
    if not battle or not battle.trickRoomActive then return end
    battle.trickRoomTurns = (battle.trickRoomTurns or 0) - 1
    if battle.trickRoomTurns <= 0 then
      battle.trickRoomActive = false
      battle.trickRoomTurns = nil
      battle:emit({ kind = "message", text = END_TEXT })
    end
  end)

  ------------------------------------------------------------------
  -- Boss-fight room-move ban: dimensionLock bans all three; trickRoom/
  -- magicRoom/wonderRoom each ban only their own move. Same "skip the
  -- native call entirely, no PP cost" simplification modern_terrain.lua's
  -- own Psychic Terrain block already establishes as this project's
  -- accepted shape for a move that "can't be used" at all, rather than
  -- the exact real mechanic (spend PP, print "used MOVE!", THEN fail).
  -- Blanket ban regardless of which side is attempting it, matching the
  -- literal spec ("the battle doesn't allow using dimension moves"), not
  -- just a player-vs-boss restriction.
  ------------------------------------------------------------------
  local ROOM_MOVE_FLAG = { TRICKROOM = "trickRoom", MAGICROOM = "magicRoom", WONDERROOM = "wonderRoom" }
  local nativeUseMoveForRooms = Battle.useMove
  function Battle:useMove(attacker, defender, moveId)
    local flags = self.bossFightFlags
    if flags then
      local ownFlag = ROOM_MOVE_FLAG[moveId]
      if flags.dimensionLock or (ownFlag and flags[ownFlag]) then
        self:emit({ kind = "message", text = "But it failed!" })
        return
      end
    end
    return nativeUseMoveForRooms(self, attacker, defender, moveId)
  end

  mod.log:info("galar_gmax_dex: trick_room installed (real 5-turn activation, -7 priority, toggle-off, boss-fight dimension protections)")
end
