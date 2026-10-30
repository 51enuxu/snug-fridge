#!/usr/bin/env python3
"""
冰箱 AI 工具: 看冰箱 / 放东西 / 吃掉 / 拿走 / 贴便签。

数据形状 = iOS 端 FridgeStore.Snapshot 的 JSON（ios/FridgeDemo.swiftpm/Sources/FridgeModels.swift 是唯一口径）:
  {items: [FridgeItem], notes: [FridgeNote], magnets: [FridgeMagnet]}
  FridgeItem: {id, name, quantity, unit, zone, positionX, positionY, addedAt, expiresAt?, eatBy?,
               stickerSource(builtIn|photo|generated), stickerAsset, notes, addedBy(me|partner), doorX?, doorY?}
  FridgeNote: {id, text, author(me|partner), x, y, tilt, createdAt, paper, attach, font, fontSize, decos[]}
  FridgeMagnet: {id, style(photo|polaroid|strip), text, hex, x, y, tilt, images?, crops?}
日期: Swift JSONEncoder 默认把 Date 编成「2001-01-01 UTC 起的秒数」(double)，这里写入也用这个基准;
读的时候顺带容忍 ISO 字符串和 unix 秒。照片字段只是手机本地文件名，服务器不碰。

接入方式: TOOLS 是 Anthropic 风格的工具定义 (name/description/input_schema)，
OpenAI function calling 只要把 input_schema 放进 parameters 即可。执行 execute(name, input) -> str。
默认直接读写本地 JSON 文件 (store.py)；想接别的存储就替换 load()/save()。
"""
import json
import random
import uuid
from datetime import datetime, timedelta, timezone

import store

TZ8 = timezone(timedelta(hours=8))  # 展示用时区；想换自己的时区改这里
SWIFT_EPOCH = 978307200  # 2001-01-01T00:00:00Z

# 顺序 = FridgeZone.allCases (展示按这个顺序)
ZONES = [
    ('freezerTop', '冷冻 · 上层'), ('freezer', '冷冻 · 下层'),
    ('freezerDoor', '冷冻门架 · 上'), ('freezerDoorLow', '冷冻门架 · 下'),
    ('chillTop', '冷藏 · 上层'), ('chillMid', '冷藏 · 中层'), ('chillLow', '冷藏 · 下层'),
    ('crisper', '蔬果抽屉'),
    ('doorTop', '门架 · 上'), ('doorMid', '门架 · 中'), ('doorLow', '门架 · 下'),
]
ZONE_TITLE = dict(ZONES)
ZONE_ALIAS = {
    '冷冻上': 'freezerTop', '冷冻上层': 'freezerTop', '冷冻': 'freezer', '冷冻下': 'freezer', '冷冻下层': 'freezer',
    '冷冻门': 'freezerDoor', '冷冻门架': 'freezerDoor', '冷冻门架上': 'freezerDoor', '冷冻门架下': 'freezerDoorLow',
    '冷藏上': 'chillTop', '冷藏上层': 'chillTop', '冷藏': 'chillMid', '冷藏中': 'chillMid', '冷藏中层': 'chillMid',
    '冷藏下': 'chillLow', '冷藏下层': 'chillLow', '抽屉': 'crisper', '蔬果抽屉': 'crisper', '蔬果': 'crisper',
    '门架上': 'doorTop', '门上': 'doorTop', '门架': 'doorMid', '门架中': 'doorMid', '门中': 'doorMid',
    '门架下': 'doorLow', '门下': 'doorLow',
}

PAPERS = ('yellow', 'lined', 'kraft', 'grid', 'pink', 'index')
ATTACHES = ('magnetPink', 'magnetBlue', 'magnetMint', 'washiStripe', 'washiDot', 'clearTape', 'heart', 'flower')
FONTS = ('kuaile', 'wenkai', 'rounded', 'system')

