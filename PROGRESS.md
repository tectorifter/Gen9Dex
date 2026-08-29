⬜ Ability-changing/suppressing moves (Skill Swap, Worry Seed,
  Entrainment, Gastro Acid) — no mechanism exists at all; standing,

  Last before tackling held item effects

## In-battle two-choice prompt (mod-facing primitive)
âœ… **Done, Gen 2.** `mod.exports.askBattleChoice` / `battleChoiceActive` /
`cancelBattleChoice` (`combat/battle_prompt.lua`): any mod supplies a
question, two labels and a callback, and gets the answer back. A
primitive, not a policy â€” nothing in it knows what a boss, a capture or
an HP threshold is, so the boss-at-1-HP "CATCH it"/"LEAVE it" case is a
caller, not a hardcoded rule. Works around a real base-engine
limitation, confirmed by source read: `src/ui/gen2/BattleState.lua:3822`
draws the yes/no box only for five hardcoded phase names, and an
unrecognised phase falls off the end of native `:update` every frame â€” a
softlock, not merely an undrawn box. Installed as Phase 17, outermost of
every `:update` wrap, so its own phase name never reaches another wrap.
ðŸ”¶ **Gen 1 is a follow-up**: `src/battle/BattleState.lua` has no yes/no
infrastructure at all, so there is no box to reuse there and the whole
widget would have to be drawn from scratch against a different chrome
stack â€” `askBattleChoice` returns `false` with a reason on a Gen 1 boot
rather than half-working.
