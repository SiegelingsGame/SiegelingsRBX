// HUD, world labels, minimap and menu panels (Inventory, Base Core, slot picker, capture, hub vendors).
import * as THREE from 'three';
import { CFG, RARITY_COLORS, RARITY_ORDER, VARIANT_COLORS } from './config.js';
import { State } from './state.js';
import { getCreature, effectiveStats, xpForLevel, playerXPForLevel, maxCreatureLevel, sellValue, creatureIncome, isNightElement, STARTERS, Creatures, captureCost } from './data.js';
import { BIOMES, biomeAt, plotCenter, PLOT_SIZE, WORLD_R, HUB_R, ROADS, RING_ROAD_R } from './world.js';
import { portrait } from './portraits.js';
import { fmt, pick } from './util.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ELEMENT_EMOJI = { Fire: '🔥', Ice: '❄️', Wind: '🌪️', Earth: '🌿', Shadow: '🌑', Light: '✨', Lightning: '⚡', Water: '💧', Psychic: '🔮', Metal: '⚙️', Poison: '☠️', Undead: '💀' };

const SIEGE_FOOD = [
  { id: 'snack', name: 'Ember Biscuit', desc: '+60 XP to one creature', xp: 60, cost: 40, icon: '🍪' },
  { id: 'meal', name: 'Hearty Stew', desc: '+350 XP to one creature', xp: 350, cost: 200, icon: '🍲' },
  { id: 'feast', name: 'Siege Feast', desc: '+2,000 XP to one creature', xp: 2000, cost: 900, icon: '🍖' },
];

export class UI {
  constructor(game) {
    this.g = game;
    this.open = null;
    this.labelPool = [];
    this.floats = [];
    this.toasts = $('#toasts');
    this.panel = $('#panel');
    this.panelBody = $('#panel-body');
    this.panelTitle = $('#panel-title');
    this.prompt = $('#prompt');
    this.mini = $('#minimap');
    this.miniCtx = this.mini.getContext('2d');
    this.buildMapImage();
    $('#panel-close').addEventListener('click', () => this.close());
    this.panelBody.addEventListener('click', (e) => this.onPanelClick(e));
    State.on((k) => { if (k === 'inventory' || k === 'slots' || k === 'floors' || k === 'coins') this.refreshOpen(); });
    this.inventoryFilter = 'all';
  }

