import { CFG } from './config.js';
import { getCreature, maxCreatureLevel, xpForLevel, playerXPForLevel, sellValue, creatureIncome, isNightElement } from './data.js';
import { uid } from './util.js';

const SAVE_KEY = 'siegelings_web_save_v1';
const listeners = new Set();

function defaultData() {
  return {
    version: 1,
    coins: CFG.StartingCoins,
    gems: 0,
    inventory: [],
    baseSlots: [],
    defenseSlots: [],
    favoriteUid: '',
    ownedFloors: [1],
    playerLevel: 1,
    playerXP: 0,
    stats: { totalCaptured: 0, totalIncome: 0, kills: 0, raidsDefended: 0 },
    starterChosen: false,
    seen: {},
    timeOfDay: CFG.DayNightStartHour,
  };
}

export const State = {
  data: defaultData(),

  on(fn) { listeners.add(fn); return () => listeners.delete(fn); },
  emit(kind, payload) { for (const fn of listeners) fn(kind, payload); },

  load() {
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (raw) this.data = Object.assign(defaultData(), JSON.parse(raw));
    } catch { /* storage unavailable */ }
    this.sanitize();
  },
  save() {
    try { localStorage.setItem(SAVE_KEY, JSON.stringify(this.data)); } catch { /* ignore */ }
  },
  reset() {
    try { localStorage.removeItem(SAVE_KEY); } catch { /* ignore */ }
    this.data = defaultData();
    this.sanitize();
    this.emit('reset');
  },

  sanitize() {
    const d = this.data;
    d.inventory = d.inventory.filter((e) => getCreature(e.id));
    const valid = new Set(d.inventory.map((e) => e.uid));
    for (const key of ['baseSlots', 'defenseSlots']) {
      const max = this.maxSlots(key === 'baseSlots' ? 'income' : 'defense');
      const arr = d[key] || [];
      d[key] = Array.from({ length: max }, (_, i) => (valid.has(arr[i]) ? arr[i] : ''));
    }
    if (!valid.has(d.favoriteUid)) d.favoriteUid = '';
  },

  // ── currency ────────────────────────────────────────────────
  addCoins(n) { this.data.coins += n; this.emit('coins'); },
  spendCoins(n) {
    if (this.data.coins < n) return false;
    this.data.coins -= n; this.emit('coins'); return true;
  },

  // ── inventory ───────────────────────────────────────────────
  get(uidv) { return this.data.inventory.find((e) => e.uid === uidv); },
  isFull() { return this.data.inventory.length >= CFG.MaxInventorySize; },
  addCreature(id, level = 1, variant = 'Normal', shiny = false) {
    if (this.isFull()) return null;
    const e = { id, uid: uid(), level, xp: 0, variant, shiny, caughtAt: Date.now() };
    this.data.inventory.push(e);
    this.data.seen[id] = true;
    this.emit('inventory');
    return e;
  },
  removeCreature(uidv) {
    this.unassign(uidv, true);
    this.data.inventory = this.data.inventory.filter((e) => e.uid !== uidv);
    this.emit('inventory');
  },
  sell(uidv) {
    const e = this.get(uidv);
    if (!e) return 0;
    const v = sellValue(e);
    this.removeCreature(uidv);
    this.addCoins(v);
    return v;
  },

  // ── slots (PlayerDataManager.AssignToBase / AssignToDefense / SetFavorite) ──
  maxSlots(type) {
    const per = type === 'defense' ? CFG.DefensePointsPerFloor : CFG.IncomePointsPerFloor;
    return this.data.ownedFloors.length * per;
  },
  slotOf(uidv) {
    if (!uidv) return null;
    let i = this.data.baseSlots.indexOf(uidv);
    if (i >= 0) return { type: 'income', index: i };
    i = this.data.defenseSlots.indexOf(uidv);
    if (i >= 0) return { type: 'defense', index: i };
    if (this.data.favoriteUid === uidv) return { type: 'companion', index: 0 };
    return null;
  },
  unassign(uidv, silent = false) {
    const d = this.data;
    d.baseSlots = d.baseSlots.map((u) => (u === uidv ? '' : u));
    d.defenseSlots = d.defenseSlots.map((u) => (u === uidv ? '' : u));
    if (d.favoriteUid === uidv) d.favoriteUid = '';
    if (!silent) this.emit('slots');
  },
  assign(uidv, type, index = -1) {
    if (!this.get(uidv)) return { ok: false, msg: 'Unknown creature' };
    const d = this.data;
    if (type === 'companion') {
      this.unassign(uidv, true);
      d.favoriteUid = uidv;
      this.emit('slots');
      return { ok: true, msg: 'Now following you' };
    }
    const key = type === 'income' ? 'baseSlots' : 'defenseSlots';
    // Remove from any current slot first (unassign replaces the slot arrays).
    const prev = this.slotOf(uidv);
    this.unassign(uidv, true);
    const arr = d[key];
    if (index < 0) index = arr.indexOf('');
    if (index < 0 || index >= arr.length) {
      if (prev) this.assign(uidv, prev.type, prev.index); // restore
      return { ok: false, msg: `All ${type} slots full — buy another floor` };
    }
    arr[index] = uidv; // any creature already here goes back to the inventory
    this.emit('slots');
    return { ok: true, msg: `Assigned to ${type} slot ${index + 1}` };
  },

  // ── floors (PlayerDataManager.BuyFloor) ─────────────────────
  floorStatus(floorNum) {
    const cfg = CFG.Floors.find((f) => f.floor === floorNum);
    const d = this.data;
    if (d.ownedFloors.includes(floorNum)) return { owned: true, cfg };
    if (!d.ownedFloors.includes(floorNum - 1)) return { owned: false, cfg, reason: `Buy Floor ${floorNum - 1} first` };
    if (d.playerLevel < cfg.levelReq) return { owned: false, cfg, reason: `Requires level ${cfg.levelReq}` };
    if (d.coins < cfg.cost) return { owned: false, cfg, reason: 'Not enough coins' };
    return { owned: false, cfg, canBuy: true };
  },
  buyFloor(floorNum) {
    const s = this.floorStatus(floorNum);
    if (s.owned) return { ok: false, msg: 'Already owned' };
    if (!s.canBuy) return { ok: false, msg: s.reason };
    this.data.coins -= s.cfg.cost;
    this.data.ownedFloors.push(floorNum);
    this.sanitize();
    this.emit('coins');
    this.emit('floors', floorNum);
    this.save();
    return { ok: true, msg: `${s.cfg.name} unlocked! +6 income & +6 defense slots` };
  },

  // ── XP ──────────────────────────────────────────────────────
  addCreatureXP(uidv, amount) {
    const e = this.get(uidv);
    if (!e) return false;
    const max = maxCreatureLevel(e.id);
    if (e.level >= max) return false;
    e.xp += amount;
    let leveled = false;
    while (e.level < max && e.xp >= xpForLevel(e.level + 1)) {
      e.xp -= xpForLevel(e.level + 1); e.level++; leveled = true;
    }
    if (leveled) this.emit('creatureLevel', e);
    return leveled;
  },
  addPlayerXP(amount) {
    const d = this.data;
    if (d.playerLevel >= CFG.PlayerMaxLevel) return;
    d.playerXP += amount;
    while (d.playerLevel < CFG.PlayerMaxLevel && d.playerXP >= playerXPForLevel(d.playerLevel + 1)) {
      d.playerXP -= playerXPForLevel(d.playerLevel + 1);
      d.playerLevel++;
      this.emit('playerLevel', d.playerLevel);
    }
    this.emit('xp');
  },

  // ── income (BaseIncomeSystem.CalculateIncome) ───────────────
  incomePerTick(isNight) {
    let total = 0;
    for (const u of this.data.baseSlots) {
      const e = u && this.get(u);
      if (!e) continue;
      const c = getCreature(e.id);
      if (isNight && CFG.NightOnlyNightElementsEarn && !isNightElement(c.element)) continue;
      total += creatureIncome(e);
    }
    return total;
  },
};
