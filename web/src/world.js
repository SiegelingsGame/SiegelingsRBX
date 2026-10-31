// World layout mirrors the Roblox map: Arena Hub in the centre, base plots ringing the hub,
// four roads (Electric / Cave / Wet / Desert) leading to the four outer dual-element biomes,
// and four inner wedge biomes (Earth / Fire / Ice / Wind) between the roads (GameConfig.BiomeZone).
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { fbm, mulberry32, smoothstep, clamp, lerp } from './util.js';

export const HUB_R = 62;
export const RING_ROAD_R = 108;
export const PLOT_RING = 160;
export const PLOT_SIZE = 50;
export const INNER_R = 470;
export const OUTER_D = 650;
export const OUTER_R = 195;
export const WORLD_R = 850;
const SIZE = 1900;
const SEG = 300;
export const WATER_Y = 0;

const D2R = Math.PI / 180;

export const BIOMES = {
  hub:       { name: 'Arena Hub', color: 0x9c9a8e, elements: [] },
  forest:    { name: 'Earth Forest', sky: 'EarthSky', color: 0x5d9a44, elements: ['Earth'], angle: 45, levels: [1, 6] },
  volcanic:  { name: 'Volcanic Wastes', sky: 'FireSky', color: 0x6a3b2b, elements: ['Fire'], angle: 135, levels: [2, 7] },
  frozen:    { name: 'Frozen Tundra', sky: 'IceSky', color: 0xdfeaf2, elements: ['Ice'], angle: 225, levels: [2, 7] },
  highlands: { name: 'Wind Highlands', sky: 'WindSky', color: 0x9ccf6e, elements: ['Wind'], angle: 315, levels: [1, 6] },
  electric:  { name: 'Electric Peaks', sky: 'ElectricSky', color: 0x3e3766, elements: ['Lightning', 'Light'], angle: 0, outer: true, levels: [8, 16] },
  caves:     { name: 'Shadow Caverns', sky: 'CaveSky', color: 0x4b4552, elements: ['Shadow', 'Metal'], angle: 90, outer: true, levels: [9, 18] },
  ocean:     { name: 'Ocean Shallows', sky: 'WaterSky', color: 0xd8cf9a, elements: ['Water', 'Poison'], angle: 180, outer: true, levels: [8, 16] },
  desert:    { name: 'Sunscorch Desert', sky: 'DesertSky', color: 0xe2c071, elements: ['Psychic', 'Undead'], angle: 270, outer: true, levels: [9, 18] },
};
export const ROADS = [
  { name: 'ElectricRoad', angle: 0 }, { name: 'CaveRoad', angle: 90 },
  { name: 'WetRoad', angle: 180 }, { name: 'DesertRoad', angle: 270 },
];

for (const b of Object.values(BIOMES)) {
  if (b.outer) b.center = new THREE.Vector2(Math.cos(b.angle * D2R) * OUTER_D, Math.sin(b.angle * D2R) * OUTER_D);
}
const OUTER_LIST = Object.entries(BIOMES).filter(([, b]) => b.outer);

export function plotCenter(i) {
  const a = (22.5 + 45 * i) * D2R;
  return new THREE.Vector3(Math.cos(a) * PLOT_RING, 0, Math.sin(a) * PLOT_RING);
}
export function plotAngle(i) { return (22.5 + 45 * i) * D2R; }

export function biomeAt(x, z) {
  const r = Math.hypot(x, z);
  if (r < HUB_R + 4) return 'hub';
  for (const [id, b] of OUTER_LIST) {
    if (Math.hypot(x - b.center.x, z - b.center.y) < OUTER_R) return id;
  }
  let a = Math.atan2(z, x) / D2R;
  if (a < 0) a += 360;
  if (a < 90) return 'forest';
  if (a < 180) return 'volcanic';
  if (a < 270) return 'frozen';
  return 'highlands';
}

function distToRoad(x, z) {
  let best = Infinity;
  for (const rd of ROADS) {
    const dx = Math.cos(rd.angle * D2R), dz = Math.sin(rd.angle * D2R);
    const t = x * dx + z * dz;
    if (t < HUB_R - 4 || t > OUTER_D) continue;
    best = Math.min(best, Math.abs(-x * dz + z * dx));
  }
  return best;
}

