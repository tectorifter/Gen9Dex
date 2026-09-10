#!/usr/bin/env python3
"""
Rebuilds assets/overworld/ from the clean, one-file-per-form source in
assets/input_overworld/, naming every output strictly by real national_dex
species-id strings (mod:find("national_dex")'s own id space -- confirmed
via its own generated species table, which keys every base species and
every nested alternate form by an `id = "..."` string, never by a numeric
index). Compatibility target is national_dex only; any other mod's own
asset-naming convention is out of scope here on purpose.

Source of the mapping rules: assets/overworld_source_assets.txt, a
1403-line manual annotation pass (one line per source file) that marks
each file as either a plain identity mapping, an explicit real-id target
(one or several, "/"-separated), or a skip (typo/duplicate, cosmetic-only
variant, or a form whose distinct art isn't needed because the species'
own overworld appearance never changes for it).

Rule set (mechanical, in priority order per source file):
  1. Explicit IGNORE / DONT USE / BAD ASSET / bare "?" marker -> skipped.
  2. A "(...)"-style single-form-family marker on the bare file (e.g.
     "(USE ONLY THIS)") marks that species' whole numbered family as
     cosmetic-only -- every sibling _N file is skipped by extension.
  3. A bare "_female" file with no further annotation -> skipped; female
     art is never a distinct national_dex id here, the base form's own
     file already covers it.
  4. Explicit target text (after "=" or standalone) -> used verbatim as
     the real id, split on "/" for the rare one-source/many-ids case. A
     fragment starting with "_" has the species' own stem prepended
     first (so a bare "_GALAR" annotation becomes "DARUMAKA_GALAR").
  5. A numbered file (_N) with NO annotation at all, whose family isn't
     rule 2's single-form case, is checked against national_dex's own
     real forms for that species (excluding Mega/Gigantamax, which never
     get a distinct overworld appearance). Exactly one real candidate for
     exactly one such file -> auto-resolved. Zero candidates -> correctly
     no output, the base file covers it. Anything else (more files than
     candidates, or more than one candidate) is reported as ambiguous,
     never guessed at. An earlier version of this rule assumed "no
     annotation" always meant Mega/Gmax-only and silently dropped ~50
     real forms (Zorua/Zoroark Hisui, Zygarde's extra formes, a dozen-plus
     Alolan/Galarian/Hisuian regional forms...) -- that assumption is
     gone; every case here is checked against live national_dex data.
  6. A `_female` file (by filename or by "female" in its annotation) is
     checked the same way, restricted to a real `_FEMALE`-suffixed id --
     most species have none (cosmetic-only, base file covers it), but a
     few (Meowstic, Oinkologne, Basculegion, Indeedee) really do register
     a separate id, caught by this check rather than assumed away.
  7. Anything left with a suffix that isn't a form number and isn't
     "_female" (pose/animation-state art, stray non-id stems) is left
     unresolved rather than guessed into a fake id.

A handful of individual files needed a correction the general rules
above can't derive on their own -- typo'd/duplicate stray filenames,
two species (Gastrodon/Shellos) whose sea-form split isn't actually a
separate registered id, and a few real ids inferred from the source
image's own content rather than stated outright in the txt. Those live
in FORCE_IGNORE / FORCE_TARGETS below, each with the reasoning inline.

Every resolved target is checked against the live set of real ids
pulled straight from national_dex's own generated species table, not a
remembered snapshot of it -- an id that doesn't match is reported, not
silently written.
"""

import csv
import json
import re
import shutil
from collections import defaultdict
from pathlib import Path

# Every path below is relative to this file's own location (or to the
# fixed mods/<name>/assets/ position within any gen1recomp install), so
# the whole assets/ folder -- script, txt, and input images together --
# can be handed to another modder and just work from wherever they place
# the mod, as long as it still sits under a real install's mods/ folder
# alongside national_dex and the engine's own tools/ directory.
ASSETS_DIR = Path(__file__).resolve().parent
MOD_DIR = ASSETS_DIR.parent
MODS_DIR = MOD_DIR.parent          # .../mods/
ENGINE_ROOT = MODS_DIR.parent      # the gen1recomp install root, whatever it's named

