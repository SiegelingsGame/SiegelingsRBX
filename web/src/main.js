import * as THREE from 'three';
import './style.css';
import { CFG } from './config.js';
import { State } from './state.js';
import { getCreature, captureCost } from './data.js';
import { World, BIOMES, biomeAt } from './world.js';
import { FX } from './fx.js';
import { CreatureManager } from './creatures.js';
import { Player, ShoulderCamera } from './player.js';
import { Companion } from './companion.js';
import { PlayerBase, buildOtherPlots } from './base.js';
import { Hub } from './hub.js';
import { UI } from './ui.js';
import { randInt, clamp, lerp } from './util.js';

// ── input ──────────────────────────────────────────────────────
class Input {
  constructor(canvas, onMouse) {
    this.canvas = canvas;
    this.keys = new Set(); this.pressedSet = new Set(); this.buttons = new Set();
    this.locked = false;
    addEventListener('keydown', (e) => {
      if (e.code === 'Tab') e.preventDefault();
      if (!e.repeat) this.pressedSet.add(e.code);
      this.keys.add(e.code);
    });
    addEventListener('keyup', (e) => this.keys.delete(e.code));
    addEventListener('blur', () => { this.keys.clear(); this.buttons.clear(); });
    this.fallback = false; // drag-to-look mode when pointer lock is unavailable (e.g. sandboxed iframe)
    canvas.addEventListener('mousedown', (e) => {
      if (this.locked || this.fallback) this.buttons.add(e.button);
      else this.capturePointer();
    });
    addEventListener('mouseup', (e) => this.buttons.delete(e.button));
    addEventListener('contextmenu', (e) => e.preventDefault());
    addEventListener('mousemove', (e) => {
      if (this.locked) onMouse(e.movementX, e.movementY);
      else if (this.fallback && this.buttons.size) onMouse(e.movementX * 1.4, e.movementY * 1.4);
    });
    document.addEventListener('pointerlockchange', () => {
      this.locked = document.pointerLockElement === canvas;
      if (!this.locked) this.buttons.clear();
      this.onLockChange && this.onLockChange(this.locked);
    });
  }
  capturePointer() {
    const useFallback = () => { if (!this.locked) { this.fallback = true; this.onLockChange && this.onLockChange(false); } };
    try {
      const p = this.canvas.requestPointerLock();
      if (p && p.catch) p.catch(useFallback);
    } catch { useFallback(); }
    setTimeout(useFallback, 400); // some sandboxes silently ignore the request
  }
  releasePointer() { this.fallback = false; this.buttons.clear(); if (document.pointerLockElement) document.exitPointerLock(); }
  get active() { return this.locked || this.fallback; }
  down(code) { return this.keys.has(code); }
  pressed(code) { return this.pressedSet.has(code); }
  mouseDown(b) { return this.buttons.has(b); }
  endFrame() { this.pressedSet.clear(); }
}

// ── sky ────────────────────────────────────────────────────────
function buildSky(scene) {
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: { top: { value: new THREE.Color(0x4a90e2) }, bottom: { value: new THREE.Color(0xcfe8ff) }, sunDir: { value: new THREE.Vector3(0, 1, 0) }, sunCol: { value: new THREE.Color(0xfff2c0) } },
    vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: `uniform vec3 top; uniform vec3 bottom; uniform vec3 sunDir; uniform vec3 sunCol; varying vec3 vP;
      void main(){ float h = clamp(vP.y*1.4+0.15,0.0,1.0); vec3 c = mix(bottom, top, h);
      float s = max(dot(vP, normalize(sunDir)), 0.0); c += sunCol * (pow(s, 900.0)*2.0 + pow(s, 12.0)*0.25);
      gl_FragColor = vec4(c,1.0); }`,
  });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(1400, 32, 16), mat);
  sky.renderOrder = -1;
  scene.add(sky);
  const starGeo = new THREE.BufferGeometry();
  const pts = [];
  for (let i = 0; i < 1500; i++) {
    const v = new THREE.Vector3(Math.random() - 0.5, Math.random() * 0.9 + 0.05, Math.random() - 0.5).normalize().multiplyScalar(1300);
    pts.push(v.x, v.y, v.z);
  }
  starGeo.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
  const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({ color: 0xffffff, size: 2.2, sizeAttenuation: false, transparent: true, opacity: 0, fog: false, depthWrite: false }));
  scene.add(stars);
  return { sky, mat, stars };
}