  // ── HUD ──────────────────────────────────────────────────────
  updateHUD() {
    const d = State.data, g = this.g;
    $('#coins').textContent = fmt(d.coins);
    $('#plevel').textContent = d.playerLevel;
    const need = playerXPForLevel(d.playerLevel + 1);
    $('#pxp-fill').style.width = `${Math.min(100, (d.playerXP / need) * 100)}%`;
    $('#pxp-text').textContent = `${fmt(d.playerXP)} / ${fmt(need)} XP`;
    $('#hp-fill').style.width = `${(g.player.hp / g.player.maxHp) * 100}%`;
    $('#hp-text').textContent = `${Math.ceil(g.player.hp)} / ${g.player.maxHp}`;
    const b = biomeAt(g.player.pos.x, g.player.pos.z);
    const onBase = g.base.isInside(g.player.pos, 2);
    $('#biome').textContent = onBase ? 'Your Base' : BIOMES[b].name;
    const h = d.timeOfDay;
    const hh = Math.floor(h), mm = Math.floor((h - hh) * 60);
    $('#clock').textContent = `${g.isNight() ? '🌙' : '☀️'} ${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
    const inc = State.incomePerTick(g.isNight());
    $('#income').textContent = `+${fmt(inc)} / ${CFG.IncomeTickSeconds}s`;
    $('#inv-count').textContent = `${d.inventory.length}/${CFG.MaxInventorySize}`;
    const comp = g.companion;
    const cw = $('#companion');
    if (comp.uid) {
      const e = comp.entry, def = e && getCreature(e.id);
      cw.style.display = 'flex';
      if (def && cw.dataset.uid !== comp.uid + e.level) {
        cw.dataset.uid = comp.uid + e.level;
        $('#comp-img').src = portrait(e.id, e.variant, e.shiny);
        $('#comp-name').textContent = `${e.nickname || def.displayName} · Lv ${e.level}`;
      }
      $('#comp-hp').style.width = comp.model ? `${(comp.hp / comp.maxHp) * 100}%` : '0%';
      $('#comp-state').textContent = comp.model ? '' : `Fainted — back in ${Math.max(0, Math.ceil(comp.respawn))}s`;
    } else cw.style.display = 'none';
    $('#hurt').style.opacity = g.player.hurtFlash > 0 ? g.player.hurtFlash * 2 : 0;
    $('#crosshair').classList.toggle('aim', g.cam.aiming);
  }

  setPrompt(text) {
    if (!text) { this.prompt.style.display = 'none'; return; }
    this.prompt.style.display = 'block';
    this.prompt.innerHTML = `<kbd>E</kbd> ${esc(text)}`;
  }

  notify(msg, kind = 'info') {
    const el = document.createElement('div');
    el.className = `toast ${kind}`;
    el.textContent = msg;
    this.toasts.prepend(el);
    setTimeout(() => el.classList.add('out'), 3800);
    setTimeout(() => el.remove(), 4400);
    while (this.toasts.children.length > 5) this.toasts.lastChild.remove();
  }

  floatText(pos, text, color = '#ffe066') {
    const el = document.createElement('div');
    el.className = 'float';
    el.textContent = text;
    el.style.color = color;
    $('#labels').appendChild(el);
    this.floats.push({ el, pos: pos.clone(), life: 1.3 });
  }

  // ── world labels (wild creatures, base creatures, floating text) ──
  updateLabels(dt, camera) {
    const W = window.innerWidth, H = window.innerHeight;
    const v = new THREE.Vector3();
    const items = [];
    const pp = this.g.player.pos;
    for (const c of this.g.creatures.list) {
      if (!c.model.root.visible) continue;
      const d = c.pos.distanceTo(pp);
      if (d > (c.isBoss ? 90 : 48)) continue;
      items.push({ d, pos: c.pos.clone().setY(c.pos.y + c.model.height + 1.4), c });
    }
    for (const b of this.g.base.labels(this.g.isNight())) {
      const d = b.pos.distanceTo(pp);
      if (d < 40) items.push({ d, pos: b.pos, b });
    }
    items.sort((a, b) => a.d - b.d);
    const max = Math.min(items.length, 28);
    while (this.labelPool.length < max) {
      const el = document.createElement('div');
      el.className = 'clabel';
      el.innerHTML = '<div class="n"></div><div class="hp"><i></i></div><div class="s"></div>';
      $('#labels').appendChild(el);
      this.labelPool.push(el);
    }
    for (let i = 0; i < this.labelPool.length; i++) {
      const el = this.labelPool[i];
      if (i >= max) { el.style.display = 'none'; continue; }
      const it = items[i];
      v.copy(it.pos).project(camera);
      if (v.z > 1 || Math.abs(v.x) > 1.1 || Math.abs(v.y) > 1.1) { el.style.display = 'none'; continue; }
      el.style.display = 'block';
      el.style.transform = `translate(${(v.x * 0.5 + 0.5) * W}px, ${(-v.y * 0.5 + 0.5) * H}px) translate(-50%, -100%)`;
      el.style.opacity = it.d > 30 ? Math.max(0.35, 1 - (it.d - 30) / 40) : 1;
      const key = it.c ? `${it.c.def.id}${it.c.level}${it.c.fainted}${it.c.variant}${it.c.isBoss}${it.c.isRaider}` : `${it.b.name}${it.b.level}${it.b.sub}`;
      if (el.dataset.key !== key) {
        el.dataset.key = key;
        const n = el.children[0], s = el.children[2];
        if (it.c) {
          const c = it.c;
          const vtag = c.variant !== 'Normal' ? `<b style="color:${VARIANT_COLORS[c.variant]}">${c.variant}</b> ` : '';
          n.innerHTML = `${c.isBoss ? '👑 ' : ''}${c.shiny ? '✨' : ''}${vtag}${esc(c.def.displayName)} <span>Lv ${c.level}</span>`;
          n.style.color = RARITY_COLORS[c.def.rarity];
          s.innerHTML = c.fainted ? `💫 Fainted · capture ${captureCost(c.def.id)} 🪙` : c.isRaider ? '⚔️ Raider' : `${ELEMENT_EMOJI[c.def.element] || ''} ${c.def.rarity}`;
          el.classList.toggle('fainted', c.fainted);
        } else {
          n.innerHTML = `${esc(it.b.name)} <span>Lv ${it.b.level}</span>`;
          n.style.color = RARITY_COLORS[it.b.rarity];
          s.textContent = it.b.sub;
          el.classList.remove('fainted');
        }
      }
      const hpEl = el.children[1];
      if (it.c && !it.c.fainted) { hpEl.style.display = 'block'; hpEl.firstChild.style.width = `${(it.c.hp / it.c.maxHp) * 100}%`; }
      else hpEl.style.display = 'none';
    }
    for (let i = this.floats.length - 1; i >= 0; i--) {
      const f = this.floats[i];
      f.life -= dt;
      f.pos.y += dt * 3;
      if (f.life <= 0) { f.el.remove(); this.floats.splice(i, 1); continue; }
      v.copy(f.pos).project(camera);
      if (v.z > 1) { f.el.style.display = 'none'; continue; }
      f.el.style.display = 'block';
      f.el.style.opacity = Math.min(1, f.life * 2);
      f.el.style.transform = `translate(${(v.x * 0.5 + 0.5) * W}px, ${(-v.y * 0.5 + 0.5) * H}px) translate(-50%, -50%)`;
    }
  }

  // ── minimap ──────────────────────────────────────────────────
  buildMapImage() {
    const S = 600;
    const c = document.createElement('canvas'); c.width = S; c.height = S;
    const ctx = c.getContext('2d');
    const img = ctx.createImageData(S, S);
    const col = new THREE.Color();
    const world = this.g.world;
    for (let j = 0; j < S; j++) for (let i = 0; i < S; i++) {
      const x = (i / S - 0.5) * WORLD_R * 2.1, z = (j / S - 0.5) * WORLD_R * 2.1;
      const r = Math.hypot(x, z);
      const k = (j * S + i) * 4;
      if (r > WORLD_R) { img.data[k + 3] = 0; continue; }
      col.setHex(BIOMES[biomeAt(x, z)].color);
      const h = world.terrainHeight(x, z);
      col.multiplyScalar(0.75 + Math.min(0.5, Math.max(-0.2, h / 80)));
      if (world.isWater(x, z)) col.setHex(0x2f8fd8);
      img.data[k] = col.r * 255; img.data[k + 1] = col.g * 255; img.data[k + 2] = col.b * 255; img.data[k + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
    const toPx = (x) => (x / (WORLD_R * 2.1) + 0.5) * S;
    ctx.strokeStyle = '#d8c39a'; ctx.lineWidth = 3;
    for (const rd of ROADS) {
      const a = rd.angle * Math.PI / 180;
      ctx.beginPath(); ctx.moveTo(toPx(Math.cos(a) * HUB_R), toPx(Math.sin(a) * HUB_R)); ctx.lineTo(toPx(Math.cos(a) * 650), toPx(Math.sin(a) * 650)); ctx.stroke();
    }
    ctx.beginPath(); ctx.arc(toPx(0), toPx(0), RING_ROAD_R / (WORLD_R * 2.1) * S, 0, Math.PI * 2); ctx.stroke();
    ctx.fillStyle = '#c9c3b2'; ctx.beginPath(); ctx.arc(toPx(0), toPx(0), HUB_R / (WORLD_R * 2.1) * S, 0, Math.PI * 2); ctx.fill();
    for (let i = 0; i < 8; i++) {
      const p = plotCenter(i);
      ctx.fillStyle = i === this.g.base.plotIndex ? '#ffd76a' : '#8e8aa0';
      const s = PLOT_SIZE / (WORLD_R * 2.1) * S;
      ctx.fillRect(toPx(p.x) - s / 2, toPx(p.z) - s / 2, s, s);
    }
    this.mapImg = c;
    this.mapScale = S / (WORLD_R * 2.1);
  }

  drawMinimap(big = false) {
    const cv = big ? $('#bigmap') : this.mini;
    const ctx = big ? cv.getContext('2d') : this.miniCtx;
    const W = cv.width, H = cv.height;
    const g = this.g, p = g.player.pos;
    const S = this.mapImg.width, sc = this.mapScale;
    ctx.clearRect(0, 0, W, H);
    ctx.save();
    if (big) {
      const k = Math.min(W, H) / S;
      ctx.translate(W / 2, H / 2); ctx.scale(k, k); ctx.translate(-S / 2, -S / 2);
      ctx.drawImage(this.mapImg, 0, 0);
      ctx.font = 'bold 13px system-ui'; ctx.textAlign = 'center';
      for (const [id, b] of Object.entries(BIOMES)) {
        let x, z;
        if (id === 'hub') { x = 0; z = 0; } else if (b.outer) { x = b.center.x; z = b.center.y; } else { const a = b.angle * Math.PI / 180; x = Math.cos(a) * 330; z = Math.sin(a) * 330; }
        ctx.fillStyle = 'rgba(0,0,0,0.6)'; ctx.fillText(b.name, x * sc + S / 2 + 1, z * sc + S / 2 + 1);
        ctx.fillStyle = '#fff'; ctx.fillText(b.name, x * sc + S / 2, z * sc + S / 2);
      }
      this.drawMarkers(ctx, (x) => x * sc + S / 2, (z) => z * sc + S / 2, 1.6);
      ctx.translate(p.x * sc + S / 2, p.z * sc + S / 2);
      ctx.rotate(-g.cam.yaw);
    } else {
      const zoom = 2.3;
      ctx.beginPath(); ctx.arc(W / 2, H / 2, W / 2 - 2, 0, Math.PI * 2); ctx.clip();
      ctx.fillStyle = '#1a1626'; ctx.fillRect(0, 0, W, H);
      ctx.translate(W / 2, H / 2);
      ctx.rotate(g.cam.yaw);
      ctx.scale(zoom, zoom);
      ctx.translate(-(p.x * sc + S / 2), -(p.z * sc + S / 2));
      ctx.drawImage(this.mapImg, 0, 0);
      this.drawMarkers(ctx, (x) => x * sc + S / 2, (z) => z * sc + S / 2, 1 / zoom * 2.2, p, 90);
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.translate(W / 2, H / 2);
    }
    // player arrow
    ctx.fillStyle = '#fff'; ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(0, -8); ctx.lineTo(6, 7); ctx.lineTo(0, 3); ctx.lineTo(-6, 7); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.restore();
    if (!big) {
      ctx.strokeStyle = 'rgba(255,215,106,0.8)'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(W / 2, H / 2, W / 2 - 2, 0, Math.PI * 2); ctx.stroke();
      ctx.fillStyle = '#ffd76a'; ctx.font = 'bold 12px system-ui'; ctx.textAlign = 'center'; ctx.fillText('N', W / 2 + Math.sin(g.cam.yaw) * (W / 2 - 12), H / 2 - Math.cos(g.cam.yaw) * (H / 2 - 12) + 4);
    }
  }

  drawMarkers(ctx, tx, tz, s, center = null, range = Infinity) {
    for (const c of this.g.creatures.list) {
      if (center && Math.hypot(c.pos.x - center.x, c.pos.z - center.z) > range) continue;
      if (!center && !c.isBoss && !c.isRaider) continue;
      ctx.fillStyle = c.isRaider ? '#ff3b3b' : c.fainted ? '#ffffff' : RARITY_COLORS[c.def.rarity];
      ctx.beginPath(); ctx.arc(tx(c.pos.x), tz(c.pos.z), (c.isBoss ? 3.2 : 1.8) * s, 0, Math.PI * 2); ctx.fill();
    }
    const comp = this.g.companion;
    if (comp.model) { ctx.fillStyle = '#7fffb0'; ctx.beginPath(); ctx.arc(tx(comp.pos.x), tz(comp.pos.z), 2.2 * s, 0, Math.PI * 2); ctx.fill(); }
    const home = this.g.base.center;
    ctx.font = `${10 * s}px system-ui`; ctx.textAlign = 'center';
    ctx.fillText('🏠', tx(home.x), tz(home.z) + 4 * s);
  }

  // ── panels ───────────────────────────────────────────────────
  show(kind, title, html) {
    this.open = kind;
    this.panelTitle.textContent = title;
    this.panelBody.innerHTML = html;
    this.panel.style.display = 'flex';
    this.g.input.releasePointer();
  }
  close() {
    this.open = null;
    this.panel.style.display = 'none';
    this.ctxData = null;
    if (!State.data.starterChosen) return this.openStarter();
    this.g.input.capturePointer();
  }
  refreshOpen() {
    if (!this.open) return;
    const k = this.open;
    if (k === 'inventory') this.openInventory();
    else if (k === 'base') this.openBase();
    else if (k === 'slot') this.openSlotPicker(this.ctxData.type, this.ctxData.index);
    else if (k === 'broker') this.openBroker();
    else if (k === 'curator') this.openCurator();
  }

  creatureCard(e, buttons = '', extra = '') {
    const def = getCreature(e.id);
    const st = effectiveStats(e.id, e.level, e.variant);
    const need = xpForLevel(e.level + 1), max = maxCreatureLevel(e.id);
    const slot = State.slotOf(e.uid);
    const where = !slot ? '' : slot.type === 'companion' ? '<em class="tag comp">Companion</em>' : `<em class="tag ${slot.type}">${slot.type === 'income' ? 'Income' : 'Defense'} #${slot.index + 1}</em>`;
    const variant = e.variant !== 'Normal' ? `<b style="color:${VARIANT_COLORS[e.variant]}">${e.variant}</b> ` : '';
    return `<div class="card" style="--rc:${RARITY_COLORS[def.rarity]}">
      <img src="${portrait(e.id, e.variant, e.shiny)}" alt="">
      <div class="info">
        <div class="name">${e.shiny ? '✨' : ''}${variant}${esc(e.nickname || def.displayName)} <span class="lv">Lv ${e.level}${e.level >= max ? ' (max)' : ''}</span></div>
        <div class="meta"><span style="color:${RARITY_COLORS[def.rarity]}">${def.rarity}</span> · ${ELEMENT_EMOJI[def.element] || ''} ${def.element} · ${def.class} ${where}</div>
        <div class="xp"><i style="width:${e.level >= max ? 100 : Math.min(100, (e.xp / need) * 100)}%"></i></div>
        <div class="stats">❤️ ${st.health} ⚔️ ${st.attack} 🛡 ${st.defense} 💨 ${st.speed} · 🪙 +${creatureIncome(e)}/tick${isNightElement(def.element) ? ' · 🌙' : ''}</div>
        ${extra}
        <div class="btns">${buttons}</div>
      </div></div>`;
  }

