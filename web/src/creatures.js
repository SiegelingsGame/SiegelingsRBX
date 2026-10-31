// Wild creature spawning + AI (CreatureSpawner.lua / CreatureAI.lua, simplified).
import * as THREE from 'three';
import { CFG, ELEMENT_COLORS } from './config.js';
import { Creatures, getCreature, effectiveStats, creaturesForElements, maxCreatureLevel } from './data.js';
import { buildCreatureModel } from './creatureModel.js';
import { rand, randInt, weightedPick, angleDiff, clamp } from './util.js';

let nextPack = 1;

export class WildCreature {
  constructor(mgr, def, opts) {
    this.mgr = mgr;
    this.def = def;
    this.kind = 'wild';
    this.level = opts.level;
    this.variant = opts.variant || 'Normal';
    this.shiny = !!opts.shiny;
    this.isBoss = !!opts.isBoss;
    this.spawnPoint = opts.spawnPoint || null;
    this.packId = opts.packId || 0;
    this.raidTarget = opts.raidTarget || null; // base plot centre when raiding
    this.stats = effectiveStats(def.id, this.level, this.variant);
    const hpMult = this.isBoss ? 4 : 1;
    this.maxHp = Math.round(this.stats.health * hpMult);
    this.hp = this.maxHp;
    this.model = buildCreatureModel(def, { variant: this.variant, shiny: this.shiny, scale: this.isBoss ? 1.7 : 1 });
    this.pos = opts.pos.clone();
    this.home = opts.pos.clone();
    this.yaw = Math.random() * Math.PI * 2;
    this.speed = 0;
    this.state = this.raidTarget ? 'raid' : 'idle';
    this.stateTime = rand(0, 3);
    this.attackCD = rand(0.5, 2);
    this.aggroTarget = null;
    this.alive = true;
    this.fainted = false;
    this.faintTimer = 0;
    this.capturing = false;
    this.lastHitTime = -99;
    this.stealTimer = 0;
    mgr.scene.add(this.model.root);
    this.syncModel(0);
  }

  hitCenter() { return this.pos.clone().setY(this.pos.y + this.model.height * 0.5); }
  hitRadius() { return this.model.radius * 1.1; }
  get displayName() { return this.def.displayName; }
  get hostile() { return !this.fainted && (this.state === 'chase' || this.state === 'raid' || this.def.behavior === 'aggressive'); }

  moveSpeed() {
    const base = CFG.AI_WanderSpeed + this.stats.speed / 12;
    if (this.state === 'flee') return CFG.AI_FleeSpeed + this.stats.speed / 10;
    if (this.state === 'chase' || this.state === 'raid' || this.state === 'return') return Math.min(22, base * 2.1);
    return base;
  }

  takeDamage(amount, attacker) {
    if (this.fainted || !this.alive) return 0;
    const dmg = Math.max(1, Math.round(amount * (1 - this.stats.defense / (this.stats.defense + 140))));
    this.hp -= dmg;
    this.lastHitTime = this.mgr.time;
    this.mgr.onDamaged(this, dmg, attacker);
    if (this.hp <= 0) { this.hp = 0; this.faint(attacker); return dmg; }
    // react
    if (this.def.behavior === 'skittish') { this.state = 'flee'; this.stateTime = 4; this.aggroTarget = attacker; }
    else if (this.state !== 'raid') { this.state = 'chase'; this.aggroTarget = attacker; this.stateTime = 12; }
    if (this.def.behavior === 'pack' && this.packId) this.mgr.alertPack(this, attacker);
    return dmg;
  }

  faint(attacker) {
    this.fainted = true;
    this.state = 'fainted';
    this.faintTimer = CFG.FaintDuration * (this.isBoss ? 2 : 1);
    this.speed = 0;
    this.mgr.onFainted(this, attacker);
  }

  syncModel(t) {
    const r = this.model.root;
    r.position.copy(this.pos);
    r.rotation.y = this.yaw;
    if (this.fainted) {
      this.model.inner.rotation.z = THREE.MathUtils.lerp(this.model.inner.rotation.z, Math.PI / 2, 0.15);
      this.model.inner.position.y = this.model.radius * 0.5;
    } else {
      this.model.inner.rotation.z = 0;
      this.model.animate(t, this.speed);
    }
  }

