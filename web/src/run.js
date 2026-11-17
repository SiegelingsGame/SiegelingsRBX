// Survival runs: pick a starter Siegeling, survive swarms of wild Siegelings in a biome arena.
// Your team (up to 6) are your weapons — each attacks automatically with its own attack pattern.
// Chests add new Siegelings, level-ups upgrade them or grant items (up to 6).
import * as THREE from 'three';
import { ELEMENT_COLORS } from './config.js';
import { Creatures, getCreature, creaturesForElements } from './data.js';
import { buildCreatureModel } from './creatureModel.js';
import { State } from './state.js';
import { BIOMES } from './world.js';
import { hashStr, rand, pick, clamp, mulberry32 } from './util.js';

export const MAX_TEAM = 6, MAX_ITEMS = 6, MAX_MEMBER_LEVEL = 8, MAX_ITEM_LEVEL = 5;
const RUN_LENGTH = 300;      // seconds until the boss arrives
// Per-biome environmental hazards: static zones, telegraphed strikes and wandering twisters.
const HAZARDS = {
  forest:    { zone: { name: 'Thorn patch', color: 0x2f5a1a, dps: 5, slow: 0.7, n: 18 }, strike: { name: 'Rockfall', every: 9, color: 0x9a8a6a } },
  volcanic:  { zone: { name: 'Lava pool', color: 0xffc23a, dps: 14, n: 20 }, strike: { name: 'Eruption', every: 5, color: 0xff7a1a } },
  frozen:    { zone: { name: 'Black ice', color: 0x9fdcff, slow: 0.5, n: 20 }, strike: { name: 'Icicle fall', every: 7, color: 0xbfeaff } },
  highlands: { mover: { name: 'Twister', color: 0xd8ffe8, n: 7 }, strike: { name: 'Gale burst', every: 10, color: 0xffffff } },
  electric:  { zone: { name: 'Static field', color: 0xffe63c, dps: 7, n: 12 }, strike: { name: 'Lightning', every: 3.2, delay: 0.8, color: 0xffe63c } },
  caves:     { zone: { name: 'Shadow pool', color: 0x5a2a8a, dps: 8, n: 14 }, strike: { name: 'Stalactite', every: 5, color: 0xb0a0c0 } },
  ocean:     { zone: { name: 'Whirlpool', color: 0x1f5fae, dps: 4, pull: 9, n: 12 }, strike: { name: 'Geyser', every: 8, color: 0x8fd8ff, launch: true } },
  desert:    { zone: { name: 'Quicksand', color: 0x9a7436, slow: 0.45, n: 18 }, mover: { name: 'Dust devil', color: 0xe8cf9a, n: 4 }, strike: { name: 'Sunstrike', every: 9, color: 0xffd76a } },
};
const TOTEM_TIME = 5; // seconds standing by a totem to claim it
const D2R = Math.PI / 180;

// TCG weakness chart: attacker element -> elements it is strong against
const BEATS = {
  Fire: ['Ice'], Ice: ['Wind'], Wind: ['Earth'], Earth: ['Fire'], Water: ['Fire', 'Ice'], Metal: ['Earth', 'Wind'],
  Lightning: ['Wind', 'Fire'], Poison: ['Ice', 'Earth'], Shadow: ['Psychic'], Psychic: ['Light'], Light: ['Undead'], Undead: ['Shadow'],
};
const ELEMENT_EFFECT = {
  Fire: 'burns', Ice: 'slows', Wind: 'knocks back', Earth: 'can stun', Water: 'splashes nearby enemies', Lightning: 'can arc to another enemy',
  Metal: 'shreds armor', Poison: 'stacks poison', Psychic: 'weakens enemy attacks', Undead: 'steals life', Light: 'heals you on kills',
  Shadow: 'crits more often', Neutral: 'deals bonus damage',
};
const RARITY_DMG = { Common: 1, Uncommon: 1.2, Rare: 1.5, Epic: 1.9, Legendary: 2.5 };

// Attack patterns. Every Siegeling gets one from its class pool; its element adds an on-hit effect
// and its id varies count / area / cooldown, so no two Siegelings attack quite the same way.
const KINDS = {
  bolt:      { cd: 0.9, dmg: 10, count: 1, text: (a) => `Fires ${a.count} homing bolt${a.count > 1 ? 's' : ''} at the nearest enemy` },
  spread:    { cd: 1.5, dmg: 7,  count: 3, text: (a) => `Fires a fan of ${a.count} shots` },
  orbit:     { cd: 0.35, dmg: 6, count: 2, text: (a) => `${a.count} orbs circle you, hitting anything they touch` },
  slam:      { cd: 2.2, dmg: 18, count: 1, text: () => 'Slams the ground, damaging everything around it' },
  dash:      { cd: 1.7, dmg: 16, count: 1, text: () => 'Dashes through the nearest enemies' },
  beam:      { cd: 2.0, dmg: 14, count: 1, text: () => 'Fires a beam that pierces a whole line of enemies' },
  nova:      { cd: 3.0, dmg: 12, count: 1, text: () => 'Sends a shockwave out from you in every direction' },
  mortar:    { cd: 2.4, dmg: 22, count: 1, text: (a) => `Lobs ${a.count} explosive shot${a.count > 1 ? 's' : ''} onto enemy groups` },
  chain:     { cd: 1.6, dmg: 9,  count: 4, text: (a) => `Strikes that chain between ${a.count} enemies` },
  aura:      { cd: 0.5, dmg: 4,  count: 1, text: () => 'A constant damaging aura around you' },
  boomerang: { cd: 2.0, dmg: 11, count: 1, text: (a) => `Throws ${a.count} piercing disc${a.count > 1 ? 's that return' : ' that returns'}` },
  mines:     { cd: 1.6, dmg: 20, count: 1, text: () => 'Leaves traps behind you that explode on contact' },
  rain:      { cd: 0.5, dmg: 12, count: 1, text: () => 'Calls down random strikes around you' },
  cone:      { cd: 1.5, dmg: 13, count: 1, text: () => 'Breathes a cone toward the nearest enemy' },
  mend:      { cd: 5.0, dmg: 6,  count: 1, text: () => 'Heals you and pushes nearby enemies back' },
};
const CLASS_POOL = {
  Bruiser: ['slam', 'dash', 'boomerang', 'cone'], Mage: ['bolt', 'beam', 'mortar', 'rain', 'chain'],
  Guardian: ['orbit', 'aura', 'nova', 'mines'], Assassin: ['dash', 'spread', 'chain', 'boomerang'], Support: ['mend', 'nova', 'orbit', 'rain'],
};

export function attackFor(def) {
  const h = hashStr(def.id);
  const pool = CLASS_POOL[def.class] || CLASS_POOL.Bruiser;
  const kind = pool[h % pool.length];
  const k = KINDS[kind];
  const a = {
    kind, element: def.element,
    name: (def.tcg && def.tcg.move) || `${def.displayName} Strike`,
    cd: k.cd * (0.9 + ((h >> 5) % 5) * 0.05),
    dmg: k.dmg * (RARITY_DMG[def.rarity] || 1),
    count: k.count + ((h >> 3) % 2),
    area: 0.9 + ((h >> 8) % 5) * 0.06,
  };
  if (['slam', 'dash', 'beam', 'nova', 'aura', 'mines', 'rain', 'cone', 'mend'].includes(kind)) a.count = 1;
  a.desc = `${k.text(a)}. ${def.element}: ${ELEMENT_EFFECT[def.element] || 'no extra effect'}.`;
  return a;
}

