// Projectiles, particles, capture-card animation and other transient effects.
import * as THREE from 'three';
import { ELEMENT_COLORS } from './config.js';

const MAX_PARTICLES = 2500;

export class FX {
  constructor(scene) {
    this.scene = scene;
    this.projectiles = [];
    this.tweens = [];
    // particle pool rendered as one Points object
    const geo = new THREE.BufferGeometry();
    this.pPos = new Float32Array(MAX_PARTICLES * 3);
    this.pCol = new Float32Array(MAX_PARTICLES * 3);
    geo.setAttribute('position', new THREE.BufferAttribute(this.pPos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(this.pCol, 3));
    this.pGeo = geo;
    this.points = new THREE.Points(geo, new THREE.PointsMaterial({ size: 0.55, vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending }));
    this.points.frustumCulled = false;
    scene.add(this.points);
    this.particles = [];
    this.projGeo = new THREE.IcosahedronGeometry(0.45, 1);
    this.projMats = new Map();
  }

  projMat(color) {
    if (!this.projMats.has(color)) this.projMats.set(color, new THREE.MeshBasicMaterial({ color }));
    return this.projMats.get(color);
  }

  // Fire a projectile. onHit(target) is called when it reaches a target from `targets()`.
  shoot({ from, dir, speed, range, color = 0x9fe8ff, radius = 0.45, damage, owner, targets, onHit, homing = null, size = 1 }) {
    const mesh = new THREE.Mesh(this.projGeo, this.projMat(color));
    mesh.scale.setScalar(size);
    mesh.position.copy(from);
    this.scene.add(mesh);
    this.projectiles.push({ mesh, vel: dir.clone().normalize().multiplyScalar(speed), speed, travelled: 0, range, color: new THREE.Color(color), radius, damage, owner, targets, onHit, homing });
  }

  burst(pos, color = 0xffffff, count = 14, speed = 6, life = 0.6, up = 2) {
    const c = new THREE.Color(color);
    for (let i = 0; i < count; i++) {
      if (this.particles.length >= MAX_PARTICLES) this.particles.shift();
      const v = new THREE.Vector3(Math.random() - 0.5, Math.random() * 0.8 + 0.1, Math.random() - 0.5).normalize().multiplyScalar(speed * (0.4 + Math.random() * 0.6));
      v.y += up;
      this.particles.push({ p: pos.clone(), v, life, max: life, c });
    }
  }

  ring(pos, color = 0xffe066, radius = 4, life = 0.8) {
    const m = new THREE.Mesh(new THREE.RingGeometry(0.6, 1, 40).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color, transparent: true, side: THREE.DoubleSide, depthWrite: false }));
    m.position.copy(pos).y += 0.3;
    this.scene.add(m);
    this.tween(life, (t) => { m.scale.setScalar(1 + t * radius); m.material.opacity = 1 - t; }, () => { this.scene.remove(m); m.geometry.dispose(); m.material.dispose(); });
  }

  tween(duration, onUpdate, onDone) {
    this.tweens.push({ t: 0, duration, onUpdate, onDone });
  }

  // Capture: card thrown in an arc, creature shrinks into it, card flies back to the player.
  captureAnimation(fromFn, creature, duration, onDone, onCancelCheck) {
    const card = new THREE.Mesh(new THREE.BoxGeometry(0.9, 1.3, 0.08), new THREE.MeshBasicMaterial({ color: 0xffe9a6 }));
    const edge = new THREE.Mesh(new THREE.BoxGeometry(1.05, 1.45, 0.05), new THREE.MeshBasicMaterial({ color: ELEMENT_COLORS[creature.def.element] || 0xffffff }));
    card.add(edge);
    this.scene.add(card);
    const beam = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.15, 1, 6, 1, true), new THREE.MeshBasicMaterial({ color: 0xfff3a0, transparent: true, opacity: 0.6, depthWrite: false }));
    this.scene.add(beam);
    const startScale = creature.model.root.scale.x;
    const color = ELEMENT_COLORS[creature.def.element] || 0xffffff;
    let cancelled = false;
    this.tween(duration, (t) => {
      if (!cancelled && onCancelCheck && onCancelCheck()) { cancelled = true; }
      if (cancelled) return;
      const from = fromFn();
      const target = creature.pos.clone().add(new THREE.Vector3(0, creature.model.height * 0.6 + 1.5, 0));
      if (t < 0.3) { // throw
        const k = t / 0.3;
        card.position.lerpVectors(from, target, k);
        card.position.y += Math.sin(k * Math.PI) * 4;
        card.rotation.y += 0.4; card.rotation.x += 0.2;
        beam.visible = false;
      } else if (t < 0.75) { // absorb
        const k = (t - 0.3) / 0.45;
        card.position.copy(target).y += Math.sin(t * 20) * 0.1;
        card.rotation.set(0, card.rotation.y + 0.15, 0);
        creature.model.root.scale.setScalar(startScale * (1 - k * 0.95));
        creature.model.root.position.y = creature.pos.y + k * 1.5;
        beam.visible = true;
        beam.position.copy(target).lerp(creature.pos, 0.5);
        beam.scale.set(1, target.distanceTo(creature.pos), 1);
        if (Math.random() < 0.6) this.burst(creature.pos.clone().add(new THREE.Vector3(0, 1, 0)), color, 2, 3, 0.5, 2);
      } else { // return
        const k = (t - 0.75) / 0.25;
        creature.model.root.visible = false;
        beam.visible = false;
        card.position.lerpVectors(target, from, k);
        card.rotation.y += 0.5;
      }
    }, () => {
      this.scene.remove(card); this.scene.remove(beam);
      card.geometry.dispose(); edge.geometry.dispose(); beam.geometry.dispose();
      if (cancelled) { creature.model.root.scale.setScalar(startScale); creature.model.root.visible = true; }
      onDone(!cancelled);
    });
  }

  update(dt, world) {
    // projectiles
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const pr = this.projectiles[i];
      if (pr.homing && pr.homing.alive) {
        const want = pr.homing.pos.clone().add(new THREE.Vector3(0, pr.homing.model.height * 0.5, 0)).sub(pr.mesh.position).normalize().multiplyScalar(pr.speed);
        pr.vel.lerp(want, Math.min(1, dt * 8));
      }
      const step = pr.vel.clone().multiplyScalar(dt);
      pr.mesh.position.add(step);
      pr.travelled += step.length();
      if (Math.random() < 0.7) this.burst(pr.mesh.position, pr.color, 1, 0.6, 0.3, 0);
      let hit = null;
      for (const t of pr.targets()) {
        if (!t.alive || t === pr.owner) continue;
        const c = t.hitCenter();
        if (c.distanceToSquared(pr.mesh.position) < (t.hitRadius() + pr.radius) ** 2) { hit = t; break; }
      }
      const ground = world.groundAt(pr.mesh.position.x, pr.mesh.position.z, pr.mesh.position.y);
      if (hit || pr.travelled > pr.range || pr.mesh.position.y < ground) {
        this.burst(pr.mesh.position, pr.color, hit ? 16 : 6, hit ? 8 : 3, 0.5, 1);
        if (hit && pr.onHit) pr.onHit(hit, pr);
        this.scene.remove(pr.mesh);
        this.projectiles.splice(i, 1);
      }
    }
    // particles
    let n = 0;
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const p = this.particles[i];
      p.life -= dt;
      if (p.life <= 0) { this.particles.splice(i, 1); continue; }
      p.v.y -= 9 * dt;
      p.p.addScaledVector(p.v, dt);
    }
    for (const p of this.particles) {
      const k = p.life / p.max;
      this.pPos[n * 3] = p.p.x; this.pPos[n * 3 + 1] = p.p.y; this.pPos[n * 3 + 2] = p.p.z;
      this.pCol[n * 3] = p.c.r * k; this.pCol[n * 3 + 1] = p.c.g * k; this.pCol[n * 3 + 2] = p.c.b * k;
      n++;
    }
    this.pGeo.setDrawRange(0, n);
    this.pGeo.attributes.position.needsUpdate = true;
    this.pGeo.attributes.color.needsUpdate = true;
    // tweens
    for (let i = this.tweens.length - 1; i >= 0; i--) {
      const tw = this.tweens[i];
      tw.t += dt;
      const k = Math.min(1, tw.t / tw.duration);
      tw.onUpdate(k);
      if (k >= 1) { this.tweens.splice(i, 1); tw.onDone && tw.onDone(); }
    }
  }
}
