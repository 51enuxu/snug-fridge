'use strict';
// 冰箱 · 入口：顶栏 / 底部按钮 / 把舞台和面板接起来
(function () {
  const F = window.Fridge;
  const h = F.h;

  const app = (F.app = {
    root: null, stage: null, viewport: null, zoneCardEl: null,

    init() {
      this.root = document.getElementById('app');
      this.viewport = document.getElementById('viewport');
      this.controls = document.getElementById('controls');
      this.hint = document.getElementById('hint');
      this.pills = document.getElementById('pills');
      document.getElementById('menuBtn').addEventListener('click', (e) => this.mainMenu(e.currentTarget));
      this.stage = new F.Stage(this, this.viewport);
      F.store.on((what) => { this.stage.onStoreChange(what); if (what !== 'paint' && what !== 'move') this.refreshZoneCard(); });
      this.renderControls();
    },

    // ---------- 顶栏菜单 ----------
    mainMenu(anchor) {
      F.ui.menu(anchor, [
        { title: '给冰箱换颜色', icon: 'brush', fn: () => F.ui.paintSheet() },
        { title: '门上贴快到期的', icon: 'clock', checked: F.store.showDoorReminders, fn: () => F.store.setShowDoorReminders(!F.store.showDoorReminders) },
        { title: '恢复示例冰箱', icon: 'rotate', fn: async () => { if (await F.ui.confirm({ title: '恢复示例？', message: '现在冰箱里的东西、便签和照片都会换成示例数据。', ok: '恢复', danger: false })) { if (this.stage.focusedZone) this.stage.setFocus(null); F.store.resetToSample(); this.toast('换回示例冰箱啦'); } } },
        { title: '清空冰箱', icon: 'trash', danger: true, fn: async () => { if (await F.ui.confirm({ title: '清空冰箱？', message: '里面的东西、门上的便签和照片都会拿掉。', ok: '清空' })) { if (this.stage.focusedZone) this.stage.setFocus(null); F.store.clearAll(); this.toast('冰箱清空啦'); } } },
      ]);
    },

    // ---------- 底部按钮 ----------
    renderControls() {
      const open = this.stage.isOpen;
      this.hint.textContent = open ? '点一层凑近看看 · 点空白处关门' : '点门打开 · 门上的东西可以拖';
      this.pills.innerHTML = '';
      const pill = (title, icon, cls, fn) => { const b = h('button', 'pill ' + cls, F.icon(icon, 13) + `<span>${title}</span>`); b.addEventListener('click', fn); this.pills.appendChild(b); };
      if (open) pill('关门', 'door', '', () => this.stage.toggleDoor());
      else {
        pill('贴便签', 'note', 'compact', () => F.ui.noteComposer((text, style) => { F.store.addNote(text, 'me', style); this.toast('便签贴上啦'); }));
        pill('贴照片', 'photo', 'compact', () => F.ui.magnetSheet());
      }
      pill('放进冰箱', 'plus', 'filled' + (open ? '' : ' compact'), () => this.openEditor({ item: null, zone: null }));
    },
    onDoorChange() { this.renderControls(); },
    onFocusChange(zone) {
      this.controls.classList.toggle('hidden', !!zone);
      this.refreshZoneCard();
    },

    // ---------- 某一层的卡片 ----------
    refreshZoneCard() {
      const zone = this.stage.focusedZone;
      if (this.zoneCardEl) { this.zoneCardEl.remove(); this.zoneCardEl = null; }
      if (!zone) return;
      const card = F.ui.zoneCard(zone, {
        onPick: (item) => this.showItem(item),
        onAdd: () => this.openEditor({ item: null, zone }),
        onClose: () => this.stage.setFocus(null),
      });
      card.addEventListener('click', (e) => e.stopPropagation());
      this.zoneCardEl = card;
      this.root.appendChild(card);
      requestAnimationFrame(() => card.classList.add('shown'));
    },

    // ---------- 详情 / 编辑 ----------
    showItem(item) {
      const live = F.store.item(item.id) || item;
      F.ui.itemSheet(live, {
        onEat: () => this.stage.eat(live),
        onEdit: () => F.later(450, () => this.openEditor({ item: live, zone: null })),
        onRemove: () => this.stage.peelOff(live, null),
      });
    },
    openEditor(target) {
      F.ui.editorSheet(target, (saved) => {
        if (target.item) F.store.update(saved); else this.stage.stickOn(saved);
      });
    },
    editMagnet(m) { F.ui.frameEditor(m, false, (edited) => F.store.updateMagnet(edited)); },
    layerMenu(id, anchor) {
      F.ui.menu(anchor, [
        { title: '放到最上面', icon: 'layers', fn: () => { F.store.layerDoorItem(id, true); this.toast('放到最上面啦'); } },
        { title: '放到最下面', icon: 'layers', fn: () => { F.store.layerDoorItem(id, false); this.toast('放到最下面啦'); } },
      ]);
    },
    toast(text) { F.ui.toast(text); },
  });

  // 调试：?debug=open | zone:<id> | note | 0.3（门停在动画中途）
  app.applyDebug = () => {
    const params = new URLSearchParams(location.search);
    if (params.get('still')) app.root.classList.add('no-anim');
    const raw = params.get('debug');
    if (!raw) return;
    const st = app.stage;
    if (raw === 'open') { st.isOpen = true; st.applyDoor(1); st.applyCamera(false); app.renderControls(); }
    if (raw.startsWith('zone:')) { st.isOpen = true; st.applyDoor(1); st.applyCamera(false); app.renderControls(); st.setFocus(raw.slice(5)); }
    if (raw === 'note') { const n = F.store.notes[0]; if (n) F.later(600, () => st.openNote(n)); }
    if (raw === 'note:style') { const n = F.store.notes[0]; if (n) { F.later(600, () => st.openNote(n)); F.later(1400, () => st.togglePanel('style')); } }
    if (raw === 'editor') F.later(300, () => app.openEditor({ item: null, zone: null }));
    if (raw === 'composer') F.later(300, () => F.ui.noteComposer((t, s) => F.store.addNote(t, 'me', s)));
    if (raw === 'paint') F.later(300, () => F.ui.paintSheet());
    if (raw === 'photos') F.later(300, () => F.ui.magnetSheet());
    if (raw.startsWith('peel:')) { st.isOpen = true; st.applyDoor(1); st.applyCamera(false); const v = Number(raw.slice(5)); F.store.itemsIn('crisper').slice(0, 2).forEach((it) => { st.peeling[it.id] = v; }); st.renderZones(); }
    if (raw.startsWith('land:')) { st.isOpen = true; st.applyDoor(1); st.applyCamera(false); const v = Number(raw.slice(5)); const it = F.store.itemsIn('chillMid')[0]; if (it) { st.landing[it.id] = v; st.renderZones(); } }
    if (raw === 'doorpeel') { const r = F.store.doorReminders[0]; if (r) F.later(800, () => st.peelOff(r, '揭下来啦', 0)); }
    const num = Number(raw);
    if (!isNaN(num) && raw.trim() !== '') { st.isOpen = num > 0.5; st.applyDoor(num); st.applyCamera(false); app.renderControls(); }
  };

  window.addEventListener('DOMContentLoaded', () => { app.init(); app.applyDebug(); });
})();