function distToPlot(x, z) {
  let best = Infinity;
  for (let i = 0; i < 8; i++) {
    const c = plotCenter(i);
    const a = -plotAngle(i);
    const lx = (x - c.x) * Math.cos(a) - (z - c.z) * Math.sin(a);
    const lz = (x - c.x) * Math.sin(a) + (z - c.z) * Math.cos(a);
    const dx = Math.max(Math.abs(lx) - PLOT_SIZE / 2, 0), dz = Math.max(Math.abs(lz) - PLOT_SIZE / 2, 0);
    best = Math.min(best, Math.hypot(dx, dz));
  }
  return best;
}

function rawBiomeHeight(id, x, z) {
  const n = fbm(x * 0.011 + 31, z * 0.011 - 17, 4) - 0.5;
  const n2 = fbm(x * 0.035, z * 0.035, 3) - 0.5;
  switch (id) {
    case 'hub': return 0;
    case 'forest': return n * 22 + n2 * 4 + 3;
    case 'volcanic': {
      const vc = { x: Math.cos(135 * D2R) * 330, z: Math.sin(135 * D2R) * 330 };
      const d = Math.hypot(x - vc.x, z - vc.z);
      let cone = d < 110 ? 70 * Math.pow(1 - d / 110, 1.4) : 0;
      if (d < 22) cone -= (1 - d / 22) * 22; // crater
      return n * 22 + n2 * 6 + cone + 2;
    }
    case 'frozen': return n * 30 + Math.abs(n2) * 10 + 4;
    case 'highlands': return n * 34 + Math.sin(x * 0.02) * Math.cos(z * 0.017) * 8 + 8;
    case 'electric': return Math.floor((n + 0.5) * 5) * 7 + n2 * 2 + 2;
    case 'caves': return n * 40 + Math.abs(n2) * 18 + 10;
    case 'ocean': {
      const b = BIOMES.ocean.center;
      const d = Math.hypot(x - b.x, z - b.y) / OUTER_R;
      const island = n > 0.18 ? (n - 0.18) * 40 : 0;
      return lerp(-7, 1.5, smoothstep(0.55, 1.0, d)) + n2 * 3 + island;
    }
    case 'desert': return Math.sin(x * 0.04 + n * 6) * 5 + Math.cos(z * 0.031) * 3 + n * 16 + 3;
    default: return 0;
  }
}

export class World {
  constructor(scene) {
    this.scene = scene;
    this.surfaces = []; // walkable platforms {cx, cz, rot, hx, hz, y}
    this.colliderGrid = new Map();
    this.spawnPoints = [];
    this.heights = new Float32Array((SEG + 1) * (SEG + 1));
    this.buildHeights();
    this.buildTerrain();
    this.buildWater();
    this.buildRoadsAndPaths();
    this.buildProps();
    this.buildSpawnPoints();
  }

