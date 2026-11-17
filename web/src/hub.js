// Arena Hub (central area): plaza, healing fountain, arena ring, and hub NPCs —
// The Curator (rotating creature stock), Siege Master (XP food), The Broker (buys creatures).
import * as THREE from 'three';
import { HUB_R, textTexture } from './world.js';
import { buildAvatar } from './player.js';

function npcLabel(name, subtitle, color) {
  const c = document.createElement('canvas');
  c.width = 512; c.height = 150;
  const ctx = c.getContext('2d');
  ctx.fillStyle = 'rgba(15,12,24,0.75)'; ctx.beginPath(); ctx.roundRect(4, 4, 504, 142, 24); ctx.fill();
  ctx.fillStyle = color; ctx.font = 'bold 56px system-ui'; ctx.textAlign = 'center'; ctx.fillText(name, 256, 70);
  ctx.fillStyle = '#ddd6f3'; ctx.font = '34px system-ui'; ctx.fillText(subtitle, 256, 120);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace;
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, depthWrite: false }));
  s.scale.set(9, 9 * 150 / 512, 1);
  return s;
}

function stall(color, awning) {
  const g = new THREE.Group();
  const counter = new THREE.Mesh(new THREE.BoxGeometry(8, 2.4, 2.4), new THREE.MeshLambertMaterial({ color }));
  counter.position.set(0, 1.2, 2.2); counter.castShadow = true; counter.receiveShadow = true; g.add(counter);
  for (const sx of [-1, 1]) {
    const p = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.25, 7, 6), new THREE.MeshLambertMaterial({ color: 0x5a3e28 }));
    p.position.set(sx * 4, 3.5, 3.3); g.add(p);
    const p2 = p.clone(); p2.position.z = -1.5; g.add(p2);
  }
  const roof = new THREE.Mesh(new THREE.BoxGeometry(9.4, 0.4, 6), new THREE.MeshLambertMaterial({ color: awning }));
  roof.position.set(0, 7.1, 0.9); roof.rotation.x = 0.18; roof.castShadow = true; g.add(roof);
  return g;
}

