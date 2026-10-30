'use strict';
// 冰箱 · 共享视图：便签、固定物、贴纸、门上提醒、照片贴、漆面换色（舞台单位 = 开门图像素）
(function () {
  const F = window.Fridge;
  const h = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  F.h = h;

  // ---------- 小图标（代替 SF Symbols） ----------
  const ICONS = {
    plus: '<path d="M12 5v14M5 12h14"/>',
    xmark: '<path d="M6 6l12 12M18 6L6 18"/>',
    trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
    pencil: '<path d="M4 20l4-1L19 8l-3-3L5 16zM14 7l3 3"/>',
    fork: '<path d="M7 3v7a3 3 0 0 0 3 3v8M7 3v4M10 3v4M17 3c-2 1-3 4-3 7h3v11"/>',
    note: '<path d="M6 3h9l5 5v13H6zM15 3v5h5M9 12h6M9 16h6"/>',
    photo: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="10" r="1.6"/><path d="M21 16l-5-5-8 8"/>',
    door: '<rect x="5" y="3" width="14" height="18" rx="1.5"/><circle cx="15" cy="12" r="1"/>',
    brush: '<path d="M14 3l7 7-9 9-7-7zM5 12l-2 7 7-2"/>',
    heart: '<path d="M12 20s-7-4.5-9-9a5 5 0 0 1 9-4 5 5 0 0 1 9 4c-2 4.5-9 9-9 9z"/>',
    hand: '<path d="M8 12V6a1.5 1.5 0 0 1 3 0v5M11 11V4a1.5 1.5 0 0 1 3 0v7M14 11V5a1.5 1.5 0 0 1 3 0v8M17 13V9a1.5 1.5 0 0 1 3 0v6c0 4-3 6-6 6s-5-1-7-4l-3-5a1.5 1.5 0 0 1 2.6-1.5L8 13"/>',
    layers: '<path d="M12 3l9 5-9 5-9-5zM3 13l9 5 9-5M3 17l9 5 9-5"/>',
    ellipsis: '<circle cx="5" cy="12" r="1.6" fill="currentColor"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/><circle cx="19" cy="12" r="1.6" fill="currentColor"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    clock: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4l3 2"/>',
    rotate: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 5v6h-6"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    circle: '<circle cx="12" cy="12" r="8"/>',
    check: '<path d="M5 12l5 5 9-10"/>',
    camera: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.2"/>',
    scissors: '<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><path d="M8 8l12 10M8 16L20 6"/>',
    strip: '<rect x="6" y="3" width="12" height="18" rx="1"/><path d="M6 9h12M6 15h12"/>',
  };
  F.icon = (name, size = 14) => `<svg class="ic" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">${ICONS[name] || ''}</svg>`;

  // ---------- 便签上的装饰贴纸 ----------
  const DECO_SVG = {
    heart: '<path d="M12 21s-7.5-4.6-9.6-9.2A5.4 5.4 0 0 1 12 6.2a5.4 5.4 0 0 1 9.6 5.6C19.5 16.4 12 21 12 21z"/>',
    star: '<path d="M12 2.5l2.9 6.3 6.9.8-5.1 4.7 1.4 6.8L12 17.7l-6.1 3.4 1.4-6.8L2.2 9.6l6.9-.8z"/>',
    sparkles: '<path d="M9 2l2.2 5.8L17 10l-5.8 2.2L9 18l-2.2-5.8L1 10l5.8-2.2zM18.5 13l1.2 3.3 3.3 1.2-3.3 1.2-1.2 3.3-1.2-3.3-3.3-1.2 3.3-1.2z"/>',
    flower: '<circle cx="12" cy="5.5" r="3.6"/><circle cx="18.2" cy="10" r="3.6"/><circle cx="15.8" cy="17.3" r="3.6"/><circle cx="8.2" cy="17.3" r="3.6"/><circle cx="5.8" cy="10" r="3.6"/><circle cx="12" cy="12" r="3" fill="#F6D77C"/>',
    cloud: '<path d="M7 19a4.5 4.5 0 0 1-.6-9A6.5 6.5 0 0 1 19 9.2 4.9 4.9 0 0 1 18.6 19z"/>',
    moon: '<path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z"/>',
    paw: '<circle cx="6" cy="9" r="2.2"/><circle cx="10" cy="5" r="2.2"/><circle cx="14.5" cy="5" r="2.2"/><circle cx="18.5" cy="9" r="2.2"/><path d="M12 10c3.5 0 6 3.2 6 6 0 2-1.5 3-3 3-1.3 0-2-.6-3-.6s-1.7.6-3 .6c-1.5 0-3-1-3-3 0-2.8 2.5-6 6-6z"/>',
    leaf: '<path d="M4 20C5 10 11 4 21 3c-.5 10-6.5 16-17 17z"/><path d="M4 20l11-11" stroke="#fff" stroke-width="1.5" fill="none"/>',
    music: '<path d="M9 19.5a3 3 0 1 1 0-6c.4 0 .7 0 1 .2V5l11-2.5v12a3 3 0 1 1-2-2.8V6L12 7.5v12a3 3 0 0 1-3 0z"/>',
    smile: '<circle cx="12" cy="12" r="9.5"/><circle cx="8.8" cy="10" r="1.3" fill="#fff"/><circle cx="15.2" cy="10" r="1.3" fill="#fff"/><path d="M8 14c1 2 2.5 3 4 3s3-1 4-3" stroke="#fff" stroke-width="1.8" fill="none" stroke-linecap="round"/>',
    gift: '<path d="M3 9h18v4H3zM5 13h14v8H5zM12 9v12"/><path d="M12 9c-2-3-5-4-6-2s2 3 6 2zM12 9c2-3 5-4 6-2s-2 3-6 2z" fill="#fff" fill-opacity=".5"/>',
    crown: '<path d="M3 18L2 7l5 4 5-7 5 7 5-4-1 11z"/>',
  };
  F.decoGlyph = (kind, size = 40) => {
    const d = F.DECOS.find((x) => x.id === kind) || F.DECOS[0];
    return `<svg class="deco-glyph" width="${size * 1.3}" height="${size * 1.3}" viewBox="-3 -3 30 30" fill="${d.hex}" stroke="#fff" stroke-width="2.4" stroke-linejoin="round" paint-order="stroke">${DECO_SVG[d.id] || DECO_SVG.heart}</svg>`;
  };

  // ---------- 固定便签用的东西（磁铁 / 胶带 / 贴纸） ----------
  F.attachEl = (kind) => {
    const el = h('div', 'attach attach-' + kind);
    switch (kind) {
      case 'magnetPink': el.innerHTML = F.magnetDot('#E58F8F'); break;
      case 'magnetBlue': el.innerHTML = F.magnetDot('#86B3D1'); break;
      case 'magnetMint': el.innerHTML = F.magnetDot('#8CC7AE'); break;
      case 'washiStripe': case 'washiDot': case 'clearTape': el.innerHTML = '<div class="tape"></div>'; break;
      case 'heart': el.innerHTML = `<svg width="38" height="38" viewBox="-2 -2 28 28" fill="#F28CA0" stroke="#fff" stroke-width="2.2" paint-order="stroke" stroke-linejoin="round">${DECO_SVG.heart}</svg>`; break;
      case 'flower': {
        let s = '';
        for (let i = 0; i < 5; i++) s += `<circle cx="20" cy="10" r="9" fill="#F7C8D4" transform="rotate(${i * 72} 20 20)"/>`;
        el.innerHTML = `<svg width="40" height="40" viewBox="0 0 40 40">${s}<circle cx="20" cy="20" r="6" fill="#F6D77C"/></svg>`;
        break;
      }
    }
    return el;
  };
  F.magnetDot = (color, size = 30) => `<div class="magnet-dot" style="--c:${color};width:${size}px;height:${size}px"></div>`;

  // ---------- 便签（宽 228） ----------
  F.noteEl = (note, opts = {}) => {
    const el = h('div', `note paper-${note.paper || 'yellow'} font-${note.font || 'kuaile'}`);
    el.style.setProperty('--fs', (note.fontSize || 26) + 'px');
    el.style.setProperty('--ls', (note.paper === 'lined' || note.paper === 'index' ? 9 : 4) + 'px');
    const paper = h('div', 'note-paper');
    const content = h('div', 'note-content');
    const text = h('div', 'note-text');
    text.textContent = note.text || '';
    content.appendChild(text);
    if (note.author === 'partner') content.appendChild(h('div', 'note-sign', '— TA'));
    paper.appendChild(content);
    const decos = h('div', 'note-decos');
    (note.decos || []).forEach((d) => {
      const de = h('div', 'deco', F.decoGlyph(d.kind, 40));
      de.dataset.decoId = d.id;
      de.style.left = d.x + 'px'; de.style.top = d.y + 'px';
      de.style.transform = `translate(-50%,-50%) rotate(${d.tilt || 0}deg)`;
      decos.appendChild(de);
    });
    paper.appendChild(decos);
    el.appendChild(paper);
    if (opts.attach !== false) el.appendChild(F.attachEl(note.attach || 'magnetBlue'));
    return el;
  };

  // ---------- 贴纸 ----------
  F.stickerEl = (item, side, opts = {}) => {
    const el = h('div', 'sticker');
    el.style.width = side + 'px'; el.style.height = side + 'px';
    el.dataset.itemId = item.id;
    const body = h('div', 'sticker-body');
    const content = h('div', 'sticker-content curl-content');
    const img = h('img');
    img.src = item.stickerSource === 'photo' ? (F.photos.get(item.stickerAsset) || {}).data || F.stickerURL('unknown_food_box') : F.stickerURL(item.stickerAsset || 'unknown_food_box');
    img.alt = item.name || '';
    img.draggable = false;
    content.appendChild(img);
    const tone = F.due.tone(item);
    if (opts.dot && tone !== 'fine' && tone !== 'none') {
      const dot = h('div', 'due-dot');
      dot.style.background = F.due.color(tone);
      content.appendChild(dot);
    }
    body.appendChild(content);
    el.appendChild(body);
    return el;
  };

  // ---------- 门上的提醒：磁铁压着贴纸，下面一张小纸签 ----------
  F.reminderEl = (item) => {
    const el = h('div', 'reminder');
    el.dataset.itemId = item.id;
    const curl = h('div', 'rem-curl');
    const content = h('div', 'rem-content curl-content');
    content.appendChild(F.stickerEl(item, 128));
    const label = h('div', 'rem-label');
    label.innerHTML = `<div class="rem-name">${F.esc(item.name)}</div><div class="rem-due" style="color:${F.due.color(F.due.tone(item))}">${F.esc(F.due.label(item))}</div>`;
    content.appendChild(label);
    curl.appendChild(content);
    el.appendChild(curl);
    const mag = h('div', 'rem-magnet', F.magnetDot('#E58F8F'));
    el.appendChild(mag);
    return el;
  };

  // ---------- 门上的照片：抠图贴 / 拍立得 / 四格 ----------
  F.photoCellEl = (magnet, index, width, height, size) => {
    const cell = h('div', 'photo-cell');
    cell.style.width = width + 'px'; cell.style.height = height + 'px';
    cell.dataset.index = index;
    const name = (magnet.images || [])[index];
    const rec = F.photos.get(name);
    if (rec) {
      const crop = F.crop(magnet, index);
      const aspect = rec.w / Math.max(rec.h, 1);
      const fw = aspect > width / height ? height * aspect : width;
      const fh = aspect > width / height ? height : width / aspect;
      const img = h('img');
      img.src = rec.data; img.draggable = false;
      img.style.width = fw * crop.scale + 'px'; img.style.height = fh * crop.scale + 'px';
      img.style.transform = `translate(calc(-50% + ${crop.u * width}px), calc(-50% + ${crop.v * height}px)) rotate(${crop.rot}deg)`;
      cell.appendChild(img);
    } else {
      cell.classList.add('empty');
    }
    return cell;
  };
  F.pinEl = (key, size = 1) => {
    key = key || 'pink';
    if (key === 'none') return null;
    if (key === 'tape') { const t = h('div', 'pin-tape'); t.style.width = 58 * size + 'px'; t.style.height = 18 * size + 'px'; return t; }
    const c = F.pinColors(key);
    const d = h('div', 'pin-dot');
    d.style.width = 26 * size + 'px'; d.style.height = 26 * size + 'px';
    d.style.background = `radial-gradient(circle at 35% 30%, ${c[0]}, ${c[1]})`;
    return d;
  };
  F.magnetEl = (magnet, size = 1) => {
    const el = h('div', 'magnet style-' + magnet.style);
    el.dataset.magnetId = magnet.id;
    if (magnet.style === 'photo') {
      el.style.width = 130 * size + 'px'; el.style.height = 130 * size + 'px';
      const rec = F.photos.get((magnet.images || [])[0]);
      if (rec) { const img = h('img'); img.src = rec.data; img.draggable = false; el.appendChild(img); } else el.classList.add('empty');
      return el;
    }
    el.style.background = magnet.hex;
    el.style.color = F.frameInk(magnet.hex);
    if (magnet.style === 'polaroid') {
      const w = 196 * size, inner = w - 24 * size;
      el.style.padding = `${12 * size}px ${12 * size}px 0`;
      el.appendChild(F.photoCellEl(magnet, 0, inner, inner, size));
      const cap = h('div', 'magnet-cap'); cap.textContent = magnet.text || '';
      cap.style.width = inner + 'px'; cap.style.height = 48 * size + 'px'; cap.style.fontSize = 19 * size + 'px';
      el.appendChild(cap);
    } else {
      const inner = 100 * size;
      el.style.padding = `${9 * size}px ${9 * size}px ${2 * size}px`;
      el.style.gap = 7 * size + 'px';
      for (let i = 0; i < 4; i++) el.appendChild(F.photoCellEl(magnet, i, inner, inner * 0.75, size));
      const cap = h('div', 'magnet-cap mono'); cap.textContent = magnet.text || '';
      cap.style.width = inner + 'px'; cap.style.height = 22 * size + 'px'; cap.style.fontSize = 11 * size + 'px';
      el.appendChild(cap);
    }
    const pin = F.pinEl(magnet.pin, size);
    if (pin) { const wrap = h('div', 'magnet-pin'); wrap.style.top = -9 * size + 'px'; wrap.appendChild(pin); el.appendChild(wrap); }
    return el;
  };

  // ---------- 漆面换色：原图 + (明暗层 × 颜色) + 高光 ----------
  const ART_DIR = '../assets/fridge/';
  const artCache = {}; // name|hex → objectURL
  const imgCache = {};
  const loadImg = (src) => imgCache[src] || (imgCache[src] = new Promise((res) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = src; }));
  F.tintedArt = async (name, hex) => {
    const key = name + '|' + hex;
    if (artCache[key]) return artCache[key];
    const shade = await loadImg(ART_DIR + name + '_shade.png');
    if (!shade) return null;
    const c = document.createElement('canvas');
    c.width = shade.naturalWidth; c.height = shade.naturalHeight;
    const ctx = c.getContext('2d');
    ctx.drawImage(shade, 0, 0);
    ctx.globalCompositeOperation = 'multiply';
    ctx.fillStyle = hex; ctx.fillRect(0, 0, c.width, c.height);
    ctx.globalCompositeOperation = 'destination-in';
    ctx.drawImage(shade, 0, 0);
    const url = await new Promise((res) => c.toBlob((b) => res(b ? URL.createObjectURL(b) : c.toDataURL()), 'image/png'));
    artCache[key] = url;
    return url;
  };
  F.artEl = (name, rect) => {
    const el = h('div', 'art');
    el.dataset.art = name;
    if (rect) { el.style.left = rect[0] + 'px'; el.style.top = rect[1] + 'px'; el.style.width = rect[2] + 'px'; el.style.height = rect[3] + 'px'; }
    el.innerHTML = `<img class="art-base" src="${ART_DIR}${name}.png" draggable="false"><img class="art-paint" draggable="false"><img class="art-gloss" src="${ART_DIR}${name}_gloss.png" draggable="false">`;
    F.applyPaintTo(el, F.store.paintHex);
    return el;
  };
  F.applyPaintTo = async (el, hex) => {
    const paint = el.querySelector('.art-paint'), gloss = el.querySelector('.art-gloss');
    if (!hex) { paint.style.display = 'none'; gloss.style.display = 'none'; paint.removeAttribute('src'); return; }
    const url = await F.tintedArt(el.dataset.art, hex);
    if (!url || F.store.paintHex !== hex) return;
    paint.src = url; paint.style.display = 'block'; gloss.style.display = 'block';
  };
  F.repaintAll = (root = document) => root.querySelectorAll('.art').forEach((el) => F.applyPaintTo(el, F.store.paintHex));
})();
