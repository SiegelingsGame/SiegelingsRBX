// Element-themed run arenas. Each biome gets its own heightfield, props and set pieces, generated
// far from the base world (so the arena can be big and shaped freely) and torn down after the run.
//
//   forest    rolling hills and river valleys, dense trees
//   volcanic  rough basalt, volcano cones with lava craters, lava pools, lava-tube caves
//   frozen    snow hills, a frozen lake, ice ridges, ice caves
//   highlands terraced mesas cut by gorges, floating rocks
//   electric  crystal terraces and canyons, crystal spires
//   caves     sunken caverns, stalagmite columns, many tunnels
//   ocean     an archipelago of islands in shallow water
//   desert    dune fields, a dry canyon, ruined pillars
import * as THREE from 'three';
import { fbm, mulberry32, smoothstep, clamp, lerp, hashStr } from './util.js';
import { BIOMES, makePropGeometries, setArenaRegion } from './world.js';

export const ARENA_CENTER = new THREE.Vector3(0, 0, 4200);
export const ARENA_R = 300;
const MARGIN = 110;            // cliff rim outside the playable radius
const SEG = 260;

const PALETTES = {
  forest:    { low: 0x3f7a35, mid: 0x5d9a44, high: 0x8fbf5a, rock: 0x6b6152, extra: 0x2f5f2a },
  volcanic:  { low: 0x3a2622, mid: 0x5a3328, high: 0x2a2020, rock: 0x1f1a1a, extra: 0xff5a14 },
  frozen:    { low: 0xcfe2f0, mid: 0xe8f2fa, high: 0xffffff, rock: 0x8a9cb0, extra: 0x9fdcff },
  highlands: { low: 0x7fae55, mid: 0x9ccf6e, high: 0xc7e39a, rock: 0x9a8a6a, extra: 0x6a9a4a },
  electric:  { low: 0x2e2852, mid: 0x3e3766, high: 0x5a4f8a, rock: 0x241f3e, extra: 0xffe63c },
  caves:     { low: 0x2c2832, mid: 0x3e3846, high: 0x55505e, rock: 0x1e1b22, extra: 0x8a5cff },
  ocean:     { low: 0xb8a878, mid: 0xe0d29a, high: 0x6fae55, rock: 0x8a8070, extra: 0x2f8fd8 },
  desert:    { low: 0xc9a25a, mid: 0xe2c071, high: 0xf0d79a, rock: 0xa47a48, extra: 0x9a7436 },
};
// prop types (from world.js makePropGeometries) and their density per biome
const PROPS = {
  forest:    [['tree', 0.5], ['bush', 0.2], ['flower', 0.12], ['rock', 0.04]],
  volcanic:  [['deadTree', 0.12], ['lavaRock', 0.25], ['ember', 0.06]],
  frozen:    [['pine', 0.28], ['iceCrystal', 0.08], ['snowRock', 0.08]],
  highlands: [['grass', 0.35], ['flower', 0.12], ['tree', 0.05], ['rock', 0.06]],
  electric:  [['crystal', 0.2], ['pylon', 0.02], ['rock', 0.08]],
  caves:     [['stalagmite', 0.3], ['mushroom', 0.16], ['rock', 0.1]],
  ocean:     [['palm', 0.14], ['coral', 0.2], ['rock', 0.05]],
  desert:    [['cactus', 0.1], ['rock', 0.08], ['bones', 0.04]],
};

function segDist(px, pz, a, b) {
  const vx = b.x - a.x, vz = b.z - a.z, wx = px - a.x, wz = pz - a.z;
  const t = clamp((wx * vx + wz * vz) / (vx * vx + vz * vz), 0, 1);
  return Math.hypot(wx - vx * t, wz - vz * t);
}

