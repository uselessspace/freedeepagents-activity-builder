# Reference — Typed KV data store 工具权威对照表

> **定位**：本文件是 LLM 在 `data_schema_enabled=true` 下能调的 5 个 data store 工具的**随包分发权威**。终极源头是平台仓库的 `app/card_system/data_tools.py` 与 `app/card_system/data_store.py`（外部不可达，路径仅供维护者对照）；发现本文与真实运行时行为不一致，按 bug 反馈而不是自行猜测。

> **typed-KV 是 card-system 模式的默认业务存储**。每个新活动都要在 `runtime.json` 开 `data_schema_enabled: true` 并提供 `data.schema.json`。所有写入受 schema 即时校验，所有读出由 runtime 自动注入到 system prompt（除非声明 `x-auto-inject: false`）。

## Contents

- 启用步骤 · 活动 @tools vs 通用 `data_*` · x-auto-inject 数据隔离合约
- 工具列表（5 个）与并发 / batch 规则 · 各工具签名逐条
- 常见踩坑（8 条）· 校验

## 启用步骤

1. `activities/<id>/runtime.json` 加 `"data_schema_enabled": true`
2. 新建 `activities/<id>/data.schema.json`（JSON Schema draft 2020-12，object 根，列出每个业务 key）
3. 每个 key 额外打两条扩展属性：
   - `"x-auto-inject": true | false`（默认 true）—— 是否把当前值注入系统提示
   - `"description": "..."` —— LLM 看到的字段说明（auto-inject 关闭时也会作为 hidden 标签项注入）
4. 在 schema 根加 `"default": { ... }`，runtime 会用它种子 `/instance/data.json`（首轮即可 `data_get` 拿到默认值，不必先 `data_set` bootstrap）

完整范例：[examples/card-typed-kv.md](../examples/card-typed-kv.md)。

## 活动 @tools vs 通用 `data_*`：用哪个

| 场景 | 用什么 |
|---|---|
| 用户语义清晰的写入（"加一条笔记"/"保存一个故事"/"完成一个日程"） | 写一个**活动 @tool**（`tools.py::make_tools`），内部调 `data_append` / `data_set`。函数名匹配用户意图，参数已经领域化（`add_note(content, tags)` 而不是 `data_append("notes", {...})`）。这是首选路径。 |
| 多 store 写入（typed-KV + gbrain / search index / etc.） | 活动 @tool 内部把次要 store 的写入做成 best-effort 副作用——见 [policies/multi-store-tool-design.md](../policies/multi-store-tool-design.md) |
| 一次性、低频的字段更新（admin / debug / 修复某个 key） | 直接调通用 `data_set(key, value)` |
| 读隐藏字段 | 通用 `data_get(key)`（auto-inject 已覆盖大多数读取需求，活动 @tool 通常无需再 wrap 读取；要取 `x-auto-inject:false` 的隐藏字段时才用 `data_get`） |
| 浏览 store 现状 | 通用 `data_list_keys()` |

## x-auto-inject 数据隔离合约

| `x-auto-inject` | 系统提示里能看到 | 取数方式 |
|---|---|---|
| `true`（默认） | 完整 key+value 段 | 不必显式 `data_get`，直接读 prompt |
| `false` | 仅 key 名 + description（值不显） | 必须显式 `data_get(key)` 才能拿到值 |

> **`x-auto-inject: false` 是数据隔离的硬合约**：runtime 在构建系统提示时绝不会带这些 key 的值。如果你的活动有"谜底"、"评分细则"、"系统配方"等不该让 LLM 在每轮都看到的字段，把它们标 `x-auto-inject: false` 是唯一受支持的做法（不要靠在 prompt 里"叮嘱别看"）。

