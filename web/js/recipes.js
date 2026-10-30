'use strict';
// 冰箱 · 今天吃什么（对应 FridgeRecipes.swift）
// 菜谱来自开源项目 HowToCook（Unlicense），放在 assets/recipes.json，第一次点开才去取。
(function () {
  const F = window.Fridge;
  const h = F.h;
  const R = (F.recipes = {});

  // ---------- 菜谱库 ----------
  let loading = null;
  R.all = [];
  R.load = () => loading || (loading = fetch('../assets/recipes.json')
    .then((r) => r.json())
    .then((j) => { R.all = (j && j.recipes) || []; return R.all; })
    .catch(() => { loading = null; return R.all; }));

  // ---------- 匹配（规则和 FridgeRecipes.swift 保持一致） ----------
  // 一般家里都有的调料：不算「缺」，也不靠它们来匹配。只认完整名字——
  // 按「包含」判断会把黄油当成油、洋葱当成葱、水饺当成水
  const PANTRY = new Set([
    '盐', '食盐', '食用盐', '生抽', '老抽', '酱油', '食用油', '植物油', '油', '花生油', '橄榄油', '菜籽油',
    '料酒', '黄酒', '糖', '白糖', '白砂糖', '冰糖', '红糖', '蚝油', '淀粉', '生粉', '玉米淀粉', '鸡精', '鸡粉',
    '味精', '水', '清水', '开水', '热水', '温水', '冰水', '冰块', '香油', '芝麻油', '醋', '香醋', '陈醋', '白醋',
    '米醋', '八角', '香叶', '桂皮', '花椒', '花椒粉', '干辣椒', '五香粉', '孜然', '孜然粉', '番茄酱', '豆瓣酱',
    '葱', '小葱', '大葱', '香葱', '葱花', '葱段', '姜', '生姜', '姜片', '姜末', '老姜', '蒜', '大蒜', '蒜头',
    '蒜瓣', '蒜末', '蒜蓉', '芝麻', '白芝麻', '黑芝麻', '辣椒粉', '辣椒面', '辣椒油', '小米辣', '小米椒',
    '香菜', '十三香', '陈皮', '草果', '甜面酱', '腐乳', '鱼露', '胡椒', '胡椒粉', '白胡椒', '白胡椒粉',
    '黑胡椒', '黑胡椒粉',
  ]);

  // 同一种东西的不同叫法
  const SYNONYMS = [
    ['西红柿', '番茄'], ['土豆', '马铃薯', '洋芋'], ['鸡蛋', '鸡蛋液', '蛋液', '鸡蛋黄', '蛋黄', '蛋清'],
    ['蘑菇', '香菇', '口蘑', '平菇', '杏鲍菇', '金针菇', '菌菇', '蟹味菇', '白玉菇'],
    ['彩椒', '甜椒', '青椒', '红椒', '灯笼椒', '青辣椒'], ['西兰花', '西蓝花', '花椰菜'],
    ['牛肉', '牛腩', '肥牛', '牛排', '牛里脊', '牛腱'], ['鸡肉', '鸡胸', '鸡腿', '鸡翅', '鸡块', '鸡爪'],
    ['猪肉', '五花肉', '里脊', '肉末', '肉馅', '排骨', '梅花肉', '瘦肉', '猪肉末'],
    ['虾', '虾仁', '大虾', '基围虾', '虾滑', '鲜虾'],
    ['鱼', '鲈鱼', '草鱼', '鳕鱼', '三文鱼', '鱼片', '鲫鱼', '龙利鱼', '巴沙鱼'],
    ['米饭', '剩饭', '隔夜饭', '白米饭', '熟米饭'], ['面条', '挂面', '拉面', '乌冬', '意面', '意大利面', '手擀面'],
    ['芝士', '奶酪', '马苏里拉'], ['牛奶', '纯牛奶', '鲜奶'], ['水饺', '饺子', '速冻水饺'],
    ['面包', '吐司'], ['橙子', '橙'], ['生菜', '球生菜'], ['培根', '烟肉'], ['黄油', '牛油'],
  ];

  const norm = (t) => String(t).replace(/ /g, '').toLowerCase();
  R.isPantry = (name) => PANTRY.has(norm(name));
  const group = (t) => SYNONYMS.findIndex((words) => words.some((w) => t === w || (w.length >= 2 && t.includes(w))));

  /// 冰箱里这样东西能不能当这个用料
  R.matches = (item, ingredient) => {
    const a = norm(item), b = norm(ingredient);
    if (!a || !b) return false;
    if (a === b) return true;
    if (a.length >= 2 && b.includes(a)) return true;
    if (b.length >= 2 && a.includes(b)) return true;
    const ga = group(a), gb = group(b);
    return ga >= 0 && ga === gb;
  };

  R.match = (recipe, items) => {
    const have = [], missing = [], used = [];
    recipe.ingredients.filter((i) => !R.isPantry(i.name)).forEach((ing) => {
      const item = items.find((it) => R.matches(it.name, ing.name));
      if (item) { have.push(ing.name); if (!used.some((u) => u.id === item.id)) used.push(item); }
      else if (!ing.optional) missing.push(ing.name);
    });
    const urgency = used.reduce((sum, item) => {
      const d = F.due.daysLeft(item);
      return d == null ? sum : sum + (d <= 2 ? 2 : d <= 5 ? 1 : 0);
    }, 0);
    return { recipe, have, missing, usedItems: used, urgency };
  };

  /// 冰箱能凑上的菜：至少用上一样，最多缺三样。能直接做的在前，其次快过期的用得多的
  R.suggestions = (items) => R.all.map((r) => R.match(r, items))
    .filter((m) => m.have.length && m.missing.length <= 3)
    .sort((a, b) => {
      if ((a.missing.length === 0) !== (b.missing.length === 0)) return a.missing.length === 0 ? -1 : 1;
      if (a.urgency !== b.urgency) return b.urgency - a.urgency;
      if (a.missing.length !== b.missing.length) return a.missing.length - b.missing.length;
      if (a.have.length !== b.have.length) return b.have.length - a.have.length;
      return a.recipe.stars - b.recipe.stars;
    });

  // ---------- 弹层 ----------
  const stars = (n) => '★'.repeat(n);
  const catLine = (r) => r.cat + (r.stars > 0 ? ' · ' + stars(r.stars) : '');
  const CREDIT = '菜谱来自开源项目 HowToCook（程序员做饭指南）';

  /// onCooked(used)：做完一道菜，勾上的东西各吃掉一份
  R.sheet = (onCooked) => {
    const ui = F.ui;
    let view = { type: 'list' };
    let query = '';
    ui.sheet({
      cls: 'recipe-sheet', full: true,
      build(el, ctl) {
        const bar = h('div', 'sheet-head');
        const back = h('button', 'text-btn muted');
        const title = h('div', 'sheet-title', '今天吃什么');
        const close = h('button', 'text-btn rose', '关上');
        bar.append(back, title, close);
        const body = h('div', 'sheet-body rc-body');
        el.append(bar, body);
        close.addEventListener('click', () => ctl.close());
        back.addEventListener('click', () => { view = view.type === 'cook' ? { type: 'detail', recipe: view.recipe } : { type: 'list' }; render(); });

        const row = (m) => {
          const b = h('button', 'rc-row');
          const used = m.usedItems.length ? `<div class="rc-used ${m.urgency > 0 ? 'urgent' : ''}">用上：${F.esc(m.usedItems.map((i) => i.name).join('、'))}</div>` : '';
          const miss = m.missing.length ? `<div class="rc-miss">还缺：${F.esc(m.missing.join('、'))}</div>` : '';
          b.innerHTML = `<div class="rc-top"><span class="rc-name">${F.esc(m.recipe.name)}</span><span class="rc-cat">${F.esc(catLine(m.recipe))}</span></div>${used}${miss}`;
          b.addEventListener('click', () => { view = { type: 'detail', recipe: m.recipe }; render(); });
          return b;
        };
        const sectionTitle = (t) => h('div', 'rc-section', F.esc(t));
        const hint = (t) => h('div', 'rc-hint', F.esc(t));

        const renderList = () => {
          const items = F.store.items;
          const search = h('label', 'rc-search', F.icon('search', 15));
          const input = h('input', 'rc-input');
          input.placeholder = '想做别的？搜菜名'; input.value = query;
          search.appendChild(input);
          const list = h('div', 'rc-list');
          body.append(search, list);
          const fill = () => {
            list.innerHTML = '';
            const q = query.trim();
            if (!R.all.length) { list.appendChild(hint('菜谱还在加载，或者没有找到 assets/recipes.json')); return; }
            if (q) {
              const found = R.all.filter((r) => r.name.includes(q));
              list.appendChild(sectionTitle(found.length ? `搜到 ${found.length} 道` : '没找到这道菜'));
              found.slice(0, 40).forEach((r) => list.appendChild(row(R.match(r, items))));
            } else if (!items.length) {
              list.appendChild(hint('冰箱是空的。先放点东西进去，或者直接搜菜名'));
            } else {
              const sug = R.suggestions(items);
              const ready = sug.filter((m) => !m.missing.length);
              const close2 = sug.filter((m) => m.missing.length && m.missing.length <= 2);
              if (!ready.length && !close2.length) list.appendChild(hint('冰箱里的东西凑不出菜谱库里的菜，搜搜菜名看看'));
              if (ready.length) { list.appendChild(sectionTitle('现在就能做')); ready.slice(0, 20).forEach((m) => list.appendChild(row(m))); }
              if (close2.length) { list.appendChild(sectionTitle('差一两样')); close2.slice(0, 20).forEach((m) => list.appendChild(row(m))); }
            }
            list.appendChild(h('div', 'rc-credit', CREDIT));
          };
          input.addEventListener('input', () => { query = input.value; fill(); });
          fill();
        };

        const card = (t, ...kids) => { const c = h('div', 'rc-card'); c.appendChild(h('div', 'rc-card-title', F.esc(t))); kids.forEach((k) => c.appendChild(k)); return c; };

        const renderDetail = () => {
          const r = view.recipe;
          const m = R.match(r, F.store.items);
          const head = h('div', 'rc-head', `<div class="rc-title">${F.esc(r.name)}</div><div class="rc-cat">${F.esc(r.cat + (r.stars > 0 ? ' · 难度 ' + stars(r.stars) : ''))}</div>${r.lead ? `<div class="rc-lead">${F.esc(r.lead)}</div>` : ''}`);
          const ings = h('div', 'rc-ings');
          r.ingredients.forEach((ing) => {
            const pantry = R.isPantry(ing.name);
            const inFridge = F.store.items.find((it) => R.matches(it.name, ing.name));
            const amount = ing.amount ? String(ing.amount).replace(/\* ?份数/g, '') : '';
            const tag = inFridge ? `冰箱有 · ${inFridge.name}` : pantry ? '调料' : '要买';
            const li = h('div', 'rc-ing' + (inFridge ? ' have' : ''));
            li.innerHTML = `<span class="rc-dot">${F.icon(inFridge ? 'check' : 'circle', 13)}</span><div class="rc-ing-main"><div class="rc-ing-name">${F.esc(ing.name + (ing.optional ? '（可选）' : ''))}</div>${amount ? `<div class="rc-ing-amt">${F.esc(amount)}</div>` : ''}</div><span class="rc-ing-tag">${F.esc(tag)}</span>`;
            ings.appendChild(li);
          });
          const steps = h('div', 'rc-steps');
          r.steps.forEach((s, i) => {
            const li = h('div', 'rc-step');
            // 步骤里可能夹着「\n· 小贴士」，按行分开显示
            const lines = String(s).split('\n').map((x) => x.trim()).filter(Boolean);
            li.innerHTML = `<span class="rc-num">${i + 1}</span><div class="rc-step-text">${lines.map((x, k) => `<div class="${k ? 'rc-tip' : ''}">${F.esc(x)}</div>`).join('')}</div>`;
            steps.appendChild(li);
          });
          body.append(head, card('用料（一人份）', ings), card('步骤', steps), h('div', 'rc-credit', CREDIT + '，分量按一人份写'));
          if (m.usedItems.length) {
            const go = h('button', 'rc-cook', '做了这道');
            go.addEventListener('click', () => { view = { type: 'cook', recipe: r, picked: new Set(m.usedItems.map((i) => i.id)) }; render(); });
            const dock = h('div', 'rc-dock'); dock.appendChild(go);
            el.appendChild(dock);
          }
        };

        // 做完了：勾上的东西各从冰箱里拿掉一份，默认全勾，可以取消
        const renderCook = () => {
          const m = R.match(view.recipe, F.store.items);
          body.appendChild(h('div', 'rc-cook-title', '用掉了哪些？'));
          body.appendChild(h('div', 'rc-cook-sub', '勾上的各吃掉一份，没用完的取消勾选就好'));
          const confirm = h('button', 'rc-cook');
          const sync = () => { confirm.textContent = view.picked.size ? '从冰箱拿掉' : '什么都没用掉'; };
          m.usedItems.forEach((item) => {
            const b = h('button', 'rc-pick');
            const paint = () => {
              const on = view.picked.has(item.id);
              b.classList.toggle('on', on);
              b.innerHTML = `<span class="rc-check">${F.icon(on ? 'check' : 'circle', 14)}</span><span class="rc-pick-name">${F.esc(item.name)}</span><span class="rc-pick-left">${item.quantity > 1 ? `还有 ${Math.round(item.quantity)} ${F.esc(item.unit)}` : `最后一${F.esc(item.unit)}`}</span>`;
            };
            b.addEventListener('click', () => { if (view.picked.has(item.id)) view.picked.delete(item.id); else view.picked.add(item.id); paint(); sync(); });
            paint();
            body.appendChild(b);
          });
          sync();
          confirm.addEventListener('click', () => {
            const used = m.usedItems.filter((i) => view.picked.has(i.id));
            ctl.close(() => onCooked(used));
          });
          const dock = h('div', 'rc-dock'); dock.appendChild(confirm);
          el.appendChild(dock);
        };

        function render() {
          el.querySelectorAll('.rc-dock').forEach((d) => d.remove());
          body.innerHTML = '';
          back.textContent = view.type === 'list' ? '' : '返回';
          back.style.visibility = view.type === 'list' ? 'hidden' : 'visible';
          if (view.type === 'list') renderList();
          else if (view.type === 'detail') renderDetail();
          else renderCook();
          body.scrollTop = 0;
        }
        body.innerHTML = '';
        body.appendChild(hint('菜谱加载中…'));
        R.load().then(render);
      },
    });
  };
})();
