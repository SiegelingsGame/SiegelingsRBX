import CREATURES from './data/creatures.json';
import { CFG } from './config.js';

export const Creatures = CREATURES.filter((c) => !c.npcOnly);
const byId = new Map(Creatures.map((c) => [c.id, c]));
export const getCreature = (id) => byId.get(id);

export const STARTERS = ['cacty', 'pursula', 'sundile', 'fawny'];

const hasRealEvolve = (c) => c.evolvesTo && c.evolvesTo !== 'Coming Soon' && byId.has(c.evolvesTo);

export function maxCreatureLevel(id) {
  const c = byId.get(id);
  if (!c) return CFG.BaseMaxLevel;
  if (c.evolvesFrom && hasRealEvolve(c)) return CFG.EvolvedMaxLevel;
  if (c.evolvesFrom) return CFG.FinalMaxLevel;
  return CFG.BaseMaxLevel;
}

export function xpForLevel(level) {
  if (level <= 1) return 0;
  return Math.floor(CFG.BaseXPRequired * Math.pow(CFG.XPScaling, level - 2));
}

export function playerXPForLevel(level) {
  if (level <= 1) return 0;
  return Math.floor(CFG.PlayerBaseXP * Math.pow(CFG.PlayerXPScaling, level - 2));
}

// Port of PlayerDataManager.GetEffectiveStats: rank-based level growth, then variant * rarity.
export function effectiveStats(id, level = 1, variant = 'Normal') {
  const c = byId.get(id);
  if (!c) return { health: 1, attack: 1, defense: 1, speed: 1 };
  const keys = ['health', 'attack', 'defense', 'speed'];
  const tiebreak = { health: 1, attack: 2, defense: 3, speed: 4 };
  const sorted = [...keys].sort((a, b) => (c[b] - c[a]) || (tiebreak[a] - tiebreak[b]));
  const mult = (CFG.VariantStatMultipliers[variant] || 1) * (CFG.RarityStatMultipliers[c.rarity] || 1);
  const out = {};
  sorted.forEach((k, rank) => {
    const lm = 1 + (level - 1) * CFG.StatGainPerLevel * CFG.StatGainByRank[rank];
    out[k] = Math.max(1, Math.floor(c[k] * lm * mult));
  });
  return out;
}

export function captureCost(id) {
  const c = byId.get(id);
  return c ? CFG.RarityCaptureCost[c.rarity] || 10 : 10;
}

export function sellValue(entry) {
  const c = byId.get(entry.id);
  if (!c) return 1;
  const v = CFG.SellValue[c.rarity] || 5;
  const vm = { Normal: 1, Silver: 2, Gold: 4, Legend: 8 }[entry.variant || 'Normal'] || 1;
  return Math.floor(v * vm * (1 + (entry.level - 1) * 0.25));
}

// Income per tick for a stationed creature (BaseIncomeSystem uses creatureInfo.baseIncome).
export function creatureIncome(entry) {
  const c = byId.get(entry.id);
  return c ? c.baseIncome : 0;
}

export const isNightElement = (el) => el === 'Shadow' || el === 'Lightning';

export function creaturesForElements(elements, spawnPointType = null) {
  return Creatures.filter((c) => elements.includes(c.element) && (c.spawnPointType || null) === spawnPointType);
}

// Port of CreatureData.Synergies / CalculateSynergies (battle team element + class bonuses).
export const SYNERGIES = {
  Fire: [[2, 'Ember', { attack: 0.10 }], [3, 'Inferno', { attack: 0.25 }]],
  Ice: [[2, 'Frost', { defense: 0.10 }], [3, 'Blizzard', { defense: 0.25, speed: -0.10 }]],
  Wind: [[2, 'Breeze', { speed: 0.15 }], [3, 'Tempest', { speed: 0.30, attack: 0.10 }]],
  Earth: [[2, 'Roots', { health: 0.10 }], [3, 'Tectonic', { health: 0.25, defense: 0.10 }]],
  Shadow: [[2, 'Dusk', { attack: 0.10, speed: 0.05 }], [3, 'Eclipse', { attack: 0.20, speed: 0.15 }]],
  Light: [[2, 'Radiant', { defense: 0.10, attack: 0.05 }], [3, 'Brilliance', { defense: 0.20, attack: 0.15 }]],
  Lightning: [[2, 'Spark', { speed: 0.10, attack: 0.05 }], [3, 'Thunder', { speed: 0.20, attack: 0.15 }]],
  Water: [[2, 'Tide', { defense: 0.10, speed: 0.05 }], [3, 'Tsunami', { defense: 0.20, speed: 0.15 }]],
  Psychic: [[2, 'Link', { health: 0.10, speed: 0.05 }], [3, 'Harmony', { health: 0.20, speed: 0.10 }]],
  Metal: [[2, 'Alloy', { defense: 0.12 }], [3, 'Tempered', { defense: 0.25, health: 0.08 }]],
  Poison: [[2, 'Toxin', { attack: 0.08, speed: 0.05 }], [3, 'Venom', { attack: 0.18, speed: 0.10 }]],
  Undead: [[2, 'Wither', { health: 0.08, defense: 0.08 }], [3, 'Necrotic', { health: 0.18, defense: 0.15 }]],
  Bruiser: [[2, 'Fury', { attack: 0.12 }], [3, 'Rampage', { attack: 0.25, health: 0.10 }]],
  Mage: [[2, 'Focus', { attack: 0.10 }], [3, 'Arcane', { attack: 0.20 }]],
  Guardian: [[2, 'Shield', { defense: 0.15 }], [3, 'Bastion', { defense: 0.30, health: 0.10 }]],
  Assassin: [[2, 'Edge', { speed: 0.10, attack: 0.05 }], [3, 'Lethal', { speed: 0.20, attack: 0.20 }]],
  Support: [[2, 'Mend', { health: 0.10 }], [3, 'Harmony', { health: 0.20, defense: 0.10 }]],
};

// Returns active synergies [{ trait, label, count, bonuses }] for a list of creature ids.
export function calculateSynergies(ids) {
  const counts = {};
  for (const id of ids) {
    const c = byId.get(id);
    if (!c) continue;
    counts[c.element] = (counts[c.element] || 0) + 1;
    counts[c.class] = (counts[c.class] || 0) + 1;
  }
  const active = [];
  for (const [trait, n] of Object.entries(counts)) {
    const tiers = SYNERGIES[trait];
    if (!tiers) continue;
    let best = null;
    for (const t of tiers) if (n >= t[0]) best = t;
    if (best) active.push({ trait, label: best[1], count: n, bonuses: best[2] });
  }
  return active;
}