> **SSE debug-view 联动**：活动只要在 `data.schema.json` 里有任何 `x-auto-inject: false` 字段，runtime verifier 就会要求 `runtime.json` 显式声明 `sse_debug_view`（即便是空 `{}`）—— 让作者明确决定 trace 工具调用是否能桥到 chat SSE。要走安全默认就写 `"sse_debug_view": {"enabled": false}`；要打开 debug 又不想暴露隐藏字段，把 `data_get` 等读访问加进 `redact_tools`。schema 见 `<package>/schemas/runtime.schema.json`，行为见 `app/models.py:SseDebugViewConfig`。

## 工具列表（5 个）

`data_set` / `data_get` / `data_append` / `data_delete` / `data_list_keys`

| 用途 | 工具 | 备注 |
|---|---|---|
| 写整个 key | `data_set(key, value)` | 替换，整 store 写后即时 schema 校验 |
| 读单个 key | `data_get(key)` | 唯一能读 `x-auto-inject: false` 的入口 |
| 数组追加 | `data_append(key, value)` | 仅对数组型 key；非数组拒绝 |
| 删除 key | `data_delete(key)` | 慎用；通常用 `data_set` 写空值代替 |
| 列所有 key | `data_list_keys()` | 返回每个 key 的 description / auto_inject / has_value / type |

## 并发 / batch 规则

- **可以同批**：同一阶段的多个独立顶层写入，例如 `data_set("theme", ...)` + `data_set("cover", ...)`，或初始化/重置时写多个互不依赖的 key。
- **顺序依赖时分批**：后续工具参数依赖前一个 data 工具结果时，先发 `data_get(...)`、等 ToolMessage 回来再发 `data_set(...)`。
- **卡片等 data 成功后再发**：`card_emit_template` 变量依赖刚写入的 data 时，先发 data 工具批次、等全部 ToolMessage 成功，再 emit 卡片（一个 assistant 消息内只放 data 写入或只放卡片，不混排）。
- **互不依赖的写入并发提交**：runtime 用 per-instance lock 串行落盘，过度逐条等待会把一次状态更新拆成多轮 LLM，明显拖慢响应。

---

## 1. `data_set(key, value)`

**写一个 typed key**，整个 store 写后立即按 `data.schema.json` 校验。校验失败该写入回滚，LLM 收到一条带 schema 错误的 ToolMessage——改正后重试即可。

- **参数**：
  - `key: str` — 必须是 `data.schema.json` 顶层 `properties` 里声明的 key。未声明的 key 在 `additionalProperties: false` 下会被 schema 拒绝。
  - `value: Any` — 任何 JSON-可序列化值（string / number / bool / object / array）。形状必须匹配 schema 中对该 key 的约束。
- **返回**：`{"status": "ok", "key": <key>, "summary": "data_set <key>"}` 或 `{"status": "error", "error": "<schema 报错原文>"}`
- **典型用法**：
  ```python
  data_set("user_profile", {"name": "Alice", "tier": "gold"})
  data_set("is_finalized", True)
  data_set("scoring_rubric", {
      "clarity": 0.4,
      "depth":   0.4,
      "style":   0.2
  })
  ```
- **追加数组元素用 `data_append`**：`data_set("notes", [...])` 永远是整数组替换；想加一项请用 `data_append("notes", {...})`。

## 2. `data_get(key)`

**读一个 typed key**。返回当前值，或 `null`（key 已在 schema 声明但未赋值，且 schema 也没给 default）。

- **参数**：`key: str`
- **返回**：`{"key": <key>, "value": <value | null>}` 或 error
- **唯一用途**：访问 `x-auto-inject: false` 的隐藏字段。auto-inject 开启的字段不必调 `data_get`——它们已经在系统提示里。
- **典型用法**：
  ```python
  # 仅在真正需要判断 / 揭晓时才读隐藏字段
  rubric = data_get("scoring_rubric")["value"]
  ```
- **过度读取会拖慢 turn** —— 不要在每轮入口都 `data_get` 一遍隐藏字段；只在确实需要判断 / 揭晓时读取。

## 3. `data_append(key, value)`

**对数组型 key 追加一个元素**。如果 key 当前不存在，先用空数组初始化再追加；如果当前值不是数组，拒绝（防止误把对象覆盖为数组）。