export const ITEMS = [
  { id: 'swiftclaw', icon: '🪶', name: 'Swift Claw', desc: (l) => `+${12 * l}% attack speed` },
  { id: 'banner', icon: '🚩', name: 'Siege Banner', desc: (l) => `+${10 * l}% damage` },
  { id: 'boots', icon: '🥾', name: 'Trail Boots', desc: (l) => `+${8 * l}% movement speed` },
  { id: 'heartroot', icon: '❤️', name: 'Heartroot', desc: (l) => `+${20 * l} max HP` },
  { id: 'moss', icon: '🌱', name: 'Regen Moss', desc: (l) => `Regenerate ${(0.6 * l).toFixed(1)} HP per second` },
  { id: 'plate', icon: '🛡️', name: 'Guard Plate', desc: (l) => `Take ${8 * l}% less damage` },
  { id: 'lodestone', icon: '🧲', name: 'Lodestone', desc: (l) => `+${30 * l}% pickup range` },
  { id: 'fang', icon: '🦷', name: 'Lucky Fang', desc: (l) => `+${8 * l}% critical hit chance` },
  { id: 'seal', icon: '🔆', name: "Giant's Seal", desc: (l) => `+${12 * l}% attack area` },
  { id: 'charm', icon: '🪙', name: 'Coin Charm', desc: (l) => `+${20 * l}% coins from the run` },
  ...['Fire', 'Ice', 'Wind', 'Earth', 'Water', 'Lightning', 'Metal', 'Poison', 'Psychic', 'Undead', 'Light', 'Shadow'].map((el) => (
    { id: `core_${el}`, icon: '💠', element: el, name: `${el} Core`, desc: (l) => `+${25 * l}% damage for ${el} Siegelings` })),
];
const itemById = Object.fromEntries(ITEMS.map((i) => [i.id, i]));

export function arenaCenter(biomeId) {
  const b = BIOMES[biomeId];
  if (b.outer) return new THREE.Vector3(b.center.x, 0, b.center.y);
  const a = b.angle * D2R; // far out along the wedge's diagonal, where the biome is widest
  return new THREE.Vector3(Math.cos(a) * 470, 0, Math.sin(a) * 470);
}

export class Run {
  constructor(game) {
    this.g = game;
    this.active = false;
    this.enemies = []; this.team = []; this.items = {}; this.shots = []; this.hazards = []; this.chests = [];
    this.group = new THREE.Group();
    game.scene.add(this.group);
    // XP gems as one instanced mesh
    this.gemMesh = new THREE.InstancedMesh(new THREE.OctahedronGeometry(0.5, 0), new THREE.MeshBasicMaterial({ color: 0x7fe8ff }), 500);
    this.gemMesh.frustumCulled = false; this.gemMesh.count = 0;
    this.group.add(this.gemMesh);
    this.gems = [];
    this.pads = []; this.tops = []; this.zones = []; this.movers = []; this.totems = []; this.strikes = [];
    this.env = { attack: { element: 'Neutral' } }; // damage source for hazards hitting enemies
  }

  item(id) { return this.items[id] || 0; }
  get itemCount() { return Object.keys(this.items).length; }

