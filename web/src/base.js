// Player base plot: floors (BuyFloor), income + defense pads (AssignToBase / AssignToDefense),
// base core terminal (upgrades), floor teleporters, defender turrets (DefenseAttack*), and rival decor plots.
import * as THREE from 'three';
import { CFG, ELEMENT_COLORS } from './config.js';
import { State } from './state.js';
import { getCreature, effectiveStats, isNightElement, creatureIncome, Creatures } from './data.js';
import { buildCreatureModel } from './creatureModel.js';
import { plotCenter, plotAngle, PLOT_SIZE, textTexture } from './world.js';
import { pick, randInt } from './util.js';

const PAD_LAYOUT = {
  income: [[-17, -12], [-9, -12], [-17, -2], [-9, -2], [-17, 8], [-9, 8]],
  defense: [[9, -12], [17, -12], [9, -2], [17, -2], [9, 8], [17, 8]],
};
const TELEPORTER = [0, 4];
const CORE = [0, -18];
const HOME_SPOT = [0, 16];

function floorY(f) { return f === 0 ? 0.6 : f * CFG.FloorHeight + 0.8; }

function labelSprite(text, sub, color = '#ffe9b8', w = 10) {
  const c = document.createElement('canvas');
  c.width = 512; c.height = 160;
  const ctx = c.getContext('2d');
  ctx.fillStyle = 'rgba(15,12,24,0.78)';
  ctx.beginPath(); ctx.roundRect(4, 4, 504, 152, 26); ctx.fill();
  ctx.fillStyle = color; ctx.font = 'bold 54px system-ui, sans-serif'; ctx.textAlign = 'center';
  ctx.fillText(text, 256, sub ? 70 : 96);
  if (sub) { ctx.fillStyle = '#d8d2ee'; ctx.font = '36px system-ui, sans-serif'; ctx.fillText(sub, 256, 124); }
  const tex = new THREE.CanvasTexture(c); tex.colorSpace = THREE.SRGBColorSpace;
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthWrite: false }));
  s.scale.set(w, w * 160 / 512, 1);
  return s;
}

function buildSlab(f, theme) {
  const g = new THREE.Group();
  const y = floorY(f);
  const thick = f === 0 ? 0.6 : 0.8;
  const slab = new THREE.Mesh(new THREE.BoxGeometry(PLOT_SIZE, thick, PLOT_SIZE), new THREE.MeshLambertMaterial({ color: theme.floor }));
  slab.position.y = y - thick / 2;
  slab.receiveShadow = true; slab.castShadow = f > 0;
  g.add(slab);
  // trim
  const trimMat = new THREE.MeshBasicMaterial({ color: theme.trim });
  for (const [w, d, x, z] of [[PLOT_SIZE, 0.5, 0, PLOT_SIZE / 2], [PLOT_SIZE, 0.5, 0, -PLOT_SIZE / 2], [0.5, PLOT_SIZE, PLOT_SIZE / 2, 0], [0.5, PLOT_SIZE, -PLOT_SIZE / 2, 0]]) {
    const t = new THREE.Mesh(new THREE.BoxGeometry(w, 0.25, d), trimMat);
    t.position.set(x, y + 0.02, z);
    g.add(t);
  }
  // carpet zones
  const carpetI = new THREE.Mesh(new THREE.BoxGeometry(16, 0.06, 30), new THREE.MeshLambertMaterial({ color: theme.income }));
  carpetI.position.set(-13, y + 0.03, -2); carpetI.receiveShadow = true; g.add(carpetI);
  const carpetD = new THREE.Mesh(new THREE.BoxGeometry(16, 0.06, 30), new THREE.MeshLambertMaterial({ color: theme.defense }));
  carpetD.position.set(13, y + 0.03, -2); carpetD.receiveShadow = true; g.add(carpetD);
  if (f > 0) {
    // pillars + railings
    const pm = new THREE.MeshLambertMaterial({ color: theme.pillar });
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      const p = new THREE.Mesh(new THREE.BoxGeometry(2, CFG.FloorHeight, 2), pm);
      p.position.set(sx * (PLOT_SIZE / 2 - 1), y - CFG.FloorHeight / 2 - 0.4, sz * (PLOT_SIZE / 2 - 1));
      p.castShadow = true;
      g.add(p);
    }
    const rm = new THREE.MeshLambertMaterial({ color: theme.trim });
    for (const [w, d, x, z] of [[PLOT_SIZE, 0.3, 0, PLOT_SIZE / 2 - 0.2], [PLOT_SIZE, 0.3, 0, -PLOT_SIZE / 2 + 0.2], [0.3, PLOT_SIZE, PLOT_SIZE / 2 - 0.2, 0], [0.3, PLOT_SIZE, -PLOT_SIZE / 2 + 0.2, 0]]) {
      const r = new THREE.Mesh(new THREE.BoxGeometry(w, 0.3, d), rm);
      r.position.set(x, y + 2.2, z);
      g.add(r);
    }
  }
  return g;
}