  update(dt, t, ctx) {
    const { player, world } = ctx;
    if (!this.alive) return;
    if (this.fainted) {
      if (!this.capturing) {
        this.faintTimer -= dt;
        if (this.faintTimer <= 0) this.mgr.despawn(this);
      }
      this.syncModel(t);
      return;
    }
    this.stateTime -= dt;
    this.attackCD -= dt;
    const toPlayer = player.pos.clone().sub(this.pos); toPlayer.y = 0;
    const dPlayer = toPlayer.length();
    let target = null; // {x,z} to steer to
    let wantFace = null;

    // passive regen when out of combat
    if (t - this.lastHitTime > 8 && this.hp < this.maxHp) this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.05 * dt);

    const playerTargetable = player.alive && !player.inSafeZone;
    switch (this.state) {
      case 'idle':
      case 'wander': {
        const b = this.def.behavior;
        if (playerTargetable && b === 'aggressive' && dPlayer < CFG.AI_AggroRange) { this.state = 'chase'; this.aggroTarget = player; this.stateTime = 12; break; }
        if (playerTargetable && b === 'lone' && dPlayer < 16) { this.state = 'chase'; this.aggroTarget = player; this.stateTime = 8; break; }
        if (b === 'skittish' && dPlayer < CFG.AI_FleeRange * 0.7) { this.state = 'flee'; this.aggroTarget = player; this.stateTime = 3; break; }
        if (this.stateTime <= 0) {
          if (this.state === 'idle') {
            this.state = 'wander';
            const a = Math.random() * Math.PI * 2, r = Math.random() * CFG.AI_WanderRadius * (this.isBoss ? 0.25 : 0.5);
            this.wanderTo = new THREE.Vector3(this.home.x + Math.cos(a) * r, 0, this.home.z + Math.sin(a) * r);
            this.stateTime = rand(4, 9);
          } else { this.state = 'idle'; this.stateTime = rand(2, 5); }
        }
        if (this.state === 'wander' && this.wanderTo) {
          if (Math.hypot(this.wanderTo.x - this.pos.x, this.wanderTo.z - this.pos.z) < 2) { this.state = 'idle'; this.stateTime = rand(2, 5); }
          else target = this.wanderTo;
        }
        break;
      }
      case 'chase': {
        const tgt = this.aggroTarget && this.aggroTarget.alive ? this.aggroTarget : (playerTargetable ? player : null);
        const homeDist = Math.hypot(this.pos.x - this.home.x, this.pos.z - this.home.z);
        if (!tgt || tgt.inSafeZone || homeDist > CFG.AI_WanderRadius * 2.2 || (this.stateTime <= 0 && this.pos.distanceTo(tgt.pos) > CFG.AI_AggroRange)) {
          this.state = 'return'; this.aggroTarget = null; break;
        }
        const d = Math.hypot(tgt.pos.x - this.pos.x, tgt.pos.z - this.pos.z);
        const keep = this.def.class === 'Mage' ? 16 : 7;
        if (d > keep) target = tgt.pos;
        wantFace = tgt.pos;
        if (d < CFG.AI_AttackRange && this.attackCD <= 0) this.attack(tgt, ctx);
        if (d < CFG.AI_AttackRange) this.stateTime = Math.max(this.stateTime, 3);
        break;
      }
      case 'flee': {
        const from = this.aggroTarget ? this.aggroTarget.pos : player.pos;
        const away = this.pos.clone().sub(from).setY(0).normalize().multiplyScalar(20).add(this.pos);
        target = away;
        if (this.stateTime <= 0 && this.pos.distanceTo(from) > CFG.AI_FleeRange) { this.state = 'idle'; this.stateTime = 2; }
        if (Math.hypot(this.pos.x - this.home.x, this.pos.z - this.home.z) > CFG.AI_WanderRadius * 1.8) this.state = 'return';
        break;
      }
      case 'return': {
        target = this.home;
        if (Math.hypot(this.pos.x - this.home.x, this.pos.z - this.home.z) < 4) { this.state = 'idle'; this.stateTime = 2; this.hp = this.maxHp; }
        break;
      }
      case 'raid': {
        // AIRaidSystem: walk to the base centre, steal coins if allowed to linger, attack the player if close
        const c = this.raidTarget;
        const d = Math.hypot(c.x - this.pos.x, c.z - this.pos.z);
        if (playerTargetable && dPlayer < 22) { wantFace = player.pos; if (this.attackCD <= 0) this.attack(player, ctx); }
        if (d > 5) target = c;
        else {
          this.stealTimer += dt;
          if (this.stealTimer > 6) { this.mgr.onRaidSteal(this); this.stealTimer = -999; this.state = 'flee'; this.aggroTarget = { pos: c }; this.stateTime = 6; this.home = this.pos.clone().add(new THREE.Vector3(rand(-80, 80), 0, rand(-80, 80))); this.despawnAfterFlee = true; }
        }
        break;
      }
    }

