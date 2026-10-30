# Fridge server

纯标准库 Python 3（无需安装依赖），一个 JSON 文件存一份冰箱快照，格式与 iOS 端 `FridgeStore.Snapshot` 的 Codable JSON 完全一致（日期是 Swift 默认的「2001-01-01 起的秒数」，author 枚举为 `me` / `partner`）。

## 运行
    export FRIDGE_TOKEN=换成你自己的长随机串
    python3 server.py          # 默认 0.0.0.0:8787，FRIDGE_HOST / FRIDGE_PORT / FRIDGE_DATA_FILE 可改

- `GET /api/fridge` -> `{"value": 快照 | null}`；`PUT /api/fridge` 体为 `{"value": 快照}`；均需 `Authorization: Bearer <token>`。
- `POST /api/tool` `{"name","input"}` 执行 AI 工具；`GET /api/tools` 返回工具 JSON Schema。
- 公网使用请放在 HTTPS 反代后面。

## AI 工具 (tools.py)
`TOOLS` = 看冰箱 `fridge_list` / 放东西 `fridge_add` / 吃掉 `fridge_consume` / 拿走 `fridge_remove` / 贴便签 `fridge_note` 的定义（Anthropic 风格 `input_schema`，OpenAI 把它当 `parameters` 即可），`execute(name, input)` 返回给模型的字符串。直接 `import tools` 读写本地数据文件，或经 `/api/tool` 远程调用。

## 自测
    python3 selftest.py        # 末尾打印 ALL OK
