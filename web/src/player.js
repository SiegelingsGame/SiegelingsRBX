// Player avatar, movement, and combat (PlayerCombatSystem: ranged orb + melee AOE).
import * as THREE from 'three';
import { CFG } from './config.js';
import { angleDiff, clamp } from './util.js';
import { HUB_R } from './world.js';

function box(w, h, d, color, y = 0) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), new THREE.MeshLambertMaterial({ color }));
  m.position.y = y;
  m.castShadow = true;
  return m;
}

export function buildAvatar({ shirt = 0x3a7bd5, pants = 0x2b2f3a, skin = 0xf2c9a0, hat = null } = {}) {
  const root = new THREE.Group();
  const hips = new THREE.Group(); hips.position.y = 2.0; root.add(hips);
  const torso = box(2, 2, 1, shirt, 1.0); hips.add(torso);
  const head = box(1.2, 1.2, 1.2, skin, 2.65); hips.add(head);
  const face = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.5), new THREE.MeshBasicMaterial({ color: 0x1a1a1a }));
  face.position.set(0, 2.7, 0.61); face.scale.set(1, 0.25, 1); hips.add(face);
  const face2 = face.clone(); face2.position.y = 2.55; face2.scale.set(0.5, 0.12, 1); hips.add(face2);
  if (hat) { const h = box(1.4, 0.4, 1.4, hat, 3.35); hips.add(h); const h2 = box(0.9, 0.6, 0.9, hat, 3.8); hips.add(h2); }
  const limb = (color, x, y) => { const g = new THREE.Group(); g.position.set(x, y, 0); const m = box(0.9, 2, 0.9, color, -1); g.add(m); return g; };
  const armL = limb(skin, -1.45, 1.9), armR = limb(skin, 1.45, 1.9);
  const sleeveL = box(0.95, 0.8, 0.95, shirt, -0.4); armL.add(sleeveL);
  const sleeveR = box(0.95, 0.8, 0.95, shirt, -0.4); armR.add(sleeveR);
  hips.add(armL, armR);
  const legL = limb(pants, -0.5, 0), legR = limb(pants, 0.5, 0);
  hips.add(legL, legR);
  return { root, hips, armL, armR, legL, legR, head };
}

export class Player {
  constructor(scene, world, fx) {
    this.scene = scene; this.world = world; this.fx = fx;
    this.avatar = buildAvatar({ hat: 0xd94a3a });
    // capture-card pouch on the back as a stand-in accessory
    const pouch = box(0.8, 0.9, 0.35, 0x7a4f2a, 1.0); pouch.position.z = -0.65; this.avatar.hips.add(pouch);
    scene.add(this.avatar.root);
    this.kind = 'player';
    this.pos = new THREE.Vector3(0, 0, 20);
    this.vel = new THREE.Vector3();
    this.yaw = Math.PI;
    this.onGround = true;
    this.maxHp = CFG.PlayerMaxHP;
    this.hp = this.maxHp;
    this.alive = true;
    this.rangedCD = 0; this.meleeCD = 0;
    this.walkT = 0;
    this.attackAnim = 0;
    this.lastTarget = null;
    this.inSafeZone = true;
    this.respawnTimer = 0;
    this.hurtFlash = 0;
  }

  hitCenter() { return this.pos.clone().setY(this.pos.y + 2.5); }
  hitRadius() { return 1.4; }

  damageScale(level) { return 1 + (level - 1) * 0.08; }

  takeDamage(dmg) {
    if (!this.alive || this.inSafeZone) return;
    this.hp -= dmg;
    this.hurtFlash = 0.3;
    this.onHurt && this.onHurt(dmg);
    if (this.hp <= 0) { this.hp = 0; this.alive = false; this.respawnTimer = 4; this.onDeath && this.onDeath(); }
  }

  teleport(p, yaw = null) {
    this.pos.copy(p); this.vel.set(0, 0, 0);
    if (yaw !== null) this.yaw = yaw;
  }

