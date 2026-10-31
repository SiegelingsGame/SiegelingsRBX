// Procedural stand-in models for Siegelings. Shape comes from class, accessories from element,
// colour from CreatureData.primaryColor, size from rarity. Deterministic per creature id.
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { ELEMENT_COLORS } from './config.js';
import { hashStr, mulberry32 } from './util.js';
import { tint } from './world.js';

const RARITY_SCALE = { Common: 1, Uncommon: 1.12, Rare: 1.3, Epic: 1.5, Legendary: 1.85 };
const VARIANT_EMISSIVE = { Normal: 0x000000, Silver: 0x1c2026, Gold: 0x3a2800, Legend: 0x3a0838 };
const VARIANT_TINT = { Normal: null, Silver: 0xd0d6e0, Gold: 0xffcc33, Legend: 0xff66ff };

const geoCache = new Map();
const matCache = new Map();

export function creatureMaterial(variant = 'Normal', shiny = false) {
  const key = variant + (shiny ? '*' : '');
  if (!matCache.has(key)) {
    const em = new THREE.Color(VARIANT_EMISSIVE[variant] || 0);
    if (shiny) em.add(new THREE.Color(0x2a2a40));
    matCache.set(key, new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true, emissive: em }));
  }
  return matCache.get(key);
}

function mix(a, b, t) { return new THREE.Color(a).lerp(new THREE.Color(b), t).getHex(); }

