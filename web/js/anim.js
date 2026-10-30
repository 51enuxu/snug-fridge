'use strict';
// 冰箱 · 动画（对应 FridgeDecor.swift 的 FridgeStickOn / FridgeCurl / FridgeTakeAway / FridgeAttachOff）
// 全部是「给一个 0…1 的 progress，把 transform/opacity 套到元素上」的纯函数，由 F.tween 逐帧驱动。
(function () {
  const F = window.Fridge;

  // 三次贝塞尔（跟 SwiftUI timingCurve 一样的四个数）
  F.bezier = (x1, y1, x2, y2) => {
    const A = (a1, a2) => 1 - 3 * a2 + 3 * a1, B = (a1, a2) => 3 * a2 - 6 * a1, C = (a1) => 3 * a1;
    const calc = (t, a1, a2) => ((A(a1, a2) * t + B(a1, a2)) * t + C(a1)) * t;
    const slope = (t, a1, a2) => 3 * A(a1, a2) * t * t + 2 * B(a1, a2) * t + C(a1);
    return (x) => {
      if (x <= 0) return 0; if (x >= 1) return 1;
      let t = x;
      for (let i = 0; i < 8; i++) { const s = slope(t, x1, x2); if (s < 1e-6) break; t -= (calc(t, x1, x2) - x) / s; }
      return calc(t, y1, y2);
    };
  };
  F.ease = {
    linear: (t) => t,
    easeOut: F.bezier(0, 0, 0.58, 1),
    easeInOut: F.bezier(0.42, 0, 0.58, 1),
    doorOpen: F.bezier(0.32, 0, 0.2, 1),
    doorClose: F.bezier(0.5, 0, 0.3, 1),
  };

  /// 逐帧：duration 毫秒，每帧 fn(progress 0…1)，结束 done()。返回 cancel()
  F.tween = (duration, easing, fn, done) => {
    const start = performance.now();
    let raf = 0, stopped = false;
    const step = (now) => {
      if (stopped) return;
      const t = Math.min(1, (now - start) / duration);
      fn(easing(t), t);
      if (t < 1) raf = requestAnimationFrame(step); else if (done) done();
    };
    raf = requestAnimationFrame(step);
    return () => { stopped = true; cancelAnimationFrame(raf); };
  };
  F.later = (ms, fn) => setTimeout(fn, ms);

  // ---------- 贴上去：从下面飞进来，悬一下 → 按下去压扁一点 → 回弹贴平 ----------
  F.stickOn = (el, p) => {
    if (p == null || p >= 1) { el.style.transform = ''; el.style.opacity = ''; el.style.filter = ''; return; }
    const travel = Math.min(p / 0.58, 1);
    const ease = 1 - Math.pow(1 - travel, 3);
    let scale;
    if (p < 0.58) scale = 1.45 - 0.3 * ease;
    else if (p < 0.8) scale = 1.15 - (p - 0.58) / 0.22 * 0.23;
    else scale = 0.92 + (p - 0.8) / 0.2 * 0.08;
    const lift = p < 0.8 ? Math.min(1, Math.max(0, 1 - (p - 0.4) / 0.4)) : 0;
    el.style.transform = `translateY(${(1 - ease) * 520}px) scale(${scale})`;
    el.style.opacity = String(Math.min(p / 0.12, 1));
    el.style.filter = lift > 0 ? `drop-shadow(0 ${6 + 22 * lift}px ${(6 + 18 * lift) / 2}px rgba(0,0,0,${0.25 * lift}))` : '';
  };

  // ---------- 软贴纸揭下来 ----------
  // host 里要有一个 .curl-content（原内容）。首次 progress>0 时克隆出三层：
  //   还贴着的部分（clip 到折痕一侧）/ 翻起那块压在下面的软影 / 翻过来的背面（剪影 × 背纸色，再沿折痕镜像）
  F.curl = (host, p, opts = {}) => {
    const fullPeel = opts.fullPeel !== false;
    const content = host.querySelector(':scope > .curl-content');
    if (!content) return;
    if (!(p > 0)) {
      if (host._curl) { host._curl.wrap.remove(); host._curl = null; }
      content.style.visibility = '';
      host.style.transform = ''; host.style.opacity = '';
      return;
    }
    const foldEnd = fullPeel ? 0.86 : 0.66;
    const fold = Math.min(p / foldEnd, 1);
    const lift = Math.max(0, (p - foldEnd) / (1 - foldEnd));
    const eased = fullPeel ? lift : lift * lift;
    const reach = fullPeel ? fold * 2 : (1 - Math.pow(1 - fold, 2)) * (opts.maxReach || 0.95);
    const k = reach; // corner = topLeading
    const w = Math.max(content.offsetWidth, 1), h = Math.max(content.offsetHeight, 1);

    let c = host._curl;
    if (!c) {
      const wrap = document.createElement('div');
      wrap.className = 'curl-wrap';
      const stuck = content.cloneNode(true); stuck.classList.add('curl-stuck');
      const shadowOuter = document.createElement('div'); shadowOuter.className = 'curl-shadow-outer';
      const shadow = content.cloneNode(true); shadow.classList.add('curl-shadow');
      shadowOuter.appendChild(shadow);
      const back = content.cloneNode(true); back.classList.add('curl-back');
      // 单张图的贴纸：背面再压一层按图形剪的渐变，像软纸卷起来
      const img = content.querySelector('img');
      if (img && content.querySelectorAll('img').length === 1 && opts.gradient !== false) {
        const g = document.createElement('div');
        g.className = 'curl-back-grad';
        g.style.webkitMaskImage = `url("${img.getAttribute('src')}")`;
        g.style.maskImage = `url("${img.getAttribute('src')}")`;
        back.appendChild(g);
      }
      wrap.append(stuck, shadowOuter, back);
      host.appendChild(wrap);
      content.style.visibility = 'hidden';
      c = host._curl = { wrap, stuck, shadowOuter, shadow, back };
    }
    [c.wrap, c.stuck, c.shadowOuter, c.shadow, c.back].forEach((e) => { e.style.width = w + 'px'; e.style.height = h + 'px'; });
    // u+v=k 的半平面。keepLess=靠左上那侧（翻起来的）
    const less = `polygon(${(k + 12) * w}px ${-12 * h}px, ${-12 * w}px ${(k + 12) * h}px, ${(k / 2 - 40) * w}px ${(k / 2 - 40) * h}px)`;
    const more = `polygon(${(k + 12) * w}px ${-12 * h}px, ${-12 * w}px ${(k + 12) * h}px, ${(k / 2 + 40) * w}px ${(k / 2 + 40) * h}px)`;
    const flip = `matrix(0, ${-(h / w)}, ${-(w / h)}, 0, ${k * w}, ${k * h})`;
    c.stuck.style.clipPath = more;
    c.shadowOuter.style.clipPath = more;
    c.shadow.style.clipPath = less;
    c.shadow.style.transform = `translate(2px, ${3 + fold * 3}px) ${flip}`;
    c.shadow.style.filter = `brightness(0) blur(${3 + fold * 3}px)`;
    c.back.style.clipPath = less;
    c.back.style.transform = flip;
    const bg = c.back.querySelector(':scope > .curl-back-grad');
    if (bg) bg.style.background = `linear-gradient(135deg, rgba(255,255,255,0.85) 0%, rgba(0,0,0,0.16) ${Math.max(1, k * 50)}%)`;
    const s = 1 + fold * 0.04 - eased * (fullPeel ? 0.15 : 0.5);
    host.style.transform = `translate(${eased * (fullPeel ? 30 : 80)}px, ${-eased * (fullPeel ? 60 : 320)}px) rotate(${eased * (fullPeel ? 8 : 22)}deg) scale(${s})`;
    host.style.opacity = String(fullPeel ? 1 - lift : 1 - Math.max(0, (lift - 0.5) / 0.5));
  };

  // ---------- 纸被手拿走：先离开门面，再往上斜着飞走 ----------
  F.takeAway = (el, p) => {
    if (!(p > 0)) { el.style.transform = ''; el.style.opacity = ''; el.style.filter = ''; return; }
    const pick = Math.min(p / 0.3, 1);
    const fly = Math.max(0, (p - 0.3) / 0.7);
    const ease = fly * fly;
    el.style.filter = `drop-shadow(0 ${4 + pick * 12}px ${(6 + pick * 14) / 2}px rgba(0,0,0,${0.22 * pick * (1 - fly)}))`;
    el.style.transform = `translate(${ease * 90}px, ${-pick * 8 - ease * 420}px) rotate(${pick * -3 + ease * 14}deg) scale(${1 + pick * 0.05 - ease * 0.25})`;
    el.style.opacity = String(1 - Math.max(0, (fly - 0.4) / 0.6));
  };

  // ---------- 固定物先拿掉：胶带从一头撕起再卷走，磁铁弹一下飞走 ----------
  F.attachOff = (el, p, isTape) => {
    if (!(p > 0)) { el.style.transform = ''; el.style.opacity = ''; return; }
    const first = Math.min(p / 0.5, 1);
    const fly = Math.max(0, (p - 0.5) / 0.5);
    const scale = isTape ? 1 : 1 + Math.sin(first * Math.PI) * 0.25;
    el.style.transformOrigin = isTape ? 'left center' : 'center';
    el.style.transform = `translate(${fly * 50}px, ${-fly * 180 - (isTape ? 0 : first * 12)}px) rotate(${fly * 30}deg) perspective(120px) rotateY(${isTape ? first * 75 : 0}deg) scale(${scale})`;
    el.style.opacity = String(1 - fly);
  };
})();