INPUT_DIR = ASSETS_DIR / "input_overworld"
OUTPUT_DIR = ASSETS_DIR / "overworld"
MAPPING_TXT = ASSETS_DIR / "overworld_source_assets.txt"
NATIONAL_DEX_LUA = MODS_DIR / "national_dex" / "data" / "species" / "generated" / "national.lua"
# national_dex's own generated table only carries ids it *adds* on top of
# the engine (Gen 2+ base species, plus every alternate form across every
# generation, via `id = "..."`). The 151 Gen 1 base species already exist
# natively in the engine and are never re-registered there, so validating
# against national.lua alone always flags every Gen 1 identity mapping as
# unrecognized -- the engine's own ROM-extracted species order is the
# second half of the real id space this tool has to check against.
GEN1_MANIFEST = ENGINE_ROOT / "tools" / "rom_manifest_yellow.json"

IGNORE_MARKERS = ("IGNORE", "DONT USE", "DON'T USE", "BAD ASSET", "DUPLICATE")
FAMILY_MARKERS = (
    "USE ONLY THIS", "ONLY USE THIS", "USE THIS ONLY",
    "USE FOR ALL", "USE ONLY", "NEVER SOLO",
)

# Stray/duplicate/mistyped source files with no real species behind them,
# confirmed by cross-checking each against the correctly-spelled sibling
# file that already covers the same species.
FORCE_IGNORE = {
    "CYCLIZARD.png",     # typo duplicate of CYCLIZAR.png
    "BRMABLIN.png",      # typo duplicate of BRAMBLIN.png
    "POLTHCAGEIST.png",  # stray duplicate of POLTCHAGEIST.png/POLTEAGEIST.png
    "TOESCRUEL.png",     # typo duplicate of TOEDSCRUEL.png
    "ORTHWORMs.png",     # stray capitalization duplicate of ORTHWORM.png
    "TERPAGOS_1.png",    # mistyped duplicate of TERAPAGOS_1.png
    "FALINKS_solo.png",  # user: "Only use falinks, never solo."
    "COMBEE_1.png",      # female Combee art; no separate registered id
    "GASTRODON_1.png",   # confirmed this session: no separate sea-form id exists
    "SHELLOS_1.png",     # same as above
    "CINDERACE.png",     # marked bad asset in the txt; CINDERACE_1.png is the real one
    "BURMY_1.png",       # confirmed: unlike Wormadam, Burmy's cloaks aren't separately registered
    "BURMY_2.png",
    # confirmed wrong/stray source files -- no matching species under any
    # spelling, and confirmed by the user not to be processed.
    "CEFIREON.png",
    "LEDIASTRA.png",
    "POMPET.png",
    "POMPRIM.png",
    "ROYALEON.png",
    # confirmed: partner Eevee's overworld sprite is the same for both
    # genders, so the female-specific art has no distinct id to target.
    "EEVEE_1_female.png",
    "ROOKIDEE_fly.png",  # pose/animation art, not a species form
}

