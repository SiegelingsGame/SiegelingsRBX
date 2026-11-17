// Touch controls for phones and tablets: floating move joystick (left), drag-to-look (anywhere else),
// action buttons (right) and menu buttons. Everything is fed into the shared Input object as the
// same key codes / mouse buttons the desktop controls use, so game code has one input path.

export const isTouchDevice = () =>
  (typeof matchMedia === 'function' && matchMedia('(pointer: coarse)').matches) || navigator.maxTouchPoints > 0;

const LOOK_SENS = 2.4;        // touch pixels → camera units (desktop mouse = 1)
const STICK_RADIUS = 56;      // px the knob can travel
const SPRINT_AT = 0.92;       // stick push (0..1) that switches to sprint

export class TouchControls {
  constructor(input, onLook) {
    this.input = input;
    this.onLook = onLook;
    this.move = { x: 0, y: 0, mag: 0 };
    this.stickId = null; this.lookId = null;
    this.aimOn = false;
    document.body.classList.add('touch');
    this.root = document.getElementById('touch-ui');
    this.stickBase = document.getElementById('stick');
    this.knob = document.getElementById('stick-knob');
    this.bindZones();
    this.bindButtons();
  }

  analog() { return this.move; }

  bindZones() {
    const zone = document.getElementById('touch-zone');
    const opts = { passive: false };
    zone.addEventListener('touchstart', (e) => {
      e.preventDefault();
      this.dropStale(e.touches);
      for (const t of e.changedTouches) {
        const leftSide = t.clientX < innerWidth * 0.42;
        if (leftSide && this.stickId === null) {
          this.stickId = t.identifier;
          this.origin = { x: t.clientX, y: t.clientY };
          this.stickBase.style.transform = `translate(${t.clientX}px, ${t.clientY}px)`;
          this.stickBase.classList.add('on');
          this.updateStick(t);
        } else if (this.lookId === null) {
          this.lookId = t.identifier;
          this.last = { x: t.clientX, y: t.clientY };
        }
      }
    }, opts);
    zone.addEventListener('touchmove', (e) => {
      e.preventDefault();
      for (const t of e.changedTouches) {
        if (t.identifier === this.stickId) this.updateStick(t);
        else if (t.identifier === this.lookId) {
          this.onLook((t.clientX - this.last.x) * LOOK_SENS, (t.clientY - this.last.y) * LOOK_SENS);
          this.last = { x: t.clientX, y: t.clientY };
        }
      }
    }, opts);
    const end = (e) => {
      for (const t of e.changedTouches) {
        if (t.identifier === this.stickId) {
          this.stickId = null;
          this.move = { x: 0, y: 0, mag: 0, sprint: false };
          this.stickBase.classList.remove('on');
          this.knob.style.transform = 'translate(-50%, -50%)';
        } else if (t.identifier === this.lookId) this.lookId = null;
      }
    };
    zone.addEventListener('touchend', end);
    zone.addEventListener('touchcancel', end);
  }

  // A finger the browser stopped reporting without a touchend (e.g. an iOS system gesture)
  // would otherwise keep the stick pushed or block a new look finger.
  dropStale(touches) {
    const live = new Set([...touches].map((t) => t.identifier));
    if (this.stickId !== null && !live.has(this.stickId)) {
      this.stickId = null; this.move = { x: 0, y: 0, mag: 0, sprint: false };
      this.stickBase.classList.remove('on'); this.knob.style.transform = 'translate(-50%, -50%)';
    }
    if (this.lookId !== null && !live.has(this.lookId)) this.lookId = null;
  }

  updateStick(t) {
    let dx = t.clientX - this.origin.x, dy = t.clientY - this.origin.y;
    const d = Math.hypot(dx, dy);
    if (d > STICK_RADIUS) { dx *= STICK_RADIUS / d; dy *= STICK_RADIUS / d; }
    const mag = Math.min(1, d / STICK_RADIUS);
    this.move = { x: dx / STICK_RADIUS, y: -dy / STICK_RADIUS, mag, sprint: mag >= SPRINT_AT };
    this.knob.style.transform = `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px))`;
  }

  bindButtons() {
    const inp = this.input;
    const hold = (id, button) => {
      const el = document.getElementById(id);
      const down = (e) => { e.preventDefault(); inp.buttons.add(button); el.classList.add('down'); };
      const up = (e) => { e.preventDefault(); inp.buttons.delete(button); el.classList.remove('down'); };
      el.addEventListener('touchstart', down, { passive: false });
      el.addEventListener('touchend', up);
      el.addEventListener('touchcancel', up);
    };
    const tap = (id, code) => {
      const el = document.getElementById(id);
      el.addEventListener('touchstart', (e) => { e.preventDefault(); inp.pressedSet.add(code); el.classList.add('down'); }, { passive: false });
      el.addEventListener('touchend', () => el.classList.remove('down'));
      el.addEventListener('click', () => inp.pressedSet.add(code)); // also works with a mouse when testing
    };
    hold('t-attack', 0);
    tap('t-jump', 'Space');
    tap('t-melee', 'KeyF');
    tap('t-bag', 'Tab');
    tap('t-base', 'KeyB');
    tap('t-map', 'KeyM');
    tap('t-home', 'KeyH');
    tap('t-help', 'Slash');
    const aim = document.getElementById('t-aim');
    aim.addEventListener('touchstart', (e) => {
      e.preventDefault();
      this.aimOn = !this.aimOn;
      aim.classList.toggle('active', this.aimOn);
      if (this.aimOn) inp.buttons.add(2); else inp.buttons.delete(2);
    }, { passive: false });
    // the interaction prompt doubles as the "E" button
    const prompt = document.getElementById('prompt');
    prompt.addEventListener('touchstart', (e) => { e.preventDefault(); inp.pressedSet.add('KeyE'); }, { passive: false });
    prompt.addEventListener('click', () => inp.pressedSet.add('KeyE'));
    // big map closes on tap
    document.getElementById('bigmap-wrap').addEventListener('click', () => inp.pressedSet.add('KeyM'));
  }
}
