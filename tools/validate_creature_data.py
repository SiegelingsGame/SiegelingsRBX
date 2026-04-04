#!/usr/bin/env python3
"""
Offline checks for CreatureData.lua:
  - evolvesTo / evolvesFrom must reference an existing id (except evolvesTo "Coming Soon").
  - Per-element rarity counts vs target 5 Common, 4 Uncommon, 3 Rare, 2 Epic, 1 Legendary.

Run from repo root:
  python tools/validate_creature_data.py
  python tools/validate_creature_data.py path/to/CreatureData.lua

Exit code 0 if evolution graph is consistent; non-zero if any invalid link.
Warnings on stderr for rarity ladder gaps (expected until roster is complete).
"""

from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

RARITY_TARGET = {
    "Common": 5,
    "Uncommon": 4,
    "Rare": 3,
    "Epic": 2,
    "Legendary": 1,
}

EVO_PLACEHOLDER = frozenset({"coming soon"})


def parse_creatures(text: str) -> list[dict[str, str | None]]:
    parts = re.split(r"\n\t\{\n", text)
    out: list[dict[str, str | None]] = []
    for p in parts:
        m = re.search(r'id = "([^"]+)"', p)
        if not m:
            continue

        def grab(field: str) -> str | None:
            mm = re.search(rf'{field} = "([^"]*)"', p)
            return mm.group(1) if mm else None

        out.append(
            {
                "id": m.group(1),
                "rarity": grab("rarity"),
                "element": grab("element"),
                "evolvesTo": grab("evolvesTo"),
                "evolvesFrom": grab("evolvesFrom"),
            }
        )
    return out


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "CreatureData.lua"
    text = path.read_text(encoding="utf-8")
    creatures = parse_creatures(text)
    valid = [c for c in creatures if c.get("element") and c.get("rarity")]
    ids = {c["id"] for c in valid}

    errors: list[str] = []
    for c in valid:
        cid = str(c["id"])
        if c.get("evolvesTo"):
            to_id = str(c["evolvesTo"]).strip()
            if to_id and to_id not in ids:
                if to_id.lower() not in EVO_PLACEHOLDER:
                    errors.append(f'{cid}: invalid evolvesTo "{to_id}"')
        if c.get("evolvesFrom"):
            from_id = str(c["evolvesFrom"]).strip()
            if from_id and from_id not in ids:
                errors.append(f'{cid}: invalid evolvesFrom "{from_id}"')

    by_el: dict[str, Counter[str]] = defaultdict(Counter)
    for c in valid:
        by_el[str(c["element"])][str(c["rarity"])] += 1

    declared_elements: list[str] = []
    el_start = text.find("CreatureData.Elements = {")
    el_end = text.find("CreatureData.Classes = {")
    if el_start != -1 and el_end != -1 and el_end > el_start:
        block = text[el_start:el_end]
        declared_elements = re.findall(r"^\t([A-Za-z]+)\s*=\s*\{", block, re.MULTILINE)

    print(f"File: {path}")
    print(f"Creature entries (with element+rarity): {len(valid)}")
    print(f"Unique ids: {len(ids)}")

    for el in sorted(declared_elements):
        ct = by_el.get(el, Counter())
        total = sum(ct.values())
        if total == 0:
            print(f"[WARN] No creatures for declared element: {el}")
        for r, want in RARITY_TARGET.items():
            have = ct.get(r, 0)
            if have != want:
                print(f"[WARN] {el} {r}: have {have}, target {want}")

    if errors:
        print("\nEvolution link errors:")
        for e in errors:
            print(f"  {e}")
        return 1

    print("\nEvolution links: OK (all evolvesTo/evolvesFrom resolve to ids, except Coming Soon).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