# Explicit id(s) the general rules can't derive from the txt's own text
# alone -- each inferred from context established earlier this session,
# not guessed cold. Anything wrong here shows up in the validation report
# rather than silently shipping.
FORCE_TARGETS = {
    "NIDORANfE.png": ["NIDORAN_F"],
    "NIDORANmA.png": ["NIDORAN_M"],
    "BURMY.png": ["BURMY"],
    "EISCUE_1.png": ["EISCUE_NOICE"],       # confirmed real id (not "_NOICE_FACE")
    "EEVEE_1.png": ["EEVEE_STARTER"],       # confirmed real
    "COMBEE.png": ["COMBEE"],
    "CINDERACE_1.png": ["CINDERACE"],
    # these four base-form labels ("...INCARNATE") describe what the bare
    # sprite depicts, not a separate registered id -- Incarnate Forme is
    # the plain, unsuffixed id; only Therian gets its own suffix.
    "ENAMORUS.png": ["ENAMORUS"],
    "LANDORUS.png": ["LANDORUS"],
    "THUNDURUS.png": ["THUNDURUS"],
    "TORNADUS.png": ["TORNADUS"],
    # confirmed: base GIMMIGHOUL id is unsuffixed "GIMMIGHOUL" (Chest Form
    # is the default), only Roaming Form gets its own "_ROAMING" id.
    "GIMMIGHOUL.png": ["GIMMIGHOUL"],
    # confirmed no separate sea-form id exists for either species.
    "GASTRODON.png": ["GASTRODON"],
    "SHELLOS.png": ["SHELLOS"],
    "ARCANINE_1.png": ["ARCANINE_HISUI"],  # confirmed; not "_ALOLA"
    # user-confirmed file<->id matches for the cases the live species
    # check couldn't resolve alone (more real forms than source files).
    "GRENINJA_2.png": ["GRENINJA_ASH", "GRENINJA_BATTLE_BOND"],
    "MAROWAK_1.png": ["MAROWAK_ALOLA", "MAROWAK_TOTEM"],
    "RATICATE_1.png": ["RATICATE_ALOLA", "RATICATE_TOTEM_ALOLA"],
    "ZYGARDE.png": ["ZYGARDE", "ZYGARDE_10_POWER_CONSTRUCT", "ZYGARDE_50_POWER_CONSTRUCT", "ZYGARDE_COMPLETE"],
    "ZYGARDE_1.png": ["ZYGARDE_10"],
    "MINIOR.png": [
        "MINIOR", "MINIOR_ORANGE_METEOR", "MINIOR_YELLOW_METEOR", "MINIOR_GREEN_METEOR",
        "MINIOR_BLUE_METEOR", "MINIOR_INDIGO_METEOR", "MINIOR_VIOLET_METEOR",
    ],
    "MINIOR_7.png": ["MINIOR_RED"],
    "MINIOR_8.png": ["MINIOR_ORANGE"],
    "MINIOR_9.png": ["MINIOR_YELLOW"],
    "MINIOR_10.png": ["MINIOR_GREEN"],
    "MINIOR_11.png": ["MINIOR_BLUE"],
    "MINIOR_12.png": ["MINIOR_INDIGO"],
    "MINIOR_13.png": ["MINIOR_VIOLET"],
}

# Needs a human answer before this tool can place it -- no confident real
# id, and skipping silently would be a guess in the other direction.
UNRESOLVED = {}

FORM_SUFFIX_RE = re.compile(r"^(?P<stem>[A-Za-z0-9]+)_(?P<num>\d+)(?P<female>_female)?$")
FEMALE_SUFFIX_RE = re.compile(r"^(?P<stem>[A-Za-z0-9]+)_female$", re.IGNORECASE)
PLAIN_ID_RE = re.compile(r"^[A-Za-z0-9]+$")


def species_stem_of(stem):
    m = FORM_SUFFIX_RE.match(stem)
    return m.group("stem").upper() if m else stem.split("_")[0].upper()


def load_real_ids():
    text = NATIONAL_DEX_LUA.read_text(encoding="utf-8")
    ids = set(re.findall(r'id\s*=\s*"([A-Z0-9_]+)"', text))
    manifest = json.loads(GEN1_MANIFEST.read_text(encoding="utf-8"))
    ids.update(manifest["dexOrder"])
    ids.add("000")  # the engine's own unknown/undiscovered placeholder icon
    return ids