function buildPad(type) {
  const g = new THREE.Group();
  const color = type === 'income' ? 0xffc93c : 0xff4a4a;
  const base = new THREE.Mesh(new THREE.CylinderGeometry(2.6, 2.9, 0.5, 20), new THREE.MeshLambertMaterial({ color: 0x3a3546 }));
  base.position.y = 0.25; base.receiveShadow = true; g.add(base);
  const ring = new THREE.Mesh(new THREE.TorusGeometry(2.4, 0.16, 6, 28).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color }));
  ring.position.y = 0.55; g.add(ring);
  const icon = new THREE.Mesh(type === 'income' ? new THREE.CylinderGeometry(0.7, 0.7, 0.15, 16) : new THREE.ConeGeometry(0.6, 0.9, 3), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.85 }));
  icon.position.y = 2.2; if (type === 'income') icon.rotation.x = Math.PI / 2;
  g.add(icon);
  g.userData.icon = icon;
  return g;
}

function buildTeleporter() {
  const g = new THREE.Group();
  const base = new THREE.Mesh(new THREE.CylinderGeometry(2.4, 2.6, 0.4, 24), new THREE.MeshLambertMaterial({ color: 0x24324a }));
  base.position.y = 0.2; g.add(base);
  const glow = new THREE.Mesh(new THREE.CylinderGeometry(2, 2, 6, 24, 1, true), new THREE.MeshBasicMaterial({ color: 0x6fd8ff, transparent: true, opacity: 0.18, side: THREE.DoubleSide, depthWrite: false }));
  glow.position.y = 3.2; g.add(glow);
  g.userData.glow = glow;
  return g;
}

function buildCore() {
  const g = new THREE.Group();
  const base = new THREE.Mesh(new THREE.CylinderGeometry(2.2, 2.8, 1.2, 8), new THREE.MeshLambertMaterial({ color: 0x3b3550 }));
  base.position.y = 0.6; base.castShadow = true; g.add(base);
  const pillar = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 1.1, 4, 8), new THREE.MeshLambertMaterial({ color: 0x5a4f78 }));
  pillar.position.y = 3.2; pillar.castShadow = true; g.add(pillar);
  const holo = new THREE.Mesh(new THREE.OctahedronGeometry(1.3, 0), new THREE.MeshBasicMaterial({ color: 0xffd76a, wireframe: true }));
  holo.position.y = 7; g.add(holo);
  const core = new THREE.Mesh(new THREE.OctahedronGeometry(0.7, 0), new THREE.MeshBasicMaterial({ color: 0xfff1b0 }));
  core.position.y = 7; g.add(core);
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(3.6, 2), new THREE.MeshBasicMaterial({ map: textTexture('BASE CORE', '#1c1830', '#ffd76a', 512, 280, 'bold 72px system-ui'), side: THREE.DoubleSide }));
  screen.position.set(0, 4.2, 1.2); screen.rotation.x = -0.25; g.add(screen);
  g.userData.holo = holo; g.userData.core = core;
  return g;
}

const THEME = { floor: 0x8e8aa0, trim: 0xffd76a, income: 0x6b5a2a, defense: 0x6a2a32, pillar: 0x5a5470 };
const RIVAL_THEMES = [
  { floor: 0x7d9a8a, trim: 0x8affc8, income: 0x3d5a40, defense: 0x5a3d3d, pillar: 0x4a6058 },
  { floor: 0x9a8a7d, trim: 0xffa86a, income: 0x5a4a30, defense: 0x5a3030, pillar: 0x6a5848 },
  { floor: 0x7d859a, trim: 0x8ac8ff, income: 0x3d4a5a, defense: 0x5a3d4a, pillar: 0x4a5068 },
];

