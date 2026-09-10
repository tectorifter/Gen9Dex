#!/usr/bin/env python3
"""
Rebuilds assets/front/ and assets/back/ from Pokemon_Back_Front's raw
sprite sheets, naming every output strictly by real national_dex
species-id strings -- same compatibility target and validation approach
as overworldExtraction.py, reused directly (see [[project_overworld_asset_extraction]]).

Two things differ from the overworld pass on purpose:

- The source is a sprite SHEET per file (multiple animation frames in one
  PNG), not one image per form. Only the first frame matters here, and
  its exact pixel box is already known -- Back_sprites_by_species/ and
  Front_sprites_by_species/'s own manifest.csv (copied in as
  back_sheet_manifest.csv / front_sheet_manifest.csv) records every
  frame's crop box per source sheet; cell_index == 1 is the one this
  tool crops, nothing guessed about frame dimensions.

- Mega Evolution and Gigantamax are real, distinct candidates here,
  unlike overworld (where they never get a distinct sprite). Battle
  sprites visibly show a Mega/Gmax transformation; overworld sprites
  don't. So the auto-resolution step below does NOT exclude them the
  way overworld's non_mechanic_forms() does.

The manifest's own "species" column is a raw candidate id from whatever
tool built Pokemon_Back_Front originally -- valid for many entries
already, wrong or ambiguous for others in the same ways overworld's
numbered files were (regional/Mega/Gmax suffix conventions that don't
match national_dex's real ids, cosmetic-only families like Alcremie/
Vivillon needing collapse to one base output, and multi-form species
where more than one real id could plausibly be the candidate). Every
correction below came from the user directly, matching a source image
against a real form -- not derived from the manifest text or guessed.
"""

import csv
import re
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import overworldExtraction as ow

ASSETS_DIR = Path(__file__).resolve().parent
INPUT_BACK = ASSETS_DIR / "input_back"
INPUT_FRONT = ASSETS_DIR / "input_front"
OUTPUT_BACK = ASSETS_DIR / "back"
OUTPUT_FRONT = ASSETS_DIR / "front"
BACK_MANIFEST = ASSETS_DIR / "back_sheet_manifest.csv"
FRONT_MANIFEST = ASSETS_DIR / "front_sheet_manifest.csv"

# Cosmetic-only families confirmed during the overworld pass -- every
# numbered sibling collapses to the one base output.
COSMETIC_FAMILIES = {
    "ALCREMIE", "VIVILLON", "UNOWN", "FLORGES", "FLABEBE", "FLOETTE",
    "FURFROU", "DEERLING", "SAWSBUCK", "GOURGEIST", "PUMPKABOO",
}