export class Hub {
  constructor(scene) {
    this.scene = scene;
    this.blockers = [];
    this.npcs = [];
    this.time = 0;
    const g = new THREE.Group();
    scene.add(g);
    this.group = g;

    // plaza + stone rings
    const plaza = new THREE.Mesh(new THREE.CylinderGeometry(HUB_R, HUB_R + 2, 0.6, 64), new THREE.MeshLambertMaterial({ color: 0xb9b3a4 }));
    plaza.position.y = -0.25; plaza.receiveShadow = true; g.add(plaza);
    for (const [r, c] of [[HUB_R - 3, 0x8e8778], [30, 0x9e9888], [14, 0x8e8778]]) {
      const ring = new THREE.Mesh(new THREE.RingGeometry(r - 1.2, r, 64).rotateX(-Math.PI / 2), new THREE.MeshLambertMaterial({ color: c }));
      ring.position.y = 0.07; ring.receiveShadow = true; g.add(ring);
    }

    // healing fountain
    const basin = new THREE.Mesh(new THREE.CylinderGeometry(8, 8.6, 1.6, 32), new THREE.MeshLambertMaterial({ color: 0x8c8676 }));
    basin.position.y = 0.8; basin.castShadow = true; g.add(basin);
    const water = new THREE.Mesh(new THREE.CylinderGeometry(7.2, 7.2, 0.2, 32), new THREE.MeshPhongMaterial({ color: 0x5ad0ff, transparent: true, opacity: 0.8, shininess: 80 }));
    water.position.y = 1.5; g.add(water);
    const spire = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 1.4, 7, 8), new THREE.MeshLambertMaterial({ color: 0xa49d8b }));
    spire.position.y = 4; spire.castShadow = true; g.add(spire);
    this.crystal = new THREE.Mesh(new THREE.OctahedronGeometry(1.6, 0), new THREE.MeshBasicMaterial({ color: 0x8affd8 }));
    this.crystal.position.y = 9; g.add(this.crystal);
    const light = new THREE.PointLight(0x8affd8, 120, 40, 1.5); light.position.y = 9; g.add(light);
    this.blockers.push({ x: 0, z: 0, r: 8.5 });

    // central arena ring (north side)
    const arenaPos = new THREE.Vector3(0, 0, -38);
    const arena = new THREE.Mesh(new THREE.CylinderGeometry(15, 15.5, 0.8, 40), new THREE.MeshLambertMaterial({ color: 0x6d5c8f }));
    arena.position.copy(arenaPos).y = 0.4; arena.receiveShadow = true; g.add(arena);
    const arenaRing = new THREE.Mesh(new THREE.TorusGeometry(15, 0.4, 6, 48).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: 0xffd76a }));
    arenaRing.position.copy(arenaPos).y = 0.9; g.add(arenaRing);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      const p = new THREE.Mesh(new THREE.BoxGeometry(1.4, 9, 1.4), new THREE.MeshLambertMaterial({ color: 0x5a4f78 }));
      p.position.set(arenaPos.x + Math.cos(a) * 17, 4.5, arenaPos.z + Math.sin(a) * 17); p.castShadow = true; g.add(p);
      const flag = new THREE.Mesh(new THREE.PlaneGeometry(2.2, 3), new THREE.MeshLambertMaterial({ color: i % 2 ? 0x3a6bd5 : 0xd53a4a, side: THREE.DoubleSide }));
      flag.position.set(p.position.x, 7.4, p.position.z); flag.rotation.y = -a; g.add(flag);
    }
    const arenaSign = npcLabel('ARENA', 'Battles coming soon', '#ffd76a');
    arenaSign.position.copy(arenaPos).y = 12; arenaSign.scale.multiplyScalar(1.4); g.add(arenaSign);

    // spawn pad
    const spawn = new THREE.Mesh(new THREE.CylinderGeometry(4, 4, 0.2, 24), new THREE.MeshLambertMaterial({ color: 0x4a7bd5 }));
    spawn.position.set(0, 0.1, 22); g.add(spawn);

    // NPC vendors around the south half of the plaza
    this.addNpc('curator', 'The Curator', 'Rare creature trader', '#7fd0ff', new THREE.Vector3(-26, 0, 22), 0x2f5a8a, 0x3a7bd5, { shirt: 0x2a3a6a, hat: 0x1a2440 });
    this.addNpc('siegemaster', 'Siege Master', 'Food & XP provisions', '#ffb36a', new THREE.Vector3(26, 0, 22), 0x7a4f2a, 0xd5853a, { shirt: 0x8a3a2a, hat: 0xf0e0c0 });
    this.addNpc('broker', 'The Broker', 'Buys your creatures', '#d59aff', new THREE.Vector3(0, 0, 40), 0x3a2f4a, 0x6a3ab5, { shirt: 0x2a1f3a, hat: 0x111111 });

    // welcome board
    const board = new THREE.Mesh(new THREE.PlaneGeometry(14, 5), new THREE.MeshBasicMaterial({ map: textTexture('SIEGELINGS', '#1c1830', '#ffd76a', 1024, 360, 'bold 170px system-ui'), side: THREE.DoubleSide }));
    board.position.set(-38, 7, -14); board.rotation.y = Math.PI / 2.6; g.add(board);
    const bpost = new THREE.Mesh(new THREE.BoxGeometry(0.6, 7, 0.6), new THREE.MeshLambertMaterial({ color: 0x5a3e28 }));
    bpost.position.set(-38, 3.5, -14); g.add(bpost);
  }

  addNpc(id, name, subtitle, color, pos, stallColor, awning, look) {
    const s = stall(stallColor, awning);
    s.position.copy(pos);
    s.lookAt(0, 0, 0);
    this.group.add(s);
    const av = buildAvatar(look);
    const back = new THREE.Vector3(0, 0, -0.2).applyQuaternion(s.quaternion);
    av.root.position.copy(pos).add(back);
    av.root.lookAt(0, 0, 0);
    this.group.add(av.root);
    const label = npcLabel(name, subtitle, color);
    label.position.copy(pos).y = 10;
    this.group.add(label);
    const front = new THREE.Vector3(0, 0, 4.5).applyQuaternion(s.quaternion);
    this.npcs.push({ id, name, pos: pos.clone().add(front), avatar: av });
    this.blockers.push({ x: pos.x, z: pos.z, r: 4.2 });
  }

  interactables(ctx) {
    const map = {
      curator: { label: 'Talk to The Curator (buy creatures)', action: () => ctx.ui.openCurator() },
      siegemaster: { label: 'Talk to Siege Master (XP food)', action: () => ctx.ui.openSiegeMaster() },
      broker: { label: 'Talk to The Broker (sell creatures)', action: () => ctx.ui.openBroker() },
    };
    const list = this.npcs.map((n) => ({ pos: n.pos, radius: 7, label: () => map[n.id].label, action: map[n.id].action }));
    list.push({ pos: new THREE.Vector3(0, 0, 0), radius: 13, label: () => 'Healing Fountain — restore HP & revive companion', action: () => ctx.healAll() });
    return list;
  }

  update(dt) {
    this.time += dt;
    this.crystal.rotation.y += dt;
    this.crystal.position.y = 9 + Math.sin(this.time * 1.5) * 0.4;
    for (const n of this.npcs) n.avatar.armR.rotation.x = Math.sin(this.time * 1.3 + n.pos.x) * 0.2;
  }
}
