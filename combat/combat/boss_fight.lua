-- Boss-fight protection flags: a cross-cutting policy layer other mods
-- (or this mod's own future boss-encounter setup code) can flip on for a
-- specific battle, gating a named set of protections that apply ONLY to
-- the enemy side of the field (the boss). Explicit user spec, this
-- session -- not derived from national_dex or any other data source, so
-- there is no abilities/data-style inclusion-list file here: the flag
-- SET itself is exactly the caller's own inclusion list, held directly
-- on the battle.
--
-- mod.exports.setBossFightProtections(battle, "sun", "mistyTerrain", ...)
-- -- variadic, not a full config object: only the NAMED protections turn
-- on, everything else stays off. Internally stored as battle.bossFightFlags
-- = {name=true, ...}, so a consumer checking one flag never has to reason
-- about the ones it didn't pass.
--
-- Recognized names (each one's actual enforcement lives next to the real
-- primitive it gates, not centralized here -- same "the gate lives beside
-- the thing it gates" convention canSetWeather already established
-- alongside setWeather):
--   sun          -- combat/modern_combat.lua's setWeather/canSetWeather:
--                    the boss's own weather-setting becomes permanent and
--                    beats even a player's primal weather; the player's
--                    side can't set or override weather at all.
--   mistyTerrain -- combat/modern_terrain.lua's setTerrain: same shape,
--                    for terrain.
--   statsDrop    -- combat/modern_combat.lua's changeStage +
--                    combat/modern_movepool_stages.lua's changeNativeStage:
--                    the boss can't have ANY stat lowered, hostile or
--                    self-inflicted.
--   type         -- combat/type_override_primitives.lua's canChangeType:
--                    the boss's type can't be changed by an opponent-
--                    directed effect (Soak et al); its own self-activated
--                    kit (Protean, Color Change, a self-targeted Conversion)
--                    is unaffected.
--   ability      -- ENFORCED (2026-08-28): abilities/ability_dispatch
--                    .lua's own mod.exports.setAbility -- the real "change
--                    a mon's ability" primitive this flag was originally
--                    reserved for -- refuses outright whenever the target
--                    is battle.enemy and this flag is set. Applies equally
--                    to every future ability-changing/copying move or
--                    ability built on top of setAbility (Skill Swap, Worry
--                    Seed, Entrainment, Gastro Acid, Trace, Mummy,
--                    Wandering Spirit, Receiver, Power of Alchemy), since
--                    none of them have any route to the boss's ability
--                    that bypasses setAbility itself.
--   dimensionLock, trickRoom, magicRoom, wonderRoom
--                -- combat/trick_room.lua: room-move banning and
--                    permanent-room application. See that file's own
--                    header for the full four-flag breakdown.
--   softStatus, hardStatus, antiDrain, healblock
--                -- pending: hook points not yet confirmed against real
--                    source at the time this file was written. Flags are
--                    stored and readable now so the API is stable, but
--                    have no enforcement yet -- to be wired once the
--                    exact status/drain/heal-block primitives are located.
return function(mod)
  mod.exports.setBossFightProtections = function(battle, ...)
    if not battle then return end
    local flags = {}
    for _, name in ipairs({ ... }) do
      flags[name] = true
    end
    battle.bossFightFlags = flags
    -- trickRoom is read as an immediate environmental fact ("the battle
    -- IS permanent Trick Room"), not something contingent on the move
    -- ever being cast -- unlike weather/terrain's boss-lock (which only
    -- activates once the boss sets one through its own kit), so it's
    -- applied right here rather than waiting on a trigger. combat/
    -- trick_room.lua owns the real field (battle.trickRoomActive/
    -- battle.trickRoomTurns) -- written directly here, the same "plain
    -- field write, no dedicated setter required" convention weather/
    -- terrain's own boss-lock already uses. magicRoom/wonderRoom have no
    -- equivalent field to set at all (see combat/trick_room.lua's own
    -- header for why) -- they only ever gate their own move.
    if flags.trickRoom then
      battle.trickRoomActive = true
      battle.trickRoomTurns = math.huge
    end
  end

  -- Plain read helper -- every gate below reads through this rather than
  -- poking battle.bossFightFlags directly, so a battle with no boss-fight
  -- flags set at all (the overwhelming majority of battles) never needs
  -- more than one nil check at each call site.
  mod.exports.bossFightHas = function(battle, name)
    return battle ~= nil and battle.bossFightFlags ~= nil and battle.bossFightFlags[name] == true
  end

  mod.log:info("g9-battle-engine-beta: boss_fight installed (setBossFightProtections, bossFightHas)")
end