# User-confirmed file(s) -> real id(s). "IGNORE" means the file produces
# no output (redundant with the base id, or no real distinct id exists).
FORCE_TARGETS = {
    # reused directly from the overworld pass, same source images depict
    # the same real forms in the same order there.
    "DEOXYS_1": ["DEOXYS_ATTACK"], "DEOXYS_2": ["DEOXYS_DEFENSE"], "DEOXYS_3": ["DEOXYS_SPEED"],
    "GENESECT_1": ["GENESECT_SHOCK"], "GENESECT_2": ["GENESECT_BURN"],
    "GENESECT_3": ["GENESECT_CHILL"], "GENESECT_4": ["GENESECT_DOUSE"],
    "LYCANROC_1": ["LYCANROC_MIDNIGHT"], "LYCANROC_2": ["LYCANROC_DUSK"],
    "ORICORIO_1": ["ORICORIO_POM_POM"], "ORICORIO_2": ["ORICORIO_PAU"], "ORICORIO_3": ["ORICORIO_SENSU"],
    "CALYREX_1": ["CALYREX_ICE"], "CALYREX_2": ["CALYREX_SHADOW"],
    "NECROZMA_1": ["NECROZMA_DUSK"], "NECROZMA_2": ["NECROZMA_DAWN"], "NECROZMA_3": ["NECROZMA_ULTRA"],
    "NECROZMA_4": "IGNORE",
    "KYUREM_1": ["KYUREM_WHITE"], "KYUREM_2": ["KYUREM_BLACK"],
    "KYUREM_3": "IGNORE", "KYUREM_4": "IGNORE",  # user: "ignore extras"
    "ROTOM_1": ["ROTOM_HEAT"], "ROTOM_2": ["ROTOM_WASH"], "ROTOM_3": ["ROTOM_FROST"],
    "ROTOM_4": ["ROTOM_FAN"], "ROTOM_5": ["ROTOM_MOW"],
    "SQUAWKABILLY_1": ["SQUAWKABILLY_BLUE_PLUMAGE"], "SQUAWKABILLY_2": ["SQUAWKABILLY_YELLOW_PLUMAGE"],
    "SQUAWKABILLY_3": ["SQUAWKABILLY_WHITE_PLUMAGE"],
    "TATSUGIRI_1": ["TATSUGIRI_DROOPY"], "TATSUGIRI_2": ["TATSUGIRI_STRETCHY"],
    "TAUROS_1": ["TAUROS_PALDEA_COMBAT_BREED"], "TAUROS_2": ["TAUROS_PALDEA_BLAZE_BREED"],
    "TAUROS_3": ["TAUROS_PALDEA_AQUA_BREED"],
    "WORMADAM_1": ["WORMADAM_SANDY"], "WORMADAM_2": ["WORMADAM_TRASH"],
    "MEOWTH_1": ["MEOWTH_ALOLA"], "MEOWTH_2": ["MEOWTH_GALAR"],
    "RAICHU_1": ["RAICHU_ALOLA"], "SLOWBRO_1": ["SLOWBRO_GALAR"],
    "DARMANITAN_1": ["DARMANITAN_GALAR_ZEN", "DARMANITAN_GALAR_STANDARD", "DARMANITAN_ZEN"],
    "DARMANITAN_2": "IGNORE", "DARMANITAN_3": "IGNORE",
    "TERAPAGOS_1": ["TERAPAGOS_TERASTAL"], "TERAPAGOS_2": ["TERAPAGOS_STELLAR"],
    # front/back's own numbering, verified directly by the user against
    # these specific images -- NOT the same order as overworld's Pikachu
    # (confirmed to differ, e.g. _9 here is Hoenn Cap, not unresolved;
    # _12-_15 are shifted relative to overworld's _12-_15).
    "PIKACHU_2": ["PIKACHU_COSPLAY"], "PIKACHU_3": ["PIKACHU_BELLE"], "PIKACHU_4": ["PIKACHU_LIBRE"],
    "PIKACHU_5": ["PIKACHU_PHD"], "PIKACHU_6": ["PIKACHU_POP_STAR"], "PIKACHU_7": ["PIKACHU_ROCK_STAR"],
    "PIKACHU_8": ["PIKACHU_ORIGINAL_CAP"], "PIKACHU_9": ["PIKACHU_HOENN_CAP"],
    "PIKACHU_10": ["PIKACHU_SINNOH_CAP"], "PIKACHU_11": ["PIKACHU_UNOVA_CAP"],
    "PIKACHU_12": ["PIKACHU_KALOS_CAP"], "PIKACHU_13": ["PIKACHU_ALOLA_CAP"],
    "PIKACHU_14": ["PIKACHU_PARTNER_CAP"], "PIKACHU_15": ["PIKACHU_WORLD_CAP"],
    "PIKACHU_17": ["PIKACHU_GMAX"],
    "MEOWSTIC_MEGA": "IGNORE",
    "MAGEARNA_MEGA_FORMA_COLOR_VETUSTA": "IGNORE",
    "TATSUGIRI_MEGA_FORMA_CURVADA": "IGNORE",
    "TATSUGIRI_MEGA_FORMA_LANGUIDA": "IGNORE",
    "TATSUGIRI_MEGA_FORMA_RECTA": "IGNORE",
    # "all totems fall to their _1 asset" -- regional form and Totem form
    # share the one source image.
    "MAROWAK_1": ["MAROWAK_ALOLA", "MAROWAK_TOTEM"],
    "RATICATE_1": ["RATICATE_ALOLA", "RATICATE_TOTEM_ALOLA"],
    # Minior: base + all 6 Meteor colors share one image; the 7 "core"
    # colors each get their own (same as overworld).
    "MINIOR": ["MINIOR", "MINIOR_ORANGE_METEOR", "MINIOR_YELLOW_METEOR", "MINIOR_GREEN_METEOR",
               "MINIOR_BLUE_METEOR", "MINIOR_INDIGO_METEOR", "MINIOR_VIOLET_METEOR"],
    "MINIOR_7": ["MINIOR_RED"], "MINIOR_8": ["MINIOR_ORANGE"], "MINIOR_9": ["MINIOR_YELLOW"],
    "MINIOR_10": ["MINIOR_GREEN"], "MINIOR_11": ["MINIOR_BLUE"], "MINIOR_12": ["MINIOR_INDIGO"],
    "MINIOR_13": ["MINIOR_VIOLET"],
    # front/back-specific
    "CRAMORANT_1": ["CRAMORANT_GULPING"], "CRAMORANT_2": ["CRAMORANT_GORGING"],
    "CASTFORM_1": ["CASTFORM_SUNNY"], "CASTFORM_2": ["CASTFORM_RAINY"], "CASTFORM_3": ["CASTFORM_SNOWY"],
    "BASCULIN": ["BASCULIN_WHITE_STRIPED"], "BASCULIN_2": ["BASCULIN"], "BASCULIN_3": ["BASCULIN_BLUE_STRIPED"],
    "OGERPON_1": ["OGERPON_WELLSPRING_MASK"], "OGERPON_2": ["OGERPON_HEARTHFLAME_MASK"],
    "OGERPON_3": ["OGERPON_CORNERSTONE_MASK"],
    "MIMIKYU": ["MIMIKYU", "MIMIKYU_TOTEM_DISGUISED"],
    "MIMIKYU_1": ["MIMIKYU_BUSTED", "MIMIKYU_TOTEM_BUSTED"],
    "GRENINJA_2": ["GRENINJA_ASH", "GRENINJA_BATTLE_BOND"],
    "GRENINJA_3": ["GRENINJA_MEGA"],
    "NIDORANFE": ["NIDORAN_F"], "NIDORANMA": ["NIDORAN_M"],
    "SNEASEL_1_F": "IGNORE",  # female of the Hisuian form; no separate id
    "EEVEE_1_F": "IGNORE",    # partner Eevee's sprite is shared by both genders
    "EEVEE_1": ["EEVEE_STARTER"],
    "EEVEE_2": ["EEVEE_GMAX"],
    # Zygarde: base + both Power Construct variants + Complete Forme
    # share one image; the 10% forme gets its own; Mega gets its own too
    # (front/back, unlike overworld, does show Mega distinctly).
    "ZYGARDE": ["ZYGARDE", "ZYGARDE_50_POWER_CONSTRUCT"],
    "ZYGARDE_1": ["ZYGARDE_10", "ZYGARDE_10_POWER_CONSTRUCT"],
    "ZYGARDE_2": ["ZYGARDE_COMPLETE"],
    "ZYGARDE_4": ["ZYGARDE_MEGA"],
}

