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