export class PlayerBase {
  constructor(scene, world, fx, plotIndex = 0) {
    this.scene = scene; this.world = world; this.fx = fx;
    this.plotIndex = plotIndex;
    this.center = plotCenter(plotIndex);
    const a = plotAngle(plotIndex);
    this.rot = Math.atan2(-Math.cos(a), -Math.sin(a)); // local +z faces the hub
    this.group = new THREE.Group();
    this.group.position.copy(this.center);
    this.group.rotation.y = this.rot;
    scene.add(this.group);
    this.floorGroups = [];
    this.pads = []; // {type, index, floor, mesh, local:[x,z]}
    this.teleporters = [];
    this.placed = new Map(); // slotKey -> {uid, model, cd}
    this.time = 0;

    this.core = buildCore();
    this.core.position.set(CORE[0], floorY(0), CORE[1]);
    this.group.add(this.core);
    this.sign = labelSprite(`${State.data.playerName || 'Your'} Base`, 'Siegelings HQ', '#ffd76a', 11);
    this.sign.position.set(0, 12.5, PLOT_SIZE / 2 - 1);
    this.group.add(this.sign);
    // entrance arch
    const archMat = new THREE.MeshLambertMaterial({ color: 0x5a4f78 });
    for (const sx of [-1, 1]) { const p = new THREE.Mesh(new THREE.BoxGeometry(1.4, 8, 1.4), archMat); p.position.set(sx * 7, 4, PLOT_SIZE / 2 - 1); p.castShadow = true; this.group.add(p); }
    const top = new THREE.Mesh(new THREE.BoxGeometry(16, 1.4, 1.6), archMat); top.position.set(0, 8.4, PLOT_SIZE / 2 - 1); this.group.add(top);
    this.rebuildFloors();
  }

  toWorld(x, y, z) { return this.group.localToWorld(new THREE.Vector3(x, y, z)); }
  homePosition() { return this.toWorld(HOME_SPOT[0], floorY(0), HOME_SPOT[1]); }
  homeYaw() { return this.rot + Math.PI; } // face into the base, toward the core

  rebuildFloors() {
    for (const fg of this.floorGroups) this.group.remove(fg);
    this.floorGroups = [];
    this.pads = [];
    this.teleporters = [];
    this.world.surfaces = this.world.surfaces.filter((s) => s.owner !== this);
    const owned = State.data.ownedFloors.length;
    for (let f = 0; f < owned; f++) {
      const fg = buildSlab(f, THEME);
      this.group.add(fg); this.floorGroups.push(fg);
      const y = floorY(f);
      this.world.addSurface(this.center.x, this.center.z, this.rot, PLOT_SIZE, PLOT_SIZE, y);
      this.world.surfaces[this.world.surfaces.length - 1].owner = this;
      for (const type of ['income', 'defense']) {
        PAD_LAYOUT[type].forEach(([x, z], i) => {
          const pad = buildPad(type);
          pad.position.set(x, y, z);
          fg.add(pad);
          this.pads.push({ type, index: f * 6 + i, floor: f, mesh: pad, local: [x, y, z] });
        });
      }
      const tp = buildTeleporter();
      tp.position.set(TELEPORTER[0], y, TELEPORTER[1]);
      fg.add(tp);
      this.teleporters.push({ floor: f, mesh: tp });
      if (f === 3) { // Siegelord Arena banner
        const banner = labelSprite('SIEGELORD ARENA', 'Floor 4', '#ff9de8', 16);
        banner.position.set(0, y + 9, -PLOT_SIZE / 2 + 3); fg.add(banner);
      }
    }
    // ghost of the next floor
    if (this.ghost) this.group.remove(this.ghost);
    this.ghost = null;
    const next = CFG.Floors[owned];
    if (next) {
      const g = new THREE.Group();
      const y = floorY(owned);
      const slab = new THREE.Mesh(new THREE.BoxGeometry(PLOT_SIZE, 0.8, PLOT_SIZE), new THREE.MeshBasicMaterial({ color: 0x9fd8ff, transparent: true, opacity: 0.12, depthWrite: false }));
      slab.position.y = y - 0.4; g.add(slab);
      const edges = new THREE.LineSegments(new THREE.EdgesGeometry(slab.geometry), new THREE.LineBasicMaterial({ color: 0x9fd8ff, transparent: true, opacity: 0.6 }));
      edges.position.copy(slab.position); g.add(edges);
      const lbl = labelSprite(`🔒 ${next.name}`, `${next.cost.toLocaleString()} coins · Lv ${next.levelReq} · Base Core`, '#9fd8ff', 14);
      lbl.position.set(0, y + 3, 0); g.add(lbl);
      this.group.add(g); this.ghost = g;
    }
    this.syncCreatures(true);
  }