const SKY_TINT = { electric: 0x6a4ad0, caves: 0x30283a, volcanic: 0xd06a3a, frozen: 0xbfe0ff, desert: 0xf0c890, ocean: 0x5ab8ff, forest: 0x8fd08a, highlands: 0xaee8ff, hub: null };

class Game {
  constructor() {
    State.load();
    const canvas = document.getElementById('game');
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    this.renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
    this.renderer.setSize(innerWidth, innerHeight);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene = new THREE.Scene();
    this.scene.fog = new THREE.Fog(0xcfe8ff, 180, 760);
    this.camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.3, 3000);
    addEventListener('resize', () => {
      this.camera.aspect = innerWidth / innerHeight; this.camera.updateProjectionMatrix();
      this.renderer.setSize(innerWidth, innerHeight);
    });

    this.hemi = new THREE.HemisphereLight(0xdfefff, 0x5a5040, 1.3);
    this.scene.add(this.hemi);
    this.sun = new THREE.DirectionalLight(0xfff2d8, 2.4);
    this.sun.castShadow = true;
    this.sun.shadow.mapSize.set(2048, 2048);
    const sc = this.sun.shadow.camera; sc.left = -90; sc.right = 90; sc.top = 90; sc.bottom = -90; sc.near = 10; sc.far = 500;
    this.sun.shadow.bias = -0.0005; this.sun.shadow.normalBias = 0.6;
    this.scene.add(this.sun, this.sun.target);
    this.skyObj = buildSky(this.scene);

    this.world = new World(this.scene);
    this.fx = new FX(this.scene);
    this.hub = new Hub(this.scene);
    this.base = new PlayerBase(this.scene, this.world, this.fx, 0);
    this.rivalModels = buildOtherPlots(this.scene, this.world, 0);
    this.player = new Player(this.scene, this.world, this.fx);
    this.cam = new ShoulderCamera(this.camera, this.world);
    this.companion = new Companion(this.scene, this.world, this.fx);
    this.input = new Input(canvas, (dx, dy) => { if (!this.ui.open) this.cam.onMouse(dx, dy); });
    this.creatures = new CreatureManager(this.scene, this.world, {
      isNight: () => this.isNight(),
      onDamaged: (c, dmg, attacker) => {
        if (c.pos.distanceTo(this.player.pos) < 80) this.ui.floatText(c.hitCenter().add(new THREE.Vector3(0, c.model.height * 0.6, 0)), `-${dmg}`, attacker === this.player ? '#ffffff' : '#9fffc0');
      },
      onFainted: (c, attacker) => {
        if (attacker === this.player || attacker === this.companion) {
          State.data.stats.kills++;
          State.addPlayerXP(CFG.PlayerXP_Kill * (c.isBoss ? 10 : 1));
        }
        if (c.isRaider) { State.data.stats.raidsDefended++; this.ui.notify(`Raider ${c.def.displayName} defeated — capture it before it fades!`, 'good'); }
        else if (c.isBoss && c.pos.distanceTo(this.player.pos) < 120) this.ui.notify(`Boss ${c.def.displayName} fainted! Capture it (${captureCost(c.def.id)} coins)`, 'good');
        this.fx.burst(c.hitCenter(), 0xffffff, 24, 6, 0.8, 2);
      },
      onRaidSteal: (c) => {
        const amt = Math.min(250, Math.floor(State.data.coins * 0.1));
        if (amt > 0) { State.spendCoins(amt); this.ui.notify(`A raiding ${c.def.displayName} stole ${amt} coins from your base!`, 'bad'); }
      },
    });
    this.ui = new UI(this);
    this.State = State; // handy for debugging from the console
    this.creatures.init();

    this.player.onHurt = (d) => this.ui.floatText(this.player.hitCenter().add(new THREE.Vector3(0, 2, 0)), `-${Math.round(d)}`, '#ff6a6a');
    this.player.onDeath = () => this.ui.notify('You fainted!', 'bad');
    this.companion.onFaint = () => this.ui.notify('Your companion fainted — it returns in 30s (or visit the fountain)', 'warn');