function buildGeometry(def, variant) {
  const rng = mulberry32(hashStr(def.id));
  const T = THREE;
  let primary = (def.primaryColor[0] << 16) | (def.primaryColor[1] << 8) | def.primaryColor[2];
  if (VARIANT_TINT[variant]) primary = mix(primary, VARIANT_TINT[variant], 0.45);
  const elem = ELEMENT_COLORS[def.element] || 0xffffff;
  const belly = mix(primary, 0xffffff, 0.45);
  const dark = mix(primary, 0x000000, 0.45);
  const parts = [];
  const legs = []; // {geo, x, y, z}
  const wings = [];
  const add = (g, c) => parts.push(tint(g, c));
  let headPos = new T.Vector3(0, 2.2, 1.0), headR = 0.75, bodyTop = 2.2, tailBase = new T.Vector3(0, 1.4, -1.1);
  const legLen = { Bruiser: 0.9, Mage: 0, Guardian: 0.55, Assassin: 1.3, Support: 0.6 }[def.class] ?? 0.8;

  switch (def.class) {
    case 'Bruiser': {
      const y = legLen + 0.75;
      add(new T.BoxGeometry(1.9, 1.5, 2.3).translate(0, y, 0), primary);
      add(new T.BoxGeometry(1.5, 0.5, 1.9).translate(0, y - 0.6, 0.05), belly);
      headPos.set(0, y + 0.75, 1.25); headR = 0.75;
      add(new T.BoxGeometry(1.4, 1.2, 1.2).translate(headPos.x, headPos.y, headPos.z), primary);
      add(new T.BoxGeometry(0.9, 0.5, 0.4).translate(0, headPos.y - 0.3, headPos.z + 0.7), belly);
      add(new T.ConeGeometry(0.22, 0.8, 5).rotateZ(0.5).translate(-0.6, headPos.y + 0.8, headPos.z), dark);
      add(new T.ConeGeometry(0.22, 0.8, 5).rotateZ(-0.5).translate(0.6, headPos.y + 0.8, headPos.z), dark);
      for (const [x, z] of [[-0.65, 0.75], [0.65, 0.75], [-0.65, -0.75], [0.65, -0.75]]) legs.push({ geo: tint(new T.CylinderGeometry(0.34, 0.3, legLen + 0.2, 6).translate(0, -(legLen + 0.2) / 2, 0), dark), x, y: legLen + 0.2, z });
      bodyTop = y + 0.75; tailBase.set(0, y, -1.15);
      break;
    }
    case 'Mage': {
      const y = 1.9;
      add(new T.IcosahedronGeometry(1.0, 1).translate(0, y, 0), primary);
      add(new T.IcosahedronGeometry(0.62, 1).translate(0, y - 0.25, 0.5), belly);
      headPos.set(0, y + 1.0, 0.25); headR = 0.7;
      add(new T.IcosahedronGeometry(0.75, 1).translate(headPos.x, headPos.y, headPos.z), primary);
      add(new T.ConeGeometry(0.25, 0.9, 4).rotateZ(0.7).translate(-0.6, headPos.y + 0.5, headPos.z - 0.1), dark);
      add(new T.ConeGeometry(0.25, 0.9, 4).rotateZ(-0.7).translate(0.6, headPos.y + 0.5, headPos.z - 0.1), dark);
      add(new T.ConeGeometry(0.6, 1.2, 6).rotateX(Math.PI).translate(0, y - 1.2, 0), primary); // wispy tail
      add(new T.CylinderGeometry(0.12, 0.16, 0.8, 5).rotateZ(1.1).translate(-1.0, y, 0.2), primary);
      add(new T.CylinderGeometry(0.12, 0.16, 0.8, 5).rotateZ(-1.1).translate(1.0, y, 0.2), primary);
      bodyTop = y + 1.0; tailBase.set(0, y - 0.6, -0.7);
      break;
    }
    case 'Guardian': {
      const y = legLen + 0.6;
      add(new T.SphereGeometry(1.6, 9, 6, 0, Math.PI * 2, 0, Math.PI / 2).scale(1, 0.8, 1.15).translate(0, y, 0), dark);
      add(new T.CylinderGeometry(1.65, 1.6, 0.4, 10).scale(1, 1, 1.15).translate(0, y, 0), primary);
      add(new T.CylinderGeometry(1.35, 1.3, 0.3, 10).scale(1, 1, 1.1).translate(0, y - 0.3, 0), belly);
      headPos.set(0, y + 0.4, 1.95); headR = 0.62;
      add(new T.IcosahedronGeometry(0.66, 1).translate(headPos.x, headPos.y, headPos.z), primary);
      add(new T.ConeGeometry(0.3, 1, 5).rotateX(-Math.PI / 2 - 0.4).translate(0, y, -1.9), primary);
      for (const [x, z] of [[-1.0, 0.9], [1.0, 0.9], [-1.0, -0.9], [1.0, -0.9]]) legs.push({ geo: tint(new T.CylinderGeometry(0.36, 0.42, legLen + 0.3, 6).translate(0, -(legLen + 0.3) / 2, 0), primary), x, y: legLen + 0.3, z });
      bodyTop = y + 1.3; tailBase.set(0, y, -1.8);
      break;
    }
    case 'Assassin': {
      const y = legLen + 0.5;
      add(new T.CapsuleGeometry(0.55, 1.7, 4, 8).rotateX(Math.PI / 2).translate(0, y, 0), primary);
      add(new T.CapsuleGeometry(0.38, 1.3, 4, 8).rotateX(Math.PI / 2).translate(0, y - 0.25, 0.05), belly);
      headPos.set(0, y + 0.75, 1.35); headR = 0.55;
      add(new T.ConeGeometry(0.55, 1.4, 6).rotateX(Math.PI / 2).translate(headPos.x, headPos.y - 0.05, headPos.z + 0.35), primary);
      add(new T.IcosahedronGeometry(0.55, 1).translate(headPos.x, headPos.y, headPos.z), primary);
      add(new T.ConeGeometry(0.18, 0.9, 4).translate(-0.32, headPos.y + 0.65, headPos.z - 0.15), dark);
      add(new T.ConeGeometry(0.18, 0.9, 4).translate(0.32, headPos.y + 0.65, headPos.z - 0.15), dark);
      add(new T.CylinderGeometry(0.28, 0.32, 0.9, 6).rotateX(-0.6).translate(0, y + 0.45, 0.95), primary);
      for (const [x, z] of [[-0.35, 0.7], [0.35, 0.7], [-0.35, -0.7], [0.35, -0.7]]) legs.push({ geo: tint(new T.CylinderGeometry(0.16, 0.12, legLen + 0.15, 5).translate(0, -(legLen + 0.15) / 2, 0), dark), x, y: legLen + 0.15, z });
      bodyTop = y + 0.6; tailBase.set(0, y + 0.1, -1.3);
      add(new T.CylinderGeometry(0.08, 0.22, 2.2, 5).rotateX(-Math.PI / 2 + 0.5).translate(0, y + 0.55, -2.1), primary);
      break;
    }
    default: { // Support
      const y = legLen + 0.95;
      add(new T.IcosahedronGeometry(1.15, 1).translate(0, y, 0), primary);
      add(new T.IcosahedronGeometry(0.75, 1).translate(0, y - 0.15, 0.55), belly);
      headPos.set(0, y + 1.05, 0.35); headR = 0.78;
      add(new T.IcosahedronGeometry(0.8, 1).translate(headPos.x, headPos.y, headPos.z), primary);
      const earT = rng() < 0.5;
      if (earT) {
        add(new T.SphereGeometry(0.45, 8, 6).scale(0.5, 1.4, 0.3).translate(-0.55, headPos.y + 0.85, headPos.z - 0.1), primary);
        add(new T.SphereGeometry(0.45, 8, 6).scale(0.5, 1.4, 0.3).translate(0.55, headPos.y + 0.85, headPos.z - 0.1), primary);
      } else {
        add(new T.SphereGeometry(0.42, 8, 6).scale(1, 1, 0.4).translate(-0.75, headPos.y + 0.5, headPos.z - 0.1), dark);
        add(new T.SphereGeometry(0.42, 8, 6).scale(1, 1, 0.4).translate(0.75, headPos.y + 0.5, headPos.z - 0.1), dark);
      }
      add(new T.IcosahedronGeometry(0.4, 0).translate(0, y - 0.1, -1.1), belly); // fluffy tail
      for (const [x, z] of [[-0.5, 0.35], [0.5, 0.35], [-0.5, -0.4], [0.5, -0.4]]) legs.push({ geo: tint(new T.CylinderGeometry(0.28, 0.26, legLen + 0.35, 6).translate(0, -(legLen + 0.35) / 2, 0), primary), x, y: legLen + 0.35, z });
      bodyTop = y + 1.1; tailBase.set(0, y, -1.15);
    }
  }

  // eyes
  const eyeColor = def.element === 'Shadow' ? 0xc070ff : def.element === 'Undead' ? 0x9cff9c : 0xffffff;
  const eyeR = headR * (0.26 + rng() * 0.1);
  for (const side of [-1, 1]) {
    const ex = side * headR * 0.45, ey = headPos.y + headR * 0.15, ez = headPos.z + headR * 0.82;
    add(new T.SphereGeometry(eyeR, 8, 6).translate(ex, ey, ez), eyeColor);
    add(new T.SphereGeometry(eyeR * 0.5, 6, 4).translate(ex, ey, ez + eyeR * 0.6), 0x101018);
  }

  // element accessories
  const back = (k) => new T.Vector3(0, bodyTop - 0.1, 0.6 - k * 0.6);
  switch (def.element) {
    case 'Fire':
      add(new T.ConeGeometry(0.35, 1.1, 6).translate(headPos.x, headPos.y + headR + 0.45, headPos.z - 0.1), 0xff7a1a);
      add(new T.ConeGeometry(0.2, 0.7, 6).translate(headPos.x, headPos.y + headR + 0.55, headPos.z), 0xffe14a);
      add(new T.ConeGeometry(0.3, 0.9, 6).rotateX(-0.8).translate(tailBase.x, tailBase.y + 0.4, tailBase.z - 0.3), 0xff5a14);
      break;
    case 'Ice':
      for (let k = 0; k < 3; k++) { const p = back(k); add(new T.OctahedronGeometry(0.32, 0).scale(0.7, 2, 0.7).translate(p.x, p.y + 0.4, p.z), 0xbfeaff); }
      break;
    case 'Wind':
      for (const s of [-1, 1]) add(new T.ConeGeometry(0.35, 1.6, 3).scale(1, 1, 0.25).rotateZ(s * 1.0).translate(s * 0.7, bodyTop - 0.2, -0.2), 0xd4ffe0);
      add(new T.ConeGeometry(0.4, 1.4, 3).scale(1, 1, 0.25).rotateX(-1.2).translate(tailBase.x, tailBase.y + 0.2, tailBase.z - 0.5), elem);
      break;
    case 'Earth':
      for (let k = 0; k < 3; k++) { const p = back(k); add(new T.DodecahedronGeometry(0.35 + rng() * 0.2, 0).translate(p.x + (rng() - 0.5) * 0.6, p.y + 0.1, p.z), k % 2 ? 0x8a6a40 : 0x5c8a3a); }
      break;
    case 'Shadow':
      add(new T.ConeGeometry(0.16, 1.2, 4).rotateZ(0.35).rotateX(-0.5).translate(-0.35, headPos.y + headR + 0.3, headPos.z - 0.3), 0x2a1238);
      add(new T.ConeGeometry(0.16, 1.2, 4).rotateZ(-0.35).rotateX(-0.5).translate(0.35, headPos.y + headR + 0.3, headPos.z - 0.3), 0x2a1238);
      break;
    case 'Light':
      add(new T.TorusGeometry(0.6, 0.08, 5, 16).rotateX(Math.PI / 2).translate(headPos.x, headPos.y + headR + 0.55, headPos.z), 0xffe680);
      break;
    case 'Lightning':
      add(new T.BoxGeometry(0.12, 0.6, 0.12).rotateZ(0.5).translate(headPos.x - 0.1, headPos.y + headR + 0.25, headPos.z), 0xffe63c);
      add(new T.BoxGeometry(0.12, 0.6, 0.12).rotateZ(-0.5).translate(headPos.x + 0.1, headPos.y + headR + 0.7, headPos.z), 0xffe63c);
      add(new T.OctahedronGeometry(0.2, 0).translate(headPos.x - 0.05, headPos.y + headR + 1.05, headPos.z), 0xffffa0);
      add(new T.BoxGeometry(0.15, 0.7, 0.15).rotateX(-0.9).translate(tailBase.x, tailBase.y + 0.3, tailBase.z - 0.3), 0xffe63c);
      break;
    case 'Water':
      add(new T.ConeGeometry(0.6, 1.2, 3).scale(0.25, 1, 1).translate(0, bodyTop + 0.3, -0.2), 0x2f8fff);
      for (const s of [-1, 1]) add(new T.ConeGeometry(0.35, 0.9, 3).scale(1, 1, 0.25).rotateZ(s * 1.8).translate(s * 0.9, bodyTop - 0.7, 0.2), 0x6fc0ff);
      break;
    case 'Psychic':
      add(new T.OctahedronGeometry(0.22, 0).translate(headPos.x, headPos.y + headR * 0.55, headPos.z + headR * 0.8), 0xff70e0);
      add(new T.TorusGeometry(0.3, 0.05, 4, 10).translate(headPos.x, headPos.y + headR * 0.55, headPos.z + headR * 0.75), 0xc896ff);
      break;
    case 'Metal':
      for (let k = 0; k < 3; k++) { const p = back(k); add(new T.BoxGeometry(1.0, 0.18, 0.5).translate(p.x, p.y + 0.05, p.z), 0xb8c0c8); }
      add(new T.BoxGeometry(headR * 1.6, 0.18, 0.2).translate(headPos.x, headPos.y + headR * 0.55, headPos.z + headR * 0.7), 0x8a929a);
      break;
    case 'Poison':
      for (let k = 0; k < 4; k++) { const p = back(k * 0.8); add(new T.SphereGeometry(0.2 + rng() * 0.15, 6, 4).translate(p.x + (rng() - 0.5) * 0.9, p.y, p.z), 0x9cff4a); }
      break;
    case 'Undead':
      for (let k = 0; k < 3; k++) add(new T.TorusGeometry(0.75, 0.07, 4, 10, Math.PI).rotateY(Math.PI / 2).translate(0, bodyTop - 0.6, 0.4 - k * 0.45), 0xf0e8d6);
      break;
  }

  // wings for flying creatures (separate meshes so they flap)
  if (def.flying) {
    for (const side of [-1, 1]) {
      const g = tint(new T.ConeGeometry(0.9, 2.4, 3).scale(1, 1, 0.12).rotateZ(side * -Math.PI / 2).translate(side * 1.2, 0, 0), mix(primary, elem, 0.5));
      wings.push({ geo: g, x: side * 0.4, y: bodyTop - 0.35, z: -0.1, side });
    }
  }

  const body = mergeGeometries(parts);
  body.computeVertexNormals();
  return { body, legs, wings, headY: headPos.y + headR };
}

