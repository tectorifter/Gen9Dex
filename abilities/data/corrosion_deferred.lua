-- Inclusion list -- Phase 14 (ability audit close-out). Deferred.
--   CORROSION -- the holder's Poison-type moves can poison Steel and
--                Poison types. Real mechanic (national_dex's own
--                record + Showdown).
--
-- WHY DEFERRED: poison is applied by moves through the base engine's
-- native type-match logic (a Poison move simply can't hit a Steel/
-- Poison target), which runs BEFORE any status primitive -- and none
-- of the status application APIs (StatusRegistry.inflict /
-- Battle:applyStatus, which only take a target + a status + a
-- move-id-string source) ever see the attacker, so they cannot
-- special-case a Corrosion attacker. Overriding the native immunity
-- would require editing the native move type-match check itself,
-- which is out of scope for the abilities layer (and would ripple
-- into damage typing). Flagged here so it is a known, named gap
-- rather than an accidental omission.
return {
  CORROSION = { deferred = "poison immunity bypassed at native type-match level; attacker never reaches status APIs" },
}