    State.on((kind, payload) => {
      if (kind === 'slots' || kind === 'inventory') this.base.syncCreatures();
      if (kind === 'playerLevel') { this.ui.notify(`⭐ Player level ${payload}!`, 'good'); this.fx.ring(this.player.pos, 0xffd76a, 8, 1); }
      if (kind === 'creatureLevel') this.ui.notify(`${getCreature(payload.id).displayName} reached Lv ${payload.level}!`, 'good');
    });

    this.ctx = {
      player: this.player, creatures: this.creatures, fx: this.fx, world: this.world, ui: this.ui, cam: this.cam,
      notify: (m, k) => this.ui.notify(m, k), isNight: () => this.isNight(), playerLevel: () => State.data.playerLevel,
      friendlyTargets: () => [this.player, ...(this.companion.alive ? [this.companion] : [])],
      healAll: () => { this.player.hp = this.player.maxHp; this.companion.heal(); this.fx.burst(this.player.hitCenter(), 0x8affd8, 30, 5, 0.9, 3); this.ui.notify('Healed at the fountain', 'good'); },
      blockers: this.hub.blockers,
    };

    if (State.data.starterChosen) this.player.teleport(this.base.homePosition(), this.base.homeYaw());
    this.cam.yaw = this.player.yaw + Math.PI;