# 照抄 FridgeCatalog.all: (asset, 名字, 默认分区, 保质天数, 量词, 是饮品)
CATALOG = [
    ('strawberry', '草莓', 'chillTop', 3, '盒', False), ('blueberries', '蓝莓', 'chillTop', 5, '盒', False),
    ('grapes', '葡萄', 'chillTop', 6, '串', False), ('lettuce', '生菜', 'crisper', 4, '颗', False),
    ('tomato', '西红柿', 'crisper', 7, '个', False), ('broccoli', '西兰花', 'crisper', 5, '颗', False),
    ('carrot', '胡萝卜', 'crisper', 14, '根', False), ('cucumber', '黄瓜', 'crisper', 6, '根', False),
    ('bell_pepper', '彩椒', 'crisper', 7, '个', False), ('mushroom', '蘑菇', 'crisper', 4, '盒', False),
    ('potato', '土豆', 'crisper', 20, '个', False), ('onion', '洋葱', 'crisper', 20, '个', False),
    ('apple', '苹果', 'crisper', 14, '个', False), ('orange', '橙子', 'crisper', 14, '个', False),
    ('banana', '香蕉', 'chillTop', 4, '根', False), ('eggs', '鸡蛋', 'chillTop', 20, '个', False),
    ('yogurt', '酸奶', 'chillTop', 7, '杯', False), ('cheese', '芝士', 'chillTop', 20, '块', False),
    ('butter', '黄油', 'chillTop', 30, '块', False), ('beef', '牛肉', 'chillLow', 2, '盒', False),
    ('chicken', '鸡肉', 'chillLow', 2, '盒', False), ('fish', '鱼', 'chillLow', 1, '块', False),
    ('shrimp', '虾', 'freezer', 60, '袋', False), ('bacon', '培根', 'chillLow', 7, '包', False),
    ('rice', '米饭', 'chillMid', 2, '碗', False), ('noodles', '面条', 'chillMid', 3, '份', False),
    ('soup', '汤', 'chillMid', 2, '碗', False), ('leftovers', '剩菜盒', 'chillMid', 2, '盒', False),
    ('lunchbox', '饭盒', 'chillMid', 2, '盒', False), ('bread', '面包', 'chillMid', 5, '袋', False),
    ('milk', '牛奶', 'doorMid', 5, '瓶', True), ('juice', '果汁', 'doorMid', 5, '瓶', True),
    ('soda', '汽水', 'doorLow', 90, '罐', True), ('water', '矿泉水', 'doorLow', 180, '瓶', True),
    ('sauce', '酱料', 'doorTop', 60, '瓶', False), ('glass_jar', '果酱', 'doorTop', 30, '罐', False),
    ('ice_cream', '冰淇淋', 'freezer', 60, '盒', False), ('frozen_dumplings', '速冻水饺', 'freezer', 90, '袋', False),
    ('frozen_meat', '冷冻肉', 'freezer', 90, '块', False), ('paper_bag', '袋装', 'chillMid', 3, '袋', False),
    ('unknown_food_box', '盒装', 'chillMid', 3, '盒', False),
]
# 名字别名 → asset (模型常用的叫法)
NAME_ALIAS = {
    '番茄': 'tomato', '圣女果': 'tomato', '蛋': 'eggs', '鸡蛋': 'eggs', '鸡胸': 'chicken', '鸡腿': 'chicken',
    '猪肉': 'frozen_meat', '排骨': 'frozen_meat', '五花肉': 'frozen_meat', '水饺': 'frozen_dumplings', '饺子': 'frozen_dumplings',
    '雪糕': 'ice_cream', '冰激凌': 'ice_cream', '可乐': 'soda', '雪碧': 'soda', '气泡水': 'soda', '水': 'water',
    '剩菜': 'leftovers', '剩饭': 'rice', '便当': 'lunchbox', '吐司': 'bread', '辣酱': 'sauce', '老干妈': 'sauce',
    '沙拉酱': 'sauce', '果酱': 'glass_jar', '蜂蜜': 'glass_jar', '奶酪': 'cheese', '橘子': 'orange', '柑': 'orange',
    '青椒': 'bell_pepper', '土豆': 'potato', '马铃薯': 'potato', '香菇': 'mushroom', '金针菇': 'mushroom',
    '虾仁': 'shrimp', '三文鱼': 'fish', '鳕鱼': 'fish', '汤': 'soup',
}

