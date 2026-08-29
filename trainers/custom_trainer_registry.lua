-- Custom trainer roster registration API (2026-08-28, explicit user
-- directive): a public mod.exports.registerTrainer(trainerId, party,
-- options) any other mod (or this one) can call to fully replace a real
-- trainer's roster -- species/level/moves/held item, PLUS modern per-mon
-- data this ROM never had a concept of at all (ability, nature, IVs,
-- EVs, Tera Type, Dynamax Level, Gigantamax Factor), PLUS the battle's
-- own combat TYPE (vanilla/doubles/triples).
--
-- Gen 2 (Gold/Silver/Crystal) ONLY, matching this mod's own established
-- scope everywhere else (Battle2/gen2/Battle.lua throughout) -- Gen 1's
-- own separate trainer pipeline (src/battle/BattleState.lua's newTrainer)
-- is a different real function this file does not touch; Tera/Dynamax/
-- Gigantamax are Gen2-exclusive concepts in this project regardless.
--
-- TRAINER IDENTITY: "CLASS:MEMBERID" (e.g. "BEAUTY:VICTORIA"), matching
-- this ROM's own real trainer identity directly -- confirmed by reading
-- the actual engine source: src/world/gen2/Trainers.lua's own
-- Trainers.lookup(trainerData, class, member) returns { class=, classId=,
-- member=, id=, name=, roster=, ... }, and src/world/gen2/World.lua's own
-- startScriptedBattle (the ONE real place every scripted trainer battle
-- in the game gets built, confirmed by that function's own comment) then
-- carries it forward as opts.trainer = { classId = record.classId,
-- memberId = record.id, ... } -- the exact same classId/memberId pair
-- this file keys its own registry on, and the exact pair
-- stats/gen2_modern_stats.lua's own generateGen2TrainerMon already reads
-- into its ctx.oppClass/ctx.partyIndex for the (pre-existing, already-
-- shipped) ability/nature/IV/EV provider system. CLASS is the trainer
-- CLASS id (e.g. "BEAUTY", "FALKNER", "YOUNGSTER"); MEMBERID is that one
-- named trainer's own real id within the class (e.g. "VICTORIA") --
-- confirmed real and populated on every trainer in a live ROM extraction
-- (tests fixture + a real Crystal cache both checked this session), NOT
-- a guessed convention.
--
-- THREE REAL INTEGRATION POINTS, one per concern, each reusing an
-- existing real primitive rather than inventing a fourth:
--   1. Species/level/moves/held item -- monkeypatches the real native
--      `Trainers.party(data, entry)` (src/world/gen2/Trainers.lua), the
--      ONE real function that turns a trainer's roster rows into actual
--      battle Mon objects (via the same real `Mon.new` every wild/gift/
--      trade mon in the game also goes through). A registered trainer's
--      roster REPLACES `entry.roster` entirely for that one lookup; every
--      other trainer in the game falls straight through to the real,
--      unmodified vanilla behavior.
--   2. Ability/nature/IVs/EVs -- registers on the EXISTING, already-
--      shipped `mod.exports.registerTrainerStatsProvider` chain
--      (stats/trainer_modern_stats.lua) at high priority, so an explicit
--      trainer registration always wins over any other installed
--      provider for the same mon. Reuses ModernStats.applySpec's own
--      real spec shape (stats/engine_modern_stats.lua) -- not a second,
--      parallel stat-writing path.
--   3. Tera Type / Dynamax Level / Gigantamax Factor -- a battle.started
--      listener (Gen2-gated) calling the real, already-shipped per-mon
--      setters (gigantamax/tera_state.lua's setTeraType, gigantamax/
--      dynamax_state.lua's setGigantamaxFactor) directly on each
--      constructed party mon. Dynamax Level itself is the one field this
--      project had NO per-mon storage for before this file -- see
--      gigantamax/dynamax_state.lua's own header for why (Dynamax Level
--      there is deliberately PER-SAVE, the player's own real account-wide
--      progression, a genuinely different real concept from "what level
--      should THIS specific opposing trainer's Pokemon Dynamax at" -- the
--      same distinction Bulbapedia's own Sword/Shield mechanics draw) --
--      stored here as a plain mon.dynamaxLevel field, the same bare-field
--      pattern mon.gigantamaxFactor already established successfully.
--   4. Combat type (vanilla/doubles/triples, 2026-08-28 addition) -- a
--      World:startBattle wrap routing a registered trainer's battle
--      through the SEPARATE, optional mods/g9-Battle-Scene mod's own
--      named layout preset system (mod.exports.pushLayoutBattle) --
--      reusing the exact real integration mods/Sample-Battle-Scene-G9's
--      own tryDoublesTrainer already established (confirmed by direct
--      read), not reinvented. g9-Battle-Scene is resolved live via
--      mod.find, never a hard dependency -- "vanilla" (the default) and
--      a missing/absent g9-Battle-Scene both fall straight through to
--      the ordinary native trainer battle, unmodified.
return function(mod)
  local Trainers = require("src.world.gen2.Trainers")
  -- Re-install guard, same real pattern stats/gen2_modern_stats.lua's own
  -- Gen2Battle.__galarGen2ModernStatsWrapped already established in this
  -- codebase -- flag lives on the real, shared, require-cached Trainers
  -- table itself (confirmed real and single-instance: src/mods/Sandbox
  -- .lua's own sandboxedRequire delegates straight to the real global
  -- require, so every mod's require("src.world.gen2.Trainers") returns
  -- the SAME table, not a per-mod copy), not on a local -- a local
  -- inside this closure would be worthless as a re-run guard since a
  -- second run gets its own fresh one. Without this, a second install
  -- (a mod-reload/re-init, if this loader ever does one) would silently
  -- build a SECOND, empty `registry` closure and repoint mod.exports
  -- .registerTrainer at it -- any earlier registerTrainer call (a
  -- caller mod whose own main.lua only ran once) would then be writing
  -- into an orphaned registry nothing still reads from, while every
  -- live battle.started/Trainers.party/World:startBattle check reads
  -- the new, empty one. Exactly the "registered but never matches"
  -- shape under live investigation as this guard was added.
  if Trainers.__g9CustomTrainerRegistryInstalled then
    mod.log:warn("g9-battle-engine-beta: custom_trainer_registry: install "
      .. "attempted a second time, refused -- mod.exports.registerTrainer "
      .. "still points at the FIRST install's own registry, unchanged")
    return
  end
  Trainers.__g9CustomTrainerRegistryInstalled = true
  local Mon = require("src.battle.gen2.Mon")
  local ModernStats = mod.exports.ModernStats
  local setTeraType = mod.exports.setTeraType
  local setGigantamaxFactor = mod.exports.setGigantamaxFactor
  local setMonDynamaxLevel = mod.exports.setMonDynamaxLevel
  local registerTrainerStatsProvider = mod.exports.registerTrainerStatsProvider
  local isGen2Battle = mod.exports.isGen2Battle
  assert(ModernStats and setTeraType and setGigantamaxFactor and setMonDynamaxLevel
      and registerTrainerStatsProvider and isGen2Battle,
    "custom_trainer_registry: stats/engine_modern_stats.lua, stats/trainer_modern_stats.lua, "
      .. "gigantamax/tera_state.lua, gigantamax/dynamax_state.lua and combat/modern_combat.lua "
      .. "must all load first")

  -- [ "CLASS:MEMBERID" ] = { party = <array of up to 6 entries>, combatType = "vanilla"|"doubles"|"triples" }
  local registry = {}
  local COMBAT_TYPES = { vanilla = true, doubles = true, triples = true }

  local function keyFor(classId, memberId)
    if classId == nil or memberId == nil then return nil end
    return tostring(classId) .. ":" .. tostring(memberId)
  end

  -- Real nature-id case normalization: this project's own convention
  -- writes ability/type/item ids ALL-CAPS everywhere (WONDERGUARD,
  -- GROUND, CHOICE_SCARF, ...), but ModernStats.NATURES (stats/
  -- engine_modern_stats.lua) is the one place natures are still spelled
  -- Capitalized ("Jolly", "Adamant") -- the exact strings its own
  -- computeAll/natureMult key off. Built once so a trainer definition
  -- can write NATURE in whichever case reads naturally (matching the
  -- user's own "JOLLY" example) without silently mismatching that table.
  local NATURE_BY_UPPER = {}
  for _, n in ipairs(ModernStats.NATURES) do NATURE_BY_UPPER[n:upper()] = n end
  local function normalizeNature(nature)
    if type(nature) ~= "string" then return nil end
    return NATURE_BY_UPPER[nature:upper()]
  end

  local STAT_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

  -- Builds ModernStats.applySpec's own real spec shape from one party
  -- entry's ivs/evs/ability/nature fields. Unset IVs default to 31 (a
  -- fully-realized modern Pokemon's own common default), unset EVs to 0
  -- -- confirmed necessary: ModernStats.applySpec's own real per-stat
  -- loop reads `part.iv`/`part.ev` off whatever sub-table IS given and
  -- falls back to a bare 0 for anything missing, so a caller that only
  -- half-fills `ivs` would otherwise silently zero the rest. Real EV
  -- cap (510 total, 252 per stat) enforced here too, scaled down
  -- proportionally rather than truncating whichever stat happens to be
  -- listed last in a definition that goes over.
  local function specFromEntry(entry)
    local spec = { ability = entry.ability, nature = normalizeNature(entry.nature) }
    local ivs, evs = entry.ivs or {}, entry.evs or {}
    for _, key in ipairs(STAT_KEYS) do
      local iv = tonumber(ivs[key])
      if iv == nil then iv = 31 end
      iv = math.max(0, math.min(31, math.floor(iv)))
      local ev = math.max(0, math.min(252, math.floor(tonumber(evs[key]) or 0)))
      spec[key] = { iv = iv, ev = ev }
    end
    local total = 0
    for _, key in ipairs(STAT_KEYS) do total = total + spec[key].ev end
    if total > 510 then
      local scale = 510 / total
      for _, key in ipairs(STAT_KEYS) do
        spec[key].ev = math.floor(spec[key].ev * scale)
      end
    end
    return spec
  end

  ------------------------------------------------------------------
  -- Public API.
  --
  --   mod.find("g9-battle-engine-beta").exports.registerTrainer(
  --     "BEAUTY:VICTORIA", {
  --       { species = "GARCHOMP", level = 100,
  --         moves = { "EARTHQUAKE", "DRAGONCLAW", "ROCKSLIDE", "SWORDSDANCE" },
  --         ability = "ROUGHSKIN", nature = "JOLLY",
  --         ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
  --         evs = { hp = 0, atk = 252, def = 0, spa = 0, spd = 4, spe = 252 },
  --         teraType = "GROUND", dynamaxLvl = 10, gigantamax = false,
  --         heldItem = "CHOICE_SCARF" },
  --       -- up to 5 more entries
  --     }, { combatType = "doubles" })
  --
  -- Only species/level are required per entry; every other field is
  -- optional and defaults the same way a vanilla trainer row does
  -- (moves -> whatever the species knows at that level; ability/nature
  -- -> ModernStats' own real random generation, same as every other
  -- trainer mon in the game; ivs -> 31 each; evs -> 0 each; teraType/
  -- gigantamax/dynamaxLvl -> unset; heldItem -> none). `heldItem` must be
  -- a real registered item id (this mod's own combat/modern_held_items*
  -- .lua registrations, or a real native one) -- e.g. "CHOICE_SCARF" WITH
  -- the underscore and WITH quotes, not a bare identifier.
  --
  -- `options` is optional; `options.combatType` is one of "vanilla"
  -- (default -- the ordinary native single battle screen, g9-Battle-Scene
  -- never invoked at all), "doubles", or "triples" -- see integration
  -- point 4 below for what the latter two actually do and what happens
  -- when g9-Battle-Scene isn't installed.
  ------------------------------------------------------------------
  mod.exports.registerTrainer = function(trainerId, party, options)
    if type(trainerId) ~= "string" or trainerId == "" then
      mod.log:warn("g9-battle-engine-beta: registerTrainer: trainerId must be a non-empty string")
      return false
    end
    if type(party) ~= "table" or #party == 0 then
      mod.log:warn("g9-battle-engine-beta: registerTrainer(%s): party must be a non-empty array",
        trainerId)
      return false
    end
    for i, row in ipairs(party) do
      if i <= 6 and (type(row) ~= "table" or type(row.species) ~= "string" or not row.level) then
        mod.log:warn("g9-battle-engine-beta: registerTrainer(%s): slot %d needs at least "
          .. "species (string) and level", trainerId, i)
        return false
      end
    end
    if #party > 6 then
      mod.log:warn("g9-battle-engine-beta: registerTrainer(%s): party has %d entries, only "
        .. "the first 6 are used", trainerId, #party)
    end
    local combatType = options and options.combatType
    if combatType ~= nil and not COMBAT_TYPES[combatType] then
      mod.log:warn("g9-battle-engine-beta: registerTrainer(%s): combatType %q is not "
        .. "\"vanilla\"/\"doubles\"/\"triples\", defaulting to \"vanilla\"",
        trainerId, tostring(combatType))
      combatType = nil
    end
    registry[trainerId] = { party = party, combatType = combatType or "vanilla" }
    return true
  end

  -- Lets another mod that ALSO makes its own blanket combat-type
  -- decisions (Sample-Battle-Scene-G9's own tryDoublesTrainer, which
  -- forces doubles on ANY trainer with 2+ Pokemon regardless of this
  -- registry -- confirmed a real conflict, 2026-08-28: it installs its
  -- own World:startBattle wrap AFTER this file's own (it loads later in
  -- the dependency chain, g9-battle-engine-beta -> g9-Battle-Scene ->
  -- Sample-Battle-Scene-G9), so it runs FIRST and can return before this
  -- file's own combatType check ever gets a turn) defer to a REGISTERED
  -- trainer's own explicit choice instead of guessing from party size.
  mod.exports.hasRegisteredTrainer = function(classId, memberId)
    local key = keyFor(classId, memberId)
    return key ~= nil and registry[key] ~= nil
  end

  ------------------------------------------------------------------
  -- 1. Species/level/moves/held item -- Trainers.party monkeypatch.
  ------------------------------------------------------------------
  local nativeParty = Trainers.party
  function Trainers.party(data, entry)
    local key = entry and keyFor(entry.classId, entry.id or entry.name)
    local record = key and registry[key]
    local custom = record and record.party
    if not custom then return nativeParty(data, entry) end
    local party = {}
    for i = 1, math.min(6, #custom) do
      local row = custom[i]
      local ok, result = pcall(function()
        local moves = nil
        if row.moves and #row.moves > 0 then
          moves = {}
          for _, id in ipairs(row.moves) do
            local moveDef = data and data.moves and data.moves[id]
            moves[#moves + 1] = { id = id, pp = moveDef and moveDef.pp or 0,
              maxPp = moveDef and moveDef.pp or 0 }
          end
        end
        -- Real, confirmed trainer-mon DV rule (Trainers.lua's own
        -- comment: "Trainer mons roll no DVs: the cart gives every one
        -- of them 9/8/8/8/8") -- kept exactly as the vanilla path
        -- already does, since a registered trainer is still a REAL
        -- in-game trainer, not a wild encounter.
        return Mon.new(data, row.species, row.level, {
          moves = moves, item = row.heldItem,
          dvs = { attack = 9, defense = 8, speed = 8, special = 8 },
        })
      end)
      if ok and result then
        party[#party + 1] = result
      else
        mod.log:warn("g9-battle-engine-beta: registerTrainer(%s): slot %d (%s) failed to "
          .. "build, skipped: %s", key, i, tostring(row and row.species), tostring(result))
      end
    end
    return party
  end

  ------------------------------------------------------------------
  -- 2. Ability/nature/IVs/EVs -- registerTrainerStatsProvider entry.
  -- Priority 100: an explicit trainer registration should always win
  -- over any other installed provider for the same mon (there are none
  -- as of this file's own writing, but the contract should hold for
  -- whatever gets added later too).
  ------------------------------------------------------------------
  registerTrainerStatsProvider(function(ctx)
    local key = keyFor(ctx.oppClass, ctx.partyIndex)
    local record = key and registry[key]
    local row = record and record.party and record.party[ctx.slotIndex]
    if not row then return nil end
    return specFromEntry(row)
  end, 100)

  ------------------------------------------------------------------
  -- 3. Tera Type / Dynamax Level / Gigantamax Factor -- applied once the
  -- real party mon objects exist (battle.started, same real event/
  -- timing stats/gen2_modern_stats.lua's own listener already uses --
  -- registered independently here since none of these three fields
  -- depend on ability/nature/IV/EV generation having run first).
  ------------------------------------------------------------------
  -- TEMPORARY DIAGNOSTIC (2026-08-28, remove once the roster-mismatch
  -- report is resolved). One tight line -- the battle text box
  -- paginates/truncates anything longer. Member id is back in (a real
  -- rematch mod, Trainer_Rematches, is active in this save, and it may
  -- be routing straight to JOEY2 instead of JOEY1 even on a first meet
  -- -- this is the one way to actually see which one fired):
  --   M1 = registry matched      M0 = no match
  --   memberId (up to 6 chars), then 4-letter species codes
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if ev.kind ~= "trainer" or not (battle and isGen2Battle(battle)) then return end
    local trainer = ev.trainer
    local memberId = trainer and (trainer.memberId or trainer.id)
    local key = keyFor(trainer and (trainer.classId or trainer.class), memberId)
    local record = key and registry[key]
    local codes = {}
    for _, mon in ipairs(battle.enemyParty or {}) do
      codes[#codes + 1] = tostring(mon and mon.species or "????"):sub(1, 4)
    end
    battle:emit({ kind = "message",
      text = "M" .. (record and "1" or "0") .. " " .. tostring(memberId):sub(1, 6)
        .. " " .. table.concat(codes, ",") })
    -- Second diagnostic line: what's ACTUALLY in the registry right now,
    -- regardless of whether this specific trainer matched -- settles
    -- "registerTrainer never ran / wrote a different key" vs. "it ran,
    -- this lookup itself is wrong" directly, no more guessing.
    local allKeys = {}
    for k in pairs(registry) do allKeys[#allKeys + 1] = k end
    battle:emit({ kind = "message",
      text = "REG " .. #allKeys .. " " .. table.concat(allKeys, ","):sub(1, 60) })
  end)

  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if ev.kind ~= "trainer" or not (battle and isGen2Battle(battle)) then return end
    local trainer = ev.trainer
    local key = trainer and keyFor(trainer.classId or trainer.class, trainer.memberId or trainer.id)
    local record = key and registry[key]
    local custom = record and record.party
    if not custom then return end
    for slotIndex, mon in ipairs(battle.enemyParty or {}) do
      local row = custom[slotIndex]
      if row and type(mon) == "table" then
        if row.teraType then setTeraType(mon, row.teraType, battle) end
        if row.gigantamax ~= nil then setGigantamaxFactor(mon, row.gigantamax) end
        if row.dynamaxLvl ~= nil then setMonDynamaxLevel(mon, row.dynamaxLvl) end
      end
    end
  end)

  ------------------------------------------------------------------
  -- 4. Combat type (vanilla/doubles/triples) -- World:startBattle wrap.
  --
  -- World:startScriptedBattle (src/world/gen2/World.lua) has ALREADY run
  -- by the time World:startBattle fires -- it builds the real opts
  -- .trainer table (classId/memberId/party/...) and calls
  -- World:startBattle(opts) itself, so opts.trainer.party here already
  -- holds THIS file's own custom roster from integration point 1 above
  -- whenever this is a registered trainer, not the vanilla one.
  --
  -- REAL DIVISION OF RESPONSIBILITY (2026-08-29, explicit user
  -- correction after live testing): this file tells g1r's own native
  -- engine the roster and moves (integration point 1, Trainers.party --
  -- unchanged, that's the one real place a mon's species/level/moveset
  -- gets decided) and holds the stats to process them in battle
  -- (integration points 2/3). It does NOT decide who fights in a
  -- doubles/triples layout -- confirmed by direct read of g9-Battle-
  -- Scene's own Screen.new (mods/g9-Battle-Scene/battle_screen.lua):
  -- it builds its enemy battler list with a bare `for i, mon in
  -- ipairs(payload.enemies)` loop, N-agnostic, no independent "how many
  -- should this layout actually show" check of its own -- so g9-Battle-
  -- Scene renders EXACTLY whatever array it's handed, at whatever size
  -- that array is, and has no way to pull a roster on its own (its own
  -- design, confirmed: "this mod never builds the roster itself").
  -- Pre-slicing `trainer.party` down to the layout preset's own
  -- enemyCount here (the ORIGINAL shape of this wrap) meant THIS file
  -- was deciding who fights, not just requesting a layout -- exactly
  -- the "preloading" a registered trainer's own already-correctly-sized
  -- roster (registerTrainer's own `party`, whatever size the caller
  -- registered it at) should never need. `trainer.party` -- the SAME
  -- real array integration point 1 already built -- is forwarded here
  -- completely unmodified; g9-Battle-Scene remains fully agnostic to
  -- WHICH Pokemon these are, only ever told the layout name.
  --
  -- Player-side ally selection is a genuinely separate, native concern
  -- (which of the PLAYER's own party comes out) -- kept at the same
  -- layout-preset-driven `allyCount` slice mods/Sample-Battle-Scene-G9's
  -- own tryDoublesTrainer already established, untouched by this
  -- correction (the directive was specifically about the NPC/enemy
  -- roster).
  --
  -- g9-Battle-Scene is a genuinely separate, optional mod -- resolved
  -- live via mod.find, never a hard dependency. Falls straight through
  -- to the real native trainer battle (nativeStartBattle, unmodified)
  -- whenever: this isn't a registered trainer; combatType is "vanilla"
  -- (the default); g9-Battle-Scene isn't installed; or that mod has no
  -- "doubles"/"triples" preset file (pushLayoutBattle's own real,
  -- confirmed refusal contract -- returns nil rather than a partial
  -- push, so this can always tell success from failure and never risk
  -- silently losing a battle).
  ------------------------------------------------------------------
  local World = require("src.world.gen2.World")
  local nativeStartBattle = World.startBattle
  function World:startBattle(opts, onDone)
    local trainer = opts and opts.trainer
    local key = trainer and keyFor(trainer.classId or trainer.class, trainer.memberId or trainer.id)
    local record = key and registry[key]
    local combatType = record and record.combatType
    if record and (combatType == "doubles" or combatType == "triples")
        and type(trainer.party) == "table" and #trainer.party > 0 then
      local ok, handled = pcall(function()
        local exportMod = mod.find("g9-Battle-Scene")
        local save = self.game and self.game.save
        if not (exportMod and exportMod.exports and exportMod.exports.pushLayoutBattle
            and save and save.party) then
          return false
        end
        local layoutData = exportMod.exports.getLayoutData
          and exportMod.exports.getLayoutData(combatType)
        local defaultCount = (combatType == "triples") and 3 or 2
        local allyCount = math.max(1, math.min(6, (layoutData and layoutData.allyCount) or defaultCount))
        local players = {}
        for i = 1, allyCount do
          if save.party[i] then players[#players + 1] = save.party[i] end
        end
        return exportMod.exports.pushLayoutBattle(combatType, self.game, self, {
          enemies = trainer.party, players = players, trainer = trainer,
        }) and true or false
      end)
      if ok and handled then return true end
      if not ok then
        mod.log:warn("g9-battle-engine-beta: registerTrainer(%s): combatType=%s push errored, "
          .. "falling back to the ordinary trainer battle: %s", key, combatType, tostring(handled))
      else
        mod.log:warn("g9-battle-engine-beta: registerTrainer(%s): combatType=%s requested but "
          .. "g9-Battle-Scene is unavailable or has no matching preset, falling back to the "
          .. "ordinary trainer battle", key, combatType)
      end
    end
    return nativeStartBattle(self, opts, onDone)
  end

  mod.log:info("g9-battle-engine-beta: custom_trainer_registry installed "
    .. "(mod.exports.registerTrainer)")
end