  // ── height field ─────────────────────────────────────────────
  buildHeights() {
    const N = SEG + 1, h = this.heights, step = SIZE / SEG;
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
      const x = -SIZE / 2 + i * step, z = -SIZE / 2 + j * step;
      h[j * N + i] = rawBiomeHeight(biomeAt(x, z), x, z);
    }
    // blur to soften biome seams
    const tmp = new Float32Array(h.length);
    for (let pass = 0; pass < 3; pass++) {
      for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
        let s = 0, c = 0;
        for (let dj = -2; dj <= 2; dj++) for (let di = -2; di <= 2; di++) {
          const ii = clamp(i + di, 0, N - 1), jj = clamp(j + dj, 0, N - 1);
          s += h[jj * N + ii]; c++;
        }
        tmp[j * N + i] = s / c;
      }
      h.set(tmp);
    }
    // flatten hub / plots / roads; gentle near the centre; mountains at the edge
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
      const x = -SIZE / 2 + i * step, z = -SIZE / 2 + j * step;
      const r = Math.hypot(x, z);
      let v = h[j * N + i];
      v *= smoothstep(PLOT_RING + 20, PLOT_RING + 140, r) * 0.85 + 0.15 * smoothstep(HUB_R, PLOT_RING, r);
      const plotMask = 1 - smoothstep(4, 22, distToPlot(x, z));
      v = lerp(v, 0, plotMask);
      const roadMask = 1 - smoothstep(6, 18, distToRoad(x, z));
      v = lerp(v, Math.max(v * 0.35, v > 0 ? 0.3 : v * 0.6), roadMask);
      const hubMask = 1 - smoothstep(HUB_R - 4, HUB_R + 18, r);
      v = lerp(v, 0, hubMask);
      if (r > WORLD_R - 50) v = Math.max(v, 0) + smoothstep(WORLD_R - 50, WORLD_R + 70, r) * (90 + (fbm(x * 0.02, z * 0.02) - 0.5) * 70);
      h[j * N + i] = v;
    }
  }

  terrainHeight(x, z) {
    const N = SEG + 1, step = SIZE / SEG;
    const fx = clamp((x + SIZE / 2) / step, 0, SEG - 0.0001), fz = clamp((z + SIZE / 2) / step, 0, SEG - 0.0001);
    const i = Math.floor(fx), j = Math.floor(fz), tx = fx - i, tz = fz - j;
    const h = this.heights;
    const a = h[j * N + i], b = h[j * N + i + 1], c = h[(j + 1) * N + i], d = h[(j + 1) * N + i + 1];
    // match PlaneGeometry triangulation
    if (tx + tz <= 1) return a + (b - a) * tx + (c - a) * tz;
    return d + (c - d) * (1 - tx) + (b - d) * (1 - tz);
  }

  // Highest walkable height under (x,z) not more than `step` above y.
  groundAt(x, z, y = Infinity, step = 1.2) {
    let g = this.terrainHeight(x, z);
    if (this.isWater(x, z)) g = Math.max(g, WATER_Y - 2.4);
    for (const s of this.surfaces) {
      const dx = x - s.cx, dz = z - s.cz;
      const lx = dx * s.cos + dz * s.sin, lz = -dx * s.sin + dz * s.cos;
      if (Math.abs(lx) <= s.hx && Math.abs(lz) <= s.hz && s.y <= y + step && s.y > g) g = s.y;
    }
    return g;
  }

  isWater(x, z) {
    return biomeAt(x, z) === 'ocean' && this.terrainHeight(x, z) < WATER_Y - 0.3;
  }

  addSurface(cx, cz, rot, w, d, y) {
    this.surfaces.push({ cx, cz, cos: Math.cos(rot), sin: Math.sin(rot), hx: w / 2, hz: d / 2, y });
  }

  // ── terrain mesh ─────────────────────────────────────────────
  buildTerrain() {
    const geo = new THREE.PlaneGeometry(SIZE, SIZE, SEG, SEG);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    const colors = new Float32Array(pos.count * 3);
    const col = new THREE.Color(), tmp = new THREE.Color();
    for (let k = 0; k < pos.count; k++) {
      const x = pos.getX(k), z = pos.getZ(k);
      const y = this.terrainHeight(x, z);
      pos.setY(k, y);
      // blended biome colour
      col.setRGB(0, 0, 0);
      const offs = [[0, 0], [14, 0], [-14, 0], [0, 14], [0, -14]];
      for (const [ox, oz] of offs) { tmp.setHex(BIOMES[biomeAt(x + ox, z + oz)].color); col.r += tmp.r / 5; col.g += tmp.g / 5; col.b += tmp.b / 5; }
      const b = biomeAt(x, z);
      const n = fbm(x * 0.05, z * 0.05, 2);
      col.multiplyScalar(0.86 + n * 0.28);
      if (b === 'frozen' || (y > 38 && b !== 'volcanic' && b !== 'caves')) col.lerp(tmp.setHex(0xf4f8ff), smoothstep(30, 60, y) * 0.8);
      if (b === 'ocean' && y < -2) col.lerp(tmp.setHex(0xc2b98a), 0.5);
      if (b === 'volcanic' && n > 0.68) col.lerp(tmp.setHex(0xff5a14), 0.55);
      if (Math.hypot(x, z) > WORLD_R - 30) col.lerp(tmp.setHex(0x6f6a62), smoothstep(WORLD_R - 30, WORLD_R + 40, Math.hypot(x, z)));
      const rd = distToRoad(x, z);
      if (rd < 7) col.lerp(tmp.setHex(0xb59a72), 1 - smoothstep(4, 7, rd));
      const rr = Math.abs(Math.hypot(x, z) - RING_ROAD_R);
      if (rr < 6) col.lerp(tmp.setHex(0xb59a72), 1 - smoothstep(3.5, 6, rr));
      colors[k * 3] = col.r; colors[k * 3 + 1] = col.g; colors[k * 3 + 2] = col.b;
    }
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geo.computeVertexNormals();
    const mat = new THREE.MeshLambertMaterial({ vertexColors: true });
    this.terrain = new THREE.Mesh(geo, mat);
    this.terrain.receiveShadow = true;
    this.scene.add(this.terrain);
  }

  buildWater() {
    const c = BIOMES.ocean.center;
    const geo = new THREE.CircleGeometry(OUTER_R + 30, 64);
    geo.rotateX(-Math.PI / 2);
    this.waterMat = new THREE.MeshPhongMaterial({ color: 0x2f8fd8, transparent: true, opacity: 0.72, shininess: 90, specular: 0x88ccff });
    const water = new THREE.Mesh(geo, this.waterMat);
    water.position.set(c.x, WATER_Y, c.y);
    this.scene.add(water);
    this.water = water;
    // lava lake in the volcano crater
    const vc = { x: Math.cos(135 * D2R) * 330, z: Math.sin(135 * D2R) * 330 };
    const lava = new THREE.Mesh(new THREE.CircleGeometry(20, 32).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xff6a1a }));
    lava.position.set(vc.x, this.terrainHeight(vc.x, vc.z) + 3, vc.z);
    this.scene.add(lava);
    const glow = new THREE.PointLight(0xff5500, 400, 120, 1.6);
    glow.position.copy(lava.position).y += 8;
    this.scene.add(glow);
  }

  buildRoadsAndPaths() {
    // lamp posts along roads for readability
    const posts = [];
    for (const rd of ROADS) {
      const dx = Math.cos(rd.angle * D2R), dz = Math.sin(rd.angle * D2R);
      for (let t = HUB_R + 30; t < OUTER_D - OUTER_R + 40; t += 46) {
        for (const side of [-1, 1]) {
          const x = dx * t - dz * 9 * side, z = dz * t + dx * 9 * side;
          posts.push([x, this.terrainHeight(x, z), z]);
        }
      }
    }
    const postGeo = mergeGeometries([
      tint(new THREE.CylinderGeometry(0.25, 0.35, 7, 6).translate(0, 3.5, 0), 0x3b3330),
      tint(new THREE.SphereGeometry(0.7, 8, 6).translate(0, 7.3, 0), 0xffe7a6),
    ]);
    const inst = new THREE.InstancedMesh(postGeo, new THREE.MeshLambertMaterial({ vertexColors: true, emissive: 0x332200 }), posts.length);
    const m = new THREE.Matrix4();
    posts.forEach((p, i) => { m.makeTranslation(p[0], p[1], p[2]); inst.setMatrixAt(i, m); });
    inst.castShadow = true;
    this.scene.add(inst);

    // road signposts at the hub edge
    for (const rd of ROADS) {
      const dx = Math.cos(rd.angle * D2R), dz = Math.sin(rd.angle * D2R);
      const target = Object.values(BIOMES).find((b) => b.outer && b.angle === rd.angle);
      const sign = makeSign(target.name, '#2b2118', '#ffe9b8');
      sign.position.set(dx * (HUB_R + 16) - dz * 12, 0, dz * (HUB_R + 16) + dx * 12);
      sign.rotation.y = -rd.angle * D2R - Math.PI / 2;
      this.scene.add(sign);
    }
  }

  // ── props (instanced, per biome) ─────────────────────────────
  buildProps() {
    const P = makePropGeometries();
    const placements = {};
    for (const k of Object.keys(P)) placements[k] = [];
    const rng = mulberry32(1337);
    const spacing = 11;
    const table = {
      forest:    [['tree', 0.42], ['bush', 0.18], ['rock', 0.05], ['flower', 0.12]],
      volcanic:  [['deadTree', 0.12], ['lavaRock', 0.22], ['rock', 0.08], ['ember', 0.05]],
      frozen:    [['pine', 0.32], ['iceCrystal', 0.08], ['snowRock', 0.08]],
      highlands: [['grass', 0.35], ['flower', 0.12], ['tree', 0.06], ['rock', 0.06], ['floatRock', 0.012]],
      electric:  [['crystal', 0.16], ['pylon', 0.025], ['rock', 0.08]],
      caves:     [['stalagmite', 0.26], ['mushroom', 0.12], ['rock', 0.1]],
      ocean:     [['palm', 0.08], ['coral', 0.16], ['rock', 0.04]],
      desert:    [['cactus', 0.12], ['rock', 0.07], ['bones', 0.03], ['obelisk', 0.006]],
      hub: [],
    };
    for (let gx = -WORLD_R; gx < WORLD_R; gx += spacing) {
      for (let gz = -WORLD_R; gz < WORLD_R; gz += spacing) {
        const x = gx + (rng() - 0.5) * spacing, z = gz + (rng() - 0.5) * spacing;
        const r = Math.hypot(x, z);
        if (r > WORLD_R - 10 || r < HUB_R + 25) continue;
        if (Math.abs(r - RING_ROAD_R) < 10) continue;
        if (distToRoad(x, z) < 13 || distToPlot(x, z) < 16) continue;
        const b = biomeAt(x, z);
        const ty = this.terrainHeight(x, z);
        const options = table[b];
        const roll = rng();
        let acc = 0;
        for (const [type, dens] of options) {
          // fewer props close to the plots
          const d = dens * smoothstep(PLOT_RING - 10, PLOT_RING + 90, r);
          acc += d;
          if (roll < acc) {
            if (b === 'ocean' && type === 'coral' && ty > WATER_Y - 0.5) break;
            if (b === 'ocean' && type === 'palm' && ty < WATER_Y + 0.2) break;
            const s = P[type].scale[0] + rng() * (P[type].scale[1] - P[type].scale[0]);
            const y = type === 'floatRock' ? ty + 25 + rng() * 25 : ty - 0.2;
            placements[type].push({ x, y, z, s, rot: rng() * Math.PI * 2, tint: 0.85 + rng() * 0.3 });
            if (P[type].collide) this.addCollider(x, z, P[type].collide * s);
            break;
          }
        }
      }
    }
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), sv = new THREE.Vector3(), pv = new THREE.Vector3(), up = new THREE.Vector3(0, 1, 0);
    const c = new THREE.Color();
    for (const [type, list] of Object.entries(placements)) {
      if (!list.length) continue;
      const def = P[type];
      const inst = new THREE.InstancedMesh(def.geo, def.mat, list.length);
      list.forEach((p, i) => {
        q.setFromAxisAngle(up, p.rot); sv.setScalar(p.s); pv.set(p.x, p.y, p.z);
        m.compose(pv, q, sv); inst.setMatrixAt(i, m);
        inst.setColorAt(i, c.setScalar(p.tint));
      });
      inst.castShadow = def.shadow !== false;
      inst.receiveShadow = true;
      this.scene.add(inst);
    }
  }

  addCollider(x, z, r) {
    const key = `${Math.floor(x / 20)},${Math.floor(z / 20)}`;
    if (!this.colliderGrid.has(key)) this.colliderGrid.set(key, []);
    this.colliderGrid.get(key).push({ x, z, r });
  }

  // Push a circle (x,z,radius) out of solid props; returns corrected [x,z].
  resolveCollision(x, z, radius) {
    const cx = Math.floor(x / 20), cz = Math.floor(z / 20);
    for (let i = -1; i <= 1; i++) for (let j = -1; j <= 1; j++) {
      const list = this.colliderGrid.get(`${cx + i},${cz + j}`);
      if (!list) continue;
      for (const c of list) {
        const dx = x - c.x, dz = z - c.z, d = Math.hypot(dx, dz), min = c.r + radius;
        if (d < min && d > 0.0001) { x = c.x + (dx / d) * min; z = c.z + (dz / d) * min; }
      }
    }
    const r = Math.hypot(x, z);
    if (r > WORLD_R - 8) { x *= (WORLD_R - 8) / r; z *= (WORLD_R - 8) / r; }
    return [x, z];
  }

  // ── spawn / dungeon / boss points (workspace.Biomes/*/SpawnPoint etc.) ──
  buildSpawnPoints() {
    const rng = mulberry32(99);
    const markerGroup = new THREE.Group();
    this.scene.add(markerGroup);
    for (const [id, b] of Object.entries(BIOMES)) {
      if (id === 'hub') continue;
      const want = { spawn: b.outer ? 10 : 8, dungeon: 2, boss: 1 };
      for (const [kind, count] of Object.entries(want)) {
        let made = 0, tries = 0;
        while (made < count && tries++ < 3000) {
          let x, z;
          if (b.outer) {
            const a = rng() * Math.PI * 2, rr = Math.sqrt(rng()) * (OUTER_R - 25);
            x = b.center.x + Math.cos(a) * rr; z = b.center.y + Math.sin(a) * rr;
          } else {
            const a = (b.angle + (rng() - 0.5) * 70) * D2R;
            const minR = kind === 'boss' ? 360 : kind === 'dungeon' ? 280 : PLOT_RING + 60;
            const rr = minR + rng() * (INNER_R - 10 - minR);
            x = Math.cos(a) * rr; z = Math.sin(a) * rr;
          }
          if (biomeAt(x, z) !== id || distToPlot(x, z) < 30 || distToRoad(x, z) < 12) continue;
          if (this.spawnPoints.some((p) => Math.hypot(p.x - x, p.z - z) < (kind === 'spawn' ? 40 : 70))) continue;
          const y = this.terrainHeight(x, z);
          if (id === 'ocean' && kind !== 'spawn' && y < WATER_Y - 1) continue;
          // outer dual biomes: alternate primary/secondary element (SpawnPoint vs SpawnPoint2)
          const elements = b.elements.length > 1 ? [b.elements[made % 2]] : b.elements;
          const r = Math.hypot(x, z);
          const t = b.outer ? 0.5 + rng() * 0.5 : clamp((r - PLOT_RING) / (INNER_R - PLOT_RING), 0, 1);
          const level = Math.round(lerp(b.levels[0], b.levels[1], t)) + (kind === 'dungeon' ? 4 : kind === 'boss' ? 10 : 0);
          this.spawnPoints.push({ x, z, y, biome: id, kind, elements, level, live: [], cooldown: 0 });
          if (kind !== 'spawn') markerGroup.add(makePointMarker(kind, x, y, z));
          made++;
        }
      }
    }
  }
}