# Arceus and Silvally: canonical in-game type-plate order, 1-8 direct,
# 9 skipped (no 18th/19th type to place there -- matches the same skip
# already confirmed for overworld's Arceus), 10-18 continuing.
_TYPE_ORDER = {
    1: "FIGHTING", 2: "FLYING", 3: "POISON", 4: "GROUND", 5: "ROCK", 6: "BUG", 7: "GHOST", 8: "STEEL",
    10: "FIRE", 11: "WATER", 12: "GRASS", 13: "ELECTRIC", 14: "PSYCHIC", 15: "ICE", 16: "DRAGON",
    17: "DARK", 18: "FAIRY",
}
for _n, _t in _TYPE_ORDER.items():
    FORCE_TARGETS[f"ARCEUS_{_n}"] = [f"ARCEUS_{_t}"]
    FORCE_TARGETS[f"SILVALLY_{_n}"] = [f"SILVALLY_{_t}"]

# Still needs a human answer -- not guessed, not processed.
STILL_UNRESOLVED = {
    "ARCEUS_9": "18th file, only 17 real Arceus types -- what does this one show?",
    "MEOWTH_3": "3rd file, only 2 real Meowth forms (Alola/Galar) -- what does this one show?",
    "OGERPON_4": "unaddressed", "OGERPON_5": "unaddressed", "OGERPON_6": "unaddressed",
    "OGERPON_7": "unaddressed",
    "OGERPON_8": "Tera-form group named but exact file<->mask correspondence not confirmed",
    "OGERPON_9": "Tera-form group named but exact file<->mask correspondence not confirmed",
    "OGERPON_10": "Tera-form group named but exact file<->mask correspondence not confirmed",
    "OGERPON_11": "Tera-form group named but exact file<->mask correspondence not confirmed",
}