    if (this.despawnAfterFlee && this.state !== 'flee') { this.mgr.despawn(this); return; }

    // steering
    let desired = 0;
    if (target) {
      const dx = target.x - this.pos.x, dz = target.z - this.pos.z;
      const want = Math.atan2(dx, dz);
      this.yaw += angleDiff(this.yaw, want) * Math.min(1, dt * 6);
      desired = this.moveSpeed();
    } else if (wantFace) {
      this.yaw += angleDiff(this.yaw, Math.atan2(wantFace.x - this.pos.x, wantFace.z - this.pos.z)) * Math.min(1, dt * 6);
    }
    this.speed += (desired - this.speed) * Math.min(1, dt * 5);
    if (this.speed > 0.05) {
      let nx = this.pos.x + Math.sin(this.yaw) * this.speed * dt;
      let nz = this.pos.z + Math.cos(this.yaw) * this.speed * dt;
      [nx, nz] = world.resolveCollision(nx, nz, this.model.radius * 0.6);
      // stay out of the hub (safe zone) unless raiding
      const r = Math.hypot(nx, nz);
      if (r < 75 && this.state !== 'raid') { nx *= 75 / r; nz *= 75 / r; }
      this.pos.x = nx; this.pos.z = nz;
    }
    const g = world.groundAt(this.pos.x, this.pos.z, this.pos.y + 2);
    this.pos.y = g;
    this.syncModel(t);
  }

  attack(tgt, ctx) {
    this.attackCD = CFG.AI_AttackCooldown * (this.isBoss ? 0.7 : 1) + rand(0, 0.5);
    const from = this.hitCenter();
    const to = tgt.hitCenter ? tgt.hitCenter() : tgt.pos.clone().setY(tgt.pos.y + 2);
    const dmg = CFG.AI_PlayerDamage * (1 + this.stats.attack / 80) * (this.isBoss ? 1.6 : 1);
    ctx.fx.shoot({
      from, dir: to.sub(from), speed: CFG.AI_CreatureProjectileSpeed * 0.6, range: CFG.AI_AttackRange + 10,
      color: ELEMENT_COLORS[this.def.element] || 0xffffff, damage: dmg, owner: this, size: this.isBoss ? 1.8 : 1,
      targets: () => ctx.friendlyTargets(),
      onHit: (hit) => hit.takeDamage(dmg, this),
    });
  }

  dispose() {
    this.alive = false;
    this.mgr.scene.remove(this.model.root);
  }
}

export class CreatureManager {
  constructor(scene, world, hooks) {
    this.scene = scene;
    this.world = world;
    this.hooks = hooks; // { onDamaged, onFainted, onRaidSteal, isNight }
    this.list = [];
    this.time = 0;
    this.respawnTimer = 0;
  }

  pickFor(sp) {
    const type = sp.kind === 'spawn' ? null : sp.kind;
    let pool = creaturesForElements(sp.elements, type);
    if (!pool.length) pool = creaturesForElements(sp.elements, null);
    if (!pool.length) pool = Creatures.filter((c) => !c.spawnPointType);
    return weightedPick(pool, (c) => c.spawnWeight || 5);
  }

  rollVariant(def) {
    if (!this.hooks.isNight()) return 'Normal';
    const rare = ['Rare', 'Epic', 'Legendary'].includes(def.rarity);
    if (!rare && Math.random() < CFG.NightSpawnSilverChance) return 'Silver';
    if (rare && Math.random() < CFG.NightSpawnGoldChance) return 'Gold';
    return 'Normal';
  }