  openInventory() {
    const d = State.data;
    const f = this.inventoryFilter;
    let list = [...d.inventory];
    if (f !== 'all') list = list.filter((e) => { const s = State.slotOf(e.uid); return f === 'none' ? !s : s && s.type === f; });
    list.sort((a, b) => (RARITY_ORDER[getCreature(b.id).rarity] - RARITY_ORDER[getCreature(a.id).rarity]) || b.level - a.level);
    const tabs = [['all', 'All'], ['income', 'Income'], ['defense', 'Defense'], ['companion', 'Companion'], ['none', 'Unassigned']]
      .map(([k, l]) => `<button class="tab ${f === k ? 'on' : ''}" data-act="filter" data-k="${k}">${l}</button>`).join('');
    const cards = list.map((e) => {
      const s = State.slotOf(e.uid);
      const btn = (t, l) => `<button data-act="assign" data-uid="${e.uid}" data-type="${t}" ${s && s.type === t ? 'disabled' : ''}>${l}</button>`;
      return this.creatureCard(e, `${btn('income', '🪙 Income')}${btn('defense', '🛡 Defense')}${btn('companion', '🐾 Follow')}${s ? `<button class="ghost" data-act="unassign" data-uid="${e.uid}">Unassign</button>` : ''}`);
    }).join('');
    const used = (arr) => arr.filter(Boolean).length;
    this.show('inventory', `Siegelings (${d.inventory.length}/${CFG.MaxInventorySize})`, `
      <div class="summary">🪙 Income slots ${used(d.baseSlots)}/${d.baseSlots.length} · 🛡 Defense slots ${used(d.defenseSlots)}/${d.defenseSlots.length} · Captured ${d.stats.totalCaptured}</div>
      <div class="tabs">${tabs}</div>
      <div class="grid">${cards || '<p class="empty">No creatures here yet. Defeat wild Siegelings, then press E on them to capture.</p>'}</div>`);
  }

