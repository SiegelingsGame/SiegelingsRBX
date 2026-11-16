"""Sync the web game's creature roster and art with the Siegelings TCG.

The TCG (SiegelingsGame/SiegelingTCG) is the source of truth for WHICH Siegelings exist: names,
elements, rarities, descriptions, evolutions and their card "overlay" art. CreatureData.lua (Roblox)
still supplies the open-world gameplay fields (class, behaviour, spawn weights, income, flying...)
for every creature both games share; TCG-only creatures get rarity-based defaults.

Writes:
  web/src/data/creatures.json   the roster the web game loads
  web/public/art/<id>.webp      trimmed, resized overlay art (billboards + UI portraits)

Usage (from repo root; needs Pillow: pip install pillow):
  python3 tools/sync_tcg_roster.py                       # fetch the live TCG card data
  python3 tools/sync_tcg_roster.py --input cards.json    # use a saved /api/cards/editor response
  python3 tools/sync_tcg_roster.py --skip-art            # roster only, keep existing art files
"""
import argparse
import hashlib
import io
import json
import os
import sys
import urllib.request

from export_creatures_web import parse_creatures, allocate

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_JSON = os.path.join(ROOT, "web", "src", "data", "creatures.json")
ART_DIR = os.path.join(ROOT, "web", "public", "art")
LIVE_URL = "https://siegelingstcgtesting.web.app/api/cards/editor"
ART_MAX = 512  # px, longest side after trimming

ELEMENT = {
    "FIRE": "Fire", "ICE": "Ice", "EARTH": "Earth", "WIND": "Wind", "WATER": "Water",
    "ELECTRIC": "Lightning", "METAL": "Metal", "POISON": "Poison", "PSYCHIC": "Psychic",
    "UNDEAD": "Undead", "LIGHT": "Light", "SHADOW": "Shadow", "NEUTRAL": "Neutral",
}
# Creatures renamed between the two games (TCG id -> Roblox id)
ALIASES = {
    "golork": "golor", "papapa": "papap", "spookweed": "spookyweed", "toxsleaf": "toxleaf",
    "cactyjacked-ty": "cactyjackedty",
}
# Rarity defaults taken from the current Roblox roster's typical values
DEFAULTS = {
    "Common":    {"spawnWeight": 16, "baseIncome": 1,  "captureTime": 0.5, "spawnPointType": None},
    "Uncommon":  {"spawnWeight": 9,  "baseIncome": 3,  "captureTime": 1.1, "spawnPointType": None},
    "Rare":      {"spawnWeight": 5,  "baseIncome": 8,  "captureTime": 1.8, "spawnPointType": "dungeon"},
    "Epic":      {"spawnWeight": 2,  "baseIncome": 20, "captureTime": 2.5, "spawnPointType": "dungeon"},
    "Legendary": {"spawnWeight": 1,  "baseIncome": 50, "captureTime": 3.5, "spawnPointType": "boss"},
}
GAMEPLAY_FIELDS = ["class", "behavior", "spawnWeight", "baseIncome", "captureTime", "packSize",
                   "flying", "crawling", "spawnPointType", "primaryColor", "modelName",
                   "modelRotationY", "modelStandUpAngles", "modelDisplaySize", "modelScaleMultiplier",
                   "modelPlacementYOffset"]


def h(s):
    return int(hashlib.md5(s.encode()).hexdigest(), 16)


def default_class(card):
    hp, spd = card.get("health") or 1, card.get("speed") or 1
    if spd > hp:
        return "Assassin"
    if hp >= 2.2 * spd:
        return "Guardian"
    return ["Bruiser", "Mage", "Support"][h(card["id"]) % 3]


def default_behavior(card_id):
    pool = ["lone"] * 4 + ["aggressive"] * 2 + ["gentle"] * 2 + ["skittish"]
    return pool[h(card_id + "b") % len(pool)]


def fetch_cards(path):
    if path:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    else:
        with urllib.request.urlopen(LIVE_URL, timeout=60) as r:
            data = json.load(r)
    data = data.get("data", data)
    moves = {m["id"]: m.get("name") for m in data.get("moves", [])}
    cards = [c for c in data["cards"] if c.get("type") == "SIEGLING"]
    for c in cards:  # first TCG move names the creature's attack in the web game
        names = [moves[m] for m in (c.get("moveIds") or []) if moves.get(m)]
        c["_move"] = names[0] if names else None
    return cards