  update(dt, input, cam, ctx) {
    const a = this.avatar;
    this.inSafeZone = Math.hypot(this.pos.x, this.pos.z) < HUB_R + 6;
    if (!this.alive) {
      this.respawnTimer -= dt;
      a.root.rotation.x = THREE.MathUtils.lerp(a.root.rotation.x, -Math.PI / 2, 0.1);
      a.root.position.copy(this.pos);
      if (this.respawnTimer <= 0) {
        this.alive = true; this.hp = this.maxHp; a.root.rotation.x = 0;
        this.teleport(new THREE.Vector3(0, 0, 20), Math.PI);
        ctx.notify('You fainted and woke up at the Arena Hub', 'warn');
      }
      return;
    }
    if (this.inSafeZone && this.hp < this.maxHp) this.hp = Math.min(this.maxHp, this.hp + 25 * dt);
    else if (this.hp < this.maxHp) this.hp = Math.min(this.maxHp, this.hp + 1.5 * dt);

    // movement relative to camera yaw
    const fwd = new THREE.Vector3(-Math.sin(cam.yaw), 0, -Math.cos(cam.yaw));
    const right = new THREE.Vector3(-fwd.z, 0, fwd.x);
    const move = new THREE.Vector3();
    if (input.down('KeyW')) move.add(fwd);
    if (input.down('KeyS')) move.sub(fwd);
    if (input.down('KeyD')) move.add(right);
    if (input.down('KeyA')) move.sub(right);
    const sprint = input.down('ShiftLeft') || input.down('ShiftRight');
    const inWater = this.world.isWater(this.pos.x, this.pos.z);
    let speed = (sprint && !cam.aiming ? CFG.SprintSpeed : CFG.WalkSpeed) * (inWater ? 0.6 : 1) * (cam.aiming ? 0.7 : 1);
    if (move.lengthSq() > 0) move.normalize().multiplyScalar(speed);
    const accel = this.onGround ? 12 : 3;
    this.vel.x += (move.x - this.vel.x) * Math.min(1, dt * accel);
    this.vel.z += (move.z - this.vel.z) * Math.min(1, dt * accel);
    if (this.onGround && input.pressed('Space')) { this.vel.y = CFG.JumpPower; this.onGround = false; }
    this.vel.y -= CFG.Gravity * dt;

    let nx = this.pos.x + this.vel.x * dt, nz = this.pos.z + this.vel.z * dt;
    [nx, nz] = this.world.resolveCollision(nx, nz, 1.0);
    for (const b of ctx.blockers) { // simple circle blockers (NPC stalls, fountain)
      const dx = nx - b.x, dz = nz - b.z, d = Math.hypot(dx, dz);
      if (d < b.r + 1 && d > 0) { nx = b.x + (dx / d) * (b.r + 1); nz = b.z + (dz / d) * (b.r + 1); }
    }
    // step limit: refuse to walk up very steep slopes
    const gNew = this.world.groundAt(nx, nz, this.pos.y);
    const gOld = this.world.groundAt(this.pos.x, this.pos.z, this.pos.y);
    const slope = (gNew - gOld) / Math.max(0.001, Math.hypot(nx - this.pos.x, nz - this.pos.z));
    if (!(this.onGround && slope > 2.2 && gNew > this.pos.y + 0.8)) { this.pos.x = nx; this.pos.z = nz; }
    this.pos.y += this.vel.y * dt;
    const g = this.world.groundAt(this.pos.x, this.pos.z, this.pos.y);
    if (this.pos.y <= g + (this.onGround ? 0.6 : 0)) {
      if (this.vel.y <= 0) { this.pos.y = g; this.vel.y = 0; this.onGround = true; }
    } else this.onGround = false;
    if (this.pos.y < g - 5) this.pos.y = g;

    // facing: aim/attack faces camera; otherwise face movement
    const horiz = Math.hypot(this.vel.x, this.vel.z);
    if (cam.aiming || this.attackAnim > 0) this.yaw += angleDiff(this.yaw, cam.yaw + Math.PI) * Math.min(1, dt * 14);
    else if (horiz > 1) this.yaw += angleDiff(this.yaw, Math.atan2(this.vel.x, this.vel.z)) * Math.min(1, dt * 10);

    // combat
    this.rangedCD -= dt; this.meleeCD -= dt; this.attackAnim -= dt; this.hurtFlash -= dt;
    if (input.mouseDown(0) && this.rangedCD <= 0 && !this.inSafeZone) this.shoot(cam, ctx);
    if (input.pressed('KeyF') && this.meleeCD <= 0 && !this.inSafeZone) this.melee(ctx);

    // animation
    this.walkT += dt * horiz * 0.55;
    const swing = Math.sin(this.walkT) * Math.min(1, horiz / 10) * 0.9;
    a.legL.rotation.x = swing; a.legR.rotation.x = -swing;
    a.armL.rotation.x = -swing * 0.8;
    a.armR.rotation.x = this.attackAnim > 0 || cam.aiming ? -Math.PI / 2 + cam.pitch * 0.8 : swing * 0.8;
    if (!this.onGround) { a.legL.rotation.x = 0.5; a.legR.rotation.x = -0.3; }
    if (inWater) a.hips.position.y = 2.0 - 0.3 + Math.sin(performance.now() / 300) * 0.1; else a.hips.position.y = 2.0;
    a.root.position.copy(this.pos);
    a.root.rotation.y = this.yaw;
  }

  handPos() {
    this.avatar.root.updateMatrixWorld(true);
    return this.avatar.armR.localToWorld(new THREE.Vector3(0, -2.1, 0));
  }

