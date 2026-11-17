// Real Siegelings assets (glTF/GLB, e.g. Meshy exports) with automatic fallback to the stand-ins.
//
// Drop files into web/public/models/ named after the creature's `modelName` from CreatureData.lua
// (e.g. Firsky.glb) or its id (firsky.glb). `npm run dev` / `npm run build` regenerate
// models/manifest.json, which is how the game knows which creatures have a real model.
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/examples/jsm/libs/meshopt_decoder.module.js';
import { clone as cloneSkinned } from 'three/examples/jsm/utils/SkeletonUtils.js';

const BASE = import.meta.env.BASE_URL + 'models/';
let manifest = {};          // lowercased name -> file name
const pending = new Map();  // url -> Promise<gltf>
const loaded = new Map();   // url -> gltf (once resolved)
const listeners = new Set();
const loader = new GLTFLoader();
loader.setMeshoptDecoder(MeshoptDecoder);

export async function initModels() {
  try {
    const res = await fetch(`${BASE}manifest.json`, { cache: 'no-cache' });
    if (res.ok) manifest = await res.json();
  } catch { manifest = {}; }
  const n = Object.keys(manifest).length;
  if (n) console.info(`[models] ${n} real creature model(s) available`);
  return n;
}

export function modelCount() { return Object.keys(manifest).length; }

export function modelUrlFor(def) {
  const file = manifest[(def.modelName || '').toLowerCase()] || manifest[def.id.toLowerCase()];
  return file ? BASE + file : null;
}

export function onModelLoaded(fn) { listeners.add(fn); return () => listeners.delete(fn); }

export function getLoaded(url) { return loaded.get(url) || null; }

export function loadModel(url) {
  if (!pending.has(url)) {
    pending.set(url, loader.loadAsync(url).then((gltf) => {
      loaded.set(url, gltf);
      for (const fn of listeners) fn(url);
      return gltf;
    }).catch((err) => {
      console.warn(`[models] could not load ${url}, keeping the stand-in`, err);
      return null;
    }));
  }
  return pending.get(url);
}

const VARIANT_EMISSIVE = { Silver: 0x1c2026, Gold: 0x3a2800, Legend: 0x3a0838 };

// Build a scene-ready instance of a loaded glTF, sized and oriented using the same hints the
// Roblox build uses (modelDisplaySize, modelScaleMultiplier, modelRotationY, modelStandUpAngles).
export function instantiate(gltf, def, { targetSize, variant = 'Normal', shiny = false }) {
  const obj = cloneSkinned(gltf.scene);
  const D = Math.PI / 180;
  if (def.modelStandUpAngles) {
    const [rx, ry, rz] = def.modelStandUpAngles;
    obj.rotation.set(rx * D, ry * D, rz * D);
  }
  const yaw = new THREE.Group();
  yaw.rotation.y = (def.modelRotationY || 0) * D;
  yaw.add(obj);
  const pivot = new THREE.Group();
  pivot.add(yaw);
  pivot.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(pivot);
  const size = box.getSize(new THREE.Vector3());
  const s = targetSize / Math.max(size.x, size.y, size.z, 0.001);
  pivot.scale.setScalar(s);
  const c = box.getCenter(new THREE.Vector3());
  // sit on the ground, centred on the creature's position
  yaw.position.set(-c.x, -box.min.y + (def.modelPlacementYOffset || 0) / s, -c.z);
  const tint = VARIANT_EMISSIVE[variant] || (shiny ? 0x2a2a40 : 0);
  obj.traverse((m) => {
    if (!m.isMesh) return;
    m.castShadow = true;
    m.frustumCulled = !m.isSkinnedMesh; // skinned bounds are unreliable after scaling
    if (tint && m.material && 'emissive' in m.material) {
      m.material = m.material.clone();
      m.material.emissive = new THREE.Color(tint);
    }
  });
  let mixer = null, idle = null, walk = null;
  if (gltf.animations && gltf.animations.length) {
    mixer = new THREE.AnimationMixer(obj);
    const find = (re) => gltf.animations.find((a) => re.test(a.name));
    const idleClip = find(/idle|stand|breath/i) || gltf.animations[0];
    const walkClip = find(/walk|run|move|locomotion/i);
    idle = mixer.clipAction(idleClip);
    idle.play();
    if (walkClip && walkClip !== idleClip) walk = mixer.clipAction(walkClip);
  }
  return { pivot, height: size.y * s, radius: Math.max(size.x, size.z) * s * 0.5, mixer, idle, walk };
}