// Base height per biome in local coordinates (u, v from the arena centre).
function baseHeight(biome, u, v, F) {
  const n = fbm(u * 0.007 + 13, v * 0.007 - 7, 4) - 0.5;
  const n2 = fbm(u * 0.025, v * 0.025, 3) - 0.5;
  const ridge = 1 - Math.abs(fbm(u * 0.005 + 40, v * 0.005 + 40, 3) * 2 - 1); // 1 along ridge lines
  switch (biome) {
    case 'forest': {
      const hills = n * 70 + n2 * 6;
      const river = 1 - smoothstep(0, 0.07, Math.abs(fbm(u * 0.0035 + 5, v * 0.0035 - 9, 2) - 0.5));
      return hills * (1 - river * 0.7) - river * 16;
    }
    case 'volcanic': {
      let h = n * 26 + Math.abs(n2) * 10;
      for (const c of F.cones) {
        const d = Math.hypot(u - c.u, v - c.v);
        if (d < c.r) h += c.h * Math.pow(1 - d / c.r, 1.5);
        if (d < c.crater) h -= (1 - d / c.crater) * c.h * 0.45;
      }
      return h;
    }
    case 'frozen': return n * 46 + Math.pow(ridge, 4) * 22 + n2 * 4;
    case 'highlands': {
      const raw = (n + 0.5) * 70;
      const terr = Math.floor(raw / 10) * 10 + smoothstep(0.75, 1, (raw % 10) / 10) * 10; // flat mesas, short cliffs
      const gorge = 1 - smoothstep(0, 0.06, Math.abs(fbm(u * 0.004 - 20, v * 0.004 + 3, 2) - 0.5));
      return terr - gorge * 26 - 20;
    }
    case 'electric': {
      const raw = (n + 0.5) * 48;
      const canyon = Math.pow(ridge, 6) * 22;
      return Math.floor(raw / 6) * 6 + n2 * 2 - canyon;
    }
    case 'caves': return n * 34 + Math.abs(n2) * 12 - Math.pow(ridge, 5) * 18;
    case 'ocean': {
      let h = -6 + n2 * 2;
      for (const isl of F.islands) {
        const d = Math.hypot(u - isl.u, v - isl.v) / isl.r;
        if (d < 1.3) h = Math.max(h, lerp(isl.h, -6, smoothstep(0.35, 1.25, d)) + n2 * 3);
      }
      return h;
    }
    case 'desert': {
      const dunes = Math.sin(u * 0.045 + n * 7) * 6 + Math.sin(v * 0.028 + u * 0.01) * 4 + n * 26;
      const canyon = 1 - smoothstep(4, 22, F.canyon ? segDist(u, v, F.canyon[0], F.canyon[1]) : 1e9);
      return dunes - canyon * 20;
    }
    default: return n * 30;
  }
}