def load_forms_by_species():
    # species stem -> every real id registered against it via
    # `baseSpecies = "..."`, pulled live so a numbered file with no
    # annotation is checked against what national_dex actually has
    # instead of assumed to be Mega/Gmax-only.
    #
    # Bounded to each id's own block (up to the NEXT `id = "..."`
    # occurrence) on purpose: an unbounded ".*?" here occasionally
    # skipped straight past a block with no baseSpecies field nearby and
    # paired an id with an unrelated baseSpecies several entries away
    # (confirmed once, DEOXYS_ATTACK's own id got paired with a stray
    # baseSpecies="DEOXYS" from much later in the file) -- bounding the
    # search to one block closes that off entirely rather than trusting
    # it doesn't happen elsewhere too.
    text = NATIONAL_DEX_LUA.read_text(encoding="utf-8")
    id_matches = list(re.finditer(r'id\s*=\s*"([A-Z0-9_]+)"', text))
    by_species = {}
    for i, m in enumerate(id_matches):
        start = m.end()
        end = id_matches[i + 1].start() if i + 1 < len(id_matches) else len(text)
        bm = re.search(r'baseSpecies\s*=\s*"([A-Z0-9_]+)"', text[start:end])
        if bm:
            by_species.setdefault(bm.group(1), []).append(m.group(1))
    return by_species


def non_mechanic_forms(species, by_species):
    # Mega Evolution and Gigantamax never get a distinct overworld
    # appearance (confirmed this session: the base file always stands in
    # for them) -- every other registered form is a genuine candidate.
    # A source filename never carries underscores mid-species-name (no
    # "MR_MIME_1.png"), so a species whose real baseSpecies key itself has
    # one (MR_MIME, TAPU_KOKO, HO_OH...) needs the same underscore-
    # normalized fallback used for target ids, or its real forms are
    # silently invisible to this lookup.
    forms = by_species.get(species)
    if forms is None:
        stripped = species.replace("_", "")
        matches = [k for k in by_species if k.replace("_", "") == stripped]
        forms = by_species[matches[0]] if len(matches) == 1 else []
    return [f for f in forms if "_MEGA" not in f and "_GMAX" not in f]


def normalize_lookup(real_ids):
    # Several real ids are two English words joined with "_" (IRON_HANDS,
    # CHIEN_PAO, TAPU_KOKO...) where the source filename has no separator
    # at all -- safe to resolve automatically only when exactly one real
    # id shares the same letters once underscores are stripped from both
    # sides, so a genuine ambiguity still falls through to the report.
    by_stripped = {}
    for rid in real_ids:
        by_stripped.setdefault(rid.replace("_", ""), []).append(rid)
    return {k: v[0] for k, v in by_stripped.items() if len(v) == 1}


# Missing-space typo in the source txt itself -- fixed here rather than
# in the txt so the txt stays exactly what the user annotated by hand.
LINE_TYPO_FIXES = {
    "PIKACHU_12.pngPIKACHU_HOENN_CAP": "PIKACHU_12.png PIKACHU_HOENN_CAP",
}


def parse_mapping_txt():
    raw = MAPPING_TXT.read_text(encoding="utf-8")
    for bad, good in LINE_TYPO_FIXES.items():
        raw = raw.replace(bad, good)
    lines = [l.rstrip("\n") for l in raw.splitlines()]
    entries = []
    family_bases = set()

    # First pass: find every species stem whose bare file carries a
    # single-form-family marker, so numbered siblings can be skipped by
    # rule 2 regardless of line order in the file.
    for line in lines:
        line = line.strip()
        if not line or ".png" not in line:
            continue
        parts = line.split(None, 1)
        fname = parts[0]
        rest = parts[1] if len(parts) > 1 else ""
        if fname.endswith(".png") and "_" not in fname[:-4] and any(m in rest.upper() for m in FAMILY_MARKERS):
            family_bases.add(fname[:-4].upper())

    for line in lines:
        line = line.strip()
        if not line or ".png" not in line:
            continue
        parts = line.split(None, 1)
        fname = parts[0]
        rest = parts[1] if len(parts) > 1 else ""
        entries.append((fname, rest, family_bases))

    return entries, family_bases