  // ── lifecycle ────────────────────────────────────────────────
  start(entry, biomeId) {
    const g = this.g;
    this.clear();
    this.active = true;
    this.biome = biomeId;
    this.center = arenaCenter(biomeId);
    this.R = BIOMES[biomeId].outer ? 182 : 205; // arena radius
    this.pendingTotems = 0; this.strikeAt = 12; this.hazAcc = 0; this.hazTick = 0; this.baseSpeed = 1;
    this.time = 0; this.kills = 0; this.level = 1; this.xp = 0; this.pendingLevels = 0; this.pendingChests = 0;
    this.spawnAcc = 0; this.eliteAt = 45; this.chestAt = 20; this.bossSpawned = false; this.boss = null; this.won = false;
    this.items = {}; this.found = [];
    this.center.y = g.world.groundAt(this.center.x, this.center.z);
    g.player.teleport(this.center.clone());
    g.player.hp = g.player.maxHp = 100;
    g.cam.dist = 22; g.cam.pitch = -0.72; g.cam.side = 0; // high, centred camera so the swarm is readable
    const ring = new THREE.Mesh(new THREE.TorusGeometry(this.R, 0.6, 6, 96).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xffd76a, transparent: true, opacity: 0.7 }));
    ring.position.copy(this.center).y += 1.5;
    this.group.add(ring); this.ring = ring;
    this.buildArena();
    this.addMember(getCreature(entry.id), true);
    document.body.classList.add('in-run');
    g.ui.notify(`${BIOMES[biomeId].name}: survive ${RUN_LENGTH / 60} minutes, then defeat the boss. Open chests to find Siegelings!`, 'info');
    this.applyItems();
  }

  clear() {
    for (const e of this.enemies) this.disposeModel(e.model);
    for (const m of this.team) { this.disposeModel(m.model); for (const o of m.orbs || []) this.group.remove(o); if (m.auraMesh) this.group.remove(m.auraMesh); }
    for (const s of this.shots) this.group.remove(s.mesh);
    for (const h of this.hazards) this.group.remove(h.mesh);
    for (const c of this.chests) this.group.remove(c.mesh);
    for (const st of this.strikes || []) this.group.remove(st.mark, st.fill);
    if (this.ring) this.group.remove(this.ring);
    if (this.arena) { this.group.remove(this.arena); this.arena = null; }
    this.g.world.removeOwned(this); this.pads = []; this.tops = []; this.zones = []; this.movers = []; this.totems = []; this.strikes = [];
    this.enemies = []; this.team = []; this.shots = []; this.hazards = []; this.chests = []; this.gems = []; this.gemMesh.count = 0;
  }

  disposeModel(model) { this.g.scene.remove(model.root); if (model.dispose) model.dispose(); }

  end(victory) {
    const g = this.g, d = State.data;
    this.active = false;
    const coins = Math.floor((this.kills * 0.5 + this.time / 5 + (victory ? 150 : 0)) * (1 + 0.2 * this.item('charm')));
    State.addCoins(coins);
    State.addPlayerXP(Math.floor(this.kills / 3) + (victory ? 60 : 0));
    const joined = [];
    for (const m of this.team) {
      if (m.starter || State.isFull()) continue;
      const e = State.addCreature(m.baseDef.id, 1);
      if (e) joined.push(m.baseDef.displayName);
    }
    d.stats.runs = (d.stats.runs || 0) + 1;
    d.stats.bestTime = Math.max(d.stats.bestTime || 0, Math.floor(this.time));
    if (victory) d.stats.wins = (d.stats.wins || 0) + 1;
    d.stats.kills += this.kills;
    State.save();
    const summary = { victory, time: this.time, kills: this.kills, level: this.level, coins, joined, team: this.team.map((m) => ({ id: m.def.id, level: m.level })) };
    this.clear();
    document.body.classList.remove('in-run');
    const p = g.player;
    p.alive = true; p.maxHp = 100; p.hp = 100; p.speedMult = 1; p.damageTakenMult = 1; p.regen = undefined; p.avatar.root.rotation.x = 0;
    g.cam.dist = 9; g.cam.side = 1;
    p.teleport(g.base.homePosition(), g.base.homeYaw());
    g.cam.yaw = g.base.homeYaw() + Math.PI; g.cam.pitch = -0.2;
    g.ui.openRunResults(summary);
  }

  // ── team ─────────────────────────────────────────────────────
  addMember(def, starter = false) {
    const m = { def, baseDef: def, level: 1, starter, attack: attackFor(def), cd: rand(0.2, 0.8), pos: this.g.player.pos.clone(), t: Math.random() * 10, lunge: null };
    m.model = buildCreatureModel(def, { scale: 0.55 });
    this.g.scene.add(m.model.root);
    this.team.push(m);
    if (!starter) this.found.push(def.id);
    this.g.fx.burst(this.g.player.hitCenter(), ELEMENT_COLORS[def.element] || 0xffffff, 30, 7, 0.8, 3);
    return m;
  }

  levelMember(m) {
    m.level++;
    // evolve along the TCG line at levels 3 and 6
    if ((m.level === 3 || m.level === 6) && m.def.evolvesTo && getCreature(m.def.evolvesTo)) {
      const next = getCreature(m.def.evolvesTo);
      this.disposeModel(m.model);
      m.def = next;
      m.model = buildCreatureModel(next, { scale: 0.55 });
      this.g.scene.add(m.model.root);
      this.g.ui.notify(`${m.baseDef.displayName} evolved into ${next.displayName}!`, 'good');
      this.g.fx.ring(m.pos, ELEMENT_COLORS[next.element] || 0xffffff, 8, 1);
    }
  }

  memberStats(m) {
    const a = m.attack, evo = m.def !== m.baseDef ? (getCreature(m.baseDef.evolvesTo) === m.def ? 1.35 : 1.8) : 1;
    return {
      dmg: a.dmg * (1 + 0.25 * (m.level - 1)) * evo * (1 + 0.1 * this.item('banner')) * (1 + 0.25 * this.item(`core_${a.element}`)) * (a.element === 'Neutral' ? 1.2 : 1),
      cd: a.cd * Math.pow(0.96, m.level - 1) / (1 + 0.12 * this.item('swiftclaw')),
      count: a.count + Math.floor((m.level - 1) / 3),
      area: a.area * (1 + 0.12 * this.item('seal')) * (1 + 0.04 * (m.level - 1)),
    };
  }

  applyItems() {
    const p = this.g.player;
    const maxHp = 100 + 20 * this.item('heartroot');
    if (maxHp > p.maxHp) p.hp += maxHp - p.maxHp;
    p.maxHp = maxHp;
    this.baseSpeed = 1 + 0.08 * this.item('boots');
    p.speedMult = this.baseSpeed;
    p.damageTakenMult = 1 - 0.08 * this.item('plate');
    p.regen = 0.6 * this.item('moss');
  }

  // ── choices (level-ups and chests) ───────────────────────────
  upgradeOptions() {
    const opts = [];
    for (const m of this.team) {
      if (m.level >= MAX_MEMBER_LEVEL) continue;
      const evo = (m.level + 1 === 3 || m.level + 1 === 6) && m.def.evolvesTo && getCreature(m.def.evolvesTo);
      opts.push({
        img: m.def.art, title: `${m.def.displayName} → Lv ${m.level + 1}`, tag: 'Upgrade',
        desc: evo ? `Evolves into ${getCreature(m.def.evolvesTo).displayName}! Much stronger ${m.attack.name}.` : `${m.attack.name}: +25% damage, faster${(m.level % 3 === 0) ? ', +1 projectile' : ''}`,
        pick: () => this.levelMember(m),
      });
    }
    const teamEls = new Set(this.team.map((m) => m.attack.element));
    for (const it of ITEMS) {
      const l = this.item(it.id);
      if (l >= MAX_ITEM_LEVEL || (!l && this.itemCount >= MAX_ITEMS)) continue;
      if (it.element && !teamEls.has(it.element)) continue;
      opts.push({ icon: it.icon, title: l ? `${it.name} Lv ${l + 1}` : it.name, tag: l ? 'Item upgrade' : 'New item', desc: it.desc(l + 1), pick: () => { this.items[it.id] = l + 1; this.applyItems(); } });
    }
    return opts;
  }

  pickN(arr, n) {
    const a = [...arr], out = [];
    while (a.length && out.length < n) out.push(a.splice(Math.floor(Math.random() * a.length), 1)[0]);
    return out;
  }

  offerLevelUp() {
    let opts = this.pickN(this.upgradeOptions(), 3);
    if (!opts.length) opts = [{ icon: '💚', title: 'Second Wind', tag: 'Heal', desc: 'Restore 30 HP', pick: () => { this.g.player.hp = Math.min(this.g.player.maxHp, this.g.player.hp + 30); } }];
    this.g.ui.openRunChoice(`Level ${this.level}! Choose one`, opts);
  }

  offerChest(better = false) {
    let opts = [];
    if (this.team.length < MAX_TEAM) {
      const usedKinds = new Set(this.team.map((m) => m.attack.kind));
      const usedIds = new Set(this.team.map((m) => m.baseDef.id));
      const stageEls = BIOMES[this.biome].elements;
      const t = this.time / RUN_LENGTH;
      const w = better ? { Common: 0, Uncommon: 12, Rare: 45, Epic: 32, Legendary: 6 } : { Common: 60 - 30 * t, Uncommon: 28, Rare: 8 + 14 * t, Epic: 2 + 8 * t, Legendary: t > 0.6 ? 2 : 0 };
      const cands = Creatures.filter((c) => (better ? RARITY_DMG[c.rarity] >= 1.2 : !c.evolvesFrom) && c.art && !usedIds.has(c.id) && !usedKinds.has(attackFor(c).kind));
      const taken = new Set();
      for (let i = 0; i < (better ? 2 : 3) && cands.length; i++) {
        let total = 0;
        const ws = cands.map((c) => { const v = taken.has(attackFor(c).kind) || taken.has(c.id) ? 0 : (w[c.rarity] || 1) * (stageEls.includes(c.element) ? 3 : 1); total += v; return v; });
        if (total <= 0) break;
        let r = Math.random() * total, idx = 0;
        while ((r -= ws[idx]) > 0) idx++;
        const c = cands[idx]; taken.add(c.id); taken.add(attackFor(c).kind);
        const a = attackFor(c);
        opts.push({ img: c.art, title: c.displayName, tag: `${c.rarity} · ${c.element} · joins your team`, rarity: c.rarity, desc: `${a.name}: ${a.desc}`, pick: () => this.addMember(c) });
      }
    }
    if (better) {
      // totem rewards: double upgrades alongside the rarer recruits
      const big = [];
      for (const m of this.team) if (m.level < MAX_MEMBER_LEVEL) big.push({ img: m.def.art, title: `${m.def.displayName} +2 levels`, tag: 'Greater upgrade', desc: `${m.attack.name} grows two levels at once.`, pick: () => { for (let k = 0; k < 2 && m.level < MAX_MEMBER_LEVEL; k++) this.levelMember(m); } });
      for (const it of ITEMS) { const l = this.item(it.id); if (l > 0 && l < MAX_ITEM_LEVEL) big.push({ icon: it.icon, title: `${it.name} +2 levels`, tag: 'Greater upgrade', desc: it.desc(Math.min(MAX_ITEM_LEVEL, l + 2)), pick: () => { this.items[it.id] = Math.min(MAX_ITEM_LEVEL, l + 2); this.applyItems(); } }); }
      opts = opts.concat(this.pickN(big, 3 - opts.length));
      this.g.player.hp = Math.min(this.g.player.maxHp, this.g.player.hp + 25);
    }
    if (opts.length < 3) opts = opts.concat(this.pickN(this.upgradeOptions(), 3 - opts.length));
    if (!opts.length) return;
    this.g.ui.openRunChoice(better ? 'Totem claimed! Choose a greater reward' : this.team.length < MAX_TEAM ? 'Chest opened! A Siegeling wants to join' : 'Chest opened! Choose a reward', opts);
  }

  // ── enemies ──────────────────────────────────────────────────
  spawnEnemy(tier = 'normal') {
    const els = BIOMES[this.biome].elements;
    let pool;
    if (tier === 'boss') pool = creaturesForElements(els, 'boss').filter((c) => c.rarity === 'Legendary');
    else if (tier === 'elite') pool = Creatures.filter((c) => els.includes(c.element) && (c.rarity === 'Rare' || c.rarity === 'Epic'));
    else pool = Creatures.filter((c) => els.includes(c.element) && (c.rarity === 'Common' || (c.rarity === 'Uncommon' && this.time > 60)));
    if (!pool || !pool.length) pool = Creatures.filter((c) => (tier === 'boss' ? c.rarity === 'Legendary' : tier === 'elite' ? c.rarity === 'Rare' : c.rarity === 'Common'));
    const def = pick(pool);
    const p = this.g.player.pos;
    let x, z;
    for (let i = 0; i < 8; i++) {
      const a = Math.random() * Math.PI * 2, r = rand(48, 62);
      x = p.x + Math.cos(a) * r; z = p.z + Math.sin(a) * r;
      if (Math.hypot(x - this.center.x, z - this.center.z) < this.R + 25) break;
    }
    const k = 1 + this.time / 60 * 0.55;
    const mult = tier === 'boss' ? 140 : tier === 'elite' ? 14 : def.rarity === 'Uncommon' ? 1.6 : 1;
    const e = {
      def, tier, isBoss: tier === 'boss', isRaider: true, fainted: false,
      pos: new THREE.Vector3(x, 0, z), hp: 14 * k * mult, speed: (tier === 'boss' ? 9.5 : tier === 'elite' ? 8 : rand(6.5, 9.5)) + Math.min(3, this.time / 120),
      dmg: (4 + this.time / 50) * (tier === 'boss' ? 3 : tier === 'elite' ? 1.8 : 1), hitCD: 0, st: {}, t: Math.random() * 10,
    };
    e.maxHp = e.hp;
    e.model = buildCreatureModel(def, { scale: tier === 'boss' ? 1.5 : tier === 'elite' ? 1.15 : 0.8 });
    e.r = Math.max(1, e.model.radius * 0.7);
    this.g.scene.add(e.model.root);
    this.enemies.push(e);
    return e;
  }

  nearest(pos, range = 60, skip = null) {
    let best = null, bd = range * range;
    for (const e of this.enemies) {
      if (skip && skip.has(e)) continue;
      const d = (e.pos.x - pos.x) ** 2 + (e.pos.z - pos.z) ** 2;
      if (d < bd) { bd = d; best = e; }
    }
    return best;
  }
  inRadius(pos, r) {
    const out = [];
    for (const e of this.enemies) if ((e.pos.x - pos.x) ** 2 + (e.pos.z - pos.z) ** 2 < (r + e.r) ** 2) out.push(e);
    return out;
  }

  hit(e, base, m, secondary = false) {
    if (e.hp <= 0) return;
    const el = m.attack.element, p = this.g.player;
    let dmg = base;
    if ((BEATS[el] || []).includes(e.def.element)) dmg *= 1.5;
    if (e.st.shred > 0) dmg *= 1.25;
    const crit = Math.random() < 0.05 + 0.08 * this.item('fang') + (el === 'Shadow' ? 0.15 : 0);
    if (crit) dmg *= 2;
    e.hp -= dmg;
    e.flash = 0.12;
    if (!secondary) {
      switch (el) {
        case 'Fire': e.st.burn = 3; e.st.burnDps = Math.max(e.st.burnDps || 0, base * 0.3); e.st.src = m; break;
        case 'Ice': e.st.slow = 2; break;
        case 'Wind': this.push(e, 4); break;
        case 'Earth': if (Math.random() < 0.15 && !e.isBoss) e.st.stun = 0.8; break;
        case 'Water': for (const o of this.inRadius(e.pos, 4)) if (o !== e) this.hit(o, base * 0.3, m, true); break;
        case 'Lightning': if (Math.random() < 0.25) { const o = this.nearest(e.pos, 12, new Set([e])); if (o) { this.zap(e.pos, o.pos, 0xffe63c); this.hit(o, base * 0.5, m, true); } } break;
        case 'Metal': e.st.shred = 3; break;
        case 'Poison': e.st.poison = 4; e.st.poisonStacks = Math.min(5, (e.st.poisonStacks || 0) + 1); e.st.poisonDps = base * 0.08; e.st.src = m; break;
        case 'Psychic': e.st.weak = 3; break;
        case 'Undead': p.hp = Math.min(p.maxHp, p.hp + dmg * 0.02); break;
      }
    }
    if (crit && this.g.ui.floats.length < 24) this.g.ui.floatText(e.pos.clone().setY(e.pos.y + e.model.height), `${Math.round(dmg)}!`, '#ffd76a');
    if (e.hp <= 0) this.kill(e, el);
  }

  push(e, dist) {
    if (e.isBoss) return;
    const p = this.g.player.pos, dx = e.pos.x - p.x, dz = e.pos.z - p.z, d = Math.hypot(dx, dz) || 1;
    e.pos.x += (dx / d) * dist; e.pos.z += (dz / d) * dist;
  }

  kill(e, el) {
    const g = this.g;
    this.kills++;
    if (el === 'Light') g.player.hp = Math.min(g.player.maxHp, g.player.hp + 1);
    g.fx.burst(e.pos.clone().setY(e.pos.y + 1.5), ELEMENT_COLORS[e.def.element] || 0xffffff, e.tier === 'normal' ? 8 : 40, 6, 0.6, 2);
    const n = e.tier === 'boss' ? 40 : e.tier === 'elite' ? 10 : 1;
    for (let i = 0; i < n && this.gems.length < 480; i++) this.gems.push({ x: e.pos.x + rand(-1, 1) * Math.sqrt(n), z: e.pos.z + rand(-1, 1) * Math.sqrt(n), y: e.pos.y + 0.8, v: e.def.rarity === 'Uncommon' ? 2 : 1 });
    if (e.tier === 'elite') this.spawnChest(e.pos);
    this.disposeModel(e.model);
    this.enemies.splice(this.enemies.indexOf(e), 1);
    if (e.isBoss) { this.won = true; g.ui.notify(`${e.def.displayName} defeated!`, 'good'); }
  }

  spawnChest(at = null) {
    if (this.chests.length >= 6) return;
    const p = this.g.player.pos;
    let x, z;
    if (!at && this.tops.length && Math.random() < 0.45) { const t = pick(this.tops); at = { x: t.x, z: t.z }; } // high-ground chest
    if (at) { x = at.x; z = at.z; } else {
      const a = Math.random() * Math.PI * 2, r = rand(22, 38);
      x = p.x + Math.cos(a) * r; z = p.z + Math.sin(a) * r;
      const dc = Math.hypot(x - this.center.x, z - this.center.z);
      if (dc > this.R - 8) { x = this.center.x + (x - this.center.x) * (this.R - 8) / dc; z = this.center.z + (z - this.center.z) * (this.R - 8) / dc; }
    }
    const mesh = new THREE.Group();
    const box = new THREE.Mesh(new THREE.BoxGeometry(2.6, 1.8, 1.8), new THREE.MeshLambertMaterial({ color: 0x8a5a2a }));
    box.position.y = 0.9; box.castShadow = true;
    const lid = new THREE.Mesh(new THREE.BoxGeometry(2.8, 0.5, 2), new THREE.MeshLambertMaterial({ color: 0xffd76a, emissive: 0x4a3a00 }));
    lid.position.y = 2;
    const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.5, 40, 8, 1, true), new THREE.MeshBasicMaterial({ color: 0xffd76a, transparent: true, opacity: 0.25, depthWrite: false }));
    beam.position.y = 20;
    mesh.add(box, lid, beam);
    mesh.position.set(x, this.g.world.groundAt(x, z), z);
    this.group.add(mesh);
    this.chests.push({ mesh, pos: mesh.position, lid, open: 0 });
  }

  zap(a, b, color) {
    const n = 6;
    for (let i = 0; i <= n; i++) this.g.fx.burst(new THREE.Vector3().lerpVectors(a, b, i / n).setY(a.y + 1.5 + rand(-0.4, 0.4)), color, 1, 0.5, 0.25, 0);
  }

  shoot(m, from, dir, opt) {
    const color = ELEMENT_COLORS[m.attack.element] || 0xffffff;
    const mesh = new THREE.Mesh(this.g.fx.projGeo, this.g.fx.projMat(color));
    mesh.scale.setScalar(opt.size || 1);
    mesh.position.copy(from);
    this.group.add(mesh);
    this.shots.push({ mesh, m, vel: dir.clone().setY(0).normalize().multiplyScalar(opt.speed || 45), life: opt.life || 1.6, dmg: opt.dmg, pierce: opt.pierce || 0, r: (opt.size || 1) * 0.6 + 0.4, target: opt.target || null, boomerang: opt.boomerang || false, hit: new Set(), age: 0, color });
  }

  // ── attacks ──────────────────────────────────────────────────
  fire(m) {
    const g = this.g, a = m.attack, s = this.memberStats(m), p = g.player.pos;
    const color = ELEMENT_COLORS[a.element] || 0xffffff;
    const from = m.pos.clone().setY(m.pos.y + 1.6);
    const target = this.nearest(a.kind === 'slam' ? m.pos : p, 55);
    const needsTarget = !['orbit', 'aura', 'nova', 'mines', 'rain', 'mend'].includes(a.kind);
    if (needsTarget && !target) return false;
    const toT = target ? target.pos.clone().sub(m.pos).setY(0) : null;
    switch (a.kind) {
      case 'bolt': {
        const skip = new Set();
        for (let i = 0; i < s.count; i++) { const t = this.nearest(p, 55, skip) || target; skip.add(t); this.shoot(m, from, t.pos.clone().sub(m.pos), { dmg: s.dmg, target: t, speed: 50 }); }
        break;
      }
      case 'spread': {
        const base = Math.atan2(toT.x, toT.z);
        for (let i = 0; i < s.count; i++) { const ang = base + (i - (s.count - 1) / 2) * 0.22; this.shoot(m, from, new THREE.Vector3(Math.sin(ang), 0, Math.cos(ang)), { dmg: s.dmg, speed: 55, pierce: 1, life: 1 }); }
        break;
      }
      case 'slam': {
        if (toT.length() > 14) return false;
        const r = 7 * s.area;
        m.lunge = { to: target.pos.clone(), t: 0.3 };
        g.fx.ring(target.pos, color, r, 0.45);
        for (const e of this.inRadius(target.pos, r)) this.hit(e, s.dmg, m);
        break;
      }
      case 'dash': {
        const dir = toT.clone().normalize(), len = Math.min(26, toT.length() + 8);
        const end = m.pos.clone().addScaledVector(dir, len);
        m.lunge = { to: end, t: 0.35 };
        for (const e of [...this.enemies]) {
          const rel = e.pos.clone().sub(m.pos).setY(0), along = clamp(rel.dot(dir), 0, len);
          if (rel.addScaledVector(dir, -along).length() < 2.6 * s.area + e.r) this.hit(e, s.dmg, m);
        }
        this.zap(m.pos, end, color);
        break;
      }
      case 'beam': {
        const dir = toT.clone().normalize(), len = 42;
        const beam = new THREE.Mesh(new THREE.BoxGeometry(1.2 * s.area, 0.5, len), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.85, depthWrite: false }));
        beam.position.copy(from).addScaledVector(dir, len / 2);
        beam.rotation.y = Math.atan2(dir.x, dir.z);
        this.group.add(beam);
        g.fx.tween(0.25, (t) => { beam.material.opacity = 0.85 * (1 - t); beam.scale.x = 1 - t * 0.7; }, () => { this.group.remove(beam); beam.geometry.dispose(); beam.material.dispose(); });
        for (const e of [...this.enemies]) {
          const rel = e.pos.clone().sub(m.pos).setY(0), along = rel.dot(dir);
          if (along > 0 && along < len && rel.addScaledVector(dir, -along).length() < 1.6 * s.area + e.r) this.hit(e, s.dmg, m);
        }
        break;
      }
      case 'nova': {
        const r = 15 * s.area;
        g.fx.ring(p, color, r, 0.6);
        for (const e of this.inRadius(p, r)) { this.hit(e, s.dmg, m); if (e.hp > 0) this.push(e, 2.5); }
        break;
      }
      case 'mortar': {
        const skip = new Set();
        for (let i = 0; i < s.count; i++) {
          const t = i === 0 ? target : (this.enemies.length ? pick(this.enemies) : target);
          if (skip.has(t)) continue; skip.add(t);
          const at = t.pos.clone(), r = 6 * s.area;
          const mark = new THREE.Mesh(new THREE.RingGeometry(r - 0.4, r, 28).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.7, side: THREE.DoubleSide, depthWrite: false }));
          mark.position.copy(at).y += 0.3;
          this.group.add(mark);
          g.fx.tween(0.7, () => {}, () => {
            this.group.remove(mark); mark.geometry.dispose(); mark.material.dispose();
            if (!this.active) return;
            g.fx.burst(at.clone().setY(at.y + 1), color, 26, 9, 0.6, 3);
            for (const e of this.inRadius(at, r)) this.hit(e, s.dmg, m);
          });
        }
        break;
      }
      case 'chain': {
        const seen = new Set(); let cur = target, prev = from;
        for (let i = 0; i < s.count && cur; i++) {
          seen.add(cur); this.zap(prev, cur.pos, color);
          const next = this.nearest(cur.pos, 14 * s.area, seen);
          prev = cur.pos.clone(); this.hit(cur, s.dmg * Math.pow(0.85, i), m); cur = next;
        }
        break;
      }
      case 'aura': { for (const e of this.inRadius(p, 9 * s.area)) this.hit(e, s.dmg, m); break; }
      case 'boomerang': {
        const base = Math.atan2(toT.x, toT.z);
        for (let i = 0; i < s.count; i++) { const ang = base + (i - (s.count - 1) / 2) * 0.5; this.shoot(m, from, new THREE.Vector3(Math.sin(ang), 0, Math.cos(ang)), { dmg: s.dmg, speed: 38, pierce: 99, life: 1.5, size: 1.6 * s.area, boomerang: true }); }
        break;
      }
      case 'mines': {
        if (this.hazards.length > 14) return false;
        const mesh = new THREE.Mesh(new THREE.OctahedronGeometry(0.9, 0), new THREE.MeshBasicMaterial({ color }));
        mesh.position.copy(p).y += 0.9;
        this.group.add(mesh);
        this.hazards.push({ mesh, pos: mesh.position, life: 12, r: 5.5 * s.area, dmg: s.dmg, m, arm: 0.5 });
        break;
      }
      case 'rain': {
        const a2 = Math.random() * Math.PI * 2, rr = Math.sqrt(Math.random()) * 26;
        const t = Math.random() < 0.6 && target ? target.pos : new THREE.Vector3(p.x + Math.cos(a2) * rr, p.y, p.z + Math.sin(a2) * rr);
        const at = t.clone(); at.y = g.world.groundAt(at.x, at.z);
        for (let i = 0; i < 5; i++) g.fx.burst(at.clone().setY(at.y + i * 2.5), color, 3, 2, 0.35, 0);
        g.fx.ring(at, color, 4 * s.area, 0.3);
        for (const e of this.inRadius(at, 4.5 * s.area)) this.hit(e, s.dmg, m);
        break;
      }
      case 'cone': {
        const dir = toT.clone().normalize(), range = 17 * s.area;
        if (toT.length() > range + 4) return false;
        for (let i = 0; i < 16; i++) { const ang = Math.atan2(dir.x, dir.z) + rand(-0.5, 0.5), d = rand(2, range); g.fx.burst(new THREE.Vector3(m.pos.x + Math.sin(ang) * d, m.pos.y + 1.4, m.pos.z + Math.cos(ang) * d), color, 1, 2, 0.4, 0.5); }
        for (const e of [...this.enemies]) {
          const rel = e.pos.clone().sub(m.pos).setY(0), d = rel.length();
          if (d < range + e.r && rel.normalize().dot(dir) > 0.8) this.hit(e, s.dmg, m);
        }
        break;
      }
      case 'mend': {
        const pl = g.player;
        pl.hp = Math.min(pl.maxHp, pl.hp + 6 + 2 * m.level);
        g.fx.ring(p, 0x8affd8, 10 * s.area, 0.6);
        g.fx.burst(pl.hitCenter(), 0x8affd8, 14, 4, 0.7, 3);
        for (const e of this.inRadius(p, 10 * s.area)) { this.hit(e, s.dmg, m); if (e.hp > 0) this.push(e, 6); }
        break;
      }
    }
    return true;
  }

  updateOrbit(m, dt) {
    const s = this.memberStats(m), p = this.g.player.pos, color = ELEMENT_COLORS[m.attack.element] || 0xffffff;
    m.orbs = m.orbs || [];
    while (m.orbs.length < s.count) { const o = new THREE.Mesh(this.g.fx.projGeo, this.g.fx.projMat(color)); o.scale.setScalar(2); o.userData.cd = new Map(); this.group.add(o); m.orbs.push(o); }
    m.orbs.forEach((o, i) => {
      const ang = m.t * 2.6 + (i / m.orbs.length) * Math.PI * 2, r = 8.5 * s.area;
      o.position.set(p.x + Math.cos(ang) * r, p.y + 2, p.z + Math.sin(ang) * r);
      for (const e of this.inRadius(o.position, 1.6)) {
        const last = o.userData.cd.get(e) || -9;
        if (this.time - last > m.attack.cd * 1.4) { o.userData.cd.set(e, this.time); this.hit(e, s.dmg, m); }
      }
      if (o.userData.cd.size > 200) o.userData.cd.clear();
    });
  }

  // ── frame update ─────────────────────────────────────────────
  update(dt) {
    if (!this.active) return;
    const g = this.g, p = g.player, pp = p.pos;
    if (!p.alive) return this.end(false);
    if (this.won) return this.end(true);
    this.time += dt;

    // jump pads launch you onto the high ground
    for (const pad of this.pads) {
      pad.mesh.children[1].rotation.y += dt * 3;
      if (p.onGround && Math.hypot(pp.x - pad.x, pp.z - pad.z) < 2.6 && Math.abs(pp.y - pad.y) < 2) {
        p.vel.y = 46; p.onGround = false; pp.y += 0.7;
        g.fx.ring(new THREE.Vector3(pad.x, pad.y, pad.z), 0x6fd8ff, 6, 0.5);
      }
    }
    // keep the player inside the arena
    const dc = Math.hypot(pp.x - this.center.x, pp.z - this.center.z);
    if (dc > this.R) { pp.x = this.center.x + (pp.x - this.center.x) * this.R / dc; pp.z = this.center.z + (pp.z - this.center.z) * this.R / dc; }

    // spawning
    const rate = this.bossSpawned ? 2.2 : 0.9 + this.time / 40;
    this.spawnAcc += dt * rate;
    while (this.spawnAcc >= 1) { this.spawnAcc -= 1; if (this.enemies.length < (g.ctx.touch ? 90 : 150)) this.spawnEnemy(); }
    if (this.time >= this.eliteAt && !this.bossSpawned) { this.eliteAt += 45; this.spawnEnemy('elite'); g.ui.notify('An elite Siegeling appears — defeat it for a chest!', 'warn'); }
    if (this.time >= this.chestAt) { this.chestAt += 30; this.spawnChest(); }
    if (this.time >= RUN_LENGTH && !this.bossSpawned) { this.bossSpawned = true; this.boss = this.spawnEnemy('boss'); g.ui.notify(`⚠️ Boss: ${this.boss.def.displayName}!`, 'bad'); }

    // enemies: chase, separate, contact damage, status effects
    const grid = new Map();
    for (const e of this.enemies) { const k = `${Math.floor(e.pos.x / 4)},${Math.floor(e.pos.z / 4)}`; (grid.get(k) || grid.set(k, []).get(k)).push(e); }
    for (const e of [...this.enemies]) {
      const st = e.st;
      if (st.burn > 0) { st.burn -= dt; e.hp -= st.burnDps * dt; }
      if (st.poison > 0) { st.poison -= dt; e.hp -= st.poisonDps * st.poisonStacks * dt; if (st.poison <= 0) st.poisonStacks = 0; }
      for (const k of ['slow', 'stun', 'shred', 'weak']) if (st[k] > 0) st[k] -= dt;
      if (e.hp <= 0) { this.kill(e, st.src ? st.src.attack.element : null); continue; }
      const dx = pp.x - e.pos.x, dz = pp.z - e.pos.z, d = Math.hypot(dx, dz) || 1;
      let sp = st.stun > 0 ? 0 : e.speed * (st.slow > 0 ? 0.5 : 1);
      if (d > 110) { this.disposeModel(e.model); this.enemies.splice(this.enemies.indexOf(e), 1); continue; }
      if (e.climbing) sp *= 0.3;
      if (d > e.r + 1.2) { e.pos.x += (dx / d) * sp * dt; e.pos.z += (dz / d) * sp * dt; } else sp = 0;
      const cell = grid.get(`${Math.floor(e.pos.x / 4)},${Math.floor(e.pos.z / 4)}`);
      if (cell) for (const o of cell) {
        if (o === e) continue;
        const ox = e.pos.x - o.pos.x, oz = e.pos.z - o.pos.z, od = Math.hypot(ox, oz), min = (e.r + o.r) * 0.8;
        if (od < min && od > 0.001) { const f = (min - od) * 0.5 / od; e.pos.x += ox * f; e.pos.z += oz * f; }
      }
      // enemies scale ledges instead of walking through them: slow climb up, quick drop down
      const gy = g.world.groundAt(e.pos.x, e.pos.z);
      if (gy > e.pos.y + 1.5) e.climbing = true;
      if (e.climbing) { e.pos.y = Math.min(gy, e.pos.y + (e.def.flying ? 14 : 6.5) * dt); if (e.pos.y >= gy) e.climbing = false; }
      else e.pos.y = Math.max(gy, e.pos.y - 40 * dt);
      e.hitCD -= dt;
      if (d < e.r + 2 && e.hitCD <= 0 && Math.abs(pp.y - e.pos.y) < 4) { e.hitCD = 0.8; p.takeDamage(e.dmg * (st.weak > 0 ? 0.6 : 1)); }
      e.t += dt;
      e.model.root.position.copy(e.pos);
      e.model.root.rotation.y = Math.atan2(dx, dz);
      e.model.animate(e.t, sp);
      if (e.model.sprite) {
        if (e.flash > 0) { e.flash -= dt; e.model.sprite.material.color.setRGB(2.2, 2.2, 2.2); if (e.flash <= 0) e.model.applyColor(); }
      }
    }

    // team: formation around the player + attacks
    const n = this.team.length;
    this.team.forEach((m, i) => {
      m.t += dt;
      const ang = (i / Math.max(1, n)) * Math.PI * 2 + this.time * 0.25;
      const home = new THREE.Vector3(pp.x + Math.cos(ang) * 4.5, 0, pp.z + Math.sin(ang) * 4.5);
      let speed = 0;
      if (m.lunge) {
        m.lunge.t -= dt;
        m.pos.lerp(m.lunge.to, Math.min(1, dt * 14)); speed = 12;
        if (m.lunge.t <= 0) m.lunge = null;
      } else {
        const d = Math.hypot(home.x - m.pos.x, home.z - m.pos.z);
        m.pos.x += (home.x - m.pos.x) * Math.min(1, dt * 7); m.pos.z += (home.z - m.pos.z) * Math.min(1, dt * 7);
        speed = Math.min(16, d * 7);
      }
      m.pos.y = g.world.groundAt(m.pos.x, m.pos.z, pp.y + 2);
      m.model.root.position.copy(m.pos);
      m.model.root.rotation.y = p.yaw;
      m.model.animate(m.t, speed);
      if (m.attack.kind === 'orbit') return this.updateOrbit(m, dt);
      if (m.attack.kind === 'aura') {
        const s = this.memberStats(m);
        if (!m.auraMesh) { m.auraMesh = new THREE.Mesh(new THREE.RingGeometry(0.92, 1, 48).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: ELEMENT_COLORS[m.attack.element] || 0xffffff, transparent: true, opacity: 0.5, side: THREE.DoubleSide, depthWrite: false })); this.group.add(m.auraMesh); }
        m.auraMesh.position.copy(pp).y += 0.4; m.auraMesh.scale.setScalar(9 * s.area);
      }
      m.cd -= dt;
      if (m.cd <= 0) m.cd = this.fire(m) ? this.memberStats(m).cd : 0.2;
    });

    // projectiles
    for (let i = this.shots.length - 1; i >= 0; i--) {
      const s = this.shots[i];
      s.age += dt; s.life -= dt;
      if (s.target && s.target.hp > 0) { const want = s.target.pos.clone().sub(s.mesh.position).setY(0).normalize().multiplyScalar(s.vel.length()); s.vel.lerp(want, Math.min(1, dt * 10)); }
      if (s.boomerang && s.age > 0.6 && !s.back) { s.back = true; s.hit.clear(); }
      if (s.back) { const want = pp.clone().sub(s.mesh.position).setY(0).normalize().multiplyScalar(48); s.vel.lerp(want, Math.min(1, dt * 8)); if (s.mesh.position.distanceTo(pp) < 3) s.life = 0; else s.life = Math.max(s.life, 0.1); if (s.age > 4) s.life = 0; }
      s.mesh.position.addScaledVector(s.vel, dt);
      s.mesh.position.y = g.world.groundAt(s.mesh.position.x, s.mesh.position.z, s.mesh.position.y + 3) + 1.6;
      if (s.boomerang) s.mesh.rotation.y += dt * 14;
      let dead = s.life <= 0;
      if (!dead) for (const e of this.inRadius(s.mesh.position, s.r)) {
        if (s.hit.has(e)) continue;
        s.hit.add(e); this.hit(e, s.dmg, s.m);
        if (s.pierce-- <= 0) { dead = true; break; }
      }
      if (dead) { g.fx.burst(s.mesh.position, s.color, 5, 3, 0.3, 1); this.group.remove(s.mesh); this.shots.splice(i, 1); }
    }

    // traps
    for (let i = this.hazards.length - 1; i >= 0; i--) {
      const h = this.hazards[i];
      h.life -= dt; h.arm -= dt; h.mesh.rotation.y += dt * 3;
      const trig = h.arm <= 0 && this.inRadius(h.pos, 2).length > 0;
      if (trig) { g.fx.ring(h.pos, h.mesh.material.color.getHex(), h.r, 0.4); g.fx.burst(h.pos, h.mesh.material.color.getHex(), 20, 8, 0.5, 2); for (const e of this.inRadius(h.pos, h.r)) this.hit(e, h.dmg, h.m); }
      if (trig || h.life <= 0) { this.group.remove(h.mesh); h.mesh.geometry.dispose(); this.hazards.splice(i, 1); }
    }

    // XP gems
    const pick2 = (7 * (1 + 0.3 * this.item('lodestone'))) ** 2;
    const mat = new THREE.Matrix4();
    for (let i = this.gems.length - 1; i >= 0; i--) {
      const gm = this.gems[i];
      const dx = pp.x - gm.x, dz = pp.z - gm.z, d2 = dx * dx + dz * dz;
      if (d2 < pick2 || gm.pull) { gm.pull = true; const d = Math.sqrt(d2) || 1; gm.x += (dx / d) * 40 * dt; gm.z += (dz / d) * 40 * dt; }
      if (d2 < 3) { this.gems.splice(i, 1); this.gainXP(gm.v); }
    }
    this.gems.forEach((gm, i) => { mat.makeTranslation(gm.x, gm.y + Math.sin(this.time * 4 + i) * 0.2, gm.z); this.gemMesh.setMatrixAt(i, mat); });
    this.gemMesh.count = this.gems.length;
    this.gemMesh.instanceMatrix.needsUpdate = true;

    // chests open the moment you touch them
    for (let i = this.chests.length - 1; i >= 0; i--) {
      const c = this.chests[i];
      if (Math.hypot(pp.x - c.pos.x, pp.z - c.pos.z) < 3.4 && Math.abs(pp.y - c.pos.y) < 3) {
        this.group.remove(c.mesh); this.chests.splice(i, 1); this.pendingChests++;
        g.fx.burst(c.pos.clone().setY(c.pos.y + 2), 0xffd76a, 40, 9, 0.9, 5);
      }
    }
    // totems: hold your ground beside one to claim better loot
    let prog = 0;
    for (const t of this.totems) {
      if (t.done) continue;
      const near = Math.hypot(pp.x - t.x, pp.z - t.z) < t.r && Math.abs(pp.y - t.y) < 4;
      t.charge = near ? t.charge + dt : Math.max(0, t.charge - dt * 0.5);
      t.gem.rotation.y += dt * (1 + t.charge * 2); t.gem.position.y = 9 + Math.sin(this.time * 2) * 0.4;
      t.ring.material.opacity = 0.35 + 0.5 * (t.charge / TOTEM_TIME);
      prog = Math.max(prog, t.charge / TOTEM_TIME);
      if (t.charge >= TOTEM_TIME) {
        t.done = true; this.pendingTotems++;
        t.gem.visible = false; t.ring.visible = false;
        g.fx.ring(new THREE.Vector3(t.x, t.y, t.z), 0xc9a6ff, 14, 1); g.fx.burst(new THREE.Vector3(t.x, t.y + 8, t.z), 0xc9a6ff, 70, 12, 1.2, 6);
      }
    }
    this.chestProgress = prog;
    this.updateHazards(dt);

    if (!g.ui.open) {
      if (this.pendingTotems > 0) { this.pendingTotems--; this.offerChest(true); }
      else if (this.pendingChests > 0) { this.pendingChests--; this.offerChest(); }
      else if (this.pendingLevels > 0) { this.pendingLevels--; this.offerLevelUp(); }
    }
  }

  // Vertical level design: tiered plateaus (each tier is one jump high), a tall spire, and jump pads.
  buildArena() {
    const g = this.g, w = g.world, rng = mulberry32(hashStr(this.biome) + 7);
    const base = new THREE.Color(BIOMES[this.biome].color);
    const wallMat = new THREE.MeshLambertMaterial({ color: base.clone().lerp(new THREE.Color(0x4a4458), 0.6).multiplyScalar(0.8), flatShading: true });
    const topMat = new THREE.MeshLambertMaterial({ color: base.clone().lerp(new THREE.Color(0xffe9b0), 0.55) });
    const arena = new THREE.Group();
    this.arena = arena; this.pads = []; this.tops = [];
    const TIER = 3.6; // just under jump height (about 4)
    const addTier = (x, z, rot, size, bottom, top) => {
      const h = top - bottom + 8; // extends below ground on slopes
      const m = new THREE.Mesh(new THREE.BoxGeometry(size, h, size), wallMat);
      m.position.set(x, top - h / 2, z); m.rotation.y = -rot; m.castShadow = true; m.receiveShadow = true;
      const cap = new THREE.Mesh(new THREE.BoxGeometry(size + 0.6, 0.5, size + 0.6), topMat);
      cap.position.set(x, top - 0.24, z); cap.rotation.y = -rot; cap.receiveShadow = true;
      arena.add(m, cap);
      w.addBlock(x, z, rot, size + 0.6, size + 0.6, top, this);
    };
    const spots = [];
    const place = (minR, maxR, clear) => {
      for (let i = 0; i < 60; i++) {
        const a = rng() * Math.PI * 2, r = minR + rng() * (maxR - minR);
        const x = this.center.x + Math.cos(a) * r, z = this.center.z + Math.sin(a) * r;
        if (spots.every((s) => Math.hypot(s.x - x, s.z - z) > s.c + clear)) { spots.push({ x, z, c: clear }); return { x, z }; }
      }
      return null;
    };
    spots.push({ x: this.center.x, z: this.center.z, c: 12 }); // keep the start clear
    // tiered plateaus: 1 to 3 tiers, each tier reachable with a jump from the one below
    for (let i = 0; i < 18; i++) {
      const size = 20 + rng() * 12, p = place(26, this.R - 22, size * 0.75);
      if (!p) continue;
      const rot = rng() * Math.PI, gy = w.terrainHeight(p.x, p.z), tiers = 1 + Math.floor(rng() * 3);
      let s = size, ox = 0, oz = 0;
      for (let t = 1; t <= tiers; t++) {
        addTier(p.x + ox, p.z + oz, rot, s, gy, gy + TIER * t);
        if (t === tiers) this.tops.push({ x: p.x + ox, z: p.z + oz, y: gy + TIER * t });
        const inset = s * 0.2; s *= 0.6;
        const dx = (rng() - 0.5) * 2 * inset, dz = (rng() - 0.5) * 2 * inset; // offset upper tiers so they form steps
        ox += dx * Math.cos(rot) - dz * Math.sin(rot); oz += dx * Math.sin(rot) + dz * Math.cos(rot);
      }
    }
    // spires: too tall to jump, reached by the jump pad at their foot
    const padGeo = new THREE.CylinderGeometry(2.4, 2.7, 0.5, 20), arrowGeo = new THREE.ConeGeometry(0.9, 1.6, 4);
    const addPad = (x, z) => {
      const y = w.groundAt(x, z, w.terrainHeight(x, z) + 0.5);
      const mesh = new THREE.Group();
      mesh.add(new THREE.Mesh(padGeo, new THREE.MeshLambertMaterial({ color: 0x24324a })), new THREE.Mesh(arrowGeo, new THREE.MeshBasicMaterial({ color: 0x6fd8ff })));
      mesh.children[1].position.y = 1.6;
      mesh.position.set(x, y + 0.25, z);
      arena.add(mesh);
      this.pads.push({ x, z, y, mesh });
    };
    for (let i = 0; i < 5; i++) {
      const p = place(34, this.R - 30, 16);
      if (!p) continue;
      const gy = w.terrainHeight(p.x, p.z), top = gy + 13;
      addTier(p.x, p.z, rng() * Math.PI, 11, gy, top);
      this.tops.push({ x: p.x, z: p.z, y: top });
      const a = Math.atan2(this.center.z - p.z, this.center.x - p.x); // pad on the side facing the centre
      spots.push({ x: p.x + Math.cos(a) * 9.5, z: p.z + Math.sin(a) * 9.5, c: 4 });
      addPad(p.x + Math.cos(a) * 9.5, p.z + Math.sin(a) * 9.5);
    }
    for (let i = 0; i < 9; i++) { const p = place(18, this.R - 15, 6); if (p) addPad(p.x, p.z); }
    this.buildHazardsAndTotems(arena, place, rng);
    this.group.add(arena);
  }

  // A flat disc draped over the terrain.
  groundDisc(x, z, r, color, opacity, inner = 0) {
    const w = this.g.world, y0 = w.terrainHeight(x, z);
    const geo = inner ? new THREE.RingGeometry(inner, r, 28, 1) : new THREE.CircleGeometry(r, 24);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    for (let i = 0; i < pos.count; i++) pos.setY(i, w.terrainHeight(x + pos.getX(i), z + pos.getZ(i)) - y0 + 0.3);
    const m = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -2 }));
    m.position.set(x, y0, z);
    return m;
  }

  buildHazardsAndTotems(arena, place, rng) {
    const w = this.g.world, cfg = HAZARDS[this.biome] || {};
    const onGround = (p) => p && !w.blocks.some((b) => { // not on top of a plateau or spire
      const dx = p.x - b.cx, dz = p.z - b.cz;
      return Math.abs(dx * b.cos + dz * b.sin) < b.hx + 2 && Math.abs(-dx * b.sin + dz * b.cos) < b.hz + 2;
    });
    if (cfg.zone) for (let i = 0; i < cfg.zone.n; i++) {
      const r = 6 + rng() * 5, p = place(20, this.R - 10, r + 2);
      if (!onGround(p)) continue;
      const mesh = this.groundDisc(p.x, p.z, r, cfg.zone.color, 0.72);
      arena.add(this.groundDisc(p.x, p.z, r + 0.5, 0x000000, 0.35, r - 0.2)); // dark rim so the zone reads on any ground
      arena.add(mesh);
      this.zones.push({ ...cfg.zone, x: p.x, z: p.z, r, mesh });
    }
    if (cfg.mover) for (let i = 0; i < cfg.mover.n; i++) {
      const a = rng() * Math.PI * 2, r = 30 + rng() * (this.R - 45);
      const mesh = new THREE.Group();
      for (let k = 0; k < 4; k++) {
        const cone = new THREE.Mesh(new THREE.ConeGeometry(1.2 + k * 1.1, 3.4, 10, 1, true).rotateX(Math.PI), new THREE.MeshBasicMaterial({ color: cfg.mover.color, transparent: true, opacity: 0.38, side: THREE.DoubleSide, depthWrite: false }));
        cone.position.y = 1.7 + k * 3; mesh.add(cone);
      }
      arena.add(mesh);
      this.movers.push({ ...cfg.mover, x: this.center.x + Math.cos(a) * r, z: this.center.z + Math.sin(a) * r, dir: rng() * Math.PI * 2, mesh, cd: 0, tick: 0 });
    }
    // totems: 6 per arena, well away from the start
    for (let i = 0; i < 6; i++) {
      const p = place(55, this.R - 18, 16);
      if (!onGround(p)) continue;
      const y = w.terrainHeight(p.x, p.z);
      const mesh = new THREE.Group();
      const stone = new THREE.MeshLambertMaterial({ color: 0x4a3f5a, flatShading: true });
      const pillar = new THREE.Mesh(new THREE.CylinderGeometry(1.1, 1.6, 7, 6), stone); pillar.position.y = 3.5; pillar.castShadow = true;
      const head = new THREE.Mesh(new THREE.BoxGeometry(3.2, 1.2, 3.2), stone); head.position.y = 7.2;
      const gem = new THREE.Mesh(new THREE.OctahedronGeometry(1.1, 0), new THREE.MeshBasicMaterial({ color: 0xc9a6ff })); gem.position.y = 9;
      mesh.add(pillar, head, gem); mesh.position.set(p.x, y, p.z);
      const ring = this.groundDisc(p.x, p.z, 7.5, 0xc9a6ff, 0.35, 6.6);
      arena.add(mesh, ring);
      this.totems.push({ x: p.x, z: p.z, y, r: 7.5, charge: 0, done: false, gem, ring });
    }
  }

  updateHazards(dt) {
    const g = this.g, p = g.player, pp = p.pos, cfg = HAZARDS[this.biome] || {};
    const grounded = pp.y - g.world.terrainHeight(pp.x, pp.z) < 1.2; // jumping or standing on high ground avoids zones
    let slow = 1;
    if (grounded) for (const z of this.zones) {
      const dx = z.x - pp.x, dz = z.z - pp.z, d = Math.hypot(dx, dz);
      if (d > z.r) continue;
      if (z.slow) slow = Math.min(slow, z.slow);
      if (z.dps) this.hazAcc += z.dps * dt;
      if (z.pull && d > 0.5) { pp.x += (dx / d) * z.pull * dt; pp.z += (dz / d) * z.pull * dt; }
    }
    p.speedMult = this.baseSpeed * slow;
    this.hazTick += dt;
    if (this.hazTick >= 0.5) { this.hazTick = 0; if (this.hazAcc > 0) { p.takeDamage(this.hazAcc); this.hazAcc = 0; } }

    for (const m of this.movers) {
      m.dir += (Math.random() - 0.5) * dt * 2;
      m.x += Math.cos(m.dir) * 9 * dt; m.z += Math.sin(m.dir) * 9 * dt;
      const dc = Math.hypot(m.x - this.center.x, m.z - this.center.z);
      if (dc > this.R - 6) m.dir = Math.atan2(this.center.z - m.z, this.center.x - m.x);
      m.mesh.position.set(m.x, g.world.terrainHeight(m.x, m.z), m.z);
      m.mesh.children.forEach((c, k) => { c.rotation.y += dt * (9 - k); c.position.x = Math.sin(this.time * 3 + k) * 0.5 * k; });
      m.cd -= dt; m.tick -= dt;
      if (m.cd <= 0 && grounded && Math.hypot(pp.x - m.x, pp.z - m.z) < 5) { m.cd = 1.5; p.vel.y = 30; p.onGround = false; pp.y += 0.6; p.takeDamage(5); }
      if (m.tick <= 0) { m.tick = 0.4; for (const e of this.inRadius(new THREE.Vector3(m.x, 0, m.z), 5)) { this.hit(e, 6 + this.time / 20, this.env, true); if (e.hp > 0) this.push(e, 3); } }
    }

    // telegraphed strikes land near you: step out of the circle (and lure enemies into it)
    if (cfg.strike && this.time >= this.strikeAt) {
      this.strikeAt = this.time + cfg.strike.every * (0.7 + Math.random() * 0.6);
      const a = Math.random() * Math.PI * 2, d = Math.random() * 14;
      const x = pp.x + p.vel.x * 0.6 + Math.cos(a) * d, z = pp.z + p.vel.z * 0.6 + Math.sin(a) * d, r = 7;
      const y = g.world.groundAt(x, z);
      const mark = new THREE.Mesh(new THREE.RingGeometry(r - 0.5, r, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: cfg.strike.color, transparent: true, opacity: 0.9, side: THREE.DoubleSide, depthWrite: false }));
      const fill = new THREE.Mesh(new THREE.CircleGeometry(r, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: cfg.strike.color, transparent: true, opacity: 0.25, side: THREE.DoubleSide, depthWrite: false }));
      mark.position.set(x, y + 0.5, z); fill.position.set(x, y + 0.45, z); fill.scale.setScalar(0.05);
      this.group.add(mark, fill);
      this.strikes.push({ x, y, z, r, t: cfg.strike.delay || 1.3, max: cfg.strike.delay || 1.3, mark, fill, cfg: cfg.strike });
    }
    for (let i = this.strikes.length - 1; i >= 0; i--) {
      const s = this.strikes[i];
      s.t -= dt;
      s.fill.scale.setScalar(Math.max(0.05, 1 - s.t / s.max));
      if (s.t > 0) continue;
      const at = new THREE.Vector3(s.x, s.y, s.z);
      for (let k = 0; k < 6; k++) g.fx.burst(at.clone().setY(s.y + k * 3), s.cfg.color, 6, 5, 0.5, 1);
      g.fx.ring(at, s.cfg.color, s.r, 0.4);
      if (Math.hypot(pp.x - s.x, pp.z - s.z) < s.r && Math.abs(pp.y - s.y) < 5) {
        p.takeDamage(16 + this.time / 20);
        if (s.cfg.launch) { p.vel.y = 34; p.onGround = false; pp.y += 0.6; }
      }
      for (const e of this.inRadius(at, s.r)) this.hit(e, 40 * (1 + this.time / 60), this.env, true);
      this.group.remove(s.mark, s.fill); s.mark.geometry.dispose(); s.fill.geometry.dispose();
      this.strikes.splice(i, 1);
    }
  }

  xpNeed() { return Math.floor(5 + this.level * 3.5 + this.level * this.level * 0.35); }
  gainXP(v) {
    this.xp += v;
    while (this.xp >= this.xpNeed()) { this.xp -= this.xpNeed(); this.level++; this.pendingLevels++; }
  }

  itemList() { return Object.entries(this.items).map(([id, level]) => ({ ...itemById[id], level })); }
}
