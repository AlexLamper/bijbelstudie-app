"""Generate the store-screenshot fixtures from the live content API.

The screenshots quote Scripture and Matthew Henry, so the text has to be the
real thing rather than something typed from memory. Both sources are public
domain and on the mobile allowlist in the website's lib/mobileLicensing.ts, so
the production API serves them to an unauthenticated request.

Run:  python tools/gen_screenshot_fixtures.py
Out:  bijbelstudie_mobile/test/screenshot_fixtures.dart
"""

from __future__ import annotations

import io
import json
import pathlib
import urllib.request

BASE = "https://www.bijbel-studie.com/api/v1"
BIBLE = f"{BASE}/bibles/statenvertaling/Genesis/1"
COMMENTARY = f"{BASE}/commentaries/matthew_henry_nl/Genesis/1"

DEST = pathlib.Path(__file__).resolve().parents[1] / (
    "bijbelstudie_mobile/test/screenshot_fixtures.dart"
)

HEADER = """// GENERATED — do not hand-edit.
//
// Real Genesis 1 text, pulled from the production API so the store screenshots
// quote Scripture and Matthew Henry accurately rather than approximately.
// Both sources are public domain and on the mobile allowlist in the website's
// lib/mobileLicensing.ts.
//
// Regenerate with: python tools/gen_screenshot_fixtures.py

import 'package:bijbelstudie_mobile/features/bible/domain/bible_models.dart';

"""


def dart_string(value: str) -> str:
    """Escape for a single-quoted Dart literal."""
    out = value.replace("\\", "\\\\")
    out = out.replace("'", "\\'")
    out = out.replace("$", "\\$")
    return " ".join(out.split())


def fetch(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=30) as response:
        if response.status != 200:
            raise SystemExit(f"{url} returned {response.status}")
        return json.loads(response.read().decode("utf-8"))


def emit(out: io.StringIO, name: str, verses: list[dict]) -> None:
    out.write(f"const List<Verse> {name} = [\n")
    for verse in verses:
        out.write(f"  Verse(number: {verse['n']}, text: '{dart_string(verse['t'])}'),\n")
    out.write("];\n\n")


def main() -> None:
    bible = fetch(BIBLE)
    commentary = fetch(COMMENTARY)

    out = io.StringIO()
    out.write(HEADER)
    out.write(f"const String kGenesisAttribution = '{dart_string(bible['attribution'])}';\n\n")
    emit(out, "kGenesis1Verses", bible["verses"])
    out.write(
        f"const String kCommentaryAttribution = '{dart_string(commentary['attribution'])}';\n\n"
    )
    emit(out, "kMatthewHenryGenesis1", commentary["verses"])

    DEST.write_text(out.getvalue(), encoding="utf-8")
    print(f"{DEST}: {len(bible['verses'])} verses, {len(commentary['verses'])} commentary entries")


if __name__ == "__main__":
    main()
