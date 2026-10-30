'use strict';
// 冰箱 · 舞台（对应 FridgePage.swift）
// 941×1672 的画布分层叠：箱体内胆 → 内胆贴纸 → 门内侧（含门架贴纸）→ 门外侧（便签、提醒、照片）
// 开门 = 门外侧绕右边合页转到 90°，再换门内侧从 90° 转平；镜头从「只看箱体」推到「箱体+门」。
(function () {
  const F = window.Fridge;
  const R = F.RECTS, C = F.CANVAS, h = F.h;
  const PERSPECTIVE = 2100;
  const REMINDER_SPOTS = [[0.42, 0.5], [0.74, 0.57], [0.4, 0.7], [0.73, 0.78], [0.52, 0.88]];
  const rectCenter = (r) => [r[0] + r[2] / 2, r[1] + r[3] / 2];
  const posAbs = (el, r) => { el.style.left = r[0] + 'px'; el.style.top = r[1] + 'px'; el.style.width = r[2] + 'px'; el.style.height = r[3] + 'px'; };

  class Stage {
    constructor(app, viewport) {
      this.app = app;
      this.store = F.store;
      this.viewport = viewport;
      this.isOpen = false;
      this.progress = 0;
      this.focusedZone = null;
      this.peeling = {}; // id → 0…1
      this.landing = {};
      this.dragging = null;
      this.selectedMagnet = null;
      this.bigNote = null;
      this.doorAnim = null;
      this.build();
      this.applyDoor(0);
      new ResizeObserver(() => this.applyCamera(false)).observe(viewport);
      this.applyCamera(false);
      viewport.addEventListener('click', (e) => {
        if (e.target.closest('.door-item, .zone-hit, .band, .door-front .art, .hit-swallow')) return;
        this.tapBlank();
      });
    }

    // ---------- DOM ----------
    build() {
      const stage = (this.stage = h('div', 'stage'));
      stage.style.width = C.w + 'px'; stage.style.height = C.h + 'px';
      this.shadow = h('div', 'floor-shadow');
      stage.appendChild(this.shadow);

      // 箱体
      const body = (this.bodyLayer = h('div', 'layer body-layer'));
      this.bodyArt = F.artEl('fridge_body', R.body);
      body.appendChild(this.bodyArt);
      this.cavities = R.cavities.map((r) => { const c = h('div', 'cavity'); posAbs(c, r); body.appendChild(c); return c; });
      // 冷冻室内胆按两层中线切成上下两块点按区；冷藏内腔整块吞点击
      const cav0 = R.cavities[0];
      const cut = (F.zone('freezerTop').rect[1] + F.zone('freezerTop').rect[3] + F.zone('freezer').rect[1]) / 2;
      this.band(body, 'freezerTop', [cav0[0], cav0[1], cav0[2], cut - cav0[1]]);
      this.band(body, 'freezer', [cav0[0], cut, cav0[2], cav0[1] + cav0[3] - cut]);
      const swallow = h('div', 'hit-swallow'); posAbs(swallow, R.cavities[1]); body.appendChild(swallow);
      this.zoneEls = {};
      F.BODY_ZONES.forEach((z) => { const el = h('div', 'zone'); el.dataset.zone = z; body.appendChild(el); this.zoneEls[z] = el; });
      stage.appendChild(body);

      // 门内侧
      const inner = (this.doorInner = h('div', 'layer door-inner'));
      inner.appendChild(F.artEl('fridge_door_top_in', R.doorTopIn));
      inner.appendChild(F.artEl('fridge_door_bottom_in', R.doorBottomIn));
      const top = R.doorTopIn, bottom = R.doorBottomIn;
      const mid = (a, b) => (F.zone(a).rect[1] + F.zone(a).rect[3] + F.zone(b).rect[1]) / 2;
      const cut0 = mid('freezerDoor', 'freezerDoorLow'), cut1 = mid('doorTop', 'doorMid'), cut2 = mid('doorMid', 'doorLow');
      this.band(inner, 'freezerDoor', [top[0], top[1], top[2], cut0 - top[1]]);
      this.band(inner, 'freezerDoorLow', [top[0], cut0, top[2], top[1] + top[3] - cut0]);
      this.band(inner, 'doorTop', [bottom[0], bottom[1], bottom[2], cut1 - bottom[1]]);
      this.band(inner, 'doorMid', [bottom[0], cut1, bottom[2], cut2 - cut1]);
      this.band(inner, 'doorLow', [bottom[0], cut2, bottom[2], bottom[1] + bottom[3] - cut2]);
      F.DOOR_ZONES.forEach((z) => { const el = h('div', 'zone'); el.dataset.zone = z; inner.appendChild(el); this.zoneEls[z] = el; });
      stage.appendChild(inner);

      // 门外侧
      const front = (this.doorFront = h('div', 'layer door-front'));
      const topOut = F.artEl('fridge_door_top_out', R.doorTopOut), bottomOut = F.artEl('fridge_door_bottom_out', R.doorBottomOut);
      [topOut, bottomOut].forEach((a) => a.addEventListener('click', () => this.tapFrontDoor()));
      front.append(topOut, bottomOut);
      this.frontItems = h('div', 'front-items');
      front.appendChild(this.frontItems);
      stage.appendChild(front);

      this.viewport.appendChild(stage);
      this.renderZones();
      this.renderDoor();
    }

    band(parent, zone, r) {
      const b = h('div', 'band'); posAbs(b, r); b.dataset.zone = zone;
      b.addEventListener('click', (e) => { e.stopPropagation(); if (this.canFocus()) this.setFocus(zone); });
      parent.appendChild(b);
    }
    canFocus() { return this.isOpen && !this.focusedZone && !this.doorAnim; }

    // ---------- 镜头 ----------
    camera() {
      const w = this.viewport.clientWidth, hh = this.viewport.clientHeight;
      if (!w || !hh) return { scale: 0.4, ox: 0, oy: 0 };
      let target, scale, ax, ay;
      if (this.focusedZone) {
        const r = F.zone(this.focusedZone).rect;
        target = [r[0] - 36, r[1] - 54, r[2] + 72, r[3] + 108];
        scale = Math.min((w * 0.94) / target[2], (hh * 0.36) / target[3]);
        ax = w / 2; ay = hh * 0.22;
      } else {
        target = this.isOpen ? R.openFrame : R.body;
        scale = Math.min((w * (this.isOpen ? 0.96 : 0.74)) / target[2], (hh * 0.95) / target[3]);
        ax = w / 2; ay = hh / 2;
      }
      const [tx, ty] = rectCenter(target);
      const mx = (tx - C.w / 2) * scale, my = (ty - C.h / 2) * scale;
      return { scale, ox: ax - w / 2 - mx, oy: ay - hh / 2 - my };
    }
    applyCamera(animated = true, curve) {
      const cam = (this.cam = this.camera());
      this.stage.style.transition = animated ? `transform ${curve || '0.48s cubic-bezier(0.22, 0.9, 0.3, 1.04)'}` : 'none';
      this.stage.style.transform = `translate(${cam.ox}px, ${cam.oy}px) scale(${cam.scale})`;
      this.stage.style.setProperty('--inv', String(1 / Math.max(cam.scale, 0.01)));
    }
    get scale() { return (this.cam || this.camera()).scale; }
    /// 舞台坐标 → viewport 内坐标
    screenPoint(x, y) {
      const cam = this.cam || this.camera();
      const w = this.viewport.clientWidth, hh = this.viewport.clientHeight;
      return [w / 2 + cam.ox + (x - C.w / 2) * cam.scale, hh / 2 + cam.oy + (y - C.h / 2) * cam.scale];
    }

    // ---------- 门 ----------
    applyDoor(p) {
      this.progress = p;
      const fPhase = Math.min(1, p * 2), iPhase = Math.max(0, (p - 0.5) * 2);
      this.doorFront.style.transform = `perspective(${PERSPECTIVE}px) rotateY(${fPhase * 90}deg)`;
      this.doorFront.style.opacity = p < 0.5 ? '1' : '0';
      this.doorInner.style.transform = `perspective(${PERSPECTIVE}px) rotateY(${(iPhase - 1) * 90}deg)`;
      this.doorInner.style.opacity = p > 0.5 ? '1' : '0';
      this.cavities.forEach((c) => (c.style.opacity = String(0.42 * (1 - p))));
      this.bodyArt.classList.toggle('closed', p === 0);
      this.stage.classList.toggle('is-open', this.isOpen);
      this.shadow.classList.toggle('open', this.isOpen);
      this.doorFront.classList.toggle('interactive', !this.isOpen && !this.doorAnim);
      this.doorInner.classList.toggle('interactive', this.isOpen && !this.doorAnim);
    }
    toggleDoor() {
      if (this.doorAnim) return;
      const opening = !this.isOpen;
      this.isOpen = opening;
      this.selectMagnet(null);
      const from = this.progress, to = opening ? 1 : 0;
      const dur = opening ? 740 : 560;
      this.applyCamera(true, opening ? '0.74s cubic-bezier(0.32, 0, 0.2, 1)' : '0.56s cubic-bezier(0.5, 0, 0.3, 1)');
      this.doorFront.classList.remove('interactive'); this.doorInner.classList.remove('interactive');
      this.doorAnim = F.tween(dur, opening ? F.ease.doorOpen : F.ease.doorClose, (t) => this.applyDoor(from + (to - from) * t), () => {
        this.doorAnim = null; this.applyDoor(to);
      });
      this.app.onDoorChange(opening);
    }
    tapFrontDoor() {
      if (this.doorAnim) return;
      if (this.selectedMagnet) this.selectMagnet(null); else if (!this.isOpen) this.toggleDoor();
    }
    tapBlank() {
      if (this.selectedMagnet) { this.selectMagnet(null); return; }
      if (this.focusedZone) this.setFocus(null); else if (this.isOpen) this.toggleDoor();
    }
    setFocus(zone) {
      this.focusedZone = zone;
      this.stage.classList.toggle('focused', !!zone);
      this.applyCamera(true);
      this.app.onFocusChange(zone);
    }

    // ---------- 分区：最多 4 张代表贴纸，多的叠起来 +N ----------
    renderZones() { F.ZONES.forEach((z) => this.renderZone(z.id)); }
    renderZone(id) {
      const z = F.zone(id), el = this.zoneEls[id];
      el.innerHTML = '';
      const list = this.store.itemsIn(id);
      const shown = list.slice(0, list.length > 4 ? 3 : 4), rest = list.slice(shown.length);
      const slots = Math.max(shown.length + (rest.length ? 1 : 0), 1);
      const [rx, ry, rw, rh] = z.rect;
      const side = Math.min(124, (rw / slots) * 1.18), slotW = rw / slots;
      const hit = h('div', 'zone-hit');
      posAbs(hit, [rx + rw / 2 - (rw + 20) / 2, ry + rh / 2 - 6 - (rh + 30) / 2, rw + 20, rh + 30]);
      hit.addEventListener('click', (e) => { e.stopPropagation(); if (this.canFocus()) this.setFocus(id); });
      el.appendChild(hit);
      shown.forEach((item, i) => {
        const s = F.stickerEl(item, side, { dot: true });
        s.style.left = rx + slotW * (i + 0.5) - side / 2 + 'px';
        s.style.top = ry + rh - side + 'px';
        s.style.transform = `rotate(${F.tilt(item.id)}deg)`;
        el.appendChild(s);
        this.applyItemAnim(item.id, s);
      });
      if (rest.length) {
        const stack = h('div', 'zone-stack');
        stack.style.width = side + 'px'; stack.style.height = side + 'px';
        stack.style.left = rx + slotW * (shown.length + 0.5) - side / 2 + 'px';
        stack.style.top = ry + rh - side + 'px';
        rest.slice(0, 2).forEach((item, i) => {
          const s = F.stickerEl(item, side * 0.86);
          s.style.left = (side - side * 0.86) / 2 + i * side * 0.22 + 'px';
          s.style.top = (side - side * 0.86) / 2 - i * side * 0.06 + 'px';
          s.style.transform = `rotate(${i === 0 ? -6 : 8}deg)`;
          s.style.zIndex = String(2 - i);
          stack.appendChild(s);
          this.applyItemAnim(item.id, s);
        });
        const badge = h('div', 'zone-badge', '+' + rest.length);
        badge.style.left = side / 2 + side * 0.3 + 'px'; badge.style.top = side / 2 - side * 0.36 + 'px';
        stack.appendChild(badge);
        el.appendChild(stack);
      }
    }
    applyItemAnim(id, stickerEl) {
      const body = stickerEl.querySelector('.sticker-body');
      if (this.landing[id] != null) F.stickOn(body, this.landing[id]);
      if (this.peeling[id] != null) F.curl(body, this.peeling[id]);
    }

    // ---------- 门外侧 ----------
    frontPoint(x, y) { return [R.front[0] + R.front[2] * x, R.front[1] + R.front[3] * y]; }
    renderDoor() {
      const root = this.frontItems;
      root.innerHTML = '';
      this.store.doorReminders.forEach((item, index) => {
        const spot = REMINDER_SPOTS[index % REMINDER_SPOTS.length];
        const x = item.doorX == null ? spot[0] : item.doorX, y = item.doorY == null ? spot[1] : item.doorY;
        const wrap = this.doorItem(x, y, F.tilt(item.id) * 0.8, 50);
        wrap.dataset.kind = 'reminder'; wrap.dataset.id = item.id;
        const rem = F.reminderEl(item);
        wrap.firstChild.appendChild(rem);
        if (this.peeling[item.id] != null) this.applyReminderPeel(rem, this.peeling[item.id]);
        this.makeDraggable(wrap, () => [x, y], (nx, ny) => this.store.moveOnDoor(item.id, nx, ny), () => this.app.showItem(item));
        root.appendChild(wrap);
      });
      this.store.notes.forEach((note) => {
        const wrap = this.doorItem(note.x, note.y, note.tilt, 100 + (note.z == null ? 0 : note.z));
        wrap.dataset.kind = 'note'; wrap.dataset.id = note.id;
        wrap.firstChild.appendChild(F.noteEl(note));
        if (this.bigNote && this.bigNote.id === note.id) wrap.style.opacity = '0';
        this.makeDraggable(wrap, () => [note.x, note.y], (nx, ny) => this.store.moveNote(note.id, nx, ny), () => this.openNote(note));
        root.appendChild(wrap);
      });
      this.store.magnets.forEach((m) => this.renderMagnet(m, root));
    }
    doorItem(x, y, tilt, z) {
      const wrap = h('div', 'door-item');
      const [px, py] = this.frontPoint(x, y);
      wrap.style.left = px + 'px'; wrap.style.top = py + 'px'; wrap.style.zIndex = String(z);
      const inner = h('div', 'door-item-inner');
      inner.style.transform = `rotate(${tilt}deg)`;
      inner.dataset.tilt = tilt;
      wrap.appendChild(inner);
      return wrap;
    }
    renderMagnet(m, root) {
      const selected = this.selectedMagnet === m.id;
      const wrap = this.doorItem(m.x, m.y, m.tilt, selected ? 10000 : 100 + (m.z == null ? 1 : m.z));
      wrap.dataset.kind = 'magnet'; wrap.dataset.id = m.id;
      const inner = wrap.firstChild;
      const mv = F.magnetEl(m);
      inner.appendChild(mv);
      if (selected) {
        inner.classList.add('selected');
        const btn = (cls, icon, title, fn) => {
          const b = h('button', 'mag-btn ' + cls, F.icon(icon, 14));
          b.title = title;
          b.addEventListener('click', (e) => { e.stopPropagation(); fn(); });
          b.addEventListener('pointerdown', (e) => e.stopPropagation());
          mv.appendChild(b);
          return b;
        };
        btn('tl', 'xmark', '拿掉', () => { this.store.removeMagnet(m.id); this.selectedMagnet = null; });
        if (m.style !== 'photo') btn('tr', 'pencil', '编辑', () => { this.selectMagnet(null); this.app.editMagnet(m); });
        btn('bl', 'layers', '层级', () => this.app.layerMenu(m.id, wrap));
        const rot = btn('br', 'rotate', '转一转', () => {});
        this.makeTurnable(rot, wrap, m);
      }
      this.makeDraggable(wrap, () => [m.x, m.y], (nx, ny) => this.store.moveMagnet(m.id, nx, ny), () => this.selectMagnet(selected ? null : m.id));
      root.appendChild(wrap);
    }
    selectMagnet(id) {
      if (this.selectedMagnet === id) return;
      this.selectedMagnet = id;
      this.renderDoor();
    }
    /// 按住把手绕照片中心拖：转过的角度 = 手指现在的方向 − 起手时的方向
    makeTurnable(handle, wrap, m) {
      let start = null;
      const center = () => { const r = wrap.getBoundingClientRect(); return [r.left, r.top]; };
      const angle = (e) => { const c = center(); return (Math.atan2(e.clientY - c[1], e.clientX - c[0]) * 180) / Math.PI; };
      handle.addEventListener('pointerdown', (e) => { e.stopPropagation(); e.preventDefault(); handle.setPointerCapture(e.pointerId); start = { a: angle(e), tilt: m.tilt, now: m.tilt }; });
      handle.addEventListener('pointermove', (e) => { if (!start) return; start.now = start.tilt + angle(e) - start.a; wrap.firstChild.style.transform = `rotate(${start.now}deg)`; });
      const end = () => { if (!start) return; this.store.setMagnetTilt(m.id, start.now); start = null; };
      handle.addEventListener('pointerup', end); handle.addEventListener('pointercancel', end);
    }
    /// 门上的东西都能拖：拖动量除以镜头倍率换成舞台单位，松手按门面归一化坐标存
    makeDraggable(wrap, getXY, commit, onTap) {
      const inner = wrap.firstChild;
      let st = null;
      wrap.addEventListener('pointerdown', (e) => {
        if (e.button !== 0 && e.pointerType === 'mouse') return;
        if (this.isOpen || this.doorAnim) return;
        st = { x: e.clientX, y: e.clientY, id: e.pointerId, moved: false };
        wrap.setPointerCapture(e.pointerId);
        e.stopPropagation();
      });
      wrap.addEventListener('pointermove', (e) => {
        if (!st || e.pointerId !== st.id) return;
        const dx = e.clientX - st.x, dy = e.clientY - st.y;
        if (!st.moved && Math.hypot(dx, dy) < 6) return;
        if (!st.moved) { st.moved = true; wrap.classList.add('dragging'); this.dragging = wrap.dataset.id; }
        const s = Math.max(this.scale, 0.01);
        inner.style.transform = `translate(${dx / s}px, ${dy / s}px) rotate(${inner.dataset.tilt}deg)`;
        e.preventDefault();
      });
      const up = (e) => {
        if (!st || e.pointerId !== st.id) return;
        const dx = e.clientX - st.x, dy = e.clientY - st.y;
        const moved = st.moved; st = null;
        this.dragging = null;
        if (moved) {
          const s = Math.max(this.scale, 0.01);
          const [x, y] = getXY();
          const nx = x + dx / s / R.front[2], ny = y + dy / s / R.front[3];
          wrap.classList.remove('dragging');
          commit(F.clamp(nx, 0.12, 0.9), F.clamp(ny, 0.06, 0.94));
        }
      };
      wrap.addEventListener('pointerup', up);
      wrap.addEventListener('pointercancel', up);
      wrap.addEventListener('click', (e) => { e.stopPropagation(); if (!wrap.classList.contains('dragging')) onTap(); });
    }

    // ---------- 放进 / 吃掉 / 揭下 ----------
    /// 门关着先开门，再让新贴纸从下面飞进那一层、按下去贴平
    stickOn(item) {
      F.later(400, () => {
        if (this.focusedZone) this.setFocus(null);
        const needsOpen = !this.isOpen;
        if (needsOpen) this.toggleDoor();
        F.later(needsOpen ? 780 : 150, () => {
          this.landing[item.id] = 0;
          this.store.add(item);
          F.later(20, () => {
            F.tween(780, F.ease.linear, (p) => {
              this.landing[item.id] = p;
              this.forEachSticker(item.id, (body) => F.stickOn(body, p));
            }, () => {
              delete this.landing[item.id];
              this.forEachSticker(item.id, (body) => F.stickOn(body, 1));
              this.app.toast(`${item.name}放进${F.zone(item.zone).title}啦`);
            });
          });
        });
      });
    }
    forEachSticker(id, fn) { document.querySelectorAll(`.sticker[data-item-id="${id}"] > .sticker-body`).forEach(fn); }
    /// 吃掉：还有剩就减一份；最后一份就从角上揭起来飞走
    eat(item) {
      F.later(320, () => {
        if (item.quantity > 1) {
          this.store.consume(item.id);
          this.app.toast(`吃掉一${item.unit}${item.name}，还剩 ${Math.round(item.quantity - 1)} ${item.unit}`);
          return;
        }
        this.peelOff(item, `${item.name}吃光光啦`, 0);
      });
    }
    applyReminderPeel(rem, p) {
      F.curl(rem.querySelector('.rem-curl'), Math.max(0, (p - 0.22) / 0.78), { gradient: false });
      F.attachOff(rem.querySelector('.rem-magnet'), Math.min(p / 0.3, 1), false);
    }
    peelOff(item, message, delay = 320) {
      F.later(delay, () => {
        this.peeling[item.id] = 0;
        F.later(20, () => {
          F.tween(1150, F.ease.easeInOut, (p) => {
            this.peeling[item.id] = p;
            this.forEachSticker(item.id, (body) => F.curl(body, p));
            document.querySelectorAll(`.reminder[data-item-id="${item.id}"]`).forEach((rem) => this.applyReminderPeel(rem, p));
          }, () => {
            delete this.peeling[item.id];
            this.store.remove(item.id);
            if (message) this.app.toast(message);
          });
        });
      });
    }

    // ---------- 居中看便签：从门上飞到正中放大，点暗处飞回去 ----------
    openNote(note) {
      if (this.bigNote) return;
      this.bigNote = note;
      this.bigPanel = null;
      this.bigPeel = 0;
      const ov = (this.bigEl = h('div', 'bignote'));
      ov.innerHTML = '<div class="bignote-dim"></div><div class="bignote-note"></div><div class="bignote-actions"></div>';
      ov.querySelector('.bignote-dim').addEventListener('click', () => this.closeNote());
      this.app.root.appendChild(ov);
      const holder = ov.querySelector('.bignote-note');
      holder.style.transition = 'none';
      this.renderBigNote(false);
      void holder.offsetHeight;
      holder.style.transition = '';
      this.renderDoor();
      requestAnimationFrame(() => requestAnimationFrame(() => { this.bigShown = true; this.renderBigNote(true); }));
    }
    bigGeometry() {
      const vp = this.viewport, vr = vp.getBoundingClientRect(), ar = this.app.root.getBoundingClientRect();
      const offX = vr.left - ar.left, offY = vr.top - ar.top;
      const panel = this.bigPanel;
      const center = [offX + vr.width / 2, offY + vr.height * (panel === 'style' ? 0.2 : panel ? 0.27 : 0.36)];
      const bigScale = Math.min((vr.width * 0.78) / 228, 1.5) * (panel === 'style' ? 0.74 : panel ? 0.88 : 1);
      return { offX, offY, center, bigScale };
    }
    renderBigNote(shown) {
      const note = this.store.note(this.bigNote.id) || this.bigNote;
      const g = this.bigGeometry();
      const holder = this.bigEl.querySelector('.bignote-note');
      let el = holder.firstChild;
      if (!el || el._noteKey !== JSON.stringify([note.paper, note.attach, note.font, note.fontSize, note.text, note.decos])) {
        holder.innerHTML = '';
        el = F.noteEl(note);
        el._noteKey = JSON.stringify([note.paper, note.attach, note.font, note.fontSize, note.text, note.decos]);
        holder.appendChild(el);
        this.wireBigDecos(el, note);
      }
      const H = el.offsetHeight || 150;
      const [ox, oy] = this.frontPoint(note.x, note.y);
      const [sx, sy] = this.screenPoint(ox, oy);
      const p = shown ? g.center : [g.offX + sx, g.offY + sy];
      const s = shown ? g.bigScale : this.scale;
      const r = note.tilt * (shown ? 0.4 : 1);
      holder.style.transform = `translate(${p[0] - 114}px, ${p[1] - H / 2}px) rotate(${r}deg) scale(${s})`;
      this.bigEl.classList.toggle('shown', !!shown);
      const actions = this.bigEl.querySelector('.bignote-actions');
      actions.style.top = g.center[1] + 120 * g.bigScale + 26 + 'px';
      actions.style.opacity = shown && !this.bigPeel ? '1' : '0';
      actions.style.pointerEvents = shown && !this.bigPeel ? '' : 'none';
      if (!actions._built || actions._panel !== this.bigPanel) this.buildBigActions(actions, note);
    }
    wireBigDecos(el, note) {
      el.querySelectorAll('.deco').forEach((de) => {
        let st = null, sel = false;
        de.addEventListener('pointerdown', (e) => { if (!this.bigShown) return; e.stopPropagation(); e.preventDefault(); de.setPointerCapture(e.pointerId); st = { x: e.clientX, y: e.clientY, moved: false }; });
        de.addEventListener('pointermove', (e) => {
          if (!st) return;
          const g = this.bigGeometry(), s = g.bigScale;
          const dx = (e.clientX - st.x) / s, dy = (e.clientY - st.y) / s;
          if (!st.moved && Math.hypot(dx, dy) < 3) return;
          st.moved = true;
          const d = (note.decos || []).find((x) => x.id === de.dataset.decoId);
          de.style.left = F.clamp(d.x + dx, 10, 218) + 'px'; de.style.top = F.clamp(d.y + dy, 10, 260) + 'px';
        });
        de.addEventListener('pointerup', (e) => {
          if (!st) return;
          const g = this.bigGeometry(), s = g.bigScale;
          const d = (note.decos || []).find((x) => x.id === de.dataset.decoId);
          if (st.moved) this.store.moveDeco(d.id, note.id, F.clamp(d.x + (e.clientX - st.x) / s, 10, 218), F.clamp(d.y + (e.clientY - st.y) / s, 10, 260));
          else { sel = !sel; de.classList.toggle('selected', sel); if (sel) { const x = h('button', 'deco-x', F.icon('xmark', 9)); x.addEventListener('pointerdown', (ev) => ev.stopPropagation()); x.addEventListener('click', (ev) => { ev.stopPropagation(); this.store.removeDeco(d.id, note.id); }); de.appendChild(x); } else de.querySelector('.deco-x')?.remove(); }
          st = null;
        });
      });
    }
    buildBigActions(actions, note) {
      actions.innerHTML = '';
      actions._built = true; actions._panel = this.bigPanel;
      const cap = h('div', 'bignote-cap', (note.decos || []).length ? '拖贴纸换位置 · 点一下可以删掉' : note.author === 'partner' ? 'TA 留的' : '你写的');
      actions.appendChild(cap);
      const row = h('div', 'bignote-row');
      const btn = (title, icon, fn) => { const b = h('button', 'pill', F.icon(icon, 13) + `<span>${title}</span>`); b.addEventListener('click', fn); row.appendChild(b); return b; };
      btn(this.bigPanel === 'style' ? '好啦' : '换样式', 'brush', () => this.togglePanel('style'));
      btn(this.bigPanel === 'deco' ? '好啦' : '贴贴纸', 'heart', () => this.togglePanel('deco'));
      btn('揭下来', 'hand', () => this.peelBigNote(note));
      const lay = h('button', 'pill round', F.icon('layers', 15));
      lay.addEventListener('click', () => this.app.layerMenu(note.id, lay));
      row.appendChild(lay);
      actions.appendChild(row);
      if (this.bigPanel === 'style') {
        actions.appendChild(F.ui.stylePicker({ paper: note.paper, attach: note.attach, font: note.font, fontSize: note.fontSize }, (style) => this.store.restyleNote(note.id, style), true));
      }
      if (this.bigPanel === 'deco') {
        const panel = h('div', 'deco-row');
        F.DECOS.forEach((d) => { const b = h('button', 'deco-pick', F.decoGlyph(d.id, 26)); b.addEventListener('click', () => this.store.addDeco(d.id, note.id)); panel.appendChild(b); });
        actions.appendChild(panel);
      }
    }
    togglePanel(panel) { this.bigPanel = this.bigPanel === panel ? null : panel; this.renderBigNote(true); }
    closeNote() {
      if (!this.bigNote) return;
      this.bigShown = false; this.bigPanel = null;
      this.renderBigNote(false);
      const id = this.bigNote.id;
      F.later(420, () => { if (!this.bigShown && this.bigNote && this.bigNote.id === id) this.destroyBigNote(); });
    }
    destroyBigNote() { if (this.bigEl) this.bigEl.remove(); this.bigEl = null; this.bigNote = null; this.bigPeel = 0; this.renderDoor(); }
    peelBigNote(note) {
      if (this.bigPeel) return;
      this.bigPanel = null;
      this.bigPeel = 0.001;
      this.renderBigNote(true);
      const el = this.bigEl.querySelector('.bignote-note > .note');
      const attach = el.querySelector('.attach');
      F.tween(1300, F.ease.easeInOut, (p) => {
        this.bigPeel = p;
        if (attach) F.attachOff(attach, Math.min(p / 0.4, 1), F.isTape(note.attach));
        F.takeAway(el, Math.max(0, (p - 0.42) / 0.58));
      }, () => {
        this.store.removeNote(note.id);
        this.bigEl.classList.remove('shown');
        F.later(260, () => { this.destroyBigNote(); this.app.toast('便签揭下来啦'); });
      });
    }

    // ---------- 数据变了 ----------
    onStoreChange(what) {
      if (what === 'paint') { F.repaintAll(this.stage); return; }
      this.renderZones();
      this.renderDoor();
      if (this.bigNote && this.bigEl) {
        if (!this.store.note(this.bigNote.id) && !this.bigPeel) this.destroyBigNote();
        else if (!this.bigPeel) { this.bigEl.querySelector('.bignote-actions')._built = false; this.renderBigNote(this.bigShown); }
      }
    }
  }
  F.Stage = Stage;
})();