    this.incomeTimer = CFG.IncomeTickSeconds;
    this.raidTimer = CFG.AIRaidInterval;
    this.saveTimer = 10;
    this.clock = new THREE.Clock();
    this.input.onLockChange = (locked) => {
      document.getElementById('lock').style.display = !this.input.active && !this.ui.open && !this.bigMap ? 'flex' : 'none';
    };
    document.getElementById('lock').addEventListener('click', () => this.input.capturePointer());
    document.getElementById('help-btn').addEventListener('click', (e) => { e.stopPropagation(); this.ui.openHelp(); });
    if (!State.data.starterChosen) this.ui.openStarter();
    addEventListener('beforeunload', () => State.save());
    this.loop();
  }

  isNight() {
    const h = State.data.timeOfDay;
    return h >= CFG.NightStartHour || h < CFG.NightEndHour;
  }

  onFloorBought(f) {
    this.base.rebuildFloors();
    this.fx.ring(this.base.center.clone().setY(0.6), 0xffd76a, 30, 1.4);
    this.fx.burst(this.base.center.clone().setY(f * CFG.FloorHeight + 2), 0xffd76a, 80, 14, 1.4, 6);
  }

  updateSky(dt) {
    const d = State.data;
    d.timeOfDay = (d.timeOfDay + dt * 24 / CFG.DayNightCycleSeconds) % 24;
    const h = d.timeOfDay;
    const elev = Math.sin(((h - 6) / 12) * Math.PI); // 1 at noon, -1 at midnight
    const day = clamp((elev + 0.15) / 0.5, 0, 1);
    const dusk = clamp(1 - Math.abs(elev) / 0.3, 0, 1);
    const top = new THREE.Color(0x0b1030).lerp(new THREE.Color(0x3d86da), day);
    const bottom = new THREE.Color(0x1a2142).lerp(new THREE.Color(0xcfe6ff), day).lerp(new THREE.Color(0xffa060), dusk * 0.55);
    const b = biomeAt(this.player.pos.x, this.player.pos.z);
    const tint = SKY_TINT[b];
    this.skyTint = this.skyTint || new THREE.Color(0xcfe6ff);
    this.skyTint.lerp(tint ? new THREE.Color(tint) : bottom.clone(), Math.min(1, dt * 1.5));
    bottom.lerp(this.skyTint, 0.35 * (0.4 + day * 0.6));
    top.lerp(this.skyTint, 0.18);
    const m = this.skyObj.mat.uniforms;
    m.top.value.copy(top); m.bottom.value.copy(bottom);
    const az = ((h - 6) / 12) * Math.PI;
    const sunDir = new THREE.Vector3(Math.cos(az) * 0.8, Math.max(-0.2, elev), 0.45).normalize();
    const moonDir = sunDir.clone().negate().setY(Math.abs(sunDir.y) + 0.3).normalize();
    m.sunDir.value.copy(day > 0.05 ? sunDir : moonDir);
    m.sunCol.value.set(day > 0.05 ? 0xfff2c0 : 0x9fb0ff);
    this.scene.fog.color.copy(bottom);
    const lightDir = elev > -0.05 ? sunDir : moonDir;
    this.sun.position.copy(this.player.pos).addScaledVector(lightDir, 220);
    this.sun.target.position.copy(this.player.pos);
    this.sun.intensity = lerp(0.35, 2.4, day);
    this.sun.color.set(day > 0.05 ? 0xfff2d8 : 0xaab8ff).lerp(new THREE.Color(0xffa060), dusk * 0.5);
    this.hemi.intensity = lerp(0.45, 1.3, day);
    this.hemi.color.set(0xdfefff).lerp(new THREE.Color(0x6a78c0), 1 - day);
    this.skyObj.stars.material.opacity = 1 - day;
    this.skyObj.sky.position.copy(this.camera.position);
    this.skyObj.stars.position.copy(this.camera.position);
    if (b === 'caves') this.hemi.intensity *= 0.75;
  }

  tickIncome() {
    const night = this.isNight();
    const inc = State.incomePerTick(night);
    if (inc > 0) {
      State.addCoins(inc);
      State.data.stats.totalIncome += inc;
      State.addPlayerXP(CFG.PlayerXP_IncomeTick);
      if (this.player.pos.distanceTo(this.base.center) < 120) {
        for (const p of this.base.placed.values()) {
          if (p.type !== 'income') continue;
          if (night && CFG.NightOnlyNightElementsEarn && !['Shadow', 'Lightning'].includes(p.def.element)) continue;
          const pos = this.base.creatureWorldPos(p); pos.y += p.model.height + 2.5;
          this.ui.floatText(pos, `+${p.def.baseIncome} 🪙`, '#ffd76a');
        }
      }
      const el = document.getElementById('coins-box');
      el.classList.remove('pulse'); void el.offsetWidth; el.classList.add('pulse');
    }
    for (const u of State.data.defenseSlots) {
      if (!u) continue;
      const e = State.get(u), def = e && getCreature(e.id);
      if (!def || (night && !['Shadow', 'Lightning'].includes(def.element))) continue;
      State.addCreatureXP(u, CFG.DefensePassiveXP);
    }
    State.save();
  }

  tickRaid() {
    if (!CFG.AIRaidEnabled) return;
    const stationed = State.data.baseSlots.some(Boolean) || State.data.defenseSlots.some(Boolean);
    if (!stationed || State.data.playerLevel < 2) return;
    const n = randInt(CFG.AIRaidPackSize[0], CFG.AIRaidPackSize[1]);
    this.creatures.spawnRaid(this.base.center, n);
    this.ui.notify(`⚠️ ${n} wild raider${n > 1 ? 's are' : ' is'} heading for your base!`, 'bad');
  }

  handleInteraction() {
    const p = this.player.pos;
    let best = null, bestScore = Infinity;
    const consider = (it) => {
      const dx = it.pos.x - p.x, dz = it.pos.z - p.z, d = Math.hypot(dx, dz);
      if (d > it.radius) return;
      if (it.yTol !== undefined && Math.abs(it.pos.y - p.y) > it.yTol) return;
      const s = d / it.radius;
      if (s < bestScore) { bestScore = s; best = it; }
    };
    for (const it of this.hub.interactables(this.ctx)) consider(it);
    if (this.player.pos.distanceTo(this.base.center) < 50) for (const it of this.base.interactables(this.ctx)) consider(it);
    // capture fainted creatures (CaptureSystem.TryCapture)
    const f = this.creatures.nearestFainted(p, CFG.CaptureRange);
    if (f) {
      const cost = captureCost(f.def.id);
      const d = f.pos.distanceTo(p);
      const s = (d / CFG.CaptureRange) * 0.9;
      if (s < bestScore) {
        bestScore = s;
        best = { label: () => `Capture ${f.variant !== 'Normal' ? f.variant + ' ' : ''}${f.def.displayName} Lv ${f.level} — ${cost} coins`, action: () => this.tryCapture(f) };
      }
    }
    if (this.capturing) best = null;
    this.ui.setPrompt(best ? best.label() : null);
    if (best && this.input.pressed('KeyE')) best.action();
  }

  tryCapture(c) {
    const cost = captureCost(c.def.id);
    if (State.isFull()) return this.ui.notify(`Inventory full (${CFG.MaxInventorySize}). Sell creatures to The Broker.`, 'warn');
    if (!State.spendCoins(cost)) return this.ui.notify(`Need ${cost} coins (you have ${State.data.coins})`, 'warn');
    c.capturing = true;
    this.capturing = true;
    this.fx.captureAnimation(() => this.player.handPos(), c, CFG.CaptureAnimationTime, (ok) => {
      this.capturing = false;
      if (!ok) {
        c.capturing = false;
        State.addCoins(cost);
        this.ui.notify('Capture failed — you moved out of range', 'warn');
        return;
      }
      const e = State.addCreature(c.def.id, Math.max(1, c.level), c.variant, c.shiny);
      this.creatures.removeCaptured(c);
      State.data.stats.totalCaptured++;
      State.addPlayerXP(CFG.PlayerXP_Capture * (c.isBoss ? 5 : 1));
      if (this.companion.uid) State.addCreatureXP(this.companion.uid, CFG.CaptureXP);
      State.save();
      this.fx.ring(this.player.pos, 0xffe9a6, 6, 0.8);
      this.ui.openCaptured(e);
    }, () => c.pos.distanceTo(this.player.pos) > CFG.CaptureRange + CFG.CaptureGracePeriod);
  }

  handleKeys() {
    const i = this.input, ui = this.ui;
    if (i.pressed('Escape') && ui.open && ui.open !== 'starter') ui.close();
    else if (i.pressed('Escape') && i.fallback) i.releasePointer();
    if (!State.data.starterChosen) return;
    const toggle = (kind, fn) => { if (ui.open === kind) ui.close(); else if (!ui.open || ui.open !== 'starter') fn(); };
    if (i.pressed('Tab') || i.pressed('KeyI')) toggle('inventory', () => ui.openInventory());
    if (i.pressed('KeyB')) toggle('base', () => ui.openBase());
    if (i.pressed('Slash') || i.pressed('F1')) toggle('help', () => ui.openHelp());
    if (ui.open) return;
    if (i.pressed('KeyM')) {
      this.bigMap = !this.bigMap;
      document.getElementById('bigmap-wrap').style.display = this.bigMap ? 'flex' : 'none';
    }
    if (i.pressed('KeyQ')) this.cam.side *= -1;
    if (i.pressed('KeyH')) {
      this.player.teleport(this.base.homePosition(), this.base.homeYaw());
      this.cam.yaw = this.base.homeYaw() + Math.PI;
      this.fx.burst(this.player.hitCenter(), 0x6fd8ff, 30, 8, 0.8, 3);
      this.ui.notify('Teleported home', 'info');
    }
  }

  loop() {
    requestAnimationFrame(() => this.loop());
    const dt = Math.min(0.05, this.clock.getDelta());
    this.handleKeys();
    const playing = !this.ui.open;
    if (playing) this.player.update(dt, this.input, this.cam, this.ctx);
    else this.player.update(dt, { down: () => false, pressed: () => false, mouseDown: () => false }, this.cam, this.ctx);
    this.cam.update(dt, this.player, playing ? this.input : { mouseDown: () => false });
    this.companion.update(dt, this.ctx);
    this.creatures.update(dt, this.ctx);
    this.base.update(dt, this.ctx);
    this.hub.update(dt);
    for (const m of this.rivalModels) m.animate(this.clock.elapsedTime, 0);
    this.fx.update(dt, this.world);
    this.world.waterMat.opacity = 0.7 + Math.sin(this.clock.elapsedTime) * 0.04;
    this.updateSky(dt);
    if (playing) this.handleInteraction(); else this.ui.setPrompt(null);

    this.incomeTimer -= dt;
    if (this.incomeTimer <= 0) { this.incomeTimer += CFG.IncomeTickSeconds; this.tickIncome(); }
    this.raidTimer -= dt;
    if (this.raidTimer <= 0) { this.raidTimer = CFG.AIRaidInterval; this.tickRaid(); }

    this.renderer.render(this.scene, this.camera);
    this.ui.updateHUD();
    this.ui.updateLabels(dt, this.camera);
    this.ui.drawMinimap(false);
    if (this.bigMap) this.ui.drawMinimap(true);
    document.getElementById('lock').style.display = !this.input.active && !this.ui.open && !this.bigMap ? 'flex' : 'none';
    this.input.endFrame();
  }
}

window.__game = new Game();
