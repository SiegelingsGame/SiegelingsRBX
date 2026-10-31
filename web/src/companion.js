// Favorite creature companion (FavoriteCreatureSystem): follows the player and fights.
import * as THREE from 'three';
import { CFG, ELEMENT_COLORS } from './config.js';
import { State } from './state.js';
import { getCreature, effectiveStats } from './data.js';
import { buildCreatureModel } from './creatureModel.js';
import { angleDiff } from './util.js';

export class Companion {
  constructor(scene, world, fx) {
    this.scene = scene; this.world = world; this.fx = fx;
    this.kind = 'companion';
    this.uid = '';
    this.model = null;
    this.alive = false;
    this.pos = new THREE.Vector3();
    this.yaw = 0; this.speed = 0;
    this.cd = 0;
    this.respawn = 0;
    this.time = 0;
  }

  get entry() { return this.uid ? State.get(this.uid) : null; }
  hitCenter() { return this.pos.clone().setY(this.pos.y + this.model.height * 0.5); }
  hitRadius() { return this.model ? this.model.radius : 1; }

  sync(player) {
    const want = State.data.favoriteUid;
    if (want === this.uid && (this.model || this.respawn > 0)) return;
    this.despawn();
    this.uid = want;
    if (!want) return;
    this.spawn(player);
  }

  spawn(player) {
    const e = this.entry;
    if (!e) return;
    this.def = getCreature(e.id);
    this.stats = effectiveStats(e.id, e.level, e.variant);
    this.maxHp = this.stats.health * 3;
    this.hp = this.maxHp;
    this.model = buildCreatureModel(this.def, { variant: e.variant, shiny: e.shiny });
    this.pos.copy(player.pos).add(new THREE.Vector3(3, 0, 3));
    this.scene.add(this.model.root);
    this.alive = true;
    this.respawn = 0;
    this.fx.burst(this.pos.clone().setY(this.pos.y + 1), ELEMENT_COLORS[this.def.element], 24, 6, 0.7, 3);
  }

  despawn() {
    if (this.model) this.scene.remove(this.model.root);
    this.model = null; this.alive = false;
  }

  heal() {
    if (this.uid && !this.model) { this.respawn = 0; this.spawnPending = true; }
    if (this.model) this.hp = this.maxHp;
  }

  takeDamage(dmg) {
    if (!this.alive) return;
    this.hp -= Math.max(1, dmg * (1 - this.stats.defense / (this.stats.defense + 140)));
    if (this.hp <= 0) {
      this.fx.burst(this.hitCenter(), 0xffffff, 20, 6);
      this.despawn();
      this.respawn = CFG.CompanionRespawnCD;
      this.onFaint && this.onFaint();
    }
  }

  update(dt, ctx) {
    this.time += dt;
    const { player } = ctx;
    this.sync(player);
    if (!this.model) {
      if (this.uid && (this.respawn > 0 || this.spawnPending)) {
        this.respawn -= dt;
        if (this.respawn <= 0) { this.spawnPending = false; this.spawn(player); }
      }
      return;
    }
    const e = this.entry;
    if (!e) { this.despawn(); return; }
    this.stats = effectiveStats(e.id, e.level, e.variant);
    if (this.hp < this.maxHp) this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.02 * dt);

    // choose target: player's last hit, else anything attacking the player
    let target = player.lastTarget && player.lastTarget.alive && !player.lastTarget.fainted ? player.lastTarget : null;
    if (!target) {
      let bd = CFG.CompanionAttackRange;
      for (const c of ctx.creatures.list) {
        if (c.fainted || !c.alive || !(c.state === 'chase' || c.isRaider)) continue;
        const d = c.pos.distanceTo(player.pos);
        if (d < bd) { bd = d; target = c; }
      }
    }
    if (target && target.pos.distanceTo(player.pos) > CFG.CompanionAttackRange * 1.5) target = null;

    // follow position: behind-left of the player
    const behind = new THREE.Vector3(Math.sin(player.yaw), 0, Math.cos(player.yaw)).multiplyScalar(-CFG.CompanionFollowDist);
    const side = new THREE.Vector3(Math.cos(player.yaw), 0, -Math.sin(player.yaw)).multiplyScalar(3);
    const follow = player.pos.clone().add(behind).add(side);
    let goal = follow;
    if (target) {
      const d = target.pos.distanceTo(this.pos);
      if (d > 14) goal = target.pos;
      else goal = null;
    }
    const dist = player.pos.distanceTo(this.pos);
    if (dist > 120) { this.pos.copy(follow); } // auto-recall
    let desired = 0;
    if (goal) {
      const dx = goal.x - this.pos.x, dz = goal.z - this.pos.z, d = Math.hypot(dx, dz);
      if (d > 1.5) {
        this.yaw += angleDiff(this.yaw, Math.atan2(dx, dz)) * Math.min(1, dt * 8);
        desired = Math.min(d * 2, d > 18 ? 34 : CFG.WalkSpeed + 2);
      }
    } else if (target) this.yaw += angleDiff(this.yaw, Math.atan2(target.pos.x - this.pos.x, target.pos.z - this.pos.z)) * Math.min(1, dt * 8);
    else if (dist < 6) this.yaw += angleDiff(this.yaw, player.yaw) * Math.min(1, dt * 3);
    this.speed += (desired - this.speed) * Math.min(1, dt * 6);
    this.pos.x += Math.sin(this.yaw) * this.speed * dt;
    this.pos.z += Math.cos(this.yaw) * this.speed * dt;
    [this.pos.x, this.pos.z] = this.world.resolveCollision(this.pos.x, this.pos.z, 0.8);
    this.pos.y = this.world.groundAt(this.pos.x, this.pos.z, Math.max(this.pos.y, player.pos.y) + 1);
    this.model.root.position.copy(this.pos);
    this.model.root.rotation.y = this.yaw;
    this.model.animate(this.time, this.speed);

    this.cd -= dt;
    if (target && this.cd <= 0 && target.pos.distanceTo(this.pos) < CFG.CompanionAttackRange * 0.7) {
      this.cd = CFG.CompanionAttackCD;
      const from = this.hitCenter();
      const dmg = Math.max(2, CFG.CompanionBaseDamage * this.stats.attack / 10 * 1.6);
      this.fx.shoot({
        from, dir: target.hitCenter().sub(from), speed: 90, range: CFG.CompanionAttackRange + 10, color: ELEMENT_COLORS[this.def.element] || 0xffffff,
        damage: dmg, owner: this, homing: target, targets: () => ctx.creatures.list, size: 1.2,
        onHit: (hit) => {
          hit.takeDamage(dmg, this);
          if (hit.fainted) { State.addCreatureXP(this.uid, 8); }
        },
      });
    }
  }
}
