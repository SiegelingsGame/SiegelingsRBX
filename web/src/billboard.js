// TCG card art as camera-facing billboards. Each Siegeling with `art` (synced from the TCG by
// tools/sync_tcg_roster.py) renders as an upright sprite of its card overlay image that always turns
// to face the player's camera, with a soft ground shadow, idle/walk motion and a fainted pose.
import * as THREE from 'three';

const RARITY_HEIGHT = { Common: 3.2, Uncommon: 3.8, Rare: 4.6, Epic: 5.6, Legendary: 7.2 }; // studs
const VARIANT_TINT = { Normal: [1, 1, 1], Silver: [0.86, 0.9, 1.0], Gold: [1.0, 0.86, 0.5], Legend: [1.0, 0.72, 1.0] };

const textures = new Map(); // url -> { normal, flipped }
const live = new Set();     // instances, for the global light level
let light = 1;
let camera = null;
const loader = new THREE.TextureLoader();
const shadowGeo = new THREE.CircleGeometry(1, 20).rotateX(-Math.PI / 2);
const shadowMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.28, depthWrite: false });

export function setBillboardCamera(cam) { camera = cam; }

// Sprites are unlit, so the sky/day-night system feeds them a brightness (0..1).
export function setBillboardLight(level) {
  light = level;
  for (const b of live) b.applyColor();
}

function getTextures(url) {
  if (!textures.has(url)) {
    const normal = loader.load(url);
    normal.colorSpace = THREE.SRGBColorSpace;
    normal.anisotropy = 4;
    const flipped = normal.clone(); // shares the image upload
    flipped.wrapS = THREE.RepeatWrapping;
    flipped.repeat.x = -1;
    flipped.offset.x = 1;
    textures.set(url, { normal, flipped });
  }
  return textures.get(url);
}

export function hasArt(def) { return !!def.art; }

// Builds a model object with the same shape as the 3D stand-ins (root, inner, height, radius, animate...).
export function buildBillboard(def, { variant = 'Normal', shiny = false, scale = 1 } = {}) {
  const tex = getTextures(def.art);
  const mat = new THREE.SpriteMaterial({ map: tex.normal, alphaTest: 0.35, transparent: false, fog: true });
  const sprite = new THREE.Sprite(mat);
  sprite.center.set(0.5, 0.02); // anchored at the feet
  const aspect = def.artAspect || 1;
  const h = (RARITY_HEIGHT[def.rarity] || 3.4) * (def.modelScaleMultiplier || 1) * scale;
  const w = h * aspect;
  sprite.scale.set(w, h, 1);
  const root = new THREE.Group();
  const inner = new THREE.Group();
  root.add(inner);
  inner.add(sprite);
  const shadow = new THREE.Mesh(shadowGeo, shadowMat);
  shadow.scale.set(Math.max(0.8, w * 0.36), 1, Math.max(0.6, w * 0.24));
  shadow.position.y = 0.06;
  shadow.renderOrder = -1;
  root.add(shadow);
  const hover = def.flying ? 1.8 * scale : 0;
  const tint = VARIANT_TINT[variant] || VARIANT_TINT.Normal;
  const phase = Math.random() * 10;
  const model = {
    root, inner, legs: [], wings: [], sprite, billboard: true,
    height: h + hover, radius: Math.max(0.9, w * 0.42), hover, scale,
    fainted: false, flip: false,
    applyColor() {
      const k = light * (model.fainted ? 0.55 : 1) * (shiny ? 1.12 : 1);
      mat.color.setRGB(tint[0] * k, tint[1] * k, tint[2] * k);
    },
    setFainted(on) {
      if (on === model.fainted) return;
      model.fainted = on;
      mat.rotation = on ? Math.PI / 2 * (model.flip ? -1 : 1) : 0;
      sprite.position.y = 0;
      model.applyColor();
    },
    animate(t, speed) {
      if (model.fainted) return;
      const moving = Math.min(1, speed / 6);
      const f = 6 + speed * 0.6;
      // waddle + bounce while walking, gentle breathing while idle
      sprite.position.y = hover + Math.abs(Math.sin(t * f * 0.5 + phase)) * 0.25 * moving + (hover ? Math.sin(t * 2 + phase) * 0.3 : 0);
      mat.rotation = Math.sin(t * f * 0.5 + phase) * 0.07 * moving;
      sprite.scale.y = h * (1 + Math.sin(t * 2.2 + phase) * 0.025 * (1 - moving));
      // face the way it walks: TCG art mostly faces left, so mirror it when moving toward screen-right
      if (camera && moving > 0.2) {
        const yaw = root.rotation.y;
        const camRight = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 0);
        const side = Math.sin(yaw) * camRight.x + Math.cos(yaw) * camRight.z;
        const flip = side > 0.15 ? true : side < -0.15 ? false : model.flip;
        if (flip !== model.flip) { model.flip = flip; mat.map = flip ? tex.flipped : tex.normal; }
      }
    },
    dispose() { live.delete(model); mat.dispose(); },
  };
  model.applyColor();
  live.add(model);
  return model;
}