FORM_RE = re.compile(r"^([A-Z0-9]+)_(\d+)$")
FEMALE_F_RE = re.compile(r"^([A-Z0-9]+)_F$")


def real_forms(species, by_species, real_ids):
    # unlike overworld's non_mechanic_forms(), Mega/Gmax are kept --
    # they're real, distinct candidates for battle sprites.
    forms = by_species.get(species)
    if forms is None:
        stripped = species.replace("_", "")
        matches = [k for k in by_species if k.replace("_", "") == stripped]
        forms = by_species[matches[0]] if len(matches) == 1 else []
    return [f for f in forms if f in real_ids]


def resolve_species(name, real_ids, normalized, by_species):
    if name in STILL_UNRESOLVED:
        return "unresolved", None
    if name in FORCE_TARGETS:
        val = FORCE_TARGETS[name]
        return ("ignore", None) if val == "IGNORE" else ("targets", val)

    if name in real_ids:
        return "targets", [name]
    fixed = normalized.get(name.replace("_", ""))
    if fixed:
        return "targets", [fixed]

    m = FEMALE_F_RE.match(name)
    if m:
        species = m.group(1)
        cands = [f for f in real_forms(species, by_species, real_ids) if f.endswith("_FEMALE")]
        if len(cands) == 1:
            return "targets", [cands[0]]
        if len(cands) == 0:
            return "ignore", None
        return "unresolved", None

    m = FORM_RE.match(name)
    if m:
        species = m.group(1)
        if species in COSMETIC_FAMILIES:
            return "ignore", None
        cands = real_forms(species, by_species, real_ids)
        if len(cands) == 0:
            return "ignore", None
        if len(cands) == 1:
            return "targets", cands
        return "unresolved", None

    return "unresolved", None


def load_manifest(path):
    rows = list(csv.DictReader(path.open(encoding="utf-8")))
    frame1 = {}
    for r in rows:
        if r["cell_index"] == "1":
            frame1[r["species"]] = {
                "source_sheet": r["source_sheet"],
                "box": (int(r["left"]), int(r["top"]), int(r["right"]), int(r["bottom"])),
            }
    return frame1


def process_side(side_name, manifest_path, input_dir, output_dir, real_ids, normalized, by_species):
    output_dir.mkdir(parents=True, exist_ok=True)
    frame1 = load_manifest(manifest_path)

    copied, ignored, unresolved, missing_source, invalid_target = [], [], [], [], []

    for species_raw, info in frame1.items():
        kind, targets = resolve_species(species_raw, real_ids, normalized, by_species)
        if kind == "ignore":
            ignored.append(species_raw)
            continue
        if kind == "unresolved":
            unresolved.append(species_raw)
            continue

        src = input_dir / info["source_sheet"]
        if not src.is_file():
            missing_source.append(species_raw)
            continue

        with Image.open(src) as im:
            frame = im.crop(info["box"])
            for target in targets:
                if target not in real_ids:
                    invalid_target.append((species_raw, target))
                    continue
                frame.save(output_dir / f"{target}.png")
                copied.append((species_raw, target))

    print(f"--- {side_name} ---")
    print(f"copied:          {len(copied)}")
    print(f"ignored:         {len(ignored)}")
    print(f"unresolved:      {len(unresolved)}")
    print(f"invalid target:  {len(invalid_target)}")
    print(f"missing source:  {len(missing_source)}")
    if unresolved:
        print("  unresolved:", ", ".join(sorted(unresolved)))
    if invalid_target:
        print("  invalid:", invalid_target)
    if missing_source:
        print("  missing source:", missing_source)
    print()
    return copied, ignored, unresolved, invalid_target, missing_source


def main():
    real_ids = ow.load_real_ids()
    normalized = ow.normalize_lookup(real_ids)
    by_species = ow.load_forms_by_species()

    process_side("BACK", BACK_MANIFEST, INPUT_BACK, OUTPUT_BACK, real_ids, normalized, by_species)
    process_side("FRONT", FRONT_MANIFEST, INPUT_FRONT, OUTPUT_FRONT, real_ids, normalized, by_species)


if __name__ == "__main__":
    main()
