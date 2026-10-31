"""Export CreatureData.lua into JSON for the Three.js web build (web/src/data/creatures.json).

Parses each creature entry in CreatureData.Creatures and computes base stats with a
port of CreatureData.AllocateBaseStats (rarity budget + class weights + element bias +
deterministic per-id spread), so the web build's numbers match the Roblox game.

Usage (from repo root):  python3 tools/export_creatures_web.py
"""
import json
import math
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "CreatureData.lua")
OUT = os.path.join(ROOT, "web", "src", "data", "creatures.json")

RARITY_BUDGET = {"Common": 100, "Uncommon": 150, "Rare": 300, "Epic": 400, "Legendary": 500}
CLASS_W = {
    "Assassin": [0.14, 0.32, 0.22, 0.32],
    "Guardian": [0.40, 0.17, 0.33, 0.10],
    "Mage": [0.20, 0.40, 0.11, 0.29],
    "Bruiser": [0.28, 0.26, 0.28, 0.18],
    "Support": [0.36, 0.14, 0.14, 0.36],
}
ELEM_BIAS = {
    "Fire": [0, 0.07, 0, 0], "Earth": [0.07, 0, 0, 0], "Wind": [0, 0, 0, 0.07],
    "Ice": [0, 0, 0.07, 0], "Water": [0.04, 0.04, 0, 0], "Lightning": [0, 0.04, 0, 0.04],
    "Poison": [0.04, 0, 0, 0.04], "Metal": [0.04, 0, 0.04, 0], "Psychic": [0, 0, 0.04, 0.04],
    "Undead": [0, 0.04, 0.04, 0], "Light": [0.03, 0, 0.03, 0.03], "Shadow": [0, 0.03, 0.03, 0.03],
}


def stat_hash(s):
    h = 5381
    for ch in s.encode():
        h = (h * 33 + ch) % 2147483647
    return h


def normalize(w):
    s = sum(w)
    return [x / s for x in w] if s > 0 else [0.25] * 4


def spread(cls, w, h):
    t = ((h % 131) / 130 - 0.5) * 0.12
    idx = {"Assassin": 2, "Guardian": 1, "Mage": 0, "Bruiser": 3}.get(cls)
    if idx is not None:
        w[idx] = max(0.02, w[idx] * (1 + t))
    elif cls == "Support":
        u = (h % 97) / 96 - 0.5
        w[0] = max(0.02, w[0] * (1 + u * 0.08))
        w[3] = max(0.02, w[3] * (1 - u * 0.08))


def partition(total, w, min_each):
    if total < 4 * min_each:
        min_each = total // 4
    rem = total - 4 * min_each
    frac = [x * rem for x in w]
    out = [min_each + math.floor(f) for f in frac]
    left = total - sum(out)
    order = sorted(range(4), key=lambda i: -(frac[i] - math.floor(frac[i])))
    for k in range(left):
        out[order[k]] += 1
    return out


def allocate(rarity, cls, element, cid):
    budget = RARITY_BUDGET.get(rarity, 100)
    cw = CLASS_W.get(cls, [0.25] * 4)
    eb = ELEM_BIAS.get(element, [0] * 4)
    w = normalize([max(0.02, cw[i] + eb[i]) for i in range(4)])
    spread(cls, w, stat_hash(cid))
    w = normalize(w)
    p = partition(budget, w, 1)
    return {"health": p[0], "attack": p[1], "defense": p[2], "speed": p[3]}


FIELD_RE = re.compile(
    r'(\w+)\s*=\s*('
    r'"(?:[^"\\]|\\.)*"'                              # string
    r'|Color3\.fromRGB\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*\)'  # color
    r'|\{[^{}]*\}'                                     # small table
    r'|true|false'
    r'|-?\d+(?:\.\d+)?'
    r')'
)


def parse_value(v):
    if v.startswith('"'):
        return v[1:-1].replace('\\"', '"')
    if v.startswith("Color3"):
        return [int(x) for x in re.findall(r"\d+", v)[-3:]]
    if v.startswith("{"):
        nums = re.findall(r"-?\d+(?:\.\d+)?", v)
        return [float(n) if "." in n else int(n) for n in nums]
    if v in ("true", "false"):
        return v == "true"
    return float(v) if "." in v else int(v)


def main():
    with open(SRC, encoding="utf-8") as f:
        src = f.read()
    start = src.index("CreatureData.Creatures = {")
    body = src[start + len("CreatureData.Creatures = {"):]
    # Walk braces to find each top-level entry
    entries, depth, buf = [], 0, None
    i = 0
    in_str = False
    while i < len(body):
        c = body[i]
        if c == '"' and body[i - 1] != "\\":
            in_str = not in_str
        if not in_str:
            if body.startswith("--", i) and depth <= 1:
                nl = body.find("\n", i)
                i = nl if nl != -1 else len(body)
                continue
            if c == "{":
                depth += 1
                if depth == 1:
                    buf = []
            elif c == "}":
                if depth == 0:
                    break
                depth -= 1
                if depth == 0:
                    entries.append("".join(buf))
                    buf = None
                    i += 1
                    continue
        if buf is not None and depth >= 1:
            buf.append(c)
        i += 1

    keep = {"id", "displayName", "rarity", "element", "class", "behavior", "spawnWeight",
            "baseIncome", "captureTime", "description", "primaryColor", "evolvesTo",
            "evolvesFrom", "flying", "crawling", "spawnPointType", "packSize", "npcOnly"}
    out = []
    for e in entries:
        d = {}
        for k, v in FIELD_RE.findall(e):
            if k in keep and k not in d:
                d[k] = parse_value(v)
        if "id" not in d or "rarity" not in d:
            continue
        d.update(allocate(d["rarity"], d.get("class", ""), d.get("element", ""), d["id"]))
        out.append(d)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print(f"Exported {len(out)} creatures -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