TOOLS = [
    {
        'name': 'fridge_list',
        'description': '看共用的冰箱(和 iOS 冰箱页同一份数据): 每一层放了什么、数量、谁放的、还有几天到期, 哪些快过期/已过期, 门上贴了哪些便签和照片。用户问冰箱里有什么、还有没有某样东西、什么快坏了、想做饭看食材, 或你想替用户盯着别放过期时, 先用这个看真实内容再说, 不许凭印象。返回里的 id 是后面 consume/remove 要用的。',
        'input_schema': {'type': 'object', 'properties': {}, 'required': []},
    },
    {
        'name': 'fridge_add',
        'description': '往冰箱里放东西(署名是助手)。name 必填; zone 不填就按食材库默认层(牛奶→门架中, 蔬菜→蔬果抽屉, 肉→冷藏下层/冷冻, 剩菜→冷藏中层); days 是建议几天内吃完(不填用食材库默认保质期), 或直接给 eat_by=YYYY-MM-DD; notes 是贴纸上给用户留的一句话(比如「热一下就能吃」「一次只许吃两勺」)。同层已有同名的会合并数量而不是贴第二张。用户说买了什么/做了什么放冰箱、或你替用户囤了东西时用。成功返回后才算放进去了。',
        'input_schema': {'type': 'object', 'properties': {
            'name': {'type': 'string', 'description': '东西的名字, 如 牛奶 / 昨晚的红烧肉'},
            'quantity': {'type': 'number', 'description': '数量, 默认1'},
            'unit': {'type': 'string', 'description': '量词(瓶/盒/个/份...), 不填按食材库'},
            'zone': {'type': 'string', 'description': '放哪层: freezerTop(冷冻上) freezer(冷冻下) freezerDoor/freezerDoorLow(冷冻门架上/下) chillTop/chillMid/chillLow(冷藏上/中/下) crisper(蔬果抽屉) doorTop/doorMid/doorLow(门架上/中/下); 也认中文如「冷藏上层」「门架」'},
            'days': {'type': 'integer', 'description': '建议几天内吃完(今天算第1天), 0=今天就要吃掉'},
            'eat_by': {'type': 'string', 'description': '建议吃完的日期 YYYY-MM-DD, 和 days 二选一'},
            'sticker': {'type': 'string', 'description': '贴纸图(食材库 asset 名, 如 milk/leftovers/lunchbox), 不填按 name 自动匹配, 匹配不到用盒装'},
            'notes': {'type': 'string', 'description': '贴纸上给用户的一句话, 可空'},
        }, 'required': ['name']},
    },
    {
        'name': 'fridge_consume',
        'description': '吃掉/用掉冰箱里的东西: 减掉 amount 份(默认1), 减到 0 就整张贴纸揭下来; all=true 表示全吃完。target 填 fridge_list 返回的 id(可只给前缀)或名字。用户说吃了/喝了/用掉了什么时用。',
        'input_schema': {'type': 'object', 'properties': {
            'target': {'type': 'string', 'description': 'item id(或前缀)或名字'},
            'amount': {'type': 'number', 'description': '吃掉几份, 默认1'},
            'all': {'type': 'boolean', 'description': 'true=全部吃完'},
        }, 'required': ['target']},
    },
    {
        'name': 'fridge_remove',
        'description': '把一样东西从冰箱整个拿走(扔掉过期的、拿出来做菜、放错了)。target 填 id(或前缀)或名字。和 consume 的区别: consume 是吃掉, remove 是拿走/扔掉, 不管还剩多少。',
        'input_schema': {'type': 'object', 'properties': {
            'target': {'type': 'string', 'description': 'item id(或前缀)或名字'},
        }, 'required': ['target']},
    },
    {
        'name': 'fridge_note',
        'description': '在冰箱门上贴一张便签(署名是助手, 用户打开冰箱页就看见)。便签是贴在门上的短话: 叮嘱用户吃什么/别放过期、买菜清单、一句想说的话; 一般一两行, 最多 80 字。不是聊天消息也不是信。纸/固定方式/字体可选, 不填就是横格纸+条纹胶带。',
        'input_schema': {'type': 'object', 'properties': {
            'text': {'type': 'string', 'description': '便签内容, 可用换行'},
            'paper': {'type': 'string', 'description': 'yellow(黄便利贴)/lined(横格撕边)/kraft(牛皮纸)/grid(方格)/pink(粉色爱心)/index(索引卡)'},
            'attach': {'type': 'string', 'description': 'magnetPink/magnetBlue/magnetMint/washiStripe/washiDot/clearTape/heart/flower'},
            'font': {'type': 'string', 'description': 'kuaile(快乐体)/wenkai(文楷)/rounded(圆体)/system'},
        }, 'required': ['text']},
    },
]
TOOL_NAMES = [t['name'] for t in TOOLS]


