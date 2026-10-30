'use strict';
// 冰箱 · 面板层（对应 FridgeSheets.swift + FridgeZoneCard）
(function () {
  const F = window.Fridge;
  const h = F.h;
  const ui = (F.ui = {});

  // ---------- 底部弹层 ----------
  ui.sheet = ({ cls = '', full = false, build, onClose }) => {
    const root = h('div', 'sheet-root');
    const dim = h('div', 'sheet-dim');
    const sheet = h('div', 'sheet ' + cls + (full ? ' full' : ''));
    sheet.innerHTML = '<div class="grabber"></div>';
    root.append(dim, sheet);
    const ctl = {
      el: sheet,
      close(cb) {
        root.classList.remove('shown');
        F.later(300, () => { root.remove(); if (onClose) onClose(); if (cb) cb(); });
      },
    };
    dim.addEventListener('click', () => ctl.close());
    build(sheet, ctl);
    F.app.root.appendChild(root);
    requestAnimationFrame(() => requestAnimationFrame(() => root.classList.add('shown')));
    return ctl;
  };
  ui.header = (title, left, right) => {
    const bar = h('div', 'sheet-head');
    const l = h('button', 'text-btn muted', left ? left.title : ''); if (left) l.addEventListener('click', left.fn); else l.style.visibility = 'hidden';
    const t = h('div', 'sheet-title', F.esc(title));
    const r = h('button', 'text-btn rose', right ? right.title : ''); if (right) r.addEventListener('click', right.fn); else r.style.visibility = 'hidden';
    bar.append(l, t, r);
    return { bar, left: l, right: r };
  };
  ui.field = (title, ...content) => {
    const f = h('div', 'field');
    f.appendChild(h('div', 'field-title', F.esc(title)));
    const box = h('div', 'field-box');
    content.forEach((c) => box.appendChild(c));
    f.appendChild(box);
    return f;
  };
  ui.chip = (title, selected, fn) => { const b = h('button', 'chip' + (selected ? ' on' : ''), F.esc(title)); b.addEventListener('click', fn); return b; };

  // ---------- 提示 / 确认 / 菜单 ----------
  let toastTimer = 0;
  ui.toast = (text) => {
    let t = F.app.root.querySelector('.toast');
    if (!t) { t = h('div', 'toast'); F.app.root.appendChild(t); }
    t.textContent = text;
    t.classList.add('shown');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('shown'), 2200);
  };
  ui.confirm = ({ title, message, ok, danger = true }) => new Promise((res) => {
    const root = h('div', 'alert-root');
    root.innerHTML = `<div class="alert"><div class="alert-title">${F.esc(title)}</div><div class="alert-msg">${F.esc(message)}</div><div class="alert-btns"><button class="alert-btn">算了</button><button class="alert-btn ${danger ? 'danger' : 'rose'}">${F.esc(ok)}</button></div></div>`;
    const [cancel, confirm] = root.querySelectorAll('button');
    cancel.addEventListener('click', () => { root.remove(); res(false); });
    confirm.addEventListener('click', () => { root.remove(); res(true); });
    F.app.root.appendChild(root);
  });
  ui.menu = (anchor, entries) => {
    document.querySelectorAll('.menu-root').forEach((m) => m.remove());
    const root = h('div', 'menu-root');
    const menu = h('div', 'menu');
    entries.forEach((en) => {
      const b = h('button', 'menu-item' + (en.danger ? ' danger' : ''), (en.icon ? F.icon(en.icon, 15) : '') + `<span>${F.esc(en.title)}</span>` + (en.checked != null ? `<span class="menu-check">${en.checked ? F.icon('check', 14) : ''}</span>` : ''));
      b.addEventListener('click', () => { root.remove(); en.fn(); });
      menu.appendChild(b);
    });
    root.appendChild(menu);
    root.addEventListener('click', (e) => { if (e.target === root) root.remove(); });
    F.app.root.appendChild(root);
    const ar = anchor.getBoundingClientRect(), rr = F.app.root.getBoundingClientRect();
    const mw = 210;
    let left = ar.right - rr.left - mw; if (left < 8) left = 8;
    let top = ar.bottom - rr.top + 6;
    menu.style.left = left + 'px'; menu.style.top = top + 'px'; menu.style.width = mw + 'px';
    requestAnimationFrame(() => { const mr = menu.getBoundingClientRect(); if (mr.bottom > rr.bottom - 8) menu.style.top = ar.top - rr.top - mr.height - 6 + 'px'; });
  };

  // ---------- 某一层放大后的卡片 ----------
  ui.zoneCard = (zoneId, { onPick, onAdd, onClose }) => {
    const z = F.zone(zoneId);
    const items = F.store.itemsIn(zoneId);
    const card = h('div', 'zone-card');
    card.innerHTML = `<div class="grabber"></div><div class="zc-head"><div class="zc-title">${F.esc(z.title)}<span class="zc-count">${items.length} 样</span></div><button class="zc-add">${F.icon('plus', 12)}<span>放这层</span></button><button class="zc-close">${F.icon('xmark', 12)}</button></div>`;
    card.querySelector('.zc-add').addEventListener('click', onAdd);
    card.querySelector('.zc-close').addEventListener('click', onClose);
    if (!items.length) card.appendChild(h('div', 'zc-empty', '这一层空空的，放点什么进来吧'));
    else {
      const grid = h('div', 'zc-grid');
      items.forEach((item) => {
        const cell = h('button', 'zc-cell');
        const s = F.stickerEl(item, 74);
        s.style.transform = `rotate(${F.tilt(item.id) * 0.6}deg)`;
        cell.appendChild(s);
        const tone = F.due.tone(item), col = F.due.color(tone);
        cell.insertAdjacentHTML('beforeend', `<div class="zc-name">${F.esc(item.name)}</div><div class="zc-due" style="color:${col};background:${col}1f">${F.esc(F.due.label(item))}</div>`);
        cell.addEventListener('click', () => onPick(item));
        grid.appendChild(cell);
        F.app.stage.applyItemAnim(item.id, s);
      });
      card.appendChild(grid);
    }
    return card;
  };

  // ---------- 点贴纸弹出的详情卡 ----------
  ui.itemSheet = (item, { onEat, onEdit, onRemove }) => {
    const expired = F.due.expired(item);
    let confirmRemove = false;
    ui.sheet({
      cls: 'item-sheet',
      build(el, ctl) {
        const tone = F.due.tone(item), col = F.due.color(tone);
        const head = h('div', 'is-head');
        const s = F.stickerEl(item, 96); s.style.transform = `rotate(${F.tilt(item.id)}deg)`;
        head.appendChild(s);
        head.insertAdjacentHTML('beforeend', `<div class="is-meta"><div class="is-name">${F.esc(item.name)}</div><div class="is-due" style="color:${col};background:${col}1f">${F.esc(F.due.label(item))}</div></div>`);
        el.appendChild(head);
        const rows = [['数量', F.quantityText(item)], ['放在', F.zone(item.zone).title], ['放进来', F.fmtDate(item.addedAt)], ['保质期到', F.fmtDate(item.expiresAt)], ['建议吃完', F.fmtDate(item.eatBy)]];
        if (item.notes) rows.push(['备注', item.notes]);
        if (item.addedBy === 'partner') rows.push(['谁放的', 'TA']);
        const box = h('div', 'is-rows', rows.map(([k, v]) => `<div class="is-row"><span>${F.esc(k)}</span><b>${F.esc(v)}</b></div>`).join(''));
        el.appendChild(box);
        const btns = h('div', 'is-btns');
        const rm = h('button', 'is-small', F.icon('trash', 15) + '<span>移除</span>');
        rm.addEventListener('click', () => { if (confirmRemove) ctl.close(onRemove); else { confirmRemove = true; rm.classList.add('danger'); rm.querySelector('span').textContent = '真的移除'; } });
        const ed = h('button', 'is-small', F.icon('pencil', 15) + '<span>编辑</span>');
        ed.addEventListener('click', () => ctl.close(onEdit));
        const main = h('button', 'is-main' + (expired ? ' gray' : ''), F.icon(expired ? 'trash' : 'fork', 14) + `<span>${expired ? '扔掉' : item.quantity > 1 ? `吃掉一${F.esc(item.unit)}` : '吃掉啦'}</span>`);
        main.addEventListener('click', () => ctl.close(() => (expired ? onRemove() : onEat())));
        btns.append(rm, ed, main);
        el.appendChild(btns);
      },
    });
  };

  // ---------- 放进冰箱 / 编辑 ----------
  // 从放进来那天起算：补记前几天放的东西，日期不会被往后推
  const shelfLife = (days, draft) => {
    const start = F.startOfDay(draft.addedAt ? new Date(draft.addedAt) : new Date());
    draft.eatBy = F.iso(F.addDays(start, Math.max(days - 1, 0)));
    draft.expiresAt = F.iso(F.addDays(start, days));
  };
  const dayText = (days) => (days >= 30 ? `${Math.floor(days / 30)} 个月` : days === 7 ? '1 周' : days === 14 ? '2 周' : `${days} 天`);
  const suggested = (draft) => {
    const z = F.zone(draft.zone);
    if (z.frozen) return { days: 60, why: '冷冻的东西一般 1–3 个月内吃掉，味道最好' };
    const e = draft.stickerSource === 'builtIn' ? F.entry(draft.stickerAsset) : null;
    if (e && e.asset !== 'paper_bag' && e.asset !== 'unknown_food_box') return { days: e.shelfDays, why: `${e.name}放冷藏，一般 ${dayText(e.shelfDays)}内吃完比较新鲜` };
    if (z.door) return { days: 30, why: '门架上的酱料、饮料，开封后一般 1 个月内用完' };
    return { days: 5, why: '拿不准的话：剩菜熟食 2–3 天，蔬果一周左右，包装零食看开没开封' };
  };
  const DUE_CHOICES = [['今天', 1], ['3 天', 3], ['1 周', 7], ['2 周', 14], ['1 个月', 30], ['3 个月', 90]];

  ui.editorSheet = ({ item, zone }, onSave) => {
    const isNew = !item;
    let draft, hasDue, dateTouched = false, category = null;
    if (item) { draft = JSON.parse(JSON.stringify(item)); hasDue = !!draft.eatBy; }
    else {
      const e = F.CATALOG[0];
      draft = F.makeItem({ name: e.name, unit: e.unit, zone: zone || e.zone, stickerAsset: e.asset });
      shelfLife(e.shelfDays, draft); hasDue = true;
    }
    ui.sheet({
      cls: 'editor-sheet', full: true,
      build(el, ctl) {
        const head = ui.header(isNew ? '放进冰箱' : '改一改', { title: '取消', fn: () => ctl.close() }, {
          title: '放好了', fn: () => {
            const saved = JSON.parse(JSON.stringify(draft));
            if (!hasDue) { saved.eatBy = null; saved.expiresAt = null; }
            saved.name = (saved.name || '').trim();
            if (!saved.name) saved.name = (F.entry(saved.stickerAsset) || {}).name || '一样东西';
            ctl.close(() => onSave(saved));
          },
        });
        el.appendChild(head.bar);
        const body = h('div', 'sheet-body');
        el.appendChild(body);

        // 贴纸库
        const picker = h('div', 'picker');
        picker.appendChild(h('div', 'field-title', '选一张贴纸'));
        const chips = h('div', 'hscroll chips');
        const grid = h('div', 'hscroll sticker-grid');
        const renderChips = () => {
          chips.innerHTML = '';
          chips.appendChild(ui.chip('全部', category == null, () => { category = null; renderChips(); renderGrid(); }));
          F.CATEGORIES.filter((c) => F.CATALOG.some((e) => F.category(e.asset) === c.id)).forEach((c) => chips.appendChild(ui.chip(c.title, category === c.id, () => { category = c.id; renderChips(); renderGrid(); })));
        };
        const renderGrid = () => {
          grid.innerHTML = '';
          F.CATALOG.filter((e) => category == null || F.category(e.asset) === category).forEach((e) => {
            const on = draft.stickerSource === 'builtIn' && draft.stickerAsset === e.asset;
            const b = h('button', 'sticker-cell' + (on ? ' on' : ''), `<img src="${F.stickerURL(e.asset)}" draggable="false"><span>${F.esc(e.name)}</span>`);
            b.addEventListener('click', () => pick(e));
            grid.appendChild(b);
          });
        };
        const pick = (e) => {
          const prev = (F.entry(draft.stickerAsset) || {}).name;
          draft.stickerAsset = e.asset; draft.stickerSource = 'builtIn';
          if (!draft.name || draft.name === prev) draft.name = e.name;
          draft.unit = e.unit;
          if (isNew) { if (!zone) draft.zone = e.zone; autoDue(); }
          nameInput.value = draft.name; zoneSel.value = draft.zone; qtyText.textContent = F.quantityText(draft);
          renderGrid(); renderDue();
        };
        renderChips(); renderGrid();
        picker.append(chips, grid);
        body.appendChild(picker);

        // 名字
        const nameInput = h('input', 'text-input'); nameInput.placeholder = '比如：草莓'; nameInput.value = draft.name;
        nameInput.addEventListener('input', () => (draft.name = nameInput.value));
        body.appendChild(ui.field('名字', nameInput));
        // 数量
        const stepper = h('div', 'stepper');
        const qtyText = h('span', 'qty', F.quantityText(draft));
        const minus = h('button', 'step', '−'), plus = h('button', 'step', '+');
        minus.addEventListener('click', () => { draft.quantity = Math.max(1, draft.quantity - 1); qtyText.textContent = F.quantityText(draft); });
        plus.addEventListener('click', () => { draft.quantity = Math.min(99, draft.quantity + 1); qtyText.textContent = F.quantityText(draft); });
        stepper.append(qtyText, minus, plus);
        body.appendChild(ui.field('数量', stepper));
        // 放在哪
        const zoneSel = h('select', 'select');
        F.ZONES.forEach((z) => { const o = h('option', '', F.esc(z.title)); o.value = z.id; zoneSel.appendChild(o); });
        zoneSel.value = draft.zone;
        zoneSel.addEventListener('change', () => { draft.zone = zoneSel.value; autoDue(); renderDue(); });
        body.appendChild(ui.field('放在哪', zoneSel));
        // 放进来（可以往前改，补记前几天买的东西）
        const addedInp = h('input', 'date-input'); addedInp.type = 'date';
        addedInp.max = F.dateInput(F.iso(new Date()));
        addedInp.value = F.dateInput(draft.addedAt || F.iso(new Date()));
        addedInp.addEventListener('change', () => {
          if (!addedInp.value) return;
          draft.addedAt = F.iso(new Date(addedInp.value + 'T12:00:00'));
          autoDue(); renderDue();
        });
        body.appendChild(ui.field('放进来', addedInp));
        // 建议吃完
        const dueBox = h('div', 'due-box');
        const autoDue = () => { if (!isNew || dateTouched) return; shelfLife(suggested(draft).days, draft); hasDue = true; };
        const renderDue = () => {
          dueBox.innerHTML = '';
          const tog = h('label', 'toggle-row', `<span>${hasDue ? '要提醒' : '不着急'}</span><span class="switch${hasDue ? ' on' : ''}"><i></i></span>`);
          tog.addEventListener('click', () => { hasDue = !hasDue; if (hasDue && !draft.eatBy) shelfLife(suggested(draft).days, draft); renderDue(); });
          dueBox.appendChild(tog);
          if (!hasDue) return;
          const hint = suggested(draft);
          dueBox.appendChild(h('div', 'hint', F.esc(hint.why)));
          const from = F.startOfDay(draft.addedAt ? new Date(draft.addedAt) : new Date());
          const cur = draft.eatBy ? Math.round((F.startOfDay(new Date(draft.eatBy)) - from) / 86400000) + 1 : hint.days;
          let closest = DUE_CHOICES[0][1], best = Infinity;
          DUE_CHOICES.forEach(([, d]) => { if (Math.abs(d - cur) < best) { best = Math.abs(d - cur); closest = d; } });
          const row = h('div', 'hscroll chips small');
          DUE_CHOICES.forEach(([t, d]) => row.appendChild(ui.chip(t, closest === d, () => { shelfLife(d, draft); dateTouched = true; renderDue(); })));
          dueBox.appendChild(row);
          const dateRow = (label, key) => {
            const r = h('div', 'date-row', `<span>${label}</span>`);
            const inp = h('input'); inp.type = 'date'; inp.value = F.dateInput(draft[key] || draft.eatBy);
            inp.addEventListener('change', () => { if (!inp.value) return; const d = new Date(inp.value + 'T12:00:00'); draft[key] = F.iso(d); dateTouched = true; renderDue(); });
            r.appendChild(inp);
            return r;
          };
          dueBox.append(dateRow('吃完日期', 'eatBy'), dateRow('保质期到', 'expiresAt'));
        };
        renderDue();
        body.appendChild(ui.field('建议吃完', dueBox));
        // 备注
        const notes = h('textarea', 'text-input'); notes.placeholder = '比如：热一下再吃'; notes.rows = 2; notes.value = draft.notes || '';
        notes.addEventListener('input', () => (draft.notes = notes.value));
        body.appendChild(ui.field('备注', notes));
      },
    });
  };

  // ---------- 便签样式：纸 / 固定 / 字体 / 字号 ----------
  ui.stylePicker = (style, onChange, dark = false) => {
    const box = h('div', 'style-picker' + (dark ? ' dark' : ''));
    const cur = Object.assign({}, style);
    const changed = (patch) => { Object.assign(cur, patch); onChange(Object.assign({}, cur)); render(); };
    const render = () => {
      box.innerHTML = '';
      const row = (title, entries) => {
        const r = h('div', 'sp-row');
        r.appendChild(h('div', 'sp-title', title));
        const sc = h('div', 'hscroll sp-chips');
        entries.forEach(({ selected, title: t, preview, fn }) => {
          const b = h('button', 'sp-chip' + (selected ? ' on' : ''));
          const pv = h('div', 'sp-preview'); pv.appendChild(preview);
          b.appendChild(pv); b.appendChild(h('span', '', F.esc(t)));
          b.addEventListener('click', fn);
          sc.appendChild(b);
        });
        r.appendChild(sc);
        box.appendChild(r);
      };
      row('纸', F.PAPERS.map((p) => ({ selected: p.id === cur.paper, title: p.title, fn: () => changed({ paper: p.id }),
        preview: (() => { const n = F.noteEl({ text: '', paper: p.id, attach: cur.attach, font: 'kuaile', fontSize: 26, decos: [] }); n.classList.add('mini'); return n; })() })));
      row('固定', F.ATTACHES.map((a) => ({ selected: a.id === cur.attach, title: a.title, fn: () => changed({ attach: a.id }),
        preview: (() => { const w = h('div', 'attach-mini'); w.appendChild(F.attachEl(a.id)); return w; })() })));
      row('字体', F.FONTS.map((f) => ({ selected: f.id === cur.font, title: f.title, fn: () => changed({ font: f.id }),
        preview: h('div', 'font-mini font-' + f.id, '便签') })));
      const sz = h('div', 'sp-size');
      sz.innerHTML = `<div class="sp-title">字号</div><div class="sp-slider"><span class="font-${cur.font}" style="font-size:13px">小</span><input type="range" min="16" max="42" step="1" value="${cur.fontSize}"><span class="font-${cur.font}" style="font-size:22px">大</span></div>`;
      sz.querySelector('input').addEventListener('input', (e) => { cur.fontSize = Number(e.target.value); onChange(Object.assign({}, cur)); });
      box.appendChild(sz);
    };
    render();
    return box;
  };

  // ---------- 贴一张新便签 ----------
  ui.noteComposer = (onSave) => {
    let text = '';
    const style = { paper: 'yellow', attach: 'magnetBlue', font: 'kuaile', fontSize: 26 };
    ui.sheet({
      cls: 'composer-sheet', full: true,
      build(el, ctl) {
        const head = ui.header('贴便签', { title: '取消', fn: () => ctl.close() }, { title: '贴上', fn: () => { const t = text.trim(); if (!t) return; ctl.close(() => onSave(t, Object.assign({}, style))); } });
        head.right.classList.add('muted');
        el.appendChild(head.bar);
        const body = h('div', 'sheet-body');
        el.appendChild(body);
        const preview = h('div', 'note-preview');
        body.appendChild(preview);
        const renderPreview = () => {
          preview.innerHTML = '';
          const n = F.noteEl({ text: text.trim() || '写点什么…', author: 'me', tilt: -3, ...style, decos: [] });
          n.style.transform = 'rotate(-3deg) scale(0.8)';
          preview.appendChild(n);
        };
        renderPreview();
        const ta = h('textarea', 'text-input big'); ta.placeholder = '写点什么，比如：要买鸡蛋'; ta.rows = 3;
        ta.addEventListener('input', () => { text = ta.value; head.right.classList.toggle('muted', !text.trim()); renderPreview(); });
        body.appendChild(ta);
        body.appendChild(ui.stylePicker(style, (s) => { Object.assign(style, s); renderPreview(); }));
        F.later(350, () => ta.focus());
      },
    });
  };

  // ---------- 给冰箱换颜色 ----------
  ui.paintSheet = () => {
    ui.sheet({
      cls: 'paint-sheet',
      build(el, ctl) {
        el.appendChild(ui.header('给冰箱换颜色', null, { title: '好了', fn: () => ctl.close() }).bar);
        const body = h('div', 'sheet-body');
        el.appendChild(body);
        const pv = h('div', 'paint-preview');
        const top = F.artEl('fridge_door_top_out'), bottom = F.artEl('fridge_door_bottom_out');
        pv.append(top, bottom);
        body.appendChild(pv);
        const grid = h('div', 'paint-grid');
        const render = () => {
          grid.innerHTML = '';
          F.PAINTS.forEach((p) => {
            const on = F.store.paintHex === p.hex;
            const b = h('button', 'paint-cell' + (on ? ' on' : ''), `<i style="background:${p.hex || '#F3E3BE'}"></i><span>${F.esc(p.name)}</span>`);
            b.addEventListener('click', () => { F.store.setPaint(p.hex); render(); F.repaintAll(pv); });
            grid.appendChild(b);
          });
          const custom = h('label', 'paint-cell custom', `<input type="color" value="${F.store.paintHex || '#A9D9C6'}"><span>自己调</span>`);
          custom.querySelector('input').addEventListener('input', (e) => { F.store.setPaint(e.target.value.toUpperCase()); F.repaintAll(pv); });
          custom.querySelector('input').addEventListener('change', render);
          grid.appendChild(custom);
        };
        render();
        body.appendChild(grid);
      },
    });
  };

  // ---------- 贴照片 ----------
  const pickFiles = (multiple) => new Promise((res) => {
    const inp = h('input'); inp.type = 'file'; inp.accept = 'image/*'; inp.multiple = !!multiple; inp.style.display = 'none';
    document.body.appendChild(inp);
    inp.addEventListener('change', () => { res(Array.from(inp.files || [])); inp.remove(); });
    inp.click();
  });
  const loadBitmap = (file) => new Promise((res) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => { URL.revokeObjectURL(url); res(img); };
    img.onerror = () => { URL.revokeObjectURL(url); res(null); };
    img.src = url;
  });
  /// 拍立得 / 四格的原图：压到 maxSide 以内存 JPG（dataURL 进 localStorage，所以压得比 iOS 版再狠一点）
  const savePhoto = async (file, maxSide = 720) => {
    const img = await loadBitmap(file);
    if (!img) return null;
    const ratio = Math.min(1, maxSide / Math.max(img.naturalWidth, img.naturalHeight));
    const c = document.createElement('canvas');
    c.width = Math.round(img.naturalWidth * ratio); c.height = Math.round(img.naturalHeight * ratio);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    const name = F.photos.put({ data: c.toDataURL('image/jpeg', 0.8), w: c.width, h: c.height });
    return name;
  };
  /// 照片冰箱贴：圆角方块 + 奶白边（iOS 版会先抠主体，网页版直接用这个兜底样式）
  const roundedSticker = async (file) => {
    const img = await loadBitmap(file);
    if (!img) return null;
    const side = 400, border = 14, c = document.createElement('canvas');
    c.width = side; c.height = side;
    const ctx = c.getContext('2d');
    const rr = (x, y, w, hh, r) => { ctx.beginPath(); ctx.roundRect(x, y, w, hh, r); };
    ctx.fillStyle = '#FFF8EE'; rr(0, 0, side, side, 55); ctx.fill();
    ctx.save(); rr(border, border, side - 2 * border, side - 2 * border, 44); ctx.clip();
    const inner = side - 2 * border, s = Math.max(inner / img.naturalWidth, inner / img.naturalHeight);
    const dw = img.naturalWidth * s, dh = img.naturalHeight * s;
    ctx.drawImage(img, side / 2 - dw / 2, side / 2 - dh / 2, dw, dh);
    ctx.restore();
    let data = c.toDataURL('image/webp', 0.85);
    if (!data.startsWith('data:image/webp')) data = c.toDataURL('image/png');
    return F.photos.put({ data, w: side, h: side });
  };
  const stripDate = () => { const d = new Date(), p = (n) => String(n).padStart(2, '0'); return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())}`; };

  ui.magnetSheet = () => {
    ui.sheet({
      cls: 'magnet-sheet',
      build(el, ctl) {
        el.appendChild(ui.header('贴照片', null, { title: '好了', fn: () => ctl.close() }).bar);
        const body = h('div', 'sheet-body');
        el.appendChild(body);
        const row = (title, detail, icon, fn) => {
          const b = h('button', 'photo-row', `<span class="pr-icon">${F.icon(icon, 17)}</span><span class="pr-text"><b>${F.esc(title)}</b><small>${F.esc(detail)}</small></span><span class="pr-chev">›</span>`);
          b.addEventListener('click', fn);
          body.appendChild(b);
        };
        const err = h('div', 'hint rose');
        const busy = (on) => el.classList.toggle('busy', on);
        row('照片冰箱贴', '选一张，做成带奶白边的圆角贴', 'scissors', async () => {
          const files = await pickFiles(false); if (!files.length) return;
          busy(true);
          const name = await roundedSticker(files[0]);
          busy(false);
          if (!name) { err.textContent = '照片没读出来（或者存不下），再选一次试试'; return; }
          F.store.addMagnet(F.makeMagnet({ style: 'photo', text: '', hex: '#FFFFFF', images: [name], pin: 'none' }));
          ctl.close();
        });
        row('拍立得', '一张照片，选完能换框、写字、挪构图', 'photo', async () => {
          const files = await pickFiles(false); if (!files.length) return;
          busy(true);
          const name = await savePhoto(files[0]);
          busy(false);
          if (!name) { err.textContent = '照片没读出来（或者存不下），再选一次试试'; return; }
          ctl.close(() => ui.frameEditor(F.makeMagnet({ style: 'polaroid', text: '', hex: F.FRAMES[0].hex, images: [name], crops: [] }), true, (m) => F.store.addMagnet(m)));
        });
        row('人生四格', '选 1 到 4 张，竖着排成一条，选完能逐格调', 'strip', async () => {
          const files = await pickFiles(true); if (!files.length) return;
          busy(true);
          const names = [];
          for (const f of files.slice(0, 4)) { const n = await savePhoto(f); if (n) names.push(n); }
          busy(false);
          if (!names.length) { err.textContent = '照片没读出来（或者存不下），再选一次试试'; return; }
          while (names.length < 4) names.push('');
          ctl.close(() => ui.frameEditor(F.makeMagnet({ style: 'strip', text: stripDate(), hex: F.FRAMES[0].hex, images: names, crops: [] }), true, (m) => F.store.addMagnet(m)));
        });
        body.appendChild(err);
      },
    });
  };

  // ---------- 拍立得 / 四格编辑页 ----------
  ui.frameEditor = (magnet, isNew, onSave) => {
    const draft = JSON.parse(JSON.stringify(magnet));
    const created = new Set(isNew ? (draft.images || []).filter(Boolean) : []);
    const slots = draft.style === 'strip' ? 4 : 1;
    let active = 0;
    const nameAt = (i) => (draft.images || [])[i] || '';
    const setCrop = (i, crop) => { draft.crops = draft.crops || []; while (draft.crops.length < slots) draft.crops.push({ u: 0, v: 0, scale: 1, rot: 0 }); draft.crops[i] = crop; };
    const replace = async (i) => {
      const files = await pickFiles(false); if (!files.length) return;
      const saved = await savePhoto(files[0]); if (!saved) return;
      draft.images = draft.images || []; while (draft.images.length < slots) draft.images.push('');
      const old = draft.images[i]; draft.images[i] = saved; created.add(saved);
      if (created.has(old)) { F.photos.remove(old); created.delete(old); }
      setCrop(i, { u: 0, v: 0, scale: 1, rot: 0 });
      render();
    };
    ui.sheet({
      cls: 'frame-sheet', full: true,
      build(el, ctl) {
        const head = ui.header(draft.style === 'strip' ? '人生四格' : '拍立得',
          { title: '取消', fn: () => { created.forEach((n) => F.photos.remove(n)); ctl.close(); } },
          { title: isNew ? '贴上去' : '保存', fn: () => { if (!isNew) { const kept = new Set(draft.images || []); (magnet.images || []).forEach((o) => { if (o && !kept.has(o)) F.photos.remove(o); }); } ctl.close(() => onSave(draft)); } });
        el.appendChild(head.bar);
        const canvas = h('div', 'frame-canvas');
        const tools = h('div', 'frame-tools');
        el.append(canvas, tools);
        var render = () => {
          renderTools();
          canvas.innerHTML = '';
          const cw = canvas.clientWidth || 360, ch = canvas.clientHeight || 360;
          const base = draft.style === 'strip' ? [118, 361] : [196, 232];
          const k = Math.min((cw * 0.8) / base[0], (ch * 0.88) / base[1]);
          const mv = F.magnetEl(draft, k);
          mv.classList.add('editing');
          mv.querySelectorAll('.photo-cell').forEach((cell) => {
            const i = Number(cell.dataset.index);
            cell.classList.toggle('active', slots > 1 && i === active);
            let st = null;
            cell.addEventListener('pointerdown', (e) => { e.preventDefault(); cell.setPointerCapture(e.pointerId); st = { x: e.clientX, y: e.clientY, moved: false }; });
            cell.addEventListener('pointermove', (e) => {
              if (!st) return;
              const dx = e.clientX - st.x, dy = e.clientY - st.y;
              if (!st.moved && Math.hypot(dx, dy) < 6) return;
              st.moved = true;
              if (i !== active || !nameAt(i)) return;
              const crop = F.crop(draft, i), w = cell.clientWidth, hh = cell.clientHeight;
              const img = cell.querySelector('img');
              if (img) img.style.transform = `translate(calc(-50% + ${(crop.u + dx / w) * w}px), calc(-50% + ${(crop.v + dy / hh) * hh}px)) rotate(${crop.rot}deg)`;
            });
            cell.addEventListener('pointerup', (e) => {
              if (!st) return;
              const dx = e.clientX - st.x, dy = e.clientY - st.y, moved = st.moved; st = null;
              if (!moved || i !== active) { active = i; if (!nameAt(i)) replace(i); else render(); return; }
              if (!nameAt(i)) return;
              const crop = F.crop(draft, i), w = cell.clientWidth, hh = cell.clientHeight;
              setCrop(i, { u: F.clamp(crop.u + dx / w, -1, 1), v: F.clamp(crop.v + dy / hh, -1, 1), scale: crop.scale, rot: crop.rot });
              render();
            });
            cell.addEventListener('wheel', (e) => { if (i !== active || !nameAt(i)) return; e.preventDefault(); const crop = F.crop(draft, i); setCrop(i, Object.assign({}, crop, { scale: F.clamp(crop.scale * (e.deltaY < 0 ? 1.08 : 0.92), 0.3, 5) })); render(); }, { passive: false });
          });
          canvas.appendChild(mv);
        };
        const renderTools = () => {
          tools.innerHTML = '';
          tools.appendChild(h('div', 'hint center', slots > 1 ? `点一格选中 · 拖动挪位置 · 第 ${active + 1} 格` : '拖动挪位置'));
          const row1 = h('div', 'btn-row');
          const has = !!nameAt(active);
          const b = (title, icon, fn, dis) => { const x = h('button', 'pill light', F.icon(icon, 13) + `<span>${title}</span>`); x.disabled = !!dis; x.addEventListener('click', fn); row1.appendChild(x); };
          b(has ? '换这张' : '加一张', 'photo', () => replace(active));
          b('放大', 'plus', () => { const c = F.crop(draft, active); setCrop(active, Object.assign({}, c, { scale: F.clamp(c.scale * 1.15, 0.3, 5) })); render(); }, !has);
          b('转 90°', 'rotate', () => { const c = F.crop(draft, active); setCrop(active, Object.assign({}, c, { rot: c.rot + 90 })); render(); }, !has);
          b('摆正', 'rotate', () => { setCrop(active, { u: 0, v: 0, scale: 1, rot: 0 }); render(); }, !has);
          tools.appendChild(row1);
          const pins = h('div', 'pin-row');
          F.PINS.forEach((p) => {
            const on = (draft.pin || 'pink') === p.key;
            const x = h('button', 'pin-pick' + (on ? ' on' : ''));
            const sw = h('div', 'pin-swatch');
            if (p.key === 'tape') sw.innerHTML = '<i class="sw-tape"></i>'; else if (p.key === 'none') sw.innerHTML = '<i class="sw-none"></i>'; else { const c = F.pinColors(p.key); sw.innerHTML = `<i class="sw-dot" style="background:radial-gradient(circle at 35% 30%, ${c[0]}, ${c[1]})"></i>`; }
            x.append(sw, h('span', '', F.esc(p.name)));
            x.addEventListener('click', () => { draft.pin = p.key; render(); });
            pins.appendChild(x);
          });
          tools.appendChild(pins);
          const frames = h('div', 'frame-row');
          F.FRAMES.forEach((f) => {
            const x = h('button', 'frame-pick' + (draft.hex === f.hex ? ' on' : ''), `<i style="background:${f.hex}"></i><span>${F.esc(f.name)}</span>`);
            x.addEventListener('click', () => { draft.hex = f.hex; render(); });
            frames.appendChild(x);
          });
          tools.appendChild(frames);
          const cap = h('input', 'text-input'); cap.placeholder = draft.style === 'strip' ? '底下印的字（默认是日期）' : '底下写一句（可不填）'; cap.value = draft.text || '';
          cap.addEventListener('input', () => { draft.text = cap.value; const c = canvas.querySelector('.magnet-cap'); if (c) c.textContent = cap.value; });
          tools.appendChild(cap);
        };
        requestAnimationFrame(() => F.later(320, render));
      },
    });
  };
})();