  shoot(cam, ctx) {
    this.rangedCD = CFG.PlayerRangedCooldown;
    this.attackAnim = 0.35;
    const from = this.handPos();
    const aim = cam.aimPoint(ctx, CFG.PlayerRangedRange);
    const dir = aim.point.clone().sub(from);
    const dmg = CFG.PlayerRangedDamage * this.damageScale(ctx.playerLevel());
    this.fx.shoot({
      from, dir, speed: CFG.PlayerRangedSpeed, range: CFG.PlayerRangedRange + 10, color: 0x9fe8ff, damage: dmg, owner: this,
      homing: aim.target && aim.target.alive ? aim.target : null,
      targets: () => ctx.creatures.list,
      onHit: (hit) => { this.lastTarget = hit; hit.takeDamage(dmg, this); },
    });
  }

  melee(ctx) {
    this.meleeCD = CFG.PlayerMeleeCooldown;
    this.attackAnim = 0.4;
    const f = new THREE.Vector3(Math.sin(this.yaw), 0, Math.cos(this.yaw));
    const center = this.pos.clone().addScaledVector(f, 4);
    this.fx.ring(center, 0x9fe8ff, 6, 0.4);
    const dmg = CFG.PlayerMeleeDamage * this.damageScale(ctx.playerLevel());
    for (const c of ctx.creatures.list) {
      if (c.fainted) continue;
      if (c.pos.distanceTo(center) < CFG.PlayerMeleeRange * 0.8 + c.model.radius) { this.lastTarget = c; c.takeDamage(dmg, this); }
    }
  }
}

// Third-person over-the-shoulder camera with right-mouse aim zoom and terrain collision.
export class ShoulderCamera {
  constructor(camera, world) {
    this.cam = camera; this.world = world;
    this.yaw = 0; this.pitch = -0.15;
    this.side = 1; // 1 = right shoulder, -1 = left
    this.aiming = false;
    this.dist = 9; this.curDist = 9;
    this.sens = 0.0024;
    this.sideLerp = 1;
  }
  onMouse(dx, dy) {
    const s = this.aiming ? this.sens * 0.6 : this.sens;
    this.yaw -= dx * s;
    this.pitch = clamp(this.pitch - dy * s, -1.15, 0.6);
  }
  forward() {
    return new THREE.Vector3(-Math.sin(this.yaw) * Math.cos(this.pitch), Math.sin(this.pitch), -Math.cos(this.yaw) * Math.cos(this.pitch));
  }
  update(dt, player, input) {
    this.aiming = input.mouseDown(2);
    this.sideLerp += (this.side - this.sideLerp) * Math.min(1, dt * 8);
    const want = this.aiming ? 4.2 : this.dist;
    const fwd = this.forward();
    const right = new THREE.Vector3(Math.cos(this.yaw), 0, -Math.sin(this.yaw));
    const pivot = player.pos.clone().add(new THREE.Vector3(0, 4.6, 0)).addScaledVector(right, (this.aiming ? 1.7 : 2.0) * this.sideLerp);
    // pull in if terrain blocks the view
    let d = want;
    for (let i = 1; i <= 8; i++) {
      const k = (i / 8) * want;
      const p = pivot.clone().addScaledVector(fwd, -k);
      if (p.y < this.world.terrainHeight(p.x, p.z) + 0.8) { d = Math.max(1.5, k - 0.8); break; }
    }
    this.curDist += (d - this.curDist) * Math.min(1, dt * (d < this.curDist ? 20 : 6));
    const pos = pivot.clone().addScaledVector(fwd, -this.curDist);
    const g = this.world.terrainHeight(pos.x, pos.z) + 0.8;
    if (pos.y < g) pos.y = g;
    this.cam.position.copy(pos);
    this.cam.lookAt(pivot.clone().addScaledVector(fwd, 30));
    const fov = this.aiming ? 50 : 70;
    this.cam.fov += (fov - this.cam.fov) * Math.min(1, dt * 10);
    this.cam.updateProjectionMatrix();
  }
  // Ray from screen centre: returns nearest creature hit (with slight aim assist) or a point at range.
  aimPoint(ctx, range) {
    const origin = this.cam.position.clone();
    const dir = new THREE.Vector3(); this.cam.getWorldDirection(dir);
    let best = null, bestT = Infinity;
    for (const c of ctx.creatures.list) {
      if (c.fainted || !c.model.root.visible) continue;
      const cc = c.hitCenter();
      const t = cc.clone().sub(origin).dot(dir);
      if (t < 0 || t > range + this.curDist + 10) continue;
      const closest = origin.clone().addScaledVector(dir, t);
      const miss = closest.distanceTo(cc);
      const assist = c.hitRadius() + t * 0.035;
      if (miss < assist && t < bestT) { bestT = t; best = c; }
    }
    if (best) return { point: best.hitCenter(), target: best };
    // march to terrain
    for (let t = 2; t < range + this.curDist; t += 2) {
      const p = origin.clone().addScaledVector(dir, t);
      if (p.y < this.world.terrainHeight(p.x, p.z)) return { point: p, target: null };
    }
    return { point: origin.addScaledVector(dir, range + this.curDist), target: null };
  }
}
