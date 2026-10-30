#!/usr/bin/env python3
"""冰箱同步后端 (纯标准库)。

  GET  /api/fridge  -> {"value": <快照或 null>}
  PUT  /api/fridge  <- {"value": <快照>}     (也接受直接就是快照的 body)
  POST /api/tool    <- {"name": "fridge_list", "input": {...}}  -> {"result": "..."}   (给 AI 助手用)
  GET  /api/tools   -> 五个工具的 JSON Schema 定义

鉴权: 环境变量 FRIDGE_TOKEN，请求头 Authorization: Bearer <token>。FRIDGE_TOKEN 没设时拒绝启动。
其它: FRIDGE_HOST(默认 0.0.0.0) FRIDGE_PORT(默认 8787) FRIDGE_DATA_FILE(默认 server/fridge_data.json)

注意: 这是个 HTTP 小服务，公网使用请放在 HTTPS 反代 (nginx/caddy) 后面。
"""
import hmac
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import store
import tools

TOKEN = os.environ.get('FRIDGE_TOKEN', '')
MAX_BODY = 8 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    server_version = 'FridgeServer/1.0'

    def _cors(self):
        # 网页前端挂在别的域名时浏览器要跨域许可；FRIDGE_CORS 填你的前端域名，默认 *（任何域名）
        self.send_header('Access-Control-Allow-Origin', os.environ.get('FRIDGE_CORS', '*'))
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.send_header('Access-Control-Allow-Methods', 'GET, PUT, POST, OPTIONS')

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def _send(self, code, obj):
        data = json.dumps(obj, ensure_ascii=False).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self._cors()
        self.end_headers()
        self.wfile.write(data)

    def _authed(self):
        got = self.headers.get('Authorization', '')
        expect = f'Bearer {TOKEN}'
        if not hmac.compare_digest(got.encode(), expect.encode()):
            self._send(401, {'error': 'unauthorized'})
            return False
        return True

    def _body(self):
        n = int(self.headers.get('Content-Length') or 0)
        if n > MAX_BODY:
            raise ValueError('body 太大')
        return json.loads(self.rfile.read(n) or b'null')

    def _path(self):
        return self.path.split('?')[0].rstrip('/')

    def do_GET(self):
        if not self._authed():
            return
        p = self._path()
        if p == '/api/fridge':
            try:
                self._send(200, {'value': store.read()})
            except RuntimeError as e:
                self._send(500, {'error': str(e)})
        elif p == '/api/tools':
            self._send(200, {'tools': tools.TOOLS})
        else:
            self._send(404, {'error': 'not found'})

    def do_PUT(self):
        if not self._authed():
            return
        if self._path() != '/api/fridge':
            return self._send(404, {'error': 'not found'})
        try:
            body = self._body()
            value = body.get('value') if isinstance(body, dict) and 'value' in body else body
            if not isinstance(value, dict):
                return self._send(400, {'error': 'value 必须是对象'})
            snap = {k: value.get(k) if isinstance(value.get(k), list) else [] for k in ('items', 'notes', 'magnets')}
            store.write(snap)
            self._send(200, {'ok': True})
        except (ValueError, json.JSONDecodeError) as e:
            self._send(400, {'error': str(e)})

    def do_POST(self):
        if not self._authed():
            return
        if self._path() != '/api/tool':
            return self._send(404, {'error': 'not found'})
        try:
            body = self._body() or {}
            self._send(200, {'result': tools.execute(body.get('name', ''), body.get('input') or {})})
        except (ValueError, json.JSONDecodeError) as e:
            self._send(400, {'error': str(e)})

    def log_message(self, fmt, *args):
        sys.stderr.write('%s - %s\n' % (self.address_string(), fmt % args))


def main():
    if not TOKEN:
        sys.exit('请先设置环境变量 FRIDGE_TOKEN (Bearer token)')
    host = os.environ.get('FRIDGE_HOST', '0.0.0.0')
    port = int(os.environ.get('FRIDGE_PORT', '8787'))
    print(f'fridge server on http://{host}:{port}/api/fridge  data={store.DATA_FILE}')
    ThreadingHTTPServer((host, port), Handler).serve_forever()


if __name__ == '__main__':
    main()