  // Place / remove creature models to match State slots.
  syncCreatures(force = false) {
    const d = State.data;
    const want = new Map();
    d.baseSlots.forEach((u, i) => { if (u) want.set(`income:${i}`, u); });
    d.defenseSlots.forEach((u, i) => { if (u) want.set(`defense:${i}`, u); });
    for (const [key, p] of this.placed) {
      if (force || want.get(key) !== p.uid || !State.get(p.uid)) { p.model.root.parent && p.model.root.parent.remove(p.model.root); this.placed.delete(key); }
    }
    for (const [key, u] of want) {
      if (this.placed.has(key)) continue;
      const e = State.get(u);
      const pad = this.pads.find((pp) => `${pp.type}:${pp.index}` === key);
      if (!e || !pad) continue;
      const def = getCreature(e.id);
      const model = buildCreatureModel(def, { variant: e.variant, shiny: e.shiny });
      model.root.position.set(pad.local[0], pad.local[1] + 0.5, pad.local[2]);
      this.group.add(model.root);
      pad.mesh.userData.icon.visible = false;
      this.placed.set(key, { uid: u, entry: e, def, model, cd: Math.random() * 2, type: pad.type, pad });
    }
    for (const pad of this.pads) pad.mesh.userData.icon.visible = !this.placed.has(`${pad.type}:${pad.index}`);
  }

  creatureWorldPos(p) { return this.toWorld(p.pad.local[0], p.pad.local[1] + 0.5, p.pad.local[2]); }

  // Floating labels for the UI layer.
  labels(isNight) {
    const out = [];
    for (const p of this.placed.values()) {
      const pos = this.creatureWorldPos(p); pos.y += p.model.height + 1.2;
      const sleeping = isNight && !isNightElement(p.def.element);
      out.push({
        pos, name: `${p.entry.nickname || p.def.displayName}`, level: p.entry.level, rarity: p.def.rarity, variant: p.entry.variant,
        sub: p.type === 'income' ? (sleeping && CFG.NightOnlyNightElementsEarn ? '💤 sleeping' : `+${creatureIncome(p.entry)} 🪙/tick`) : '🛡 Defender',
      });
    }
    return out;
  }

  // Interactables near the player.
  interactables(ctx) {
    const list = [];
    const coreW = this.toWorld(CORE[0], floorY(0), CORE[1]);
    list.push({ pos: coreW, radius: 6, label: () => 'Open Base Core (upgrades & slots)', action: () => ctx.ui.openBase() });
    for (const tp of this.teleporters) {
      const owned = this.teleporters.length;
      const target = (tp.floor + 1) % owned;
      if (owned < 2) continue;
      list.push({
        pos: this.toWorld(TELEPORTER[0], floorY(tp.floor), TELEPORTER[1]), radius: 3.2, yTol: 3,
        label: () => target === 0 ? 'Teleport down to Ground Floor' : `Teleport up to ${CFG.Floors[target].name}`,
        action: () => {
          ctx.player.teleport(this.toWorld(TELEPORTER[0] + 0, floorY(target) + 0.1, TELEPORTER[1] + 4));
          ctx.fx.burst(ctx.player.pos.clone().setY(ctx.player.pos.y + 2), 0x6fd8ff, 30, 8, 0.8, 3);
        },
      });
    }
    for (const pad of this.pads) {
      const key = `${pad.type}:${pad.index}`;
      const p = this.placed.get(key);
      list.push({
        pos: this.toWorld(pad.local[0], pad.local[1], pad.local[2]), radius: 3.6, yTol: 3,
        label: () => p ? `Manage ${p.def.displayName} (${pad.type} slot ${pad.index + 1})` : `Assign a creature to ${pad.type} slot ${pad.index + 1}`,
        action: () => ctx.ui.openSlotPicker(pad.type, pad.index),
      });
    }
    return list;
  }

  isInside(pos, margin = 0) {
    const local = this.group.worldToLocal(pos.clone());
    return Math.abs(local.x) < PLOT_SIZE / 2 + margin && Math.abs(local.z) < PLOT_SIZE / 2 + margin;
  }