  populatePoint(sp) {
    const def = this.pickFor(sp);
    const n = sp.kind === 'boss' ? 1 : sp.kind === 'dungeon' ? 2 : def.behavior === 'pack' && def.packSize ? randInt(def.packSize[0], def.packSize[1]) : 1;
    const packId = n > 1 ? nextPack++ : 0;
    for (let i = 0; i < n; i++) {
      const d = i === 0 ? def : (sp.kind === 'dungeon' ? this.pickFor(sp) : def);
      const spread = sp.kind === 'boss' ? 0 : sp.kind === 'dungeon' ? 8 : 14;
      const pos = new THREE.Vector3(sp.x + rand(-spread, spread), 0, sp.z + rand(-spread, spread));
      pos.y = this.world.groundAt(pos.x, pos.z);
      const level = clamp(sp.level + randInt(-1, 1), 1, maxCreatureLevel(d.id) + (sp.kind === 'boss' ? 30 : 5));
      const c = new WildCreature(this, d, {
        level, pos, spawnPoint: sp, packId, isBoss: sp.kind === 'boss',
        variant: this.rollVariant(d), shiny: Math.random() < CFG.ShinySpawnChance,
      });
      sp.live.push(c);
      this.list.push(c);
    }
  }

  init() {
    for (const sp of this.world.spawnPoints) this.populatePoint(sp);
  }

  spawnRaid(plotCenter, count) {
    const out = [];
    const pool = Creatures.filter((c) => !c.spawnPointType && (c.behavior === 'aggressive' || c.behavior === 'pack') && ['Common', 'Uncommon'].includes(c.rarity));
    const outward = plotCenter.clone().setY(0).normalize();
    for (let i = 0; i < count; i++) {
      const def = pool[Math.floor(Math.random() * pool.length)];
      const pos = plotCenter.clone().addScaledVector(outward, 70).add(new THREE.Vector3(rand(-15, 15), 0, rand(-15, 15)));
      pos.y = this.world.groundAt(pos.x, pos.z);
      const c = new WildCreature(this, def, { level: randInt(2, 6), pos, raidTarget: plotCenter.clone() });
      c.isRaider = true;
      this.list.push(c);
      out.push(c);
    }
    return out;
  }

  alertPack(src, attacker) {
    for (const c of this.list) {
      if (c !== src && c.packId === src.packId && !c.fainted && c.pos.distanceTo(src.pos) < CFG.AI_PackCallRange) {
        c.state = 'chase'; c.aggroTarget = attacker; c.stateTime = 10;
      }
    }
  }

  onDamaged(c, dmg, attacker) { this.hooks.onDamaged && this.hooks.onDamaged(c, dmg, attacker); }
  onFainted(c, attacker) { this.hooks.onFainted && this.hooks.onFainted(c, attacker); }
  onRaidSteal(c) { this.hooks.onRaidSteal && this.hooks.onRaidSteal(c); }

  despawn(c) {
    c.dispose();
    this.list = this.list.filter((x) => x !== c);
    if (c.spawnPoint) {
      c.spawnPoint.live = c.spawnPoint.live.filter((x) => x !== c);
      if (!c.spawnPoint.live.length) c.spawnPoint.cooldown = c.spawnPoint.kind === 'boss' ? 120 : c.spawnPoint.kind === 'dungeon' ? 45 : 12;
    }
  }

  // Remove a captured creature without starting a respawn penalty.
  removeCaptured(c) { this.despawn(c); }

  update(dt, ctx) {
    this.time += dt;
    const pp = ctx.player.pos;
    const R2 = CFG.CreatureActiveRadius ** 2;
    for (const c of [...this.list]) {
      const d2 = (c.pos.x - pp.x) ** 2 + (c.pos.z - pp.z) ** 2;
      const active = d2 < R2 || c.isRaider;
      c.model.root.visible = active && !(c.capturing && c.model.root.visible === false);
      if (active) c.update(dt, this.time, ctx);
      else if (c.fainted) c.update(dt, this.time, ctx);
    }
    // refill spawn points
    this.respawnTimer -= dt;
    if (this.respawnTimer <= 0) {
      this.respawnTimer = 1;
      for (const sp of this.world.spawnPoints) {
        if (sp.live.length) continue;
        sp.cooldown -= 1;
        if (sp.cooldown <= 0 && this.list.length < CFG.MaxWorldCreatures + 60) {
          // don't pop creatures into existence right in front of the player
          if (Math.hypot(sp.x - pp.x, sp.z - pp.z) > 45) this.populatePoint(sp);
        }
      }
    }
  }

  nearestFainted(pos, range) {
    let best = null, bd = range;
    for (const c of this.list) {
      if (!c.fainted || c.capturing) continue;
      const d = c.pos.distanceTo(pos);
      if (d < bd) { bd = d; best = c; }
    }
    return best;
  }

  getById(id) { return getCreature(id); }
}
