// Projectiles, particles, capture-card animation and other transient effects.
import * as THREE from 'three';
import { ELEMENT_COLORS } from './config.js';
import { ATLAS_URL, ATLAS_GRID, FRAMES } from './fxAtlas.js';

const VERT = `attribute vec3 color; attribute vec4 info; uniform float uScale; varying vec3 vColor; varying vec3 vInfo;
  void main() { vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mv; gl_PointSize = info.x * uScale / max(0.1, -mv.z); vColor = color; vInfo = info.yzw; }`;
const FRAG = `uniform sampler2D map; uniform float grid; varying vec3 vColor; varying vec3 vInfo;
  void main() { vec2 pc = gl_PointCoord - 0.5; float cs = cos(vInfo.z), sn = sin(vInfo.z); pc = vec2(pc.x * cs - pc.y * sn, pc.x * sn + pc.y * cs) + 0.5;
    if (pc.x < 0.0 || pc.x > 1.0 || pc.y < 0.0 || pc.y > 1.0) discard; pc = clamp(pc, 0.02, 0.98);
    float f = floor(vInfo.x + 0.5); vec2 cell = vec2(mod(f, grid), floor(f / grid));
    vec4 t = texture2D(map, vec2((cell.x + pc.x) / grid, 1.0 - (cell.y + pc.y) / grid));
    float a = t.a * vInfo.y; if (a < 0.03) discard; gl_FragColor = vec4(t.rgb * vColor, a);
    #include <colorspace_fragment>
  }`;

class ParticleLayer {
  constructor(scene, tex, blending, max) {
    this.max = max; this.list = [];
    this.pos = new Float32Array(max * 3); this.col = new Float32Array(max * 3); this.info = new Float32Array(max * 4);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(this.col, 3));
    geo.setAttribute('info', new THREE.BufferAttribute(this.info, 4));
    this.geo = geo;
    this.mat = new THREE.ShaderMaterial({ uniforms: { map: { value: tex }, grid: { value: ATLAS_GRID }, uScale: { value: 600 } }, vertexShader: VERT, fragmentShader: FRAG, transparent: true, depthWrite: false, blending });
    this.points = new THREE.Points(geo, this.mat);
    this.points.frustumCulled = false;
    scene.add(this.points);
  }
  add(p) { if (this.list.length >= this.max) this.list.shift(); this.list.push(p); }
  update(dt, uScale) {
    this.mat.uniforms.uScale.value = uScale;
    const L = this.list;
    let n = 0;
    for (let i = 0; i < L.length; i++) {
      const p = L[i];
      p.life -= dt;
      if (p.life <= 0) continue;
      p.v.y -= p.g * dt; p.p.addScaledVector(p.v, dt); p.rot += p.spin * dt;
      const k = p.life / p.max;
      this.pos[n * 3] = p.p.x; this.pos[n * 3 + 1] = p.p.y; this.pos[n * 3 + 2] = p.p.z;
      this.col[n * 3] = p.c.r; this.col[n * 3 + 1] = p.c.g; this.col[n * 3 + 2] = p.c.b;
      this.info[n * 4] = p.size * (1 + (p.grow || 0) * (1 - k)); this.info[n * 4 + 1] = p.frame; this.info[n * 4 + 2] = Math.min(1, k * 2.2); this.info[n * 4 + 3] = p.rot;
      L[n++] = p;
    }
    L.length = n;
    this.geo.setDrawRange(0, n);
    this.geo.attributes.position.needsUpdate = true; this.geo.attributes.color.needsUpdate = true; this.geo.attributes.info.needsUpdate = true;
  }
}


export class FX {
  constructor(scene) {
    this.scene = scene;
    this.projectiles = [];
    this.tweens = [];
    this.spriteMats = new Map();
    // two particle layers sharing one sprite atlas: additive glows and normal-blended pixel sprites
    const tex = new THREE.TextureLoader().load(ATLAS_URL, () => { for (const m of this.spriteMats.values()) m.map.needsUpdate = true; });
    tex.magFilter = THREE.NearestFilter; tex.minFilter = THREE.NearestFilter; tex.generateMipmaps = false;
    tex.colorSpace = THREE.SRGBColorSpace;
    this.atlas = tex;
    this.glow = new ParticleLayer(scene, tex, THREE.AdditiveBlending, 2200);
    this.pix = new ParticleLayer(scene, tex, THREE.NormalBlending, 1800);
    this.view = null; // { renderer, camera } for point sizing
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

  // Soft glowing motes (additive).
  burst(pos, color = 0xffffff, count = 14, speed = 6, life = 0.6, up = 2, size = 1.0) {
    const c = new THREE.Color(color);
    for (let i = 0; i < count; i++) {
      const v = new THREE.Vector3(Math.random() - 0.5, Math.random() * 0.8 + 0.1, Math.random() - 0.5).normalize().multiplyScalar(speed * (0.4 + Math.random() * 0.6));
      v.y += up;
      this.glow.add({ p: pos.clone(), v, life, max: life, c, size: size * (0.7 + Math.random() * 0.6), frame: 0, g: 9, spin: 0, rot: 0 });
    }
  }

  // Pixel-art sprites from the atlas (frame = name in FRAMES). opts.vel aims them; otherwise they scatter.
  sprites(pos, frame, { count = 4, speed = 5, life = 0.6, up = 2, size = 1.6, gravity = 9, spin = 5, spread = 1, vel = null, tint = 0xffffff, grow = 0 } = {}) {
    const f = FRAMES[frame] ?? 0, c = new THREE.Color(tint);
    for (let i = 0; i < count; i++) {
      const v = new THREE.Vector3(Math.random() - 0.5, Math.random() * 0.8 + 0.1, Math.random() - 0.5).normalize().multiplyScalar(speed * (0.4 + Math.random() * 0.6) * spread);
      v.y += up;
      if (vel) v.add(vel);
      this.pix.add({ p: pos.clone(), v, life: life * (0.8 + Math.random() * 0.4), max: life, c, size: size * (0.8 + Math.random() * 0.4), frame: f, g: gravity, spin: (Math.random() - 0.5) * spin, rot: spin ? Math.random() * 6.28 : 0, grow });
    }
  }

  // Material for a THREE.Sprite showing one atlas frame (projectiles, orbs, traps).
  spriteMaterial(frame) {
    if (!this.spriteMats.has(frame)) {
      const f = FRAMES[frame] ?? 0, t = this.atlas.clone();
      t.repeat.set(1 / ATLAS_GRID, 1 / ATLAS_GRID);
      t.offset.set((f % ATLAS_GRID) / ATLAS_GRID, 1 - (Math.floor(f / ATLAS_GRID) + 1) / ATLAS_GRID);
      if (this.atlas.image) t.needsUpdate = true; // otherwise flagged when the atlas finishes loading
      this.spriteMats.set(frame, new THREE.SpriteMaterial({ map: t, alphaTest: 0.3, fog: false }));
    }
    return this.spriteMats.get(frame);
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
    let uScale = 600;
    if (this.view) uScale = this.view.renderer.domElement.height / (2 * Math.tan(THREE.MathUtils.degToRad(this.view.camera.fov) / 2));
    this.glow.update(dt, uScale);
    this.pix.update(dt, uScale);
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