  openBase() {
    const d = State.data, night = this.g.isNight();
    const floors = CFG.Floors.map((f) => {
      const s = State.floorStatus(f.floor);
      const right = s.owned ? '<span class="owned">✔ Owned</span>' : s.canBuy ? `<button data-act="buyfloor" data-f="${f.floor}">Buy · ${fmt(f.cost)} 🪙</button>` : `<button disabled>${esc(s.reason)}</button>`;
      return `<div class="floor ${s.owned ? 'own' : ''}"><div><b>${esc(f.name)}</b><small>${f.cost ? `${fmt(f.cost)} coins · Player Lv ${f.levelReq}` : 'Starter floor'} · +6 income & +6 defense slots</small></div>${right}</div>`;
    }).join('');
    const slotGrid = (type) => {
      const arr = type === 'income' ? d.baseSlots : d.defenseSlots;
      return arr.map((u, i) => {
        const e = u && State.get(u);
        if (!e) return `<button class="slot empty" data-act="slot" data-type="${type}" data-i="${i}"><span>+</span><small>Slot ${i + 1}</small></button>`;
        const def = getCreature(e.id);
        const zz = type === 'income' && night && !isNightElement(def.element) && CFG.NightOnlyNightElementsEarn;
        return `<button class="slot" style="--rc:${RARITY_COLORS[def.rarity]}" data-act="slot" data-type="${type}" data-i="${i}"><img src="${portrait(e.id, e.variant, e.shiny)}"><small>${esc(def.displayName)} · Lv ${e.level}${zz ? ' 💤' : ''}</small></button>`;
      }).join('');
    };
    const inc = State.incomePerTick(night), incDay = State.incomePerTick(false);
    this.show('base', 'Base Core', `
      <div class="summary big">🪙 <b>${fmt(inc)}</b> coins every ${CFG.IncomeTickSeconds}s ${night ? `(night — only 🌙 Shadow/Lightning creatures earn; day rate ${fmt(incDay)})` : ''} · Total earned ${fmt(d.stats.totalIncome)}</div>
      <h3>Base Upgrades</h3><div class="floors">${floors}</div>
      <h3>🪙 Income Slots <small>creatures here earn coins every tick</small></h3><div class="slots">${slotGrid('income')}</div>
      <h3>🛡 Defense Slots <small>creatures here shoot raiders & gain ${CFG.DefensePassiveXP} XP per tick</small></h3><div class="slots">${slotGrid('defense')}</div>
      <p class="hint">Tip: walk up to any pad on your base and press <kbd>E</kbd> to assign directly. Wild raids hit your base every few minutes — keep defenders posted.</p>`);
  }