def resolve(fname, rest, family_bases):
    if fname in UNRESOLVED:
        return "unresolved", None, UNRESOLVED[fname]
    if fname in FORCE_IGNORE:
        return "ignore", None, "forced (typo/duplicate/no-real-id)"
    if fname in FORCE_TARGETS:
        return "targets", FORCE_TARGETS[fname], "forced (inferred, not stated verbatim)"

    stem = fname[:-4]  # strip .png
    rest_upper = rest.upper()

    if rest.strip() == "?" or any(m in rest_upper for m in IGNORE_MARKERS):
        return "ignore", None, "explicit ignore marker"

    if any(m in rest_upper for m in FAMILY_MARKERS):
        # bare file that IS the family's canonical asset
        base = stem.upper()
        return "targets", [base], "family base marker"

    fm = FEMALE_SUFFIX_RE.match(stem)
    female_marked = (fm and not rest.strip()) or ("FEMALE" in rest_upper and "=" not in rest)
    if female_marked:
        species = fm.group("stem").upper() if fm else species_stem_of(stem)
        return "species_check", (species, "female"), "female-marked, checking for a real _FEMALE id"

    if rest.strip():
        text = rest.strip()
        if text.startswith("="):
            text = text[1:].strip()
        targets = [t.strip().strip("()").upper() for t in text.split("/") if t.strip()]
        resolved = []
        for t in targets:
            if t.startswith("_"):
                base_stem = FORM_SUFFIX_RE.match(stem)
                species = base_stem.group("stem").upper() if base_stem else stem.upper()
                resolved.append(species + t)
            else:
                resolved.append(t)
        if resolved:
            return "targets", resolved, "explicit annotation"

    numm = FORM_SUFFIX_RE.match(stem)
    if numm:
        species = numm.group("stem").upper()
        if species in family_bases:
            return "ignore", None, "single-form family, no distinct id"
        return "species_check", (species, "numbered"), "unnamed numbered variant, checking for a real non-mega/gmax id"

    if PLAIN_ID_RE.match(stem):
        return "targets", [stem.upper()], "identity"

    return "unresolved", None, "non-standard filename, no safe default"