# ---------- 时间 ----------

def _now():
    return datetime.now(TZ8)


def _to_swift(dt):
    return round(dt.timestamp() - SWIFT_EPOCH, 3)


def _from_swift(value):
    """容忍: swift 基准秒(数字) / ISO 字符串 / None"""
    if value is None or value == '':
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(value + SWIFT_EPOCH, TZ8)
        except (OverflowError, OSError, ValueError):
            return None
    if isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value.replace('Z', '+00:00'))
            return (dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)).astimezone(TZ8)
        except ValueError:
            return None
    return None


def _days_left(item):
    due = _from_swift(item.get('eatBy')) or _from_swift(item.get('expiresAt'))
    if due is None:
        return None
    return (due.date() - _now().date()).days


def _due_label(item):
    d = _days_left(item)
    if d is None:
        return '不着急'
    if d < 0:
        return f'过期{-d}天了'
    if d == 0:
        return '今天要吃掉'
    if d == 1:
        return '明天前吃完'
    if d <= 3:
        return f'还剩{d}天'
    return f'还能放{d}天'


# ---------- 存取 ----------

def load():
    """读最新快照; 读不到抛 RuntimeError (调用方拒写)"""
    value = store.read()
    if value is None:
        return {'items': [], 'notes': [], 'magnets': []}
    if not isinstance(value, dict):
        raise RuntimeError('冰箱数据形状不对(不是对象), 不敢动')
    snap = dict(value)
    for key in ('items', 'notes', 'magnets'):
        if not isinstance(snap.get(key), list):
            snap[key] = []
    return snap


def save(snap):
    store.write(snap)


# ---------- 查找 ----------

def _qty_text(item):
    q = item.get('quantity', 1)
    try:
        q = float(q)
    except (TypeError, ValueError):
        q = 1.0
    qs = str(int(q)) if q == int(q) else f'{q:.1f}'
    return f"{qs} {item.get('unit') or '份'}"


def _short(item_id):
    return str(item_id or '')[:8]


def _find_items(items, target):
    """按 id / id 前缀 / 名字(精确 → 包含) 找; 返回匹配列表"""
    t = str(target or '').strip()
    if not t:
        return []
    exact = [it for it in items if str(it.get('id')) == t]
    if exact:
        return exact
    if len(t) >= 4:
        pre = [it for it in items if str(it.get('id', '')).lower().startswith(t.lower())]
        if pre:
            return pre
    tl = t.lower()
    byname = [it for it in items if str(it.get('name', '')).strip().lower() == tl]
    if byname:
        return byname
    return [it for it in items if tl in str(it.get('name', '')).lower()]