export function generateArena(scene, biome) {
  const rng = mulberry32(hashStr('arena:' + biome));
  const R = ARENA_R, half = R + MARGIN, size = half * 2, cell = size / SEG, N = SEG + 1;
  const cx = ARENA_CENTER.x, cz = ARENA_CENTER.z;
  const rnd = (a, b) => a + rng() * (b - a);
  const ringPos = (minR, maxR) => { const a = rng() * Math.PI * 2, r = rnd(minR, maxR); return { u: Math.cos(a) * r, v: Math.sin(a) * r }; };

  // ── set pieces decided before the heightfield so the terrain can be shaped around them ──
  const F = { cones: [], islands: [], pools: [], caves: [], lake: null, canyon: null, ruins: [] };
  if (biome === 'volcanic') {
    for (let i = 0; i < 3; i++) { const p = ringPos(90, R - 70); F.cones.push({ ...p, r: rnd(45, 70), h: rnd(38, 55), crater: rnd(10, 16) }); }
    for (let i = 0; i < 14; i++) { const p = ringPos(40, R - 20); F.pools.push({ ...p, r: rnd(7, 14), depth: 3, kind: 'lava' }); }
  }
  if (biome === 'frozen') { const p = ringPos(60, 130); F.lake = { ...p, r: rnd(65, 85) }; }
  if (biome === 'ocean') {
    F.islands.push({ u: 0, v: 0, r: 60, h: 4 }); // the start island
    for (let i = 0; i < 9; i++) { const p = ringPos(90, R - 30); F.islands.push({ ...p, r: rnd(28, 55), h: rnd(3, 14) }); }
  }
  if (biome === 'desert') {
    const a = rng() * Math.PI;
    F.canyon = [{ x: Math.cos(a) * (R - 20), z: Math.sin(a) * (R - 20) }, { x: Math.cos(a + Math.PI) * (R - 20) + 40, z: Math.sin(a + Math.PI) * (R - 20) }]; // segDist takes {x, z}
    for (let i = 0; i < 5; i++) F.ruins.push(ringPos(60, R - 40));
  }
  // Underground tunnels: a ramp down at each end, a covered section below the surface, and a
  // roof flush with the ground above so the surface stays walkable.
  const caveCount = { volcanic: 3, frozen: 2, caves: 6, electric: 2, highlands: 1, forest: 2, desert: 2, ocean: 0 }[biome] || 0;
  for (let i = 0; i < caveCount; i++) {
    const p = ringPos(80, R - 75), a = rng() * Math.PI, len = rnd(44, 72);
    F.caves.push({ a: { u: p.u - Math.cos(a) * len / 2, v: p.v - Math.sin(a) * len / 2 }, b: { u: p.u + Math.cos(a) * len / 2, v: p.v + Math.sin(a) * len / 2 }, w: 12, depth: 10, ramp: 22, mid: p, ang: a, len });
  }
  for (const c of F.caves) {
    const dir = { u: Math.cos(c.ang), v: Math.sin(c.ang) }, reach = c.len / 2 + c.ramp;
    let top = -1e9;
    for (let t = -reach; t <= reach; t += 6) top = Math.max(top, baseHeight(biome, c.mid.u + dir.u * t, c.mid.v + dir.v * t, F));
    c.surface = top; c.floor = top - c.depth; c.dir = dir;
  }
  for (const p of F.pools) p.floor = baseHeight(biome, p.u, p.v, F) - p.depth;

  // ── heightfield ──
  const H = new Float32Array(N * N);
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
    const u = -half + i * cell, v = -half + j * cell, d = Math.hypot(u, v);
    let h = baseHeight(biome, u, v, F);
    if (F.lake) { const k = 1 - smoothstep(F.lake.r - 6, F.lake.r + 14, Math.hypot(u - F.lake.u, v - F.lake.v)); h = lerp(h, -1.5, k); }
    for (const p of F.pools) { const k = 1 - smoothstep(p.r * 0.6, p.r + 4, Math.hypot(u - p.u, v - p.v)); h = lerp(h, Math.min(h, p.floor), k); }
    for (const c of F.caves) {
      const du = u - c.mid.u, dv = v - c.mid.v, along = Math.abs(du * c.dir.u + dv * c.dir.v), perp = Math.abs(-du * c.dir.v + dv * c.dir.u);
      const reach = c.len / 2 + c.ramp;
      if (along > reach + 8 || perp > c.w / 2 + 12) continue;
      // level the ground around the tunnel to the roof height, then cut the trench and ramps
      const band = (1 - smoothstep(c.w / 2 + 6, c.w / 2 + 12, perp)) * (1 - smoothstep(reach, reach + 8, along));
      h = lerp(h, c.surface, band);
      if (perp < c.w / 2 + 1 && along <= reach) {
        const floorAt = along <= c.len / 2 ? c.floor : lerp(c.floor, c.surface, (along - c.len / 2) / c.ramp);
        h = lerp(h, floorAt, 1 - smoothstep(c.w / 2 - 0.5, c.w / 2 + 1, perp));
      }
    }
    h = lerp(h, 0, 1 - smoothstep(16, 40, d)); // clear, level start
    if (d > R + 4) h += Math.pow((d - R - 4) * 0.14, 2) * 2.4 + (fbm(u * 0.03, v * 0.03) - 0.5) * 18 * smoothstep(R, R + 50, d); // rim cliffs
    H[j * N + i] = h;
  }
  const height = (x, z) => {
    const fx = clamp((x - cx + half) / cell, 0, SEG - 0.0001), fz = clamp((z - cz + half) / cell, 0, SEG - 0.0001);
    const i = Math.floor(fx), j = Math.floor(fz), tx = fx - i, tz = fz - j;
    const a = H[j * N + i], b = H[j * N + i + 1], c = H[(j + 1) * N + i], dd = H[(j + 1) * N + i + 1];
    if (tx + tz <= 1) return a + (b - a) * tx + (c - a) * tz;
    return dd + (c - dd) * (1 - tx) + (b - dd) * (1 - tz);
  };

  const group = new THREE.Group();
  scene.add(group);
  const pal = PALETTES[biome] || PALETTES.forest;
  const waterY = biome === 'ocean' ? 0 : null;

  // ── terrain mesh with height + slope colouring ──
  const geo = new THREE.PlaneGeometry(size, size, SEG, SEG).rotateX(-Math.PI / 2);
  const pos = geo.attributes.position, col = new Float32Array(pos.count * 3);
  const cLow = new THREE.Color(pal.low), cMid = new THREE.Color(pal.mid), cHigh = new THREE.Color(pal.high), cRock = new THREE.Color(pal.rock), c = new THREE.Color();
  let minH = Infinity, maxH = -Infinity;
  for (let k = 0; k < H.length; k++) { if (H[k] < minH) minH = H[k]; if (H[k] > maxH) maxH = H[k]; }
  const span = Math.max(1, Math.min(maxH, 60) - Math.max(minH, -25));
  for (let k = 0; k < pos.count; k++) {
    const i = k % N, j = Math.floor(k / N), h = H[k];
    pos.setY(k, h);
    const hx = H[j * N + Math.min(N - 1, i + 1)] - H[j * N + Math.max(0, i - 1)], hz = H[Math.min(N - 1, j + 1) * N + i] - H[Math.max(0, j - 1) * N + i];
    const slope = Math.hypot(hx, hz) / (2 * cell);
    const t = clamp((h - Math.max(minH, -25)) / span, 0, 1);
    c.copy(cLow).lerp(cMid, smoothstep(0, 0.45, t)).lerp(cHigh, smoothstep(0.55, 1, t));
    c.lerp(cRock, smoothstep(0.45, 1.1, slope));
    const u = -half + i * cell, v = -half + j * cell;
    c.multiplyScalar(0.88 + fbm(u * 0.06, v * 0.06, 2) * 0.24);
    if (biome === 'ocean' && h < -1) c.lerp(new THREE.Color(0xc2b98a), 0.6);
    if (biome === 'volcanic' && fbm(u * 0.05 + 3, v * 0.05) > 0.7 && slope < 0.5) c.lerp(new THREE.Color(0xff5a14), 0.45); // glowing cracks
    col[k * 3] = c.r; col[k * 3 + 1] = c.g; col[k * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  geo.computeVertexNormals();
  const terrain = new THREE.Mesh(geo, new THREE.MeshLambertMaterial({ vertexColors: true }));
  terrain.position.set(cx, 0, cz);
  terrain.receiveShadow = true;
  group.add(terrain);

  // ── colliders (props, columns) on a coarse grid ──
  const grid = new Map();
  const addCollider = (x, z, r) => { const key = `${Math.floor(x / 20)},${Math.floor(z / 20)}`; if (!grid.has(key)) grid.set(key, []); grid.get(key).push({ x, z, r }); };
  const nearColliders = (x, z) => {
    const out = [], gx = Math.floor(x / 20), gz = Math.floor(z / 20);
    for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) { const l = grid.get(`${gx + i},${gz + j}`); if (l) out.push(...l); }
    return out;
  };
  const region = { cx, cz, half, biome, height, waterY, colliders: [], nearColliders, underground: () => null };
  setArenaRegion(region);

  // ── water, lava, ice ──
  const disc = (u, v, r, color, y, opts = {}) => {
    const m = new THREE.Mesh(new THREE.CircleGeometry(r, 40).rotateX(-Math.PI / 2), opts.basic ? new THREE.MeshBasicMaterial({ color }) : new THREE.MeshPhongMaterial({ color, transparent: true, opacity: opts.opacity ?? 0.75, shininess: 90 }));
    m.position.set(cx + u, y, cz + v);
    group.add(m);
    return m;
  };
  if (waterY !== null) disc(0, 0, half + 20, 0x2f8fd8, waterY, { opacity: 0.72 });
  for (const p of F.pools) disc(p.u, p.v, p.r + 0.5, 0xff6a1a, p.floor + p.depth * 0.45, { basic: true });
  for (const k of F.cones) {
    const top = height(cx + k.u, cz + k.v);
    disc(k.u, k.v, k.crater * 0.8, 0xff6a1a, top + 1, { basic: true });
    const light = new THREE.PointLight(0xff5500, 300, 90, 1.6); light.position.set(cx + k.u, top + 10, cz + k.v); group.add(light);
  }
  if (F.lake) disc(F.lake.u, F.lake.v, F.lake.r + 6, 0xbfe6ff, -1.2, { opacity: 0.85 });

  // ── underground tunnels: a ground-coloured roof over the covered section, lit inside ──
  const blocks = [], roofs = [];
  const roofMat = new THREE.MeshLambertMaterial({ color: new THREE.Color(pal.mid).multiplyScalar(0.92), flatShading: true });
  const lipMat = new THREE.MeshLambertMaterial({ color: pal.rock, flatShading: true });
  const glowMat = new THREE.MeshBasicMaterial({ color: pal.extra });
  for (const cv of F.caves) {
    const mx = cx + cv.mid.u, mz = cz + cv.mid.v, rot = cv.ang, top = cv.surface + 0.3, thick = 2.6;
    const roof = new THREE.Mesh(new THREE.BoxGeometry(cv.len, thick, cv.w + 12), roofMat);
    roof.position.set(mx, top - thick / 2, mz); roof.rotation.y = -rot; roof.castShadow = true; roof.receiveShadow = true;
    group.add(roof);
    for (const end of [-1, 1]) { // a rocky lip over each mouth so it reads as a cave entrance
      for (let k = 0; k < 4; k++) {
        const lump = new THREE.Mesh(new THREE.DodecahedronGeometry(rnd(2.2, 3.6), 0), lipMat);
        lump.position.set(end * cv.len / 2, rnd(0.2, 1.6), (k / 3 - 0.5) * (cv.w + 4));
        roof.add(lump);
      }
    }
    // glowing crystals along the walls and warm lights inside
    for (let t = -cv.len / 2 + 7; t < cv.len / 2 - 4; t += 14) {
      const lx = mx + Math.cos(rot) * t, lz = mz + Math.sin(rot) * t;
      const light = new THREE.PointLight(new THREE.Color(pal.extra).lerp(new THREE.Color(0xffffff), 0.4), 45, 24, 1.6);
      light.position.set(lx, cv.floor + 6.5, lz); group.add(light);
      for (const sgn of [-1, 1]) {
        const gem = new THREE.Mesh(new THREE.OctahedronGeometry(0.7, 0).scale(0.7, 1.6, 0.7), glowMat);
        gem.position.set(lx - Math.sin(rot) * sgn * (cv.w / 2 - 0.6), cv.floor + 2.5 + rnd(0, 3), lz + Math.cos(rot) * sgn * (cv.w / 2 - 0.6));
        group.add(gem);
      }
    }
    roofs.push({ x: mx, z: mz, cos: Math.cos(rot), sin: Math.sin(rot), hx: cv.len / 2, hz: cv.w / 2 + 6, w: cv.w, top, ceil: top - thick, floor: cv.floor, ang: rot });
    // solid side walls along the covered section and both ramps (the terrain alone can be climbed a step at a time)
    const reach = cv.len / 2 + cv.ramp;
    for (const sgn of [-1, 1]) {
      const off = cv.w / 2 + 1;
      blocks.push({ x: mx - Math.sin(rot) * sgn * off, z: mz + Math.cos(rot) * sgn * off, rot: -rot, w: reach * 2, d: 2, bottom: cv.floor - 2, top: cv.surface, hidden: true });
    }
  }
  // Is (x, z, y) inside a covered tunnel? Returns that tunnel (for the interior camera) or null.
  const underground = (x, z, y) => {
    for (const r of roofs) {
      const dx = x - r.x, dz = z - r.z, lx = dx * r.cos + dz * r.sin, lz = -dx * r.sin + dz * r.cos;
      if (Math.abs(lx) <= r.hx + 1 && Math.abs(lz) <= r.w / 2 + 1 && y < r.ceil - 1) return r;
    }
    return null;
  };
  // biome columns: caves stalagmite pillars, desert ruins, electric crystal spires
  const columns = [];
  if (biome === 'caves') for (let i = 0; i < 26; i++) columns.push({ ...ringPos(30, R - 10), r: rnd(2.5, 5), h: rnd(16, 34), color: 0x4a4452, kind: 'cone' });
  if (biome === 'electric') for (let i = 0; i < 14; i++) columns.push({ ...ringPos(40, R - 10), r: rnd(2, 3.5), h: rnd(18, 32), color: 0xffe85a, kind: 'crystal' });
  for (const ru of F.ruins) for (let k = 0; k < 6; k++) { const a = (k / 6) * Math.PI * 2; columns.push({ u: ru.u + Math.cos(a) * 12, v: ru.v + Math.sin(a) * 12, r: 1.6, h: rnd(5, 12), color: 0xc9a768, kind: 'box' }); }
  for (const col2 of columns) {
    const x = cx + col2.u, z = cz + col2.v, y = height(x, z);
    const g = col2.kind === 'cone' ? new THREE.ConeGeometry(col2.r, col2.h, 7) : col2.kind === 'crystal' ? new THREE.OctahedronGeometry(col2.r, 0).scale(1, col2.h / col2.r / 2, 1) : new THREE.BoxGeometry(col2.r * 2, col2.h, col2.r * 2);
    const m = new THREE.Mesh(g, new THREE.MeshLambertMaterial({ color: col2.color, flatShading: true, emissive: col2.kind === 'crystal' ? 0x3a3010 : 0 }));
    m.position.set(x, y + col2.h / 2 - 0.5, z); m.castShadow = true;
    group.add(m);
    addCollider(x, z, col2.r);
  }

  // ── floating rocks over the highlands ──
  if (biome === 'highlands') {
    const P = makePropGeometries().floatRock;
    for (let i = 0; i < 16; i++) { const p = ringPos(40, R); const m = new THREE.Mesh(P.geo, P.mat); m.scale.setScalar(rnd(1.2, 2.6)); m.position.set(cx + p.u, height(cx + p.u, cz + p.v) + rnd(30, 60), cz + p.v); group.add(m); }
  }

  // ── scattered props ──
  const P = makePropGeometries();
  const placements = {};
  const blocked = (u, v) => Math.hypot(u, v) < 30 || F.caves.some((cv) => segDist(u, v, { x: cv.a.u - cv.dir.u * cv.ramp, z: cv.a.v - cv.dir.v * cv.ramp }, { x: cv.b.u + cv.dir.u * cv.ramp, z: cv.b.v + cv.dir.v * cv.ramp }) < cv.w / 2 + 8)
    || F.pools.some((p) => Math.hypot(u - p.u, v - p.v) < p.r + 3) || (F.lake && Math.hypot(u - F.lake.u, v - F.lake.v) < F.lake.r + 4);
  const spacing = 9;
  for (let gu = -R; gu < R; gu += spacing) for (let gv = -R; gv < R; gv += spacing) {
    const u = gu + (rng() - 0.5) * spacing, v = gv + (rng() - 0.5) * spacing;
    if (Math.hypot(u, v) > R + 30 || blocked(u, v)) continue;
    const y = height(cx + u, cz + v);
    let acc = 0; const roll = rng();
    for (const [type, dens] of PROPS[biome] || []) {
      acc += dens;
      if (roll >= acc) continue;
      if (biome === 'ocean' && type === 'palm' && y < 0.4) break;
      if (biome === 'ocean' && type === 'coral' && y > -0.6) break;
      if (biome === 'forest' && type === 'tree' && rng() < 0.4 && y < -6) break; // thinner in the river valleys
      const s = P[type].scale[0] + rng() * (P[type].scale[1] - P[type].scale[0]);
      (placements[type] = placements[type] || []).push({ x: cx + u, y: y - 0.2, z: cz + v, s, rot: rng() * Math.PI * 2, tint: 0.85 + rng() * 0.3 });
      if (P[type].collide) addCollider(cx + u, cz + v, P[type].collide * s);
      break;
    }
  }
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), sv = new THREE.Vector3(), pv = new THREE.Vector3(), up = new THREE.Vector3(0, 1, 0), tc = new THREE.Color();
  for (const [type, list] of Object.entries(placements)) {
    const inst = new THREE.InstancedMesh(P[type].geo, P[type].mat, list.length);
    list.forEach((p, i) => { q.setFromAxisAngle(up, p.rot); sv.setScalar(p.s); pv.set(p.x, p.y, p.z); m4.compose(pv, q, sv); inst.setMatrixAt(i, m4); inst.setColorAt(i, tc.setScalar(p.tint)); });
    inst.castShadow = P[type].shadow !== false; inst.receiveShadow = true;
    group.add(inst);
  }

  // ── minimap image ──
  const MS = 360, mc = document.createElement('canvas'); mc.width = MS; mc.height = MS;
  const mctx = mc.getContext('2d'), img = mctx.createImageData(MS, MS);
  for (let j = 0; j < MS; j++) for (let i = 0; i < MS; i++) {
    const u = (i / MS - 0.5) * size, v = (j / MS - 0.5) * size, k = (j * MS + i) * 4;
    const gi = clamp(Math.round((u + half) / cell), 0, SEG), gj = clamp(Math.round((v + half) / cell), 0, SEG), idx = (gj * N + gi) * 3;
    let r = col[idx], gg = col[idx + 1], b = col[idx + 2];
    if (waterY !== null && H[gj * N + gi] < waterY - 0.3) { r = 0.18; gg = 0.56; b = 0.85; }
    if (Math.hypot(u, v) > R) { r *= 0.45; gg *= 0.45; b *= 0.45; }
    img.data[k] = r * 255; img.data[k + 1] = gg * 255; img.data[k + 2] = b * 255; img.data[k + 3] = 255;
  }
  mctx.putImageData(img, 0, 0);
  mctx.fillStyle = 'rgba(20,16,28,0.75)';
  for (const cv of F.caves) { mctx.save(); mctx.translate((cv.mid.u / size + 0.5) * MS, (cv.mid.v / size + 0.5) * MS); mctx.rotate(cv.ang); mctx.fillRect(-cv.len / size * MS / 2, -cv.w / size * MS / 2, cv.len / size * MS, cv.w / size * MS); mctx.fillStyle = 'rgba(20,16,28,0.4)'; mctx.fillRect(-(cv.len / 2 + cv.ramp) / size * MS, -cv.w / size * MS / 2, (cv.len + cv.ramp * 2) / size * MS, cv.w / size * MS); mctx.fillStyle = 'rgba(20,16,28,0.75)'; mctx.restore(); }

  return {
    group, region, features: F, blocks, roofs, underground, R, palette: pal, center: new THREE.Vector3(cx, 0, cz),
    map: { img: mc, scale: MS / size, ox: cx - half, oz: cz - half },
    // world-space feature positions for hazards and level layout
    pools: F.pools.map((p) => ({ x: cx + p.u, z: cz + p.v, r: p.r })),
    lake: F.lake && { x: cx + F.lake.u, z: cz + F.lake.v, r: F.lake.r },
    keepOut: [
      ...F.caves.map((cv) => ({ x: cx + cv.mid.u, z: cz + cv.mid.v, c: cv.len / 2 + cv.ramp + 6 })),
      ...F.pools.map((p) => ({ x: cx + p.u, z: cz + p.v, c: p.r + 4 })),
      ...F.cones.map((k) => ({ x: cx + k.u, z: cz + k.v, c: k.r * 0.7 })),
      ...(F.lake ? [{ x: cx + F.lake.u, z: cz + F.lake.v, c: F.lake.r }] : []),
      ...columns.map((k) => ({ x: cx + k.u, z: cz + k.v, c: k.r + 3 })),
    ],
    dispose() {
      setArenaRegion(null);
      scene.remove(group);
      group.traverse((o) => { if (o.geometry) o.geometry.dispose(); });
    },
  };
}

export const ARENA_NAMES = Object.fromEntries(Object.entries(BIOMES).map(([k, b]) => [k, b.name]));