  openSlotPicker(type, index) {
    this.ctxData = { type, index };
    const arr = type === 'income' ? State.data.baseSlots : State.data.defenseSlots;
    const cur = arr[index] && State.get(arr[index]);
    let html = '';
    if (cur) html += `<h3>Currently in slot</h3>${this.creatureCard(cur, `<button class="ghost" data-act="unassign" data-uid="${cur.uid}">Remove from slot</button>`)}`;
    const list = State.data.inventory.filter((e) => e.uid !== arr[index]).sort((a, b) => {
      const sa = State.slotOf(a.uid) ? 1 : 0, sb = State.slotOf(b.uid) ? 1 : 0;
      if (sa !== sb) return sa - sb;
      return type === 'income' ? creatureIncome(b) - creatureIncome(a) || b.level - a.level : effectiveStats(b.id, b.level, b.variant).attack - effectiveStats(a.id, a.level, a.variant).attack;
    });
    html += `<h3>Choose a creature</h3><div class="grid">${list.map((e) => this.creatureCard(e, `<button data-act="place" data-uid="${e.uid}">Place here</button>`)).join('') || '<p class="empty">Your inventory is empty — go capture some Siegelings!</p>'}</div>`;
    this.show('slot', `${type === 'income' ? '🪙 Income' : '🛡 Defense'} Slot ${index + 1}`, html);
  }