def avg_color(im):
    """Average colour of the visible pixels -> primaryColor for UI accents, effects and the minimap."""
    small = im.convert("RGBA").resize((32, 32))
    px = [p for p in small.getdata() if p[3] > 128]
    return [round(sum(p[i] for p in px) / len(px)) for i in range(3)] if px else None


def process_art(card, skip):
    """Download + trim + resize the overlay art. Returns (relative path, aspect, avg colour) or Nones."""
    from PIL import Image
    out_path = os.path.join(ART_DIR, card["id"] + ".webp")
    if skip or not card.get("cardArtUrl"):
        if os.path.exists(out_path):
            im = Image.open(out_path)
            return f"art/{card['id']}.webp", round(im.width / im.height, 3), avg_color(im)
        return None, None, None
    try:
        req = urllib.request.Request(card["cardArtUrl"], headers={"User-Agent": "siegelings-sync"})
        with urllib.request.urlopen(req, timeout=60) as r:
            im = Image.open(io.BytesIO(r.read())).convert("RGBA")
    except Exception as e:  # expired storage token, network error...
        print(f"  ! art for {card['id']}: {e}", file=sys.stderr)
        if os.path.exists(out_path):  # keep the last good copy
            im = Image.open(out_path)
            return f"art/{card['id']}.webp", round(im.width / im.height, 3), avg_color(im)
        return None, None, None
    bbox = im.getchannel("A").point(lambda a: 255 if a > 12 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    im.thumbnail((ART_MAX, ART_MAX), Image.LANCZOS)
    os.makedirs(ART_DIR, exist_ok=True)
    im.save(out_path, "WEBP", quality=82, method=6)
    return f"art/{card['id']}.webp", round(im.width / im.height, 3), avg_color(im)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", help="saved /api/cards/editor JSON instead of fetching live")
    ap.add_argument("--skip-art", action="store_true")
    args = ap.parse_args()

    rbx = {c["id"]: c for c in parse_creatures()}
    cards = fetch_cards(args.input)
    print(f"TCG roster: {len(cards)} Sieglings")
    out, missing_art = [], []
    for card in cards:
        cid = card["id"]
        rarity = card["rarity"].title()
        element = ELEMENT.get(card["element"], card["element"].title())
        src = rbx.get(cid) or rbx.get(ALIASES.get(cid, ""))
        c = {"id": cid, "displayName": card["name"], "rarity": rarity, "element": element,
             "description": card.get("description") or (src or {}).get("description", "")}
        if src:
            for k in GAMEPLAY_FIELDS:
                if k in src:
                    c[k] = src[k]
        else:
            c.update({k: v for k, v in DEFAULTS[rarity].items() if v is not None})
            c["class"] = default_class(card)
            c["behavior"] = default_behavior(cid)
        c["class"] = c["class"].title()  # CreatureData.lua has a few lowercase class names
        if element == "Neutral":
            c["spawnPointType"] = "boss"
        c["evolvesFrom"] = card.get("evolvesFromId") or None
        c["tcg"] = {"health": card.get("health"), "speed": card.get("speed"),
                    "starter": bool(card.get("expeditionStarter")), "move": card.get("_move")}
        art, aspect, avg = process_art(card, args.skip_art)
        if art:
            c["art"], c["artAspect"] = art, aspect
        else:
            missing_art.append(cid)
        if avg and "primaryColor" not in c:
            c["primaryColor"] = avg
        c.setdefault("primaryColor", [200, 200, 200])
        c.update(allocate(rarity, c["class"], element, cid))
        out.append(c)
    ids = {c["id"] for c in out}
    for c in out:  # evolution links within the TCG roster
        if c["evolvesFrom"] not in ids:
            c["evolvesFrom"] = None
        kids = [x["id"] for x in out if x["evolvesFrom"] == c["id"]]
        c["evolvesTo"] = kids[0] if kids else None
    out = [{k: v for k, v in c.items() if v is not None} for c in out]
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print(f"wrote {len(out)} creatures -> {os.path.relpath(OUT_JSON, ROOT)}")
    print(f"art: {len(out) - len(missing_art)} ok, {len(missing_art)} missing {missing_art}")


if __name__ == "__main__":
    main()
