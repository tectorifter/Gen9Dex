-- Shared "does the effect's own setter hold the item that stretches its
-- duration" primitive -- the real Pokemon Showdown mechanic behind Damp
-- Rock/Heat Rock/Smooth Rock/Icy Rock (weather) and Terrain Extender
-- (terrain): 5 turns normally, 8 when the mon that SET the effect is
-- holding the matching item at the moment it's set (confirmed directly
-- against the real, current Pokemon Showdown source -- data/moves.ts's own
-- durationCallback on electricterrain/grassyterrain/mistyterrain/
-- psychicterrain, all four an identical `source?.hasItem('terrainextender')
-- ? 8 : 5`, fetched directly rather than recalled from memory).
--
-- One function, reused by every field-effect setter (weather, terrain,
-- Trick Room) rather than three separate copies of the same "check .item,
-- pick a number" logic -- and, per explicit user decision, built to read
-- `setter.item` generically rather than "whichever move used it": the real
-- games extend this to an ABILITY holder too (Drizzle+Damp Rock, etc.),
-- and this engine has no ability system yet, but a future one only has to
-- pass its own ability-holder mon as `setter` here -- nothing about this
-- function's own contract needs to change when that day comes.
return function(mod)
  -- Real current Showdown's own base/extended pair -- shared, not
  -- redeclared per file, since every real field effect that has ANY
  -- extension at all (weather, terrain) uses this exact same 5/8 split.
  mod.exports.FIELD_BASE_TURNS = 5
  mod.exports.FIELD_EXTENDED_TURNS = 8

  local function holdsExtender(setter, extendingItem)
    if not (setter and setter.item and extendingItem) then return false end
    if type(extendingItem) == "table" then return extendingItem[setter.item] == true end
    return setter.item == extendingItem
  end

  -- setter: whichever mon caused the effect -- a move's own attacker
  -- today, an ability's own holder once this engine has abilities.
  -- extendingItem: a single item id string, a set of ids ({FOO=true,...}),
  -- or nil for an effect with no real extending item at all -- Trick Room,
  -- per explicit user decision ("we will have this exist too, but it will
  -- have no item in the future that triggers it, it's just future proof
  -- in case it becomes wanted"): always resolves to baseTurns until a real
  -- id is ever supplied here, no rewrite needed when one is.
  function mod.exports.resolveFieldDuration(setter, baseTurns, extendedTurns, extendingItem)
    if holdsExtender(setter, extendingItem) then return extendedTurns end
    return baseTurns
  end

  mod.log:info("g9-battle-engine-beta: field_duration installed (resolveFieldDuration, FIELD_BASE_TURNS=5, FIELD_EXTENDED_TURNS=8)")
end