  openCaptured(e) {
    const def = getCreature(e.id);
    this.ctxData = { uid: e.uid };
    const free = (arr) => arr.indexOf('') >= 0;
    this.show('captured', `Captured ${def.displayName}!`, `
      <div class="captured">${this.creatureCard(e, '')}
      <p>${esc(def.description || '')}</p>
      <h3>Assign it now?</h3>
      <div class="btns wide">
        <button data-act="assign-close" data-uid="${e.uid}" data-type="income" ${free(State.data.baseSlots) ? '' : 'disabled'}>🪙 Income slot</button>
        <button data-act="assign-close" data-uid="${e.uid}" data-type="defense" ${free(State.data.defenseSlots) ? '' : 'disabled'}>🛡 Defense slot</button>
        <button data-act="assign-close" data-uid="${e.uid}" data-type="companion">🐾 Make companion</button>
        <button class="ghost" data-act="close">Keep in inventory</button>
      </div></div>`);
  }

  openStarter() {
    const cards = STARTERS.map((id) => {
      const def = getCreature(id);
      const st = effectiveStats(id, 1, 'Normal');
      return `<button class="starter" data-act="starter" data-id="${id}"><img src="${portrait(id)}"><b>${def.displayName}</b><small>${ELEMENT_EMOJI[def.element]} ${def.element} · ${def.class}</small><small>❤️ ${st.health} ⚔️ ${st.attack} 🛡 ${st.defense} 💨 ${st.speed}</small><p>${esc(def.description)}</p></button>`;
    }).join('');
    this.show('starter', 'Choose your starter Siegeling', `<p class="hint">Your starter follows you as a companion and fights by your side. You'll find more in the wild.</p><div class="starters">${cards}</div>`);
  }