  update(dt, ctx) {
    this.time += dt;
    const t = this.time;
    this.core.userData.holo.rotation.y += dt;
    this.core.userData.core.rotation.y -= dt * 2;
    this.core.userData.holo.position.y = 7 + Math.sin(t * 2) * 0.3;
    for (const tp of this.teleporters) tp.mesh.userData.glow.material.opacity = 0.14 + Math.sin(t * 3) * 0.06;
    for (const pad of this.pads) if (pad.mesh.userData.icon.visible) { pad.mesh.userData.icon.rotation.y += dt * 1.5; pad.mesh.userData.icon.position.y = 2.2 + Math.sin(t * 2 + pad.index) * 0.2; }
    const isNight = ctx.isNight();
    for (const p of this.placed.values()) {
      const sleeping = isNight && !isNightElement(p.def.element);
      p.model.animate(t, 0);
      p.model.root.rotation.y = 0;
      if (sleeping) p.model.inner.rotation.z = THREE.MathUtils.lerp(p.model.inner.rotation.z, 0.5, 0.05);
      else p.model.inner.rotation.z = THREE.MathUtils.lerp(p.model.inner.rotation.z, 0, 0.1);
      if (p.type !== 'defense' || sleeping) continue;
      p.cd -= dt;
      if (p.cd > 0) continue;
      const from = this.creatureWorldPos(p); from.y += p.model.height * 0.6;
      let target = null, bd = CFG.DefenseAttackRange;
      for (const c of ctx.creatures.list) {
        if (c.fainted || !c.alive) continue;
        const hostileToBase = c.isRaider || c.state === 'chase' || this.isInside(c.pos, 10);
        if (!hostileToBase) continue;
        const d = c.pos.distanceTo(from);
        if (d < bd) { bd = d; target = c; }
      }
      if (!target) { p.cd = 0.4; continue; }
      p.cd = CFG.DefenseAttackCD;
      const stats = effectiveStats(p.entry.id, p.entry.level, p.entry.variant);
      const dmg = CFG.DefenseBaseDamage * stats.attack / 10 * 0.35;
      const owner = { base: true, uid: p.uid, pos: from };
      ctx.fx.shoot({
        from, dir: target.hitCenter().sub(from), speed: 90, range: CFG.DefenseAttackRange + 20, color: ELEMENT_COLORS[p.def.element] || 0xffffff,
        damage: dmg, owner, homing: target, targets: () => ctx.creatures.list,
        onHit: (hit) => {
          hit.takeDamage(dmg, owner);
          if (hit.fainted) { const lv = State.addCreatureXP(p.uid, CFG.DefenseKillXP); ctx.notify(`${p.def.displayName} defended your base! +${CFG.DefenseKillXP} XP${lv ? ' — level up!' : ''}`, 'good'); }
        },
      });
    }
  }
}

// Decorative rival / unclaimed plots for the remaining seven spots.
export function buildOtherPlots(scene, world, playerPlot) {
  const names = ['SiegeKnight_42', 'EmberQueen', 'TidalTom', 'Unclaimed', 'GoldGrubber', 'Unclaimed', 'FrostByte77', 'Unclaimed'];
  const out = [];
  for (let i = 0; i < 8; i++) {
    if (i === playerPlot) continue;
    const c = plotCenter(i), a = plotAngle(i);
    const g = new THREE.Group();
    g.position.copy(c);
    g.rotation.y = Math.atan2(-Math.cos(a), -Math.sin(a));
    scene.add(g);
    const name = names[i];
    const rival = name !== 'Unclaimed';
    const theme = rival ? RIVAL_THEMES[i % RIVAL_THEMES.length] : { floor: 0x77736a, trim: 0x55524a, income: 0x5c5850, defense: 0x5c5850, pillar: 0x55524a };
    g.add(buildSlab(0, theme));
    world.addSurface(c.x, c.z, g.rotation.y, PLOT_SIZE, PLOT_SIZE, 0.6);
    const sign = labelSprite(rival ? `${name}'s Base` : 'Unclaimed Plot', rival ? 'Rival Siegeler' : 'Available', rival ? '#bfe9ff' : '#cfcac0', 13);
    sign.position.set(0, 9, PLOT_SIZE / 2 - 2); g.add(sign);
    if (rival) {
      const floors = randInt(1, 2);
      if (floors > 1) g.add(buildSlab(1, theme));
      if (floors > 1) world.addSurface(c.x, c.z, g.rotation.y, PLOT_SIZE, PLOT_SIZE, floorY(1));
      const pool = Creatures.filter((cc) => !cc.spawnPointType && cc.rarity !== 'Legendary');
      for (let f = 0; f < floors; f++) {
        for (const type of ['income', 'defense']) {
          PAD_LAYOUT[type].forEach(([x, z]) => {
            const pad = buildPad(type); pad.position.set(x, floorY(f), z); g.add(pad);
            if (Math.random() < 0.65) {
              const def = pick(pool);
              const m = buildCreatureModel(def, { variant: Math.random() < 0.15 ? 'Silver' : 'Normal' });
              m.root.position.set(x, floorY(f) + 0.5, z);
              g.add(m.root);
              out.push(m);
              pad.userData.icon.visible = false;
            }
          });
        }
      }
    }
  }
  return out;
}
