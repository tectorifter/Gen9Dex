# national_dex API reference — schema/convention cheat sheet

Compiled 2026-08-27 from direct source reads across Phases 2-8 of the
ability roadmap, so future phases don't re-derive the same field names
and engine conventions from scratch every time.

**What this file is NOT**: a snapshot of per-ability data. Ability
`behaviour.effects` content (factors, conditions, `when` text) has
genuinely changed under us mid-session more than once already (flags
landed twice, unannounced) — always re-dump the specific abilities a new
phase touches directly from the live files below, never trust a cached
number here. This file only covers the STABLE stuff: field names, string
conventions, taxonomy, and where to find things — the schema shape, not
the data in it.

## Where the real data lives

- `mods/national_dex/data/moves/generated/api/<NNN>.lua` — the full
  PokeAPI-shaped move record. Reachable ONLY via `nationalDex.exports
  .moveById(id)`, never the raw registry files directly.
- `mods/national_dex/data/moves/generated/registry_gen1.lua` /
  `registry_gen2.lua` — a DIFFERENT, narrower record shape, the one this
  engine's own native `self:moveDef(moveId)` reads internally (accuracy/
  category/effect/effectModeled/power/pp/priority/type only). Note
  `category` here means physical/special/status — see the field-name trap
  below.
- `mods/national_dex/data/moves/generated/flags.lua` — real Showdown
  move flags. Reachable ONLY via `nationalDex.exports.moveFlags(id)`, a
  SEPARATE export from `moveById`, never nested under `.flags`.
- `mods/national_dex/data/abilities/generated/api/<NNN>.lua` — the full
  ability record, reachable via `nationalDex.exports.abilityById(id)` /
  `abilityBehaviorOf(mon)` (this mod's own export, reads the mon's
  current `.ability` field and looks it up).

## Move record fields (via `moveById`)

Confirmed real field names, spot-checked against RECOVER/AERIALACE/
STEALTHROCK/SPIKES/TOXICSPIKES/REFLECT/TAILWIND/SPORE/HORN_DRILL/
FISSURE/GUILLOTINE/SHEERCOLD:

- `damageClass` = `"physical"` / `"special"` / `"status"` — **NOT**
  `category`. `category` is a DIFFERENT PokeAPI field with unrelated
  values (`"heal"`, `"ailment"`, `"net-good-stats"`, etc.) that happens
  to also be truthy on some records — a real bug this session (Prankster
  build) came from reaching for `category` first because it read more
  obviously right.
- `target` — real PokeAPI values seen: `"selected-pokemon"` (the
  overwhelming majority), `"all-other-pokemon"` (Earthquake, Surf),
  `"all-opponents"` (Muddy Water), `"opponents-field"` (Stealth Rock,
  Spikes, Toxic Spikes), `"users-field"` (Reflect, Tailwind), `"user"`
  (Recover).
- `type` — UPPERCASE (`"GRASS"`, `"FLYING"`, `"DARK"`), matches this
  engine's own `curTypesOf`/STAB convention directly, no translation
  needed.
- `healing` — a number (e.g. Recover's `healing = 50`), 0 when the move
  doesn't heal. `drain` — recoil is expressed as a NEGATIVE `drain`
  value (Brave Bird: `drain = -33`), not a separate `recoil` field.
- `flinchChance`, `ailment`/`ailmentChance`, `critRate`, `minHits`/
  `maxHits`, `minTurns`/`maxTurns`, `statChance`/`statChanges` — the
  rest of the "meta" block, all live off `moveById`, none duplicated
  anywhere in this mod's own data.
- `effect` — this mod's OWN move-record field (not PokeAPI's), the
  native effect id (`"OHKO_EFFECT"`, `"DRAIN_HP_EFFECT"`, a mod-custom
  `"GALAR_..."` id, etc.) — the same field `def.effect` carries via
  `self:moveDef`. Useful for identifying a move FAMILY generically
  (e.g. all 4 real OHKO moves share `effect == "OHKO_EFFECT"`) instead
  of hardcoding an id list.

Real confirmed `moveFlags(id)` keys: `contact`, `punch`, `bite`,
`pulse`, `slicing`, `distance`, `wind`, `bullet`, `sound`. (Others may
exist unconfirmed — check `flags.lua` directly before assuming one
isn't there.)

## Ability record fields (via `abilityBehaviorOf`)

`record.behaviour = { chance, effects = {...}, expressible, notes,
scope, trigger }`. Per effect entry: `kind` plus kind-specific fields
(`factor`, `amount`, `stages`, `stat`, `moveType`, `status`, `fraction`,
`when`, `what`, `always`, ...).

- `expressible` (boolean) — whether the ability's FULL behavior is
  captured by its own `effects` array. `false` does not mean
  unbuildable — it means at least one real condition/nuance lives only
  in the free-text `notes`/`effect` fields, not in structured data.
  Several real, correct builds this session came from an
  `expressible=false` record whose `notes` field spelled out the exact
  missing condition (Prankster's `damageClass=="status"`, Orichalcum
  Pulse's/Toxic Boost's missing `when`, Merciless's poison-target
  condition, Plus's real ally-requirement contradicting a naive read of
  the bare effects array).
- `chance` — the ability's own real per-activation percentage (NOT
  always 100 — Shed Skin is 33, Healer is 30, both confirmed). Always
  read live, never assume 100.