def _describe(item):
    who = '助手放的' if item.get('addedBy') == 'partner' else '用户放的'
    note = f" 「{item['notes']}」" if item.get('notes') else ''
    return f"{item.get('name')} {_qty_text(item)} · {ZONE_TITLE.get(item.get('zone'), item.get('zone'))} · {_due_label(item)} · {who}{note} [id {_short(item.get('id'))}]"


def _pick_one(items, target):
    hits = _find_items(items, target)
    if not hits:
        return None, f'冰箱里没找到「{target}」, 先 fridge_list 看看叫什么'
    if len(hits) > 1:
        return None, '有好几样都对得上, 用 id 指定一下:\n' + '\n'.join('- ' + _describe(it) for it in hits)
    return hits[0], None


def _catalog_entry(name='', sticker=''):
    s = str(sticker or '').strip()
    if s:
        for e in CATALOG:
            if e[0] == s:
                return e
    n = str(name or '').strip()
    if not n:
        return None
    for e in CATALOG:
        if e[1] == n or e[0] == n:
            return e
    if n in NAME_ALIAS:
        return _catalog_entry(sticker=NAME_ALIAS[n])
    # 「昨晚的红烧肉」这种: 名字里包含食材库的词, 取最长的那个
    best = None
    for e in CATALOG:
        if e[1] in n and (best is None or len(e[1]) > len(best[1])):
            best = e
    if best is None:
        for alias, asset in NAME_ALIAS.items():
            if alias in n and (best is None or len(alias) > len(best[1])):
                best = _catalog_entry(sticker=asset)
    return best


def _zone_of(raw, fallback):
    z = str(raw or '').strip()
    if not z:
        return fallback
    if z in ZONE_TITLE:
        return z
    key = z.replace(' ', '').replace('·', '')
    if key in ZONE_ALIAS:
        return ZONE_ALIAS[key]
    for title, zone in ((t.replace(' ', '').replace('·', ''), zz) for zz, t in ZONES):
        if key == title:
            return zone
    for alias, zone in ZONE_ALIAS.items():
        if alias in key:
            return zone
    raise ValueError(f'不认识的分区「{raw}」, 可选: ' + ' '.join(f'{z}({t})' for z, t in ZONES))


# ---------- 工具 ----------

def fridge_list(_input=None):
    snap = load()
    items, notes, magnets = snap['items'], snap['notes'], snap['magnets']
    lines = []
    if not items:
        lines.append('冰箱是空的, 一样东西都没有。')
    else:
        lines.append(f'冰箱里共 {len(items)} 样:')
        for zone, title in ZONES:
            inzone = [it for it in items if it.get('zone') == zone]
            if not inzone:
                continue
            inzone.sort(key=lambda it: float(it.get('positionX') or 0))
            lines.append(f'[{title}]')
            for it in inzone:
                lines.append('  - ' + _describe(it))
        stray = [it for it in items if it.get('zone') not in ZONE_TITLE]
        if stray:
            lines.append('[分区不明]')
            lines.extend('  - ' + _describe(it) for it in stray)
        urgent = [(d, it) for it in items for d in [_days_left(it)] if d is not None and d <= 2]
        if urgent:
            urgent.sort(key=lambda p: p[0])
            lines.append('要盯的(2天内到期/已过期): ' + '; '.join(
                f"{it.get('name')}({_due_label(it)})" for _, it in urgent))
    if notes:
        lines.append(f'门上的便签 {len(notes)} 张:')
        for n in notes:
            who = '助手' if n.get('author') == 'partner' else '用户'
            when = _from_swift(n.get('createdAt'))
            when_s = when.strftime('%m-%d') if when else ''
            text = str(n.get('text') or '').replace('\n', ' / ')
            lines.append(f'  - {who}写的 {when_s}: {text} [id {_short(n.get("id"))}]')
    else:
        lines.append('门上没有便签。')
    if magnets:
        desc = []
        for m in magnets:
            style = {'photo': '照片贴', 'polaroid': '拍立得', 'strip': '四格'}.get(m.get('style'), m.get('style'))
            desc.append(style + (f"「{m['text']}」" if m.get('text') else ''))
        lines.append(f'门上的照片 {len(magnets)} 张: ' + ', '.join(desc) + ' (照片本身只在手机里, 你看不到图)')
    return '\n'.join(lines)