// ── helpers ───────────────────────────────────────────────────
export function tint(geo, hex) {
  const g = geo.index ? geo.toNonIndexed() : geo;
  const c = new THREE.Color(hex);
  const arr = new Float32Array(g.attributes.position.count * 3);
  for (let i = 0; i < arr.length; i += 3) { arr[i] = c.r; arr[i + 1] = c.g; arr[i + 2] = c.b; }
  g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
  if (g.attributes.uv) g.deleteAttribute('uv');
  return g;
}

function makePropGeometries() {
  const lam = (opts = {}) => new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true, ...opts });
  const std = lam();
  const T = THREE;
  return {
    tree: { geo: mergeGeometries([
      tint(new T.CylinderGeometry(0.5, 0.8, 6, 6).translate(0, 3, 0), 0x6b4a2e),
      tint(new T.IcosahedronGeometry(3.6, 0).translate(0, 8, 0), 0x3f8a37),
      tint(new T.IcosahedronGeometry(2.6, 0).translate(1.4, 10.4, 0.6), 0x4ea043),
    ]), mat: std, scale: [0.8, 1.5], collide: 1.1 },
    pine: { geo: mergeGeometries([
      tint(new T.CylinderGeometry(0.4, 0.6, 4, 6).translate(0, 2, 0), 0x5a4030),
      tint(new T.ConeGeometry(3.6, 5, 7).translate(0, 5.5, 0), 0x2f6a4a),
      tint(new T.ConeGeometry(2.8, 4.4, 7).translate(0, 8.4, 0), 0x3b7d57),
      tint(new T.ConeGeometry(1.8, 3.6, 7).translate(0, 11, 0), 0xeef6ff),
    ]), mat: std, scale: [0.8, 1.6], collide: 1 },
    deadTree: { geo: mergeGeometries([
      tint(new T.CylinderGeometry(0.3, 0.6, 7, 5).translate(0, 3.5, 0), 0x2b2220),
      tint(new T.BoxGeometry(0.3, 3, 0.3).rotateZ(0.8).translate(1, 5.5, 0), 0x2b2220),
      tint(new T.BoxGeometry(0.25, 2.4, 0.25).rotateZ(-0.9).translate(-0.9, 4.6, 0.2), 0x2b2220),
    ]), mat: std, scale: [0.8, 1.4], collide: 0.7 },
    rock: { geo: tint(new T.DodecahedronGeometry(1.6, 0).scale(1.3, 0.8, 1).translate(0, 0.6, 0), 0x8a8a86), mat: std, scale: [0.6, 2.4], collide: 1.5 },
    snowRock: { geo: mergeGeometries([tint(new T.DodecahedronGeometry(1.6, 0).scale(1.3, 0.8, 1).translate(0, 0.6, 0), 0x9aa6b4), tint(new T.DodecahedronGeometry(1.2, 0).scale(1.2, 0.4, 1).translate(0, 1.6, 0), 0xffffff)]), mat: std, scale: [0.6, 2.0], collide: 1.5 },
    lavaRock: { geo: mergeGeometries([tint(new T.DodecahedronGeometry(1.6, 0).scale(1.2, 1.1, 1).translate(0, 0.9, 0), 0x2a2222), tint(new T.OctahedronGeometry(0.5, 0).translate(0.6, 1.9, 0.3), 0xff6a1a)]), mat: lam({ emissive: 0x220800 }), scale: [0.8, 2.6], collide: 1.6 },
    ember: { geo: tint(new T.CircleGeometry(3, 10).rotateX(-Math.PI / 2).translate(0, 0.25, 0), 0xff7a1a), mat: new T.MeshBasicMaterial({ vertexColors: true }), scale: [0.6, 1.8], shadow: false },
    bush: { geo: mergeGeometries([tint(new T.IcosahedronGeometry(1.5, 0).translate(0, 1, 0), 0x3d7f33), tint(new T.IcosahedronGeometry(1.1, 0).translate(1.1, 0.8, 0.4), 0x4b9440)]), mat: std, scale: [0.7, 1.4] },
    flower: { geo: mergeGeometries([tint(new T.CylinderGeometry(0.06, 0.06, 1.2, 4).translate(0, 0.6, 0), 0x3a7a2a), tint(new T.IcosahedronGeometry(0.35, 0).translate(0, 1.3, 0), 0xff7ab8), tint(new T.CylinderGeometry(0.06, 0.06, 0.9, 4).translate(0.6, 0.45, 0.3), 0x3a7a2a), tint(new T.IcosahedronGeometry(0.3, 0).translate(0.6, 1, 0.3), 0xffe066)]), mat: std, scale: [0.8, 1.5], shadow: false },
    grass: { geo: mergeGeometries([0, 1, 2, 3, 4].map((k) => tint(new T.ConeGeometry(0.25, 1.8, 3).rotateZ((k - 2) * 0.25).translate((k - 2) * 0.35, 0.8, (k % 2) * 0.3), k % 2 ? 0x7fbf4a : 0x9fd860))), mat: std, scale: [0.8, 1.6], shadow: false },
    floatRock: { geo: mergeGeometries([tint(new T.DodecahedronGeometry(3, 0).scale(1.4, 0.7, 1.2), 0x8d8a7a), tint(new T.ConeGeometry(3.4, 4, 6).rotateX(Math.PI).translate(0, -3.2, 0), 0x6f6a5c), tint(new T.CylinderGeometry(3.6, 3.6, 0.6, 7).translate(0, 1.6, 0), 0x7fc455)]), mat: std, scale: [0.8, 1.8] },
    crystal: { geo: mergeGeometries([tint(new T.OctahedronGeometry(1.2, 0).scale(0.7, 3, 0.7).translate(0, 2.6, 0), 0xffe85a), tint(new T.OctahedronGeometry(0.8, 0).scale(0.7, 2.6, 0.7).rotateZ(0.4).translate(0.9, 1.6, 0.2), 0xb57aff)]), mat: lam({ emissive: 0x3a2a40 }), scale: [0.7, 2.2], collide: 1 },
    pylon: { geo: mergeGeometries([tint(new T.CylinderGeometry(0.6, 1.2, 16, 4).translate(0, 8, 0), 0x55506a), tint(new T.TorusGeometry(1.6, 0.3, 6, 12).rotateX(Math.PI / 2).translate(0, 13, 0), 0xffe85a), tint(new T.SphereGeometry(1, 8, 6).translate(0, 16.6, 0), 0xfff6a0)]), mat: lam({ emissive: 0x444010 }), scale: [0.9, 1.3], collide: 1.4 },
    stalagmite: { geo: mergeGeometries([tint(new T.ConeGeometry(1.6, 7, 6).translate(0, 3.5, 0), 0x5a5262), tint(new T.ConeGeometry(0.9, 4, 6).translate(1.5, 2, 0.5), 0x6a6274)]), mat: std, scale: [0.7, 2.2], collide: 1.3 },
    mushroom: { geo: mergeGeometries([tint(new T.CylinderGeometry(0.3, 0.4, 2, 6).translate(0, 1, 0), 0xd8d0e0), tint(new T.SphereGeometry(1.2, 8, 5, 0, Math.PI * 2, 0, Math.PI / 2).translate(0, 2, 0), 0x52e0ff)]), mat: lam({ emissive: 0x0b3a48 }), scale: [0.6, 1.8] },
    palm: { geo: mergeGeometries([
      tint(new T.CylinderGeometry(0.35, 0.55, 9, 6).translate(0, 4.5, 0).rotateZ(0.12), 0x8a6a43),
      ...[0, 1, 2, 3, 4].map((k) => tint(new T.BoxGeometry(5, 0.15, 1.2).translate(2.5, 0, 0).rotateZ(-0.35).rotateY((k / 5) * Math.PI * 2).translate(-1, 9, 0), 0x3f9a3a)),
    ]), mat: std, scale: [0.9, 1.4], collide: 0.7 },
    coral: { geo: mergeGeometries([tint(new T.ConeGeometry(0.5, 2.5, 5).translate(0, 1.2, 0), 0xff7a8a), tint(new T.ConeGeometry(0.4, 2, 5).rotateZ(0.4).translate(0.6, 1, 0), 0xffa060), tint(new T.SphereGeometry(0.6, 6, 4).translate(-0.6, 0.4, 0.4), 0xb070ff)]), mat: std, scale: [0.8, 1.8], shadow: false },
    cactus: { geo: mergeGeometries([tint(new T.CylinderGeometry(0.7, 0.8, 6, 7).translate(0, 3, 0), 0x4f8a3c), tint(new T.CylinderGeometry(0.45, 0.45, 2.5, 6).translate(1.3, 3.8, 0), 0x4f8a3c), tint(new T.CylinderGeometry(0.45, 0.45, 1.4, 6).rotateZ(Math.PI / 2).translate(0.7, 2.6, 0), 0x4f8a3c)]), mat: std, scale: [0.7, 1.5], collide: 0.9 },
    bones: { geo: mergeGeometries([tint(new T.TorusGeometry(1.6, 0.18, 4, 10, Math.PI).translate(0, 0.2, 0), 0xf0e8d6), tint(new T.TorusGeometry(1.3, 0.16, 4, 10, Math.PI).translate(0, 0.2, 1.1), 0xf0e8d6), tint(new T.BoxGeometry(0.3, 0.3, 4).translate(0, 0.2, 0.5), 0xe8dcc6)]), mat: std, scale: [0.8, 1.8], shadow: false },
    obelisk: { geo: mergeGeometries([tint(new T.BoxGeometry(3, 18, 3).translate(0, 9, 0), 0xc9a768), tint(new T.ConeGeometry(2.2, 3, 4).rotateY(Math.PI / 4).translate(0, 19.5, 0), 0xffd76a), tint(new T.BoxGeometry(0.4, 3, 3.1).translate(0, 12, 0), 0x9a5cff)]), mat: std, scale: [0.9, 1.3], collide: 2.4 },
    iceCrystal: { geo: mergeGeometries([tint(new T.OctahedronGeometry(1.2, 0).scale(0.6, 3, 0.6).translate(0, 2.6, 0), 0xaee6ff), tint(new T.OctahedronGeometry(0.8, 0).scale(0.6, 2.4, 0.6).rotateZ(-0.5).translate(-0.8, 1.6, 0.2), 0xd8f4ff)]), mat: lam({ emissive: 0x10283a }), scale: [0.7, 2.0], collide: 1 },
  };
}