  // Curator: six rotating Silver/Gold creatures (2 Common, 1 Uncommon, 1 Rare, 1 Epic, 1 Legendary)
  curatorStock() {
    const d = State.data;
    const period = 15 * 60 * 1000;
    const slotT = Math.floor(Date.now() / period);
    if (!d.curator || d.curator.t !== slotT) {
      const pool = (r) => Creatures.filter((c) => c.rarity === r);
      const stock = ['Common', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'].map((r) => ({ id: pick(pool(r)).id, variant: Math.random() < 0.5 ? 'Silver' : 'Gold', sold: false }));
      d.curator = { t: slotT, stock };
    }
    return { stock: d.curator.stock, refreshIn: period - (Date.now() % period) };
  }

  openCurator() {
    const { stock, refreshIn } = this.curatorStock();
    const html = stock.map((s, i) => {
      const def = getCreature(s.id);
      const price = CFG.CuratorCoinPrice[def.rarity];
      const e = { id: s.id, uid: '', level: 5, xp: 0, variant: s.variant };
      return this.creatureCard(e, s.sold ? '<button disabled>Sold</button>' : `<button data-act="curbuy" data-i="${i}" ${State.data.coins < price ? 'disabled' : ''}>Buy · ${fmt(price)} 🪙</button>`);
    }).join('');
    this.show('curator', 'The Curator', `<p class="hint">"Only the finest specimens — every one Silver or Gold." Stock rotates in ${Math.ceil(refreshIn / 60000)} min.</p><div class="grid">${html}</div>`);
  }

  openSiegeMaster(selected = null) {
    this.ctxData = { food: selected };
    if (!selected) {
      const html = SIEGE_FOOD.map((f) => `<div class="floor"><div><b>${f.icon} ${f.name}</b><small>${f.desc}</small></div><button data-act="food" data-id="${f.id}" ${State.data.coins < f.cost ? 'disabled' : ''}>Buy · ${fmt(f.cost)} 🪙</button></div>`).join('');
      return this.show('siege', 'Siege Master', `<p class="hint">"A well-fed Siegeling is a strong Siegeling." Pick a meal, then choose who eats it.</p><div class="floors">${html}</div>`);
    }
    const food = SIEGE_FOOD.find((f) => f.id === selected);
    const list = State.data.inventory.filter((e) => e.level < maxCreatureLevel(e.id));
    this.show('siege', `Feed ${food.name}`, `<div class="grid">${list.map((e) => this.creatureCard(e, `<button data-act="feed" data-uid="${e.uid}">Feed (+${food.xp} XP)</button>`)).join('') || '<p class="empty">No creatures that can still level up.</p>'}</div>`);
  }

  openBroker() {
    const list = [...State.data.inventory].sort((a, b) => sellValue(b) - sellValue(a));
    this.show('broker', 'The Broker', `<p class="hint">"I'll take them off your hands… for a price." Selling removes the creature permanently.</p><div class="grid">${list.map((e) => this.creatureCard(e, `<button class="danger" data-act="sell" data-uid="${e.uid}">Sell · ${fmt(sellValue(e))} 🪙</button>`)).join('') || '<p class="empty">Nothing to sell.</p>'}</div>`);
  }

  openHelp() {
    this.show('help', 'How to play', `
      <div class="help">
      <p><b>Goal:</b> capture Siegelings in the wild, station them at your base to earn coins, and upgrade your base with new floors.</p>
      <table>
      <tr><td><kbd>W A S D</kbd></td><td>Move · <kbd>Shift</kbd> sprint · <kbd>Space</kbd> jump</td></tr>
      <tr><td><kbd>Mouse</kbd></td><td>Look (over-the-shoulder camera) · <kbd>Q</kbd> swap shoulder</td></tr>
      <tr><td><kbd>Left click</kbd></td><td>Fire energy orb · <kbd>Right click</kbd> hold to aim · <kbd>F</kbd> melee</td></tr>
      <tr><td><kbd>E</kbd></td><td>Interact / capture a fainted creature</td></tr>
      <tr><td><kbd>Tab</kbd> / <kbd>I</kbd></td><td>Siegelings inventory &amp; assignment</td></tr>
      <tr><td><kbd>B</kbd></td><td>Base Core (upgrades &amp; slots)</td></tr>
      <tr><td><kbd>M</kbd></td><td>World map · <kbd>H</kbd> go home · <kbd>?</kbd> this help</td></tr>
      </table>
      <p><b>Capturing:</b> knock a creature's HP to zero to make it faint (10s), then press <kbd>E</kbd> to throw a capture card. Costs coins by rarity (Common 10 → Legendary 400).</p>
      <p><b>Base:</b> Income pads earn each creature's base income every ${CFG.IncomeTickSeconds}s. At night only Shadow & Lightning creatures work. Defense pads shoot raiders. Buy Floors 2–4 at the Base Core for 6 more of each slot.</p>
      <p><b>Arena Hub:</b> safe zone with a healing fountain, The Curator (rare stock), Siege Master (XP food) and The Broker (sell).</p>
      <p class="hint"><button class="ghost" data-act="reset">Reset save</button></p>
      </div>`);
  }

  onPanelClick(ev) {
    const b = ev.target.closest('[data-act]');
    if (!b || b.disabled) return;
    const a = b.dataset.act, g = this.g;
    switch (a) {
      case 'close': this.close(); break;
      case 'filter': this.inventoryFilter = b.dataset.k; this.openInventory(); break;
      case 'assign': { const r = State.assign(b.dataset.uid, b.dataset.type); this.notify(r.msg, r.ok ? 'good' : 'warn'); break; }
      case 'assign-close': { const r = State.assign(b.dataset.uid, b.dataset.type); this.notify(r.msg, r.ok ? 'good' : 'warn'); if (r.ok) this.close(); break; }
      case 'unassign': State.unassign(b.dataset.uid); break;
      case 'place': { const { type, index } = this.ctxData; const r = State.assign(b.dataset.uid, type, index); this.notify(r.msg, r.ok ? 'good' : 'warn'); if (r.ok) this.close(); break; }
      case 'slot': this.openSlotPicker(b.dataset.type, +b.dataset.i); break;
      case 'buyfloor': { const r = State.buyFloor(+b.dataset.f); this.notify(r.msg, r.ok ? 'good' : 'warn'); if (r.ok) g.onFloorBought(+b.dataset.f); break; }
      case 'starter': {
        const e = State.addCreature(b.dataset.id, 1);
        State.data.starterChosen = true;
        State.assign(e.uid, 'companion');
        State.save();
        this.notify(`${getCreature(e.id).displayName} joined you!`, 'good');
        setTimeout(() => this.notify('Your base is the 🏠 gold plot on the minimap — press H to teleport home', 'info'), 1200);
        this.close();
        break;
      }
      case 'curbuy': {
        const { stock } = this.curatorStock();
        const s = stock[+b.dataset.i], def = getCreature(s.id), price = CFG.CuratorCoinPrice[def.rarity];
        if (State.isFull()) { this.notify('Inventory full', 'warn'); break; }
        if (!State.spendCoins(price)) { this.notify('Not enough coins', 'warn'); break; }
        s.sold = true;
        const e = State.addCreature(s.id, 5, s.variant);
        State.save();
        this.openCaptured(e);
        break;
      }
      case 'food': this.openSiegeMaster(b.dataset.id); break;
      case 'feed': {
        const food = SIEGE_FOOD.find((f) => f.id === this.ctxData.food);
        if (!State.spendCoins(food.cost)) { this.notify('Not enough coins', 'warn'); break; }
        const e = State.get(b.dataset.uid);
        const lv = e.level;
        State.addCreatureXP(e.uid, food.xp);
        this.notify(`${getCreature(e.id).displayName} ate ${food.name}${e.level > lv ? ` — now Lv ${e.level}!` : ''}`, 'good');
        State.save();
        this.openSiegeMaster(food.id);
        break;
      }
      case 'sell': {
        const e = State.get(b.dataset.uid);
        const def = getCreature(e.id);
        if (RARITY_ORDER[def.rarity] >= 3 && !confirm(`Sell ${def.displayName} (${def.rarity})?`)) break;
        const v = State.sell(e.uid);
        this.notify(`Sold ${def.displayName} for ${v} coins`, 'good');
        State.save();
        break;
      }
      case 'reset': if (confirm('Erase all progress?')) { State.reset(); location.reload(); } break;
    }
  }
}