def fridge_add(inp):
    name = str(inp.get('name') or '').strip()[:30]
    if not name:
        raise ValueError('name 不能空')
    entry = _catalog_entry(name, inp.get('sticker'))
    zone = _zone_of(inp.get('zone'), entry[2] if entry else 'chillMid')
    try:
        qty = float(inp.get('quantity') if inp.get('quantity') is not None else 1)
    except (TypeError, ValueError):
        raise ValueError('quantity 要是数字')
    if not (0 < qty <= 999):
        raise ValueError('quantity 要在 0 到 999 之间')
    if qty == int(qty):
        qty = int(qty)
    unit = str(inp.get('unit') or '').strip()[:6] or (entry[4] if entry else '份')
    sticker = str(inp.get('sticker') or '').strip()
    if sticker and not any(e[0] == sticker for e in CATALOG):
        sticker = ''
    sticker = sticker or (entry[0] if entry else 'unknown_food_box')
    notes = str(inp.get('notes') or '').strip()[:60]

    now = _now()
    eat_by = exp = None
    if inp.get('eat_by'):
        try:
            d = datetime.strptime(str(inp['eat_by']).strip(), '%Y-%m-%d').replace(tzinfo=TZ8, hour=12)
        except ValueError:
            raise ValueError('eat_by 要是 YYYY-MM-DD')
        eat_by, exp = d, d + timedelta(days=1)
    else:
        days = inp.get('days')
        if days is None and entry:
            days = entry[3]
        if days is not None:
            try:
                days = int(days)
            except (TypeError, ValueError):
                raise ValueError('days 要是整数')
            days = max(0, min(days, 365))
            # 照 iOS 端加东西的算法: 建议吃完 = 今天+(days-1), 保质期到 = 今天+days
            eat_by = now + timedelta(days=max(days - 1, 0))
            exp = now + timedelta(days=days)

    snap = load()
    items = snap['items']
    same = [it for it in items if it.get('zone') == zone and str(it.get('name', '')).strip() == name]
    if same:
        it = same[0]
        try:
            old = float(it.get('quantity') or 0)
        except (TypeError, ValueError):
            old = 0
        total = old + qty
        it['quantity'] = int(total) if total == int(total) else round(total, 1)
        if eat_by is not None and (inp.get('days') is not None or inp.get('eat_by')):
            it['eatBy'], it['expiresAt'] = _to_swift(eat_by), _to_swift(exp)
        if notes:
            it['notes'] = notes
        save(snap)
        return f"{ZONE_TITLE[zone]}已经有{name}了, 合并成 {_qty_text(it)}; {_due_label(it)} [id {_short(it.get('id'))}]"
    pos = [float(it.get('positionX') or 0) for it in items if it.get('zone') == zone]
    item = {
        'id': str(uuid.uuid4()).upper(),
        'name': name, 'quantity': qty, 'unit': unit, 'zone': zone,
        'positionX': (min(pos) if pos else 0) - 1, 'positionY': 1,
        'addedAt': _to_swift(now),
        'stickerSource': 'builtIn', 'stickerAsset': sticker,
        'notes': notes, 'addedBy': 'partner',
    }
    if eat_by is not None:
        item['eatBy'], item['expiresAt'] = _to_swift(eat_by), _to_swift(exp)
    items.append(item)
    save(snap)
    return f"放进去了: {_describe(item)}"


