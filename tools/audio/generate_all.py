#!/usr/bin/env python3
"""Deterministic generator for every HOUSE RULES audio asset (SFX, ambience, music, PA voice).

    python3 -I tools/audio/generate_all.py                  # everything
    python3 -I tools/audio/generate_all.py --only step_     # names/ids that equal or start with a prefix
    python3 -I tools/audio/generate_all.py --sfx-only | --voice-only | --manifest-only

Reads data/sound_catalog.json + data/pa_lines.json, writes audio/{amb,music,sfx,voice}/, then rebuilds
audio/manifest.json and audio/REPORT.md from what is on disk.  All randomness is seeded from the sound
name (crc32), so repeated runs give identical files.
"""
import os
import sys
import time

# `python3 -I` does not put the script directory on sys.path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import core  # noqa: E402

RECIPE_MODULES = ["sfx_ambience", "sfx_foley", "sfx_interact", "sfx_camcorder",
                  "sfx_elevator", "sfx_entity", "sfx_scare", "sfx_pa", "music"]


def load_recipes():
    import importlib
    for m in RECIPE_MODULES:
        try:
            importlib.import_module(m)
        except ModuleNotFoundError as ex:
            if ex.name != m:
                raise
            print(f"(recipe module {m} not present yet -- placeholders will be used)")


def matches(name, prefixes):
    return not prefixes or any(name == p or name.startswith(p) for p in prefixes)


def main(argv):
    only = []
    sfx_only = voice_only = manifest_only = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--only":
            only.append(argv[i + 1])
            i += 2
            continue
        if a.startswith("--only="):
            only.append(a.split("=", 1)[1])
        elif a == "--sfx-only":
            sfx_only = True
        elif a == "--voice-only":
            voice_only = True
        elif a == "--manifest-only":
            manifest_only = True
        else:
            print(__doc__)
            return 2
        i += 1

    t0 = time.time()
    if not manifest_only:
        load_recipes()
        if not voice_only:
            for e in core.load_catalog():
                if matches(e["name"], only):
                    print(f"[sfx] {e['name']}")
                    core.generate_entry(e)
        if not sfx_only:
            try:
                import voice
            except ModuleNotFoundError as ex:
                if ex.name != "voice":
                    raise
                voice = None
                print("(voice module not present yet)")
            if voice is not None:
                ids = [ln["id"] for ln in core.load_pa_lines() if matches(ln["id"], only)]
                if ids:
                    print(f"[voice] {len(ids)} lines")
                    voice.generate_voice(ids)
    import manifest
    manifest.write_manifest()
    manifest.write_report()
    print(f"done in {time.time() - t0:.1f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