- **参数**：
  - `key: str` — schema 中类型必须是 `array`
  - `value: Any` — 追加的单个元素（任意 JSON 值），需满足该数组 `items` 的 schema
- **返回**：`{"status": "ok", "key": <key>, "summary": "data_append <key>"}` 或 error
- **典型用法**：history-style 数据（每轮新增一条），例如 notes / 任务列表 / 已生成的章节：
  ```python
  data_append("notes", {
      "created_at": "2026-05-16T10:30:00",
      "content": "下周二三点接孩子"
  })
  ```
- **不会去重**：append 永远追加。需要去重逻辑请先 `data_get` 拿当前数组、判重、再 `data_set` 整体写回。

## 4. `data_delete(key)`

**整个删除一个 key**。返回该 key 删除前是否存在。

- **参数**：`key: str`
- **返回**：`{"status": "ok", "key": <key>, "existed": <bool>}`
- **慎用**：大多数"清空一个字段"的需求其实想保留 schema shape，请用 `data_set` 写空值代替（`""` / `[]` / `{}` / `null` 视字段类型），这样后续读不会拿到"字段不存在"的歧义。
- **真正适合 delete 的场景**：scratch 字段、debug-only key、活动初始化阶段清空残留。

## 5. `data_list_keys()`

**列出 schema 声明的所有 key**，每个带元信息。用来探查"现在 store 里有什么"，但不泄露隐藏字段的值。

- **无参数**
- **返回**：
  ```json
  {
    "keys": {
      "<key1>": {
        "description": "<schema description>",
        "auto_inject": true | false,
        "has_value": true | false,
        "type": "string" | "object" | "array" | ...
      },
      ...
    }
  }
  ```
- **典型用法**：开局/恢复某轮时确认 store 里都有哪些字段，但不一次性把所有 hidden 值读出来。

## 常见踩坑

1. **schema 写完忘了在根加 `default`** —— 首轮 `data_get` 全返回 `null`，LLM 容易卡死在"先 bootstrap 再用"。给 `default: { ... }` 让首轮就有完整 shape。
2. **`x-auto-inject` 写在 properties 外面** —— 必须写在每个 key 自己的 schema 对象里。
3. **`additionalProperties` 默认 true** —— 想严格白名单写 `"additionalProperties": false`，否则 LLM 误写 `data_set("typoed_key", ...)` 不会被拒。
4. **想"清空但保留 shape" 误用 `data_delete`** —— 用 `data_set(key, <empty value of correct type>)`。
5. **`data_append` 对非数组使用** —— 报错，但 LLM 经常以为可以"自动转换为单元素数组"，不会。
6. **把 `data_get` 当兜底缓存** —— 每轮 prompt 已经带 auto-inject=true 的值，再 `data_get` 是冗余读，会撞 support-read budget。
7. **强制所有 `data_set` 逐条等待** —— 对互不依赖的顶层 key 是浪费。把独立 data 写放在同一个 tool-call batch，然后等结果成功后再 emit 依赖这些值的卡片。
8. **写活动 @tool 时用裸 `list` / `dict` 参数类型** —— `items: list = []` 在 DeepSeek strict 模式下被 400 拒（空 `items: {}` 无 type）。参数化容器（`list[str]` / `list[dict]`）合法；复杂/含可选字段的载荷用 JSON-encoded `str` + 函数内 `json.loads` 最稳。完整规则与自查脚本见 [../policies/llm-output-discipline.md](../policies/llm-output-discipline.md) §8d。

## 校验

活动启用 typed KV 后，verifier 会硬检查：

- `runtime.json.data_schema_enabled = true` 时 `data.schema.json` 必须存在
- `data.schema.json` 必须是合法 JSON-Schema object，根含 `properties`
- 校验源代码见 [tools/activity_verifier.py](../tools/activity_verifier.py) `_verify_runtime_configs` + 平台仓库 `app/card_system/data_store.py:load_data_schema`（外部不可达，路径供对照）
