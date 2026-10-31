// Renders small 3D portraits of creature stand-in models for the UI (cached data URLs).
import * as THREE from 'three';
import { buildCreatureModel } from './creatureModel.js';
import { getCreature } from './data.js';

let renderer = null, scene, camera;
const cache = new Map();

function init() {
  renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
  renderer.setSize(160, 160);
  renderer.setPixelRatio(1);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xffffff, 0x554466, 2.2));
  const d = new THREE.DirectionalLight(0xffffff, 2.2); d.position.set(3, 5, 6); scene.add(d);
  camera = new THREE.PerspectiveCamera(32, 1, 0.1, 100);
}

export function portrait(id, variant = 'Normal', shiny = false) {
  const key = `${id}:${variant}:${shiny}`;
  if (cache.has(key)) return cache.get(key);
  const def = getCreature(id);
  if (!def) return '';
  try {
    if (!renderer) init();
    const m = buildCreatureModel(def, { variant, shiny });
    m.inner.position.y = m.hover;
    scene.add(m.root);
    const box = new THREE.Box3().setFromObject(m.root);
    const size = box.getSize(new THREE.Vector3()), center = box.getCenter(new THREE.Vector3());
    const r = Math.max(size.x, size.y, size.z);
    camera.position.set(center.x + r * 1.1, center.y + r * 0.5, center.z + r * 1.9);
    camera.lookAt(center);
    renderer.render(scene, camera);
    const url = renderer.domElement.toDataURL('image/png');
    scene.remove(m.root);
    cache.set(key, url);
    return url;
  } catch {
    cache.set(key, '');
    return '';
  }
}