def resolve_species_checks(raw_results, by_species):
    # Group every "species_check" result by (species, kind) so a numbered
    # or female-marked file is judged against ALL of that species' real
    # candidates at once, not file-by-file -- a 1-file/1-candidate match
    # is unambiguous and safe to auto-resolve; anything else (0 files but
    # candidates exist, or more than one of either) needs a human to say
    # which file is which, not a guessed order.
    groups = {}
    for fname, rest, kind, payload, reason in raw_results:
        if kind != "species_check":
            continue
        groups.setdefault(payload, []).append(fname)

    resolution = {}  # fname -> ("targets", [ids], reason) | ("ignore", None, reason) | ("ambiguous", candidates, reason)
    for (species, check_kind), fnames in groups.items():
        candidates = non_mechanic_forms(species, by_species)
        if check_kind == "female":
            candidates = [c for c in candidates if c.endswith("_FEMALE")]

        if not candidates:
            for f in fnames:
                resolution[f] = ("ignore", None, "no real distinct id for this species (mega/gmax-only or none)")
        elif len(candidates) == 1 and len(fnames) == 1:
            resolution[fnames[0]] = ("targets", candidates, "matched to the species' one real non-mega/gmax id")
        else:
            for f in fnames:
                resolution[f] = ("ambiguous", candidates, f"{len(fnames)} source file(s) vs {len(candidates)} real candidate(s) -- needs a human match")
    return resolution


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    real_ids = load_real_ids()
    normalized = normalize_lookup(real_ids)
    by_species = load_forms_by_species()
    entries, family_bases = parse_mapping_txt()

    raw_results = []
    for fname, rest, _ in entries:
        kind, payload, reason = resolve(fname, rest, family_bases)
        raw_results.append((fname, rest, kind, payload, reason))

    species_resolution = resolve_species_checks(raw_results, by_species)

    copied, ignored, unresolved, ambiguous, invalid_target, missing_source = [], [], [], [], [], []
    referenced = set()

    for fname, rest, kind, payload, reason in raw_results:
        referenced.add(fname)

        if kind == "species_check":
            kind, targets, reason = species_resolution[fname]
        else:
            targets = payload

        if kind == "ignore":
            ignored.append((fname, reason))
            continue
        if kind == "unresolved":
            unresolved.append((fname, reason))
            continue
        if kind == "ambiguous":
            ambiguous.append((fname, targets, reason))
            continue

        src = INPUT_DIR / fname
        if not src.is_file():
            missing_source.append(fname)
            continue

        for target in targets:
            if target not in real_ids:
                fixed = normalized.get(target.replace("_", ""))
                if fixed:
                    target = fixed
                else:
                    invalid_target.append((fname, target, reason))
                    continue
            dst = OUTPUT_DIR / f"{target}.png"
            shutil.copy2(src, dst)
            copied.append((fname, target, reason))

    orphan_inputs = sorted(
        p.name for p in INPUT_DIR.glob("*.png") if p.name not in referenced
    )

    report = []
    report.append(f"copied:          {len(copied)}")
    report.append(f"ignored:         {len(ignored)}")
    report.append(f"unresolved:      {len(unresolved)}")
    report.append(f"ambiguous:       {len(ambiguous)}  (real forms exist but file<->id match isn't 1:1)")
    report.append(f"invalid target:  {len(invalid_target)}  (resolved id not found in national_dex)")
    report.append(f"missing source:  {len(missing_source)}  (listed in txt, not present in input_overworld/)")
    report.append(f"orphan inputs:   {len(orphan_inputs)}  (present in input_overworld/, not in txt at all)")
    report.append("")

    if ambiguous:
        report.append("=== AMBIGUOUS (real forms exist, need a human to match file -> id) ===")
        for fname, candidates, reason in ambiguous:
            report.append(f"  {fname}: {reason}")
            report.append(f"      candidates: {', '.join(candidates)}")
        report.append("")

    if unresolved:
        report.append("=== UNRESOLVED (need a human answer) ===")
        for fname, reason in unresolved:
            report.append(f"  {fname}: {reason}")
        report.append("")

    if invalid_target:
        report.append("=== INVALID TARGET (not a real national_dex id) ===")
        for fname, target, reason in invalid_target:
            report.append(f"  {fname} -> {target}  ({reason})")
        report.append("")

    if missing_source:
        report.append("=== MISSING SOURCE FILE ===")
        for fname in missing_source:
            report.append(f"  {fname}")
        report.append("")

    if orphan_inputs:
        report.append("=== ORPHAN INPUT FILES (not referenced in overworld_source_assets.txt) ===")
        for fname in orphan_inputs:
            report.append(f"  {fname}")
        report.append("")

    by_source = defaultdict(list)
    for fname, target, _reason in copied:
        by_source[fname].append(target)
    csv_path = ASSETS_DIR / "shared_overworld_sprites.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["source_file", "national_dex_id", "ids_sharing_this_source"])
        for fname in sorted(by_source):
            targets = sorted(by_source[fname])
            if len(targets) < 2:
                continue
            for target in targets:
                writer.writerow([fname, target, "; ".join(targets)])
    shared_groups = sum(1 for v in by_source.values() if len(v) >= 2)
    print(f"shared-sprite groups: {shared_groups}  -> {csv_path}")

    report_path = ASSETS_DIR / "overworldExtraction_report.txt"
    report_path.write_text("\n".join(report), encoding="utf-8")
    print("\n".join(report))
    print(f"\nfull report written to {report_path}")


if __name__ == "__main__":
    main()
