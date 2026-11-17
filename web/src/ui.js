// HUD, world labels, minimap and menu panels (Inventory, Base Core, slot picker, capture, hub vendors).
import * as THREE from 'three';
import { CFG, RARITY_COLORS, RARITY_ORDER, VARIANT_COLORS } from './config.js';
import { State } from './state.js';
import { calculateSynergies, getCreature, effectiveStats, xpForLevel, playerXPForLevel, maxCreatureLevel, sellValue, creatureIncome, isNightElement, STARTERS, Creatures, captureCost } from './data.js';
import { BIOMES, biomeAt, plotCenter, PLOT_SIZE, WORLD_R, HUB_R, ROADS, RING_ROAD_R } from './world.js';
import { portrait } from './portraits.js';
import { fmt, pick } from './util.js';
import { attackFor, MAX_TEAM, MAX_ITEMS } from './run.js';

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ELEMENT_EMOJI = { Fire: '🔥', Ice: '❄️', Wind: '🌪️', Earth: '🌿', Shadow: '🌑', Light: '✨', Lightning: '⚡', Water: '💧', Psychic: '🔮', Metal: '⚙️', Poison: '☠️', Undead: '💀', Neutral: '✴️' };

const fmtTime = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

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
    addEventListener('siegelings:models-updated', () => {
      clearTimeout(this.modelRefresh);
      this.modelRefresh = setTimeout(() => { delete document.getElementById('companion').dataset.uid; this.refreshOpen(); }, 200);
    });
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
    this.updateRunHUD();
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
    const run = this.g.run;
    if (run.active) for (const t of run.totems) { if (t.done) continue; ctx.fillStyle = '#c9a6ff'; ctx.beginPath(); ctx.moveTo(tx(t.x), tz(t.z) - 5 * s); ctx.lineTo(tx(t.x) + 4 * s, tz(t.z)); ctx.lineTo(tx(t.x), tz(t.z) + 5 * s); ctx.lineTo(tx(t.x) - 4 * s, tz(t.z)); ctx.fill(); }
    if (run.active) for (const ch of run.chests) { ctx.fillStyle = '#ffd76a'; ctx.fillRect(tx(ch.pos.x) - 3 * s, tz(ch.pos.z) - 3 * s, 6 * s, 6 * s); }
    for (const c of (run.active ? run.enemies : this.g.creatures.list)) {
      if (center && Math.hypot(c.pos.x - center.x, c.pos.z - center.z) > range) continue;
      if (!center && !c.isBoss && !c.isRaider) continue;
      ctx.fillStyle = c.isBoss ? '#ffb800' : c.tier === 'elite' ? '#b450ff' : c.isRaider ? '#ff3b3b' : c.fainted ? '#ffffff' : RARITY_COLORS[c.def.rarity];
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
    document.getElementById('panel-close').style.visibility = 'visible';
    this.g.input.releasePointer();
  }
  close() {
    if (this.open === 'runchoice') return; // a run choice must be picked
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
    else if (k === 'starter') this.openStarter();
    else if (k === 'runsetup') this.openRunSetup();
  }

  creatureCard(e, buttons = '', extra = '') {
    const def = getCreature(e.id);
    const st = effectiveStats(e.id, e.level, e.variant);
    const need = xpForLevel(e.level + 1), max = maxCreatureLevel(e.id);
    const slot = State.slotOf(e.uid);
    const where = !slot ? '' : slot.type === 'companion' ? '<em class="tag comp">Companion</em>' : slot.type === 'battle' ? '<em class="tag battle">Battle Team</em>' : `<em class="tag ${slot.type}">${slot.type === 'income' ? 'Income' : 'Defense'} #${slot.index + 1}</em>`;
    const variant = e.variant !== 'Normal' ? `<b style="color:${VARIANT_COLORS[e.variant]}">${e.variant}</b> ` : '';
    return `<div class="card" style="--rc:${RARITY_COLORS[def.rarity]}">
      <img src="${portrait(e.id, e.variant, e.shiny)}" alt="">
      <div class="info">
        <div class="name">${e.shiny ? '✨' : ''}${variant}${esc(e.nickname || def.displayName)} <span class="lv">Lv ${e.level}${e.level >= max ? ' (max)' : ''}</span></div>
        <div class="meta"><span style="color:${RARITY_COLORS[def.rarity]}">${def.rarity}</span> · ${ELEMENT_EMOJI[def.element] || ''} ${def.element} · ${def.class} ${where}</div>
        <div class="xp"><i style="width:${e.level >= max ? 100 : Math.min(100, (e.xp / need) * 100)}%"></i></div>
        <div class="stats">❤️ ${st.health} ⚔️ ${st.attack} 🛡 ${st.defense} 💨 ${st.speed} · 🪙 +${creatureIncome(e)}/tick${isNightElement(def.element) ? ' · 🌙' : ''}</div>
        <div class="atk">⚔ <b>${esc(attackFor(def).name)}</b> — ${esc(attackFor(def).desc)}</div>
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
    const tabs = [['all', 'All'], ['income', 'Income'], ['defense', 'Defense'], ['battle', 'Battle Team'], ['companion', 'Companion'], ['none', 'Unassigned']]
      .map(([k, l]) => `<button class="tab ${f === k ? 'on' : ''}" data-act="filter" data-k="${k}">${l}</button>`).join('');
    const cards = list.map((e) => {
      const s = State.slotOf(e.uid);
      const btn = (t, l) => `<button data-act="assign" data-uid="${e.uid}" data-type="${t}" ${s && s.type === t ? 'disabled' : ''}>${l}</button>`;
      return this.creatureCard(e, `${btn('income', '🪙 Income')}${btn('defense', '🛡 Defense')}${btn('battle', '⚔ Battle')}${btn('companion', '🐾 Follow')}${s ? `<button class="ghost" data-act="unassign" data-uid="${e.uid}">Unassign</button>` : ''}`);
    }).join('');
    const used = (arr) => arr.filter(Boolean).length;
    this.show('inventory', `Siegelings (${d.inventory.length}/${CFG.MaxInventorySize})`, `
      <div class="summary">🪙 Income slots ${used(d.baseSlots)}/${d.baseSlots.length} · 🛡 Defense slots ${used(d.defenseSlots)}/${d.defenseSlots.length} · ⚔ Battle Team ${State.battleUnlocked() ? `${State.battleCount()}/${CFG.MaxBattleTeamCreatures}` : 'locked (Floor 2)'} · Captured ${d.stats.totalCaptured}</div>
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
        if (!e) return `<button class="slot open" data-act="slot" data-type="${type}" data-i="${i}"><span>+</span><small>Slot ${i + 1}</small></button>`;
        const def = getCreature(e.id);
        const zz = type === 'income' && night && !isNightElement(def.element) && CFG.NightOnlyNightElementsEarn;
        return `<button class="slot" style="--rc:${RARITY_COLORS[def.rarity]}" data-act="slot" data-type="${type}" data-i="${i}"><img src="${portrait(e.id, e.variant, e.shiny)}"><small>${esc(def.displayName)} · Lv ${e.level}${zz ? ' 💤' : ''}</small></button>`;
      }).join('');
    };
    const battleGrid = d.battleTeam.map((u, i) => {
      const e = u && State.get(u);
      if (!State.battleUnlocked()) return '<button class="slot open" disabled><span>🔒</span></button>';
      if (!e) return `<button class="slot open" data-act="slot" data-type="battle" data-i="${i}"><span>+</span></button>`;
      const def = getCreature(e.id);
      return `<button class="slot" style="--rc:${RARITY_COLORS[def.rarity]}" data-act="slot" data-type="battle" data-i="${i}"><img src="${portrait(e.id, e.variant, e.shiny)}"><small>${esc(def.displayName)} · Lv ${e.level}</small></button>`;
    }).join('');
    const syn = calculateSynergies(d.battleTeam.filter(Boolean).map((u) => State.get(u)?.id));
    const synHtml = syn.length
      ? syn.map((x) => `<span class="syn">${ELEMENT_EMOJI[x.trait] || '◆'} <b>${esc(x.label)}</b> (${x.trait} ×${x.count}) ${Object.entries(x.bonuses).map(([k, v]) => `${v > 0 ? '+' : ''}${Math.round(v * 100)}% ${k}`).join(', ')}</span>`).join('')
      : '<span class="hint">No synergies yet. Field 2+ creatures of the same element or class.</span>';
    const inc = State.incomePerTick(night), incDay = State.incomePerTick(false);
    this.show('base', 'Base Core', `
      <div class="summary big">🪙 <b>${fmt(inc)}</b> coins every ${CFG.IncomeTickSeconds}s ${night ? `(night — only 🌙 Shadow/Lightning creatures earn; day rate ${fmt(incDay)})` : ''} · Total earned ${fmt(d.stats.totalIncome)}</div>
      <h3>Base Upgrades</h3><div class="floors">${floors}</div>
      <h3>🪙 Income Slots <small>creatures here earn coins every tick</small></h3><div class="slots">${slotGrid('income')}</div>
      <h3>🛡 Defense Slots <small>creatures here shoot raiders & gain ${CFG.DefensePassiveXP} XP per tick</small></h3><div class="slots">${slotGrid('defense')}</div>
      <h3>⚔ Battle Team <small>${State.battleUnlocked() ? `3x3 grid on Floor 2 · ${State.battleCount()}/${CFG.MaxBattleTeamCreatures} creatures` : 'unlocks with Floor 2'}</small></h3>
      <div class="battle-wrap"><div class="battle-grid">${battleGrid}</div><div class="synergies">${synHtml}</div></div>
      <p class="hint">Tip: walk up to any pad on your base and press <kbd>E</kbd> to assign directly. Wild raids hit your base every few minutes — keep defenders posted.</p>`);
  }

  openSlotPicker(type, index) {
    this.ctxData = { type, index };
    const arr = type === 'income' ? State.data.baseSlots : type === 'battle' ? State.data.battleTeam : State.data.defenseSlots;
    const cur = arr[index] && State.get(arr[index]);
    let html = '';
    if (cur) html += `<h3>Currently in slot</h3>${this.creatureCard(cur, `<button class="ghost" data-act="unassign" data-uid="${cur.uid}">Remove from slot</button>`)}`;
    const list = State.data.inventory.filter((e) => e.uid !== arr[index]).sort((a, b) => {
      const sa = State.slotOf(a.uid) ? 1 : 0, sb = State.slotOf(b.uid) ? 1 : 0;
      if (sa !== sb) return sa - sb;
      if (type === 'battle') { const sa2 = effectiveStats(a.id, a.level, a.variant), sb2 = effectiveStats(b.id, b.level, b.variant); return (sb2.attack + sb2.health + sb2.defense + sb2.speed) - (sa2.attack + sa2.health + sa2.defense + sa2.speed); }
      return type === 'income' ? creatureIncome(b) - creatureIncome(a) || b.level - a.level : effectiveStats(b.id, b.level, b.variant).attack - effectiveStats(a.id, a.level, a.variant).attack;
    });
    html += `<h3>Choose a creature</h3><div class="grid">${list.map((e) => this.creatureCard(e, `<button data-act="place" data-uid="${e.uid}">Place here</button>`)).join('') || '<p class="empty">Your inventory is empty — go capture some Siegelings!</p>'}</div>`;
    if (type === 'battle') {
      html = `<p class="hint">Battle Team: ${State.battleCount()}/${CFG.MaxBattleTeamCreatures} creatures on the 3x3 grid. Matching elements and classes give team synergies.</p>${html}`;
      return this.show('slot', `⚔ Battle Team — ${['Top', 'Middle', 'Bottom'][Math.floor(index / 3)]} ${['left', 'centre', 'right'][index % 3]}`, html);
    }
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
        <button data-act="assign-close" data-uid="${e.uid}" data-type="battle" ${State.battleUnlocked() && State.battleCount() < CFG.MaxBattleTeamCreatures ? '' : 'disabled'}>⚔ Battle Team</button>
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

  // ── survival runs ────────────────────────────────────────────
  openRunSetup() {
    const stage = this.runStage || 'forest';
    const d = State.data;
    const stages = Object.entries(BIOMES).filter(([id]) => id !== 'hub').map(([id, b]) =>
      `<button class="tab ${stage === id ? 'on' : ''}" data-act="runstage" data-k="${id}">${b.elements.map((e) => ELEMENT_EMOJI[e] || '').join('')} ${esc(b.name)}</button>`).join('');
    const list = [...d.inventory].sort((a, b) => RARITY_ORDER[getCreature(b.id).rarity] - RARITY_ORDER[getCreature(a.id).rarity]);
    const cards = list.map((e) => this.creatureCard(e, `<button data-act="runstart" data-uid="${e.uid}">Start run with ${esc(getCreature(e.id).displayName)}</button>`)).join('');
    this.show('runsetup', 'Expedition Gate', `
      <div class="summary big">Runs ${d.stats.runs || 0} · Wins ${d.stats.wins || 0} · Best time ${fmtTime(d.stats.bestTime || 0)}</div>
      <p class="hint">Survive the swarm for 5 minutes, then beat the boss. Your Siegelings attack on their own. Open chests to recruit up to ${MAX_TEAM} Siegelings and level up to collect up to ${MAX_ITEMS} items. Siegelings you recruit join your collection after the run.</p>
      <h3>1. Choose a stage <small>enemies are ${BIOMES[stage].elements.join(' & ')}</small></h3><div class="tabs">${stages}</div>
      <h3>2. Choose your starting Siegeling</h3><div class="grid">${cards}</div>`);
  }

  openRunChoice(title, options) {
    this.runOptions = options;
    const html = options.map((o, i) => `<button class="choice" data-act="runpick" data-i="${i}" style="--rc:${RARITY_COLORS[o.rarity] || '#6a5aa0'}">
      ${o.img ? `<img src="${o.img}" alt="">` : `<span class="ico">${o.icon || '⭐'}</span>`}
      <b>${esc(o.title)}</b><em>${esc(o.tag || '')}</em><p>${esc(o.desc)}</p></button>`).join('');
    this.show('runchoice', title, `<div class="choices">${html}</div>`);
    document.getElementById('panel-close').style.visibility = 'hidden';
  }

  openRunResults(r) {
    const team = r.team.map((m) => `<div class="mini"><img src="${portrait(m.id)}" alt=""><small>Lv ${m.level}</small></div>`).join('');
    this.show('runresults', r.victory ? '🏆 Victory!' : 'Run over', `
      <div class="summary big">${r.victory ? 'You beat the boss!' : 'Your team was overwhelmed.'} Survived <b>${fmtTime(r.time)}</b> · <b>${r.kills}</b> defeated · reached level <b>${r.level}</b> · earned <b>${fmt(r.coins)}</b> 🪙</div>
      <h3>Your team</h3><div class="minis">${team}</div>
      ${r.joined.length ? `<p>Joined your collection: <b>${r.joined.map(esc).join(', ')}</b></p>` : ''}
      <div class="btns wide"><button data-act="close">Back to base</button></div>`);
  }

  updateRunHUD() {
    const run = this.g.run, el = document.getElementById('run-hud');
    if (!run.active) { if (el.style.display !== 'none') el.style.display = 'none'; return; }
    el.style.display = 'flex';
    const left = Math.max(0, 300 - run.time);
    document.getElementById('run-timer').textContent = run.bossSpawned ? 'BOSS' : fmtTime(left);
    document.getElementById('run-kills').textContent = `☠ ${run.kills}`;
    document.getElementById('run-level').textContent = `Lv ${run.level}`;
    document.getElementById('run-xp').style.width = `${Math.min(100, run.xp / run.xpNeed() * 100)}%`;
    const boss = document.getElementById('run-boss');
    if (run.boss && run.boss.hp > 0) { boss.style.display = 'block'; boss.firstElementChild.style.width = `${run.boss.hp / run.boss.maxHp * 100}%`; boss.dataset.name = run.boss.def.displayName; } else boss.style.display = 'none';
    const chest = document.getElementById('run-chest');
    chest.style.display = run.chestProgress > 0.02 ? 'block' : 'none';
    chest.firstElementChild.style.width = `${run.chestProgress * 100}%`;
    const key = run.team.map((m) => m.def.id + m.level).join() + '|' + run.itemList().map((i) => i.id + i.level).join();
    if (key !== this.runKey) {
      this.runKey = key;
      const slots = (arr, max, fn) => Array.from({ length: max }, (_, i) => arr[i] ? fn(arr[i]) : '<div class="rs empty"></div>').join('');
      document.getElementById('run-team').innerHTML = slots(run.team, MAX_TEAM, (m) => `<div class="rs" title="${esc(m.attack.name)}"><img src="${portrait(m.def.id)}" alt=""><i>${m.level}</i></div>`);
      document.getElementById('run-items').innerHTML = slots(run.itemList(), MAX_ITEMS, (it) => `<div class="rs" title="${esc(it.name)}"><span>${it.icon}</span><i>${it.level}</i></div>`);
    }
  }

  openHelp() {
    this.show('help', 'How to play', `
      <div class="help">
      <p><b>Goal:</b> survive runs with a team of Siegelings as your weapons, and grow your base between runs.</p>
      ${this.g.ctx.touch ? `<table>
      <tr><td><b>Left thumb</b></td><td>Drag anywhere on the left side to move · push all the way to sprint</td></tr>
      <tr><td><b>Right thumb</b></td><td>Drag to look around</td></tr>
            <tr><td>⤒</td><td>Jump</td></tr>
      <tr><td><b>TAP prompt</b></td><td>Interact / capture a fainted creature</td></tr>
      <tr><td>🎒 🏰 🗺️ 🏠</td><td>Siegelings · Base Core · map · teleport home</td></tr>
      </table>` : ''}
      <table class="keys">
      <tr><td><kbd>W A S D</kbd></td><td>Move · <kbd>Shift</kbd> sprint · <kbd>Space</kbd> jump</td></tr>
      <tr><td><kbd>Mouse</kbd></td><td>Look (over-the-shoulder camera) · <kbd>Q</kbd> swap shoulder</td></tr>
            <tr><td><kbd>E</kbd></td><td>Interact / capture a fainted creature</td></tr>
      <tr><td><kbd>Tab</kbd> / <kbd>I</kbd></td><td>Siegelings inventory &amp; assignment</td></tr>
      <tr><td><kbd>B</kbd></td><td>Base Core (upgrades &amp; slots)</td></tr>
      <tr><td><kbd>M</kbd></td><td>World map · <kbd>H</kbd> go home · <kbd>?</kbd> this help</td></tr>
      </table>
      <p><b>Runs:</b> walk into the <b>Expedition Gate</b> in front of your base, pick a stage and a starting Siegeling. Wild Siegelings swarm you — your team attacks automatically, each with its own attack. Collect the blue XP gems to level up (upgrade a Siegeling or take an item, up to ${MAX_ITEMS}). Attacks come in five classes — Melee, Projectile, Aura, Random strike and Chain — and each class has a boost item; the Splitting Prism adds extra projectiles. Stand next to a <b>chest</b> to open it and recruit a new Siegeling (up to ${MAX_TEAM}). Survive 5 minutes, then defeat the boss.</p>
      <p><b>Base:</b> between runs, spend coins at the Base Core on new floors and station Siegelings on income pads. Siegelings you recruit in a run join your collection.</p>
      <p class="hint"><button class="ghost" data-act="reset">Reset save</button></p>
      </div>`);
  }

  onPanelClick(ev) {
    const b = ev.target.closest('[data-act]');
    if (!b || b.disabled) return;
    const a = b.dataset.act, g = this.g;
    switch (a) {
      case 'close': this.close(); break;
      case 'runpick': { const o = this.runOptions[+b.dataset.i]; this.open = null; this.close(); o.pick(); break; }
      case 'runstage': this.runStage = b.dataset.k; this.openRunSetup(); break;
      case 'runstart': { const e = State.get(b.dataset.uid); this.close(); g.run.start(e, this.runStage || 'forest'); break; }
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
        setTimeout(() => this.notify('Walk into the Expedition Gate in front of your base to start a run', 'info'), 1200);
        g.player.teleport(g.base.homePosition(), g.base.homeYaw()); g.cam.yaw = g.base.homeYaw() + Math.PI;
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
        // two-step confirm in the page itself (dialogs are not available everywhere)
        if (RARITY_ORDER[def.rarity] >= 3 && b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = `Confirm sell ${def.rarity}?`; break; }
        const v = State.sell(e.uid);
        this.notify(`Sold ${def.displayName} for ${v} coins`, 'good');
        State.save();
        break;
      }
      case 'reset':
        if (b.dataset.armed !== '1') { b.dataset.armed = '1'; b.textContent = 'Click again to erase all progress'; break; }
        State.reset(); location.reload(); break;
    }
  }
}