function makePointMarker(kind, x, y, z) {
  const g = new THREE.Group();
  const isBoss = kind === 'boss';
  const r = isBoss ? 16 : 10;
  const ring = new THREE.Mesh(new THREE.RingGeometry(r - 1.2, r, 40).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: isBoss ? 0xffb800 : 0xb450ff, transparent: true, opacity: 0.55, side: THREE.DoubleSide }));
  ring.position.y = 0.4;
  g.add(ring);
  const n = isBoss ? 8 : 5;
  const stoneMat = new THREE.MeshLambertMaterial({ color: isBoss ? 0x6b5a3a : 0x4a3f5a, flatShading: true });
  const runeMat = new THREE.MeshBasicMaterial({ color: isBoss ? 0xffcf4a : 0xd08aff });
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const h = isBoss ? 9 : 5;
    const p = new THREE.Mesh(new THREE.BoxGeometry(1.6, h, 1.6), stoneMat);
    p.position.set(Math.cos(a) * (r + 1.5), h / 2, Math.sin(a) * (r + 1.5));
    p.castShadow = true;
    g.add(p);
    const rune = new THREE.Mesh(new THREE.BoxGeometry(0.2, 1.2, 0.8), runeMat);
    rune.position.set(Math.cos(a) * (r + 0.6), h * 0.6, Math.sin(a) * (r + 0.6));
    rune.rotation.y = -a;
    g.add(rune);
  }
  g.position.set(x, y, z);
  return g;
}

export function makeSign(text, bg = '#2b2118', fg = '#ffe9b8') {
  const g = new THREE.Group();
  const post = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 6, 6), new THREE.MeshLambertMaterial({ color: 0x5a3e28 }));
  post.position.y = 3;
  g.add(post);
  const board = new THREE.Mesh(new THREE.PlaneGeometry(11, 2.6), new THREE.MeshBasicMaterial({ map: textTexture(text, bg, fg), side: THREE.DoubleSide }));
  board.position.y = 5.6;
  g.add(board);
  return g;
}

export function textTexture(text, bg, fg, w = 512, h = 120, font = 'bold 54px system-ui, sans-serif') {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  const ctx = c.getContext('2d');
  if (bg) { ctx.fillStyle = bg; ctx.fillRect(0, 0, w, h); }
  ctx.fillStyle = fg; ctx.font = font; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(text, w / 2, h / 2 + 2);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}
