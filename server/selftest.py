#!/usr/bin/env python3
"""最小自测: 起一个临时服务, 验证鉴权、GET/PUT、五个工具, 以及产出 JSON 的日期/枚举格式符合 Swift 端 Codable。
用法: python3 selftest.py   (全过打印 ALL OK, 否则非零退出)"""
import json
import os
import tempfile
import threading
import urllib.error
import urllib.request

tmp = tempfile.mkdtemp()
os.environ['FRIDGE_DATA_FILE'] = os.path.join(tmp, 'fridge.json')
os.environ['FRIDGE_TOKEN'] = 'test-token'

import server  # noqa: E402
import tools   # noqa: E402
from http.server import ThreadingHTTPServer  # noqa: E402

httpd = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()
BASE = f'http://127.0.0.1:{httpd.server_address[1]}'


def call(method, path, body=None, token='test-token'):
    req = urllib.request.Request(BASE + path, method=method,
                                 data=None if body is None else json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json'})
    if token:
        req.add_header('Authorization', f'Bearer {token}')
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def check(cond, msg):
    print(('ok   ' if cond else 'FAIL ') + msg)
    if not cond:
        raise SystemExit(1)


# 鉴权
check(call('GET', '/api/fridge', token=None)[0] == 401, '无 token -> 401')
check(call('GET', '/api/fridge', token='bad')[0] == 401, '错 token -> 401')
# 空
code, body = call('GET', '/api/fridge')
check(code == 200 and body == {'value': None}, '空冰箱 GET -> value null')
# PUT 一份「Swift 风格」快照 (日期 = 2001 基准秒)
now_swift = tools._to_swift(tools._now())
seed = {'items': [{'id': 'AAAAAAAA-0000-0000-0000-000000000001', 'name': '牛奶', 'quantity': 2, 'unit': '瓶',
                   'zone': 'doorMid', 'positionX': 0, 'positionY': 1, 'addedAt': now_swift,
                   'eatBy': now_swift + 86400, 'expiresAt': now_swift + 2 * 86400, 'stickerSource': 'builtIn',
                   'stickerAsset': 'milk', 'notes': '', 'addedBy': 'me'}], 'notes': [], 'magnets': []}
check(call('PUT', '/api/fridge', {'value': seed})[0] == 200, 'PUT 快照')
check(call('GET', '/api/fridge')[1]['value']['items'][0]['name'] == '牛奶', 'GET 读回')
check(call('PUT', '/api/fridge', {'value': 5})[0] == 400, 'PUT 非对象 -> 400')

# 五个工具 (通过 HTTP 和直接调用各走一遍)
def tool(tool_name, **inp):
    code, body = call('POST', '/api/tool', {"name": tool_name, "input": inp})
    check(code == 200, f'POST /api/tool {tool_name}')
    print('      ' + body['result'].replace('\n', '\n      '))
    return body['result']

check(len(tools.TOOLS) == 5 and all('input_schema' in t for t in tools.TOOLS), '5 个工具有 JSON Schema')
r = tool('fridge_list'); check('牛奶' in r, 'fridge_list 看得到牛奶')
r = tool('fridge_add', name='昨晚的红烧肉', notes='热一下就能吃', days=2); check('放进去了' in r, 'fridge_add')
r = tool('fridge_add', name='牛奶', quantity=1, zone='门架中'); check('合并成 3 瓶' in r, 'fridge_add 同层同名合并')
r = tool('fridge_consume', target='牛奶', amount=2); check('还剩 1 瓶' in r, 'fridge_consume 减量')
r = tool('fridge_note', text='牛奶周五前喝完哦'); check('便签贴到门上' in r, 'fridge_note')
r = tool('fridge_remove', target='红烧肉'); check('拿走了' in r, 'fridge_remove')
r = tool('fridge_consume', target='牛奶', all=True); check('吃完了' in r, 'fridge_consume all')
check('参数不对' in tools.execute('fridge_note', {'text': ''}), '坏参数不动冰箱且不抛异常')
tool('fridge_add', name='草莓')

# 格式校验: 与 Swift Codable 对齐
snap = call('GET', '/api/fridge')[1]['value']
ZONES = {z for z, _ in tools.ZONES}
for it in snap['items']:
    check(it['zone'] in ZONES and it['addedBy'] in ('me', 'partner') and it['stickerSource'] == 'builtIn', f"item {it['name']} 枚举合法")
    for k in ('addedAt', 'eatBy', 'expiresAt'):
        if k in it:
            # Swift 默认日期 = 2001 基准秒: 现在约 8e8; 若误写成 unix 秒会是 1.7e9
            check(isinstance(it[k], (int, float)) and 0 < it[k] < 1_500_000_000, f"item {it['name']}.{k} 是 2001 基准秒 ({it[k]})")
n = snap['notes'][0]
check(n['author'] == 'partner' and n['paper'] in tools.PAPERS and n['attach'] in tools.ATTACHES
      and isinstance(n['createdAt'], float) and n['createdAt'] < 1_500_000_000 and n['decos'] == [], 'note 字段合法')
httpd.shutdown()
print('ALL OK')