def fridge_consume(inp):
    snap = load()
    it, err = _pick_one(snap['items'], inp.get('target'))
    if err:
        return err
    try:
        q = float(it.get('quantity') or 1)
    except (TypeError, ValueError):
        q = 1.0
    if inp.get('all'):
        amount = q
    else:
        try:
            amount = float(inp.get('amount') if inp.get('amount') is not None else 1)
        except (TypeError, ValueError):
            raise ValueError('amount 要是数字')
        if amount <= 0:
            raise ValueError('amount 要大于 0')
    left = q - amount
    if left <= 0.0001:
        snap['items'] = [x for x in snap['items'] if x is not it]
        save(snap)
        return f"{it.get('name')}吃完了, 贴纸揭下来了"
    it['quantity'] = int(left) if left == int(left) else round(left, 1)
    save(snap)
    return f"{it.get('name')}吃掉 {int(amount) if amount == int(amount) else amount} {it.get('unit') or '份'}, 还剩 {_qty_text(it)} · {_due_label(it)}"


def fridge_remove(inp):
    snap = load()
    it, err = _pick_one(snap['items'], inp.get('target'))
    if err:
        return err
    snap['items'] = [x for x in snap['items'] if x is not it]
    save(snap)
    return f"拿走了: {it.get('name')} {_qty_text(it)}({ZONE_TITLE.get(it.get('zone'), '')})"


def fridge_note(inp):
    text = str(inp.get('text') or '').strip()
    if not text:
        raise ValueError('text 不能空')
    if len(text) > 80:
        raise ValueError('便签最多 80 字, 长话写信或直接聊')
    paper = str(inp.get('paper') or 'lined')
    attach = str(inp.get('attach') or 'washiStripe')
    font = str(inp.get('font') or 'kuaile')
    if paper not in PAPERS:
        raise ValueError('paper 要是 ' + '/'.join(PAPERS))
    if attach not in ATTACHES:
        raise ValueError('attach 要是 ' + '/'.join(ATTACHES))
    if font not in FONTS:
        raise ValueError('font 要是 ' + '/'.join(FONTS))
    snap = load()
    notes = snap['notes']
    spots = [(0.62, 0.16), (0.36, 0.30), (0.66, 0.42), (0.40, 0.92)]  # 同 iOS 端 FridgeStore.addNote
    x, y = spots[len(notes) % len(spots)]
    note = {
        'id': str(uuid.uuid4()).upper(),
        'text': text, 'author': 'partner',
        'x': x, 'y': y, 'tilt': round(random.uniform(-6, 6), 2),
        'createdAt': _to_swift(_now()),
        'paper': paper, 'attach': attach, 'font': font, 'fontSize': 26,
        'decos': [],
    }
    notes.append(note)
    save(snap)
    return f"便签贴到门上了(第 {len(notes)} 张) [id {_short(note['id'])}]"


def execute(name, inp):
    """工具入口; 返回给模型看的字符串, 不抛异常"""
    inp = inp if isinstance(inp, dict) else {}
    fn = {'fridge_list': fridge_list, 'fridge_add': fridge_add, 'fridge_consume': fridge_consume,
          'fridge_remove': fridge_remove, 'fridge_note': fridge_note}.get(name)
    if fn is None:
        return f'没有 {name} 这个冰箱工具'
    try:
        return fn(inp)
    except ValueError as e:
        return f'参数不对, 没动冰箱: {e}'
    except RuntimeError as e:
        return f'没动冰箱: {e}'
    except Exception as e:
        return f'冰箱工具出错: {type(e).__name__}: {e}'


if __name__ == '__main__':
    import sys
    print(execute(sys.argv[1] if len(sys.argv) > 1 else 'fridge_list',
                  json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}))