function getGeometry(def, variant) {
  const key = def.id + ':' + variant;
  if (!geoCache.has(key)) geoCache.set(key, buildGeometry(def, variant));
  return geoCache.get(key);
}

// Returns { root, inner, legs[], wings[], height, radius, setFaint(), animate() }
export function buildCreatureModel(def, { variant = 'Normal', shiny = false, scale = 1 } = {}) {
  const g = getGeometry(def, variant);
  const mat = creatureMaterial(variant, shiny);
  const root = new THREE.Group();
  const inner = new THREE.Group();
  root.add(inner);
  const body = new THREE.Mesh(g.body, mat);
  body.castShadow = true;
  inner.add(body);
  const legs = g.legs.map((l) => {
    const m = new THREE.Mesh(l.geo, mat);
    m.position.set(l.x, l.y, l.z);
    m.castShadow = true;
    inner.add(m);
    return m;
  });
  const wings = g.wings.map((w) => {
    const m = new THREE.Mesh(w.geo, mat);
    m.position.set(w.x, w.y, w.z);
    m.userData.side = w.side;
    inner.add(m);
    return m;
  });
  const s = (RARITY_SCALE[def.rarity] || 1) * scale;
  inner.scale.setScalar(def.crawling ? s : s);
  if (def.crawling) inner.scale.set(s * 1.1, s * 0.7, s * 1.25);
  const height = g.headY * inner.scale.y + (def.flying ? 1.5 : 0);
  const radius = 1.4 * s;
  const hover = def.flying || def.class === 'Mage' ? (def.flying ? 2.2 : 0.4) * s : 0;
  inner.position.y = hover;
  const phase = Math.random() * 10;
  return {
    root, inner, legs, wings, height: height + hover, radius, hover, scale: s,
    animate(t, speed) {
      const moving = Math.min(1, speed / 6);
      const f = 6 + speed * 0.6;
      legs.forEach((l, i) => { l.rotation.x = Math.sin(t * f + phase + (i % 2 ? Math.PI : 0) + (i > 1 ? Math.PI / 2 : 0)) * 0.6 * moving; });
      wings.forEach((w) => { w.rotation.z = Math.sin(t * 10 + phase) * 0.55 * w.userData.side; });
      inner.position.y = hover + Math.abs(Math.sin(t * f * 0.5 + phase)) * 0.15 * moving * s + (hover ? Math.sin(t * 2 + phase) * 0.3 : 0);
      if (!moving) inner.scale.y = (def.crawling ? s * 0.7 : s) * (1 + Math.sin(t * 2.2 + phase) * 0.025);
    },
  };
}
