'use strict';
// 冰箱 · 数据层（对应 iOS 版 FridgeModels.swift）
// 坐标统一用「开门图」原图像素 941×1672，页面再整体按比例缩放。
(function () {
  const F = (window.Fridge = window.Fridge || {});

  F.CANVAS = { w: 941, h: 1672 };
  F.RECTS = {
    body: [30, 230, 551, 1240],
    doorTopOut: [37, 237, 541, 428],
    doorBottomOut: [37, 665, 541, 757],
    doorTopIn: [578, 180, 338, 488],
    doorBottomIn: [548, 665, 368, 865],
    front: [37, 237, 541, 1185],
    openFrame: [30, 180, 886, 1350],
    cavities: [[70, 318, 498, 342], [70, 693, 498, 699]],
  };
  F.HINGE_X = 578;

  // 分区：贴纸底边落在 rect 的 maxY（站在隔板 / 门架上）
  F.ZONES = [
    { id: 'freezerTop', title: '冷冻 · 上层', rect: [112, 390, 414, 104], door: false, frozen: true },
    { id: 'freezer', title: '冷冻 · 下层', rect: [112, 528, 414, 112], door: false, frozen: true },
    { id: 'freezerDoor', title: '冷冻门架 · 上', rect: [592, 396, 200, 92], door: true, frozen: true },
    { id: 'freezerDoorLow', title: '冷冻门架 · 下', rect: [592, 546, 200, 92], door: true, frozen: true },
    { id: 'chillTop', title: '冷藏 · 上层', rect: [112, 770, 410, 114], door: false },
    { id: 'chillMid', title: '冷藏 · 中层', rect: [112, 906, 410, 114], door: false },
    { id: 'chillLow', title: '冷藏 · 下层', rect: [118, 1040, 400, 104], door: false },
    { id: 'crisper', title: '蔬果抽屉', rect: [132, 1204, 378, 122], door: false },
    { id: 'doorTop', title: '门架 · 上', rect: [566, 786, 240, 86], door: true },
    { id: 'doorMid', title: '门架 · 中', rect: [564, 986, 244, 100], door: true },
    { id: 'doorLow', title: '门架 · 下', rect: [564, 1250, 244, 124], door: true },
  ];
  const zoneMap = {};
  F.ZONES.forEach((z) => (zoneMap[z.id] = z));
  F.zone = (id) => zoneMap[id] || zoneMap.chillMid;
  F.BODY_ZONES = ['freezerTop', 'freezer', 'chillTop', 'chillMid', 'chillLow', 'crisper'];
  F.DOOR_ZONES = ['freezerDoor', 'freezerDoorLow', 'doorTop', 'doorMid', 'doorLow'];

  F.CATEGORIES = [
    { id: 'fruit', title: '水果' }, { id: 'veggie', title: '蔬菜' }, { id: 'protein', title: '肉蛋海鲜' },
    { id: 'dairy', title: '奶制品' }, { id: 'meal', title: '主食熟食' }, { id: 'drink', title: '饮品酱料' },
    { id: 'frozen', title: '冷冻' }, { id: 'other', title: '自定义' },
  ];
  const CAT = {
    fruit: ['strawberry', 'blueberries', 'grapes', 'banana', 'apple', 'orange'],
    veggie: ['lettuce', 'tomato', 'broccoli', 'carrot', 'cucumber', 'bell_pepper', 'mushroom', 'potato', 'onion'],
    protein: ['beef', 'chicken', 'fish', 'shrimp', 'bacon', 'eggs'],
    dairy: ['yogurt', 'cheese', 'butter', 'milk'],
    meal: ['rice', 'noodles', 'soup', 'leftovers', 'lunchbox', 'bread'],
    drink: ['juice', 'soda', 'water', 'sauce', 'glass_jar'],
    frozen: ['ice_cream', 'frozen_dumplings', 'frozen_meat'],
  };
  F.category = (asset) => {
    for (const k in CAT) if (CAT[k].includes(asset)) return k;
    return 'other';
  };

  const E = (asset, name, zone, shelfDays, unit, isDrink) => ({ asset, name, zone, shelfDays, unit, isDrink: !!isDrink });
  F.CATALOG = [
    E('strawberry', '草莓', 'chillTop', 3, '盒'), E('blueberries', '蓝莓', 'chillTop', 5, '盒'), E('grapes', '葡萄', 'chillTop', 6, '串'),
    E('lettuce', '生菜', 'crisper', 4, '颗'), E('tomato', '西红柿', 'crisper', 7, '个'), E('broccoli', '西兰花', 'crisper', 5, '颗'),
    E('carrot', '胡萝卜', 'crisper', 14, '根'), E('cucumber', '黄瓜', 'crisper', 6, '根'), E('bell_pepper', '彩椒', 'crisper', 7, '个'),
    E('mushroom', '蘑菇', 'crisper', 4, '盒'), E('potato', '土豆', 'crisper', 20, '个'), E('onion', '洋葱', 'crisper', 20, '个'),
    E('apple', '苹果', 'crisper', 14, '个'), E('orange', '橙子', 'crisper', 14, '个'), E('banana', '香蕉', 'chillTop', 4, '根'),
    E('eggs', '鸡蛋', 'chillTop', 20, '个'), E('yogurt', '酸奶', 'chillTop', 7, '杯'), E('cheese', '芝士', 'chillTop', 20, '块'),
    E('butter', '黄油', 'chillTop', 30, '块'), E('beef', '牛肉', 'chillLow', 2, '盒'), E('chicken', '鸡肉', 'chillLow', 2, '盒'),
    E('fish', '鱼', 'chillLow', 1, '块'), E('shrimp', '虾', 'freezer', 60, '袋'), E('bacon', '培根', 'chillLow', 7, '包'),
    E('rice', '米饭', 'chillMid', 2, '碗'), E('noodles', '面条', 'chillMid', 3, '份'), E('soup', '汤', 'chillMid', 2, '碗'),
    E('leftovers', '剩菜盒', 'chillMid', 2, '盒'), E('lunchbox', '饭盒', 'chillMid', 2, '盒'), E('bread', '面包', 'chillMid', 5, '袋'),
    E('milk', '牛奶', 'doorMid', 5, '瓶', true), E('juice', '果汁', 'doorMid', 5, '瓶', true), E('soda', '汽水', 'doorLow', 90, '罐', true),
    E('water', '矿泉水', 'doorLow', 180, '瓶', true), E('sauce', '酱料', 'doorTop', 60, '瓶'), E('glass_jar', '果酱', 'doorTop', 30, '罐'),
    E('ice_cream', '冰淇淋', 'freezer', 60, '盒'), E('frozen_dumplings', '速冻水饺', 'freezer', 90, '袋'), E('frozen_meat', '冷冻肉', 'freezer', 90, '块'),
    E('paper_bag', '袋装', 'chillMid', 3, '袋'), E('unknown_food_box', '盒装', 'chillMid', 3, '盒'),
  ];
  F.entry = (asset) => F.CATALOG.find((e) => e.asset === asset) || null;
  F.stickerURL = (asset) => '../assets/stickers/' + asset + '.png';

  F.PAPERS = [
    { id: 'yellow', title: '黄色便利贴' }, { id: 'lined', title: '横格撕边' }, { id: 'kraft', title: '牛皮纸' },
    { id: 'grid', title: '方格纸' }, { id: 'pink', title: '粉色爱心' }, { id: 'index', title: '索引卡' },
  ];
  F.ATTACHES = [
    { id: 'magnetPink', title: '粉磁铁' }, { id: 'magnetBlue', title: '蓝磁铁' }, { id: 'magnetMint', title: '绿磁铁' },
    { id: 'washiStripe', title: '条纹胶带' }, { id: 'washiDot', title: '波点胶带' }, { id: 'clearTape', title: '透明胶带' },
    { id: 'heart', title: '爱心贴' }, { id: 'flower', title: '小花贴' },
  ];
  F.isTape = (attach) => attach === 'washiStripe' || attach === 'washiDot' || attach === 'clearTape';
  F.FONTS = [
    { id: 'kuaile', title: '快乐体' }, { id: 'wenkai', title: '文楷' }, { id: 'rounded', title: '手写' }, { id: 'system', title: '系统' },
  ];
  F.DECOS = [
    { id: 'heart', hex: '#F28CA0' }, { id: 'star', hex: '#F4C94E' }, { id: 'sparkles', hex: '#E3AE3C' }, { id: 'flower', hex: '#EE9CB4' },
    { id: 'cloud', hex: '#9EC3E6' }, { id: 'moon', hex: '#EFC75E' }, { id: 'paw', hex: '#B98A6A' }, { id: 'leaf', hex: '#7DBE9E' },
    { id: 'music', hex: '#9B8AD0' }, { id: 'smile', hex: '#F2B35B' }, { id: 'gift', hex: '#E58F8F' }, { id: 'crown', hex: '#E8B94A' },
  ];
  F.PAINTS = [
    { name: '奶油', hex: null }, { name: '薄荷绿', hex: '#A9D9C6' }, { name: '樱花粉', hex: '#F3C3CC' }, { name: '天蓝', hex: '#B5D3EC' },
    { name: '黄油黄', hex: '#F6DE8D' }, { name: '鼠尾草', hex: '#B7C6A5' }, { name: '奶咖', hex: '#D8BFA5' },
  ];
  F.FRAMES = [
    { name: '白', hex: '#FFFDF8' }, { name: '奶油', hex: '#F4E6CC' }, { name: '粉', hex: '#F6D3D8' }, { name: '黑', hex: '#2B2522' },
  ];
  F.PINS = [
    { key: 'pink', name: '粉磁铁' }, { key: 'blue', name: '蓝磁铁' }, { key: 'mint', name: '绿磁铁' },
    { key: 'gold', name: '金磁铁' }, { key: 'tape', name: '胶带' }, { key: 'none', name: '不贴' },
  ];
  F.pinColors = (key) => ({
    blue: ['#B5D3EE', '#6F9CC8'], mint: ['#BFE3CF', '#6FAE8C'], gold: ['#F4DDA0', '#C99A3E'],
  })[key] || ['#F2A7B0', '#C9707D'];
  F.frameInk = (hex) => (hex === '#2B2522' ? '#F4ECE2' : '#6E5240');

  // ---------- 工具 ----------
  F.uid = () => (crypto.randomUUID ? crypto.randomUUID() : 'id-' + Math.random().toString(36).slice(2) + Date.now().toString(36));
  F.tilt = (id) => {
    let sum = 0;
    for (const ch of String(id)) sum += ch.codePointAt(0);
    return (sum % 11) - 5;
  };
  F.rand = (a, b) => a + Math.random() * (b - a);
  F.clamp = (v, a, b) => Math.min(Math.max(v, a), b);
  F.startOfDay = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
  F.addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
  F.iso = (d) => (d ? new Date(d).toISOString() : null);

  // 和 iOS / 后端互通的格式：日期是 Swift JSONEncoder 默认的「2001-01-01 起的秒数」，网页里存的是 ISO 字符串
  const APPLE_EPOCH = 978307200;
  const DATE_FIELDS = { items: ['addedAt', 'expiresAt', 'eatBy'], notes: ['createdAt'] };
  const mapDates = (snap, fn) => {
    const out = JSON.parse(JSON.stringify(snap));
    Object.entries(DATE_FIELDS).forEach(([list, fields]) => (out[list] || []).forEach((row) => fields.forEach((f) => {
      if (row[f] != null) row[f] = fn(row[f]);
    })));
    out.items = out.items || []; out.notes = out.notes || []; out.magnets = out.magnets || [];
    return out;
  };
  F.toServer = (snap) => mapDates(snap, (iso) => new Date(iso).getTime() / 1000 - APPLE_EPOCH);
  F.fromServer = (value) => mapDates(value, (v) => (typeof v === 'number' ? new Date((v + APPLE_EPOCH) * 1000).toISOString() : v));
  F.sync = (typeof window !== 'undefined' && window.FRIDGE_SYNC && window.FRIDGE_SYNC.url) ? window.FRIDGE_SYNC : null;
  F.date = (s) => (s ? new Date(s) : null);
  F.fmtDate = (s) => {
    const d = F.date(s);
    if (!d || isNaN(d)) return '—';
    const wd = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][d.getDay()];
    return `${d.getMonth() + 1}月${d.getDate()}日 ${wd}`;
  };
  F.dateInput = (s) => {
    const d = F.date(s) || new Date();
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  };
  F.quantityText = (item) => {
    const q = Math.round(item.quantity) === item.quantity ? String(item.quantity) : item.quantity.toFixed(1);
    return `${q} ${item.unit}`;
  };
  F.esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // ---------- 到期 ----------
  F.due = {
    daysLeft(item, now = new Date()) {
      const due = F.date(item.eatBy || item.expiresAt);
      if (!due || isNaN(due)) return null;
      return Math.round((F.startOfDay(due) - F.startOfDay(now)) / 86400000);
    },
    tone(item) {
      const d = this.daysLeft(item);
      if (d == null) return 'none';
      if (d < 0) return 'overdue';
      if (d === 0) return 'today';
      if (d <= 2) return 'soon';
      return 'fine';
    },
    label(item) {
      const d = this.daysLeft(item);
      const due = F.date(item.eatBy || item.expiresAt);
      if (d == null || !due) return '不着急';
      const e = F.entry(item.stickerAsset);
      const verb = e && e.isDrink ? '喝' : '吃';
      if (d < 0) return `过期${-d}天啦`;
      if (d === 0) return `今天${verb}掉`;
      if (d === 1) return `明天${verb}完`;
      if (d <= 3) return `还剩${d}天`;
      if (d <= 6) return `${['周日', '周一', '周二', '周三', '周四', '周五', '周六'][due.getDay()]}前${verb}完`;
      return `还能放${d}天`;
    },
    color(tone) {
      return { overdue: '#C9524F', today: '#D9744A', soon: '#C98A2E', fine: '#6E9A6A', none: '#9A8A89' }[tone];
    },
    expired(item) {
      const due = F.date(item.expiresAt || item.eatBy);
      if (!due) return false;
      return F.startOfDay(due) < F.startOfDay(new Date());
    },
  };

  // ---------- 建对象 ----------
  F.makeItem = (o) => Object.assign({
    id: F.uid(), name: '', quantity: 1, unit: '份', zone: 'chillMid', positionX: 0.5, positionY: 1,
    addedAt: F.iso(new Date()), expiresAt: null, eatBy: null, stickerSource: 'builtIn', stickerAsset: 'unknown_food_box',
    notes: '', addedBy: 'me', doorX: null, doorY: null,
  }, o);
  F.makeNote = (o) => Object.assign({
    id: F.uid(), text: '', author: 'me', x: 0.5, y: 0.3, tilt: 0, createdAt: F.iso(new Date()),
    paper: 'yellow', attach: 'magnetBlue', font: 'kuaile', fontSize: 26, decos: [], z: null,
  }, o);
  F.makeMagnet = (o) => Object.assign({
    id: F.uid(), style: 'polaroid', text: '', hex: '#FFFDF8', x: 0.5, y: 0.2, tilt: 0, images: [], crops: [], pin: 'pink', z: null,
  }, o);
  F.crop = (m, i) => (m.crops && m.crops[i]) || { u: 0, v: 0, scale: 1, rot: 0 };

  // ---------- 示例 ----------
  F.sample = () => {
    const now = new Date();
    const make = (asset, zone, days, qty = 1, name = null, by = 'me', note = '', added = -1) => {
      const e = F.entry(asset);
      const due = F.addDays(now, days);
      return F.makeItem({
        name: name || (e ? e.name : asset), quantity: qty, unit: e ? e.unit : '份', zone,
        addedAt: F.iso(F.addDays(now, added)), expiresAt: F.iso(F.addDays(due, 1)), eatBy: F.iso(due),
        stickerAsset: asset, notes: note, addedBy: by,
      });
    };
    const items = [
      make('frozen_dumplings', 'freezer', 40, 2),
      make('ice_cream', 'freezerTop', 25, 1, null, 'partner', '给你囤的，一次只许吃两勺'),
      make('frozen_meat', 'freezer', 30),
      make('shrimp', 'freezer', 45),
      make('bacon', 'freezerDoor', 20),
      make('yogurt', 'chillTop', 2, 3),
      make('strawberry', 'chillTop', 1),
      make('eggs', 'chillTop', 12, 6),
      make('cheese', 'chillTop', 9),
      make('leftovers', 'chillMid', 1, 1, '昨晚的红烧肉', 'partner', '热一下就能吃'),
      make('lunchbox', 'chillMid', 0, 1, '午饭便当'),
      make('soup', 'chillMid', 2),
      make('beef', 'chillLow', 1),
      make('chicken', 'chillLow', 3),
      make('lettuce', 'crisper', 3),
      make('carrot', 'crisper', 10, 3),
      make('broccoli', 'crisper', 4),
      make('tomato', 'crisper', 5, 4),
      make('cucumber', 'crisper', 5, 2),
      make('apple', 'crisper', 12, 5),
      make('sauce', 'doorTop', 60),
      make('glass_jar', 'doorTop', 30),
      make('milk', 'doorMid', 2, 1, null, 'partner', '周五前喝完，不许又放过期'),
      make('juice', 'doorMid', 5),
      make('water', 'doorLow', 120, 4),
      make('soda', 'doorLow', 80, 2),
    ];
    F.ZONES.forEach((z) => {
      let order = 0;
      items.forEach((it) => { if (it.zone === z.id) it.positionX = order++; });
    });
    const notes = [
      F.makeNote({ text: '牛奶周五前喝完哦\n不许又放过期', author: 'partner', x: 0.6, y: 0.15, tilt: 4, paper: 'lined', attach: 'washiStripe' }),
      F.makeNote({ text: '要买：\n鸡蛋 / 草莓 / 酸奶', author: 'me', x: 0.38, y: 0.29, tilt: -5, paper: 'yellow', attach: 'magnetBlue',
        decos: [{ id: F.uid(), kind: 'heart', x: 186, y: 118, tilt: 12 }] }),
    ];
    return { items, notes, magnets: [] };
  };

  // ---------- Store（localStorage） ----------
  const KEY = 'fridge.web.v1', PAINT_KEY = 'fridge.web.paint', REM_KEY = 'fridge.web.doorReminders', PHOTO_PREFIX = 'fridge.web.photo.';
  class Store {
    constructor() {
      this.listeners = [];
      let snap = null;
      try { snap = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { snap = null; }
      if (!snap || !Array.isArray(snap.items)) snap = F.sample();
      this.items = snap.items || [];
      this.notes = snap.notes || [];
      this.magnets = snap.magnets || [];
      // 早期版本把 TA 存成 'ta'，统一成和 iOS / 后端一样的 'partner'
      this.items.forEach((i) => { if (i.addedBy === 'ta') i.addedBy = 'partner'; });
      this.notes.forEach((n) => { if (n.author === 'ta') n.author = 'partner'; });
      try { this.paintHex = localStorage.getItem(PAINT_KEY) || null; } catch (e) { this.paintHex = null; }
      try { const r = localStorage.getItem(REM_KEY); this.showDoorReminders = r == null ? true : r === '1'; } catch (e) { this.showDoorReminders = true; }
      this.save();
      if (F.sync) this.pull();
    }
    on(fn) { this.listeners.push(fn); }

    // ---------- 可选：和后端同步（server/，或任何实现了 GET/PUT /api/fridge 的服务） ----------
    // 在加载这些脚本之前设 window.FRIDGE_SYNC = { url: 'https://你的域名/api/fridge', token: '…' } 即可开启。
    // 打开时先拉一次；之后每次改动 0.5 秒后整份写回（后写的覆盖先写的，多台设备同时改以最后一次为准）。
    async pull() {
      try {
        const res = await fetch(F.sync.url, { headers: { Authorization: 'Bearer ' + F.sync.token } });
        if (!res.ok) return;
        const value = (await res.json()).value;
        if (!value) { this.push(); return; }            // 服务器上还没有：把本机这份传上去
        const snap = F.fromServer(value);
        this.items = snap.items; this.notes = snap.notes; this.magnets = snap.magnets;
        this.saveLocal(); this.emit('data');
      } catch (e) { /* 连不上就先用本机的 */ }
    }
    push() {
      clearTimeout(this.pushTimer);
      this.pushTimer = setTimeout(() => {
        fetch(F.sync.url, {
          method: 'PUT',
          headers: { Authorization: 'Bearer ' + F.sync.token, 'Content-Type': 'application/json' },
          body: JSON.stringify({ value: F.toServer({ items: this.items, notes: this.notes, magnets: this.magnets }) }),
        }).catch(() => {});
      }, 500);
    }
    emit(what) { this.listeners.forEach((fn) => fn(what)); }
    saveLocal() {
      try { localStorage.setItem(KEY, JSON.stringify({ items: this.items, notes: this.notes, magnets: this.magnets })); } catch (e) { /* 存不下就只留在内存 */ }
    }
    save() {
      this.saveLocal();
      if (F.sync) this.push();
    }
    mutate(fn, what = 'data') { fn(this); this.save(); this.emit(what); }

    setPaint(hex) { this.paintHex = hex; try { hex ? localStorage.setItem(PAINT_KEY, hex) : localStorage.removeItem(PAINT_KEY); } catch (e) {} this.emit('paint'); }
    setShowDoorReminders(on) { this.showDoorReminders = on; try { localStorage.setItem(REM_KEY, on ? '1' : '0'); } catch (e) {} this.emit('data'); }

    itemsIn(zone) { return this.items.filter((i) => i.zone === zone).sort((a, b) => a.positionX - b.positionX); }
    item(id) { return this.items.find((i) => i.id === id); }
    note(id) { return this.notes.find((n) => n.id === id); }
    magnet(id) { return this.magnets.find((m) => m.id === id); }
    get doorReminders() {
      if (!this.showDoorReminders) return [];
      return this.items.filter((i) => { const d = F.due.daysLeft(i); return d != null && d <= 2; })
        .sort((a, b) => (F.due.daysLeft(a) || 0) - (F.due.daysLeft(b) || 0)).slice(0, 5);
    }

    add(item) {
      this.mutate((s) => {
        const xs = s.items.filter((i) => i.zone === item.zone).map((i) => i.positionX);
        item.positionX = (xs.length ? Math.min(...xs) : 0) - 1;
        s.items.push(item);
      });
    }
    update(item) {
      const idx = this.items.findIndex((i) => i.id === item.id);
      if (idx < 0) return;
      this.mutate((s) => {
        if (s.items[idx].zone !== item.zone) {
          const xs = s.items.filter((i) => i.zone === item.zone).map((i) => i.positionX);
          item.positionX = (xs.length ? Math.max(...xs) : 0) + 1;
        }
        s.items[idx] = item;
      });
    }
    consume(id) {
      const it = this.item(id);
      if (!it) return true;
      const gone = it.quantity <= 1;
      this.mutate((s) => {
        const i = s.items.findIndex((x) => x.id === id);
        if (i < 0) return;
        if (s.items[i].quantity > 1) s.items[i].quantity -= 1; else s.items.splice(i, 1);
      });
      return gone;
    }
    remove(id) { this.mutate((s) => { s.items = s.items.filter((i) => i.id !== id); }); }
    moveOnDoor(id, x, y) { const it = this.item(id); if (!it) return; this.mutate(() => { it.doorX = x; it.doorY = y; }, 'move'); }

    addNote(text, author, style) {
      const spots = [[0.62, 0.16], [0.36, 0.3], [0.66, 0.42], [0.4, 0.92]];
      const spot = spots[this.notes.length % spots.length];
      const note = F.makeNote({ text, author, x: spot[0], y: spot[1], tilt: F.rand(-6, 6), ...style });
      this.mutate((s) => s.notes.push(note));
      return note;
    }
    restyleNote(id, style) { const n = this.note(id); if (!n) return; this.mutate(() => Object.assign(n, style)); }
    moveNote(id, x, y) { const n = this.note(id); if (!n) return; this.mutate(() => { n.x = x; n.y = y; }, 'move'); }
    removeNote(id) { this.mutate((s) => { s.notes = s.notes.filter((n) => n.id !== id); }); }
    addDeco(kind, noteID) {
      const n = this.note(noteID); if (!n) return;
      const deco = { id: F.uid(), kind, x: F.rand(150, 200), y: F.rand(90, 130), tilt: F.rand(-15, 15) };
      this.mutate(() => { n.decos = n.decos || []; n.decos.push(deco); });
    }
    moveDeco(decoID, noteID, x, y) { const n = this.note(noteID); const d = n && n.decos.find((x) => x.id === decoID); if (!d) return; this.mutate(() => { d.x = x; d.y = y; }, 'move'); }
    removeDeco(decoID, noteID) { const n = this.note(noteID); if (!n) return; this.mutate(() => { n.decos = n.decos.filter((d) => d.id !== decoID); }); }

    addMagnet(draft) {
      const m = Object.assign({}, draft, { x: F.rand(0.35, 0.7), y: F.rand(0.14, 0.3), tilt: F.rand(-6, 6) });
      this.mutate((s) => s.magnets.push(m));
      return m;
    }
    updateMagnet(edited) {
      const m = this.magnet(edited.id); if (!m) return;
      this.mutate(() => { m.images = edited.images; m.crops = edited.crops; m.hex = edited.hex; m.text = edited.text; m.pin = edited.pin; });
    }
    moveMagnet(id, x, y) { const m = this.magnet(id); if (!m) return; this.mutate(() => { m.x = x; m.y = y; }, 'move'); }
    setMagnetTilt(id, tilt) { const m = this.magnet(id); if (!m) return; const t = ((tilt + 540) % 360 + 360) % 360 - 180; this.mutate(() => { m.tilt = t; }, 'move'); }
    removeMagnet(id) {
      const m = this.magnet(id);
      if (m) (m.images || []).forEach((n) => n && F.photos.remove(n));
      this.mutate((s) => { s.magnets = s.magnets.filter((x) => x.id !== id); });
    }
    layerDoorItem(id, toTop) {
      this.mutate((s) => {
        const all = s.notes.map((n) => n.z == null ? 0 : n.z).concat(s.magnets.map((m) => m.z == null ? 1 : m.z));
        const target = toTop ? (all.length ? Math.max(...all) : 0) + 1 : (all.length ? Math.min(...all) : 0) - 1;
        const n = s.note(id); if (n) n.z = target;
        const m = s.magnet(id); if (m) m.z = target;
      });
    }
    resetToSample() { const snap = F.sample(); this.mutate((s) => { s.items = snap.items; s.notes = snap.notes; s.magnets = snap.magnets; }); }
    clearAll() {
      this.magnets.forEach((m) => (m.images || []).forEach((n) => n && F.photos.remove(n)));
      this.mutate((s) => { s.items = []; s.notes = []; s.magnets = []; });
    }
  }

  // 照片存 localStorage：{ data: dataURL, w, h }
  F.photos = {
    cache: {},
    get(name) {
      if (!name) return null;
      if (this.cache[name]) return this.cache[name];
      try { const v = JSON.parse(localStorage.getItem(PHOTO_PREFIX + name) || 'null'); if (v) this.cache[name] = v; return v; } catch (e) { return null; }
    },
    put(rec) {
      const name = 'magnet-' + F.uid();
      this.cache[name] = rec;
      try { localStorage.setItem(PHOTO_PREFIX + name, JSON.stringify(rec)); } catch (e) { return null; }
      return name;
    },
    remove(name) { delete this.cache[name]; try { localStorage.removeItem(PHOTO_PREFIX + name); } catch (e) {} },
  };

  F.store = new Store();
})();