- `scope` — `"self"` / `"allies"` / `"foes"` / `"field"` / `"all"`.
  **Not fully reliable for "does this include the holder itself"** —
  Sweet Veil/Aroma Veil/Flower Gift family are `scope="allies"` in the
  data but real game behavior also protects/boosts the HOLDER, not just
  allies (confirmed via each one's own prose `effect` text, not the
  `scope` label). Cross-check prose text before trusting `scope` alone
  on an ally-shaped ability.
- `kind` taxonomy and real counts as of this audit (313 total
  abilities, 143 expressible / 170 not — re-run the audit script below
  if this feels stale):

  | kind | raw count | expressible-only |
  |---|---|---|
  | other | 122 | 10 |
  | prevent | 43 | 26 |
  | damage_dealt_multiplier | 41 | 30 |
  | stat_change | 39 | 19 |
  | stat_multiplier | 31 | 21 |
  | status_immunity | 22 | 10 |
  | damage_taken_multiplier | 16 | 9 |
  | inflict_status | 16 | 6 |
  | change_type | 11 | 2 |
  | type_immunity | 9 | 5 |
  | heal | 9 | 8 |
  | set_weather | 8 | 6 |
  | set_terrain | 6 | 5 |
  | accuracy_multiplier | 3 | 1 |
  | damage_self | 3 | 3 |
  | priority_change | 3 | 2 |
  | crit_change | 2 | 1 |

  Ability-roadmap phase mapping: Phase 0/1/1.5/1.8 = partial stat_change/
  set_weather/set_terrain/change_type (the pre-numbered early phases).
  Phase 2 = damage_dealt/taken_multiplier. Phase 3 = status_immunity +
  type_immunity. Phase 4 = stat_multiplier. Phase 5 = priority_change
  (fully done). Phase 6 = heal + crit_change + accuracy_multiplier.
  Phase 8 = other (122, largest bucket, multi-pass). **inflict_status
  (16) and Phase 7 (prevent, 43) have NOT been started at all** as of
  this file's own last update — see PROGRESS.md for the live status.

## Engine-side conventions (not national_dex's own, but load-bearing)

- **Status strings differ by generation, neither matches national_dex's
  own spelling.** Gen 1 (`src/battle/Status.lua`, `StatusRegistry
  .inflict`'s own `status` param): `"SLP"`/`"FRZ"`/`"BRN"`/`"PAR"`/
  `"PSN"`/`"TOX"` (uppercase 2-3 letter codes). Gen 2 (`gen2/Battle.lua`'s
  `Battle:applyStatus`): `"sleep"`/`"freeze"`/`"burn"`/`"paralyze"`/
  `"poison"`/`"toxic"` (lowercase words — note `"paralyze"`, not
  `"paralysis"`). national_dex's own canonical spelling (used by
  `ailment` and `status_immunity`'s own `status` field) is
  `"paralysis"`/`"freeze"`/`"burn"`/`"sleep"`/`"poison"`/`"confusion"`/
  `"flinch"`/`"any"`. `abilities/engine/status_immunity.lua`'s own
  `canonicalStatusOf`/`STATUS_ALIASES` is the one normalizer — reuse it,
  don't rebuild a second one.
- **`Battle:battleStat(mon, key)`'s own key convention is camelCase**
  (`"attack"`, `"defense"`, `"specialAttack"`, `"specialDefense"`,
  `"speed"`) — different from `changeStage`'s own shorthand
  (`"spa"`/`"spd"`) and from national_dex's own hyphenated stat names
  (`"special-attack"`). Evasion/accuracy have NO base stat at all —
  stage-only, never routed through `battleStat` (confirmed:
  `vanillaAccuracyRoll` reads `self.stages[side].evasion` directly).
- **Weather values, this engine's own normalized set** (via
  `mod.exports.currentWeather(battle, gen2)`): `"RAIN"` / `"SUN"` /
  `"SAND"` / `"SNOW"` / `"STRONGWINDS"` / nil. `"SNOW"` is Gen 9's
  Snowscape, standing in for classic Hail — this engine has NO hail/snow
  chip damage mechanic at all (deliberate scope decision, not a gap).
- **A "battler" and a "flat mon" are two different shapes depending on
  call site**, and this mod's own convention for handling both
  defensively is `local m = mon.mon or mon`. `abilityIdOf`/
  `abilityBehaviorOf`/`requestAdjacency` all expect the BATTLER (e.g.
  `battle.player`/`battle.enemy` directly); HP/stats reads
  (`mon.hp`/`mon.stats.hp`) need the unwrap.

## Re-running the audit yourself

The kind-taxonomy table above came from a small standalone Lua script
iterating `mods/national_dex/data/abilities/generated/api/001.lua`
through `011.lua` (`loadfile` each shard, tally `behaviour.effects[].kind`
occurrences, split by `behaviour.expressible`). Not checked into this
repo — quick enough to re-write ad hoc (a dozen lines) whenever a phase
needs a fresh count; safer than trusting a committed script to still
match a shard layout that itself isn't guaranteed stable.
