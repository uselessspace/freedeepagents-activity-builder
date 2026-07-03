# Policy — LLM Output Discipline（工具调用纪律 + 常踩坑）

适用：**所有活动 host SKILL.md** 都应在显眼位置引用本文档（如 `Always Apply` 段）。

> **Business state 通过 typed-KV `/instance/data.json`**：用活动 @tools（`tools.py::make_tools` 暴露的那些）或通用 `data_*` 工具读写。这两类不在下面的 card-system 工具列表里。

## Card-system mode（新活动默认）

活动 `runtime.json` 设 `data_schema_enabled = true` 启用 typed-KV。**LLM 不直接构造 `ActivityAgentOutput`**——通过工具调用表达副作用，完成时直接停（transport 汇编契约权威：[output-protocol.md](output-protocol.md)）。11 个 card-system 工具 + 5 个 `data_*` 工具的完整签名权威：[references/card-system-tools.md](../references/card-system-tools.md)。

本文只管 **LLM 侧调用纪律**——下面每条都来自真实事故汇总，是 LLM 默认输出最容易偏差的位置。两条全局语义先记住：工具入参校验失败立刻返 `ToolMessage(error=...)`，修单条调用 retry；撤销同 turn 内任意撤、跨 turn 一律拒（typed-KV 写入幂等，重调覆盖即可）。

---

## 1. `assignment_id` 用模板 hard-coded 的字面 ID

每张固定卡的 `assignment_id` 在 `card_templates/<name>.json` 顶层硬编码（例如 `"<id>-welcome"`、`"<id>-result"`），调用 `card_emit_template(...)` 时直接使用模板里的字面 ID，不要在调用侧拼接序号。

写法：维护一份"模板名 → assignment_id"对照表（放在 cards SKILL.md 或 host SKILL.md 的卡片输出约定段），host SKILL.md 引用该表的字面 ID 即可。

后果说明：同一逻辑卡每轮换 assignment_id 会让前端误判成多张卡，live-update 失效。LLM 的默认倾向是按调用次序生成 `welcome_card_1` / `_2` 这种递增 ID，必须在 SKILL.md 里压住。

---

## 2. `OutputArtifact.artifact_id` 必填非空 string

`artifact_emit(...)` 必须传非空 string；pydantic 直接拒掉 `null` / 缺失。两类 artifact 的命名约定：

- markdown artifact: `story-<turn_id 前 12>` 或 `<domain>-<short uuid>`
- 非图片 file artifact: 类似上述命名

图片 artifact 由 runtime 的 live-artifact pipeline 自动 surface，LLM 只用 `image_generate` / `image_edit` 返回的 `file_url` 填卡片变量即可，不必调 `artifact_emit`。

---

## 3. 图片 artifact 由 runtime 自动 surface

见 §2 末行：`image_generate` / `image_edit` 的产物由 runtime live-artifact pipeline 自动 surface，**LLM 只填返回的 `file_url` 进卡片变量，不调 `artifact_emit`**（那是给 markdown 等非图片 artifact 的）。完整 artifact 规则见 [output-protocol.md](output-protocol.md) §artifacts。

---

## 4. `OutputArtifact` 引用字段是 `url` / `path`

`artifact_emit({"url": "https://..."})` 或 `artifact_emit({"path": "/instance/..."})`，二选一。字段名是 `url` 或 `path`；StrictModel 不接受其它别名（写 `file_url` 会触发 `Extra inputs are not permitted`）。

---

## 5. 写业务数据的纪律（typed-KV）

完整编辑规则（首选活动 @tool / 兜底 `data_*` / 校验回滚语义 / runtime-derived 7 字段禁写 / 两个 phase 命名空间）的**权威是 [output-protocol.md](output-protocol.md) §state 编辑规则**。本节只留 LLM 高频踩坑三条：

- 读隐藏字段的**唯一入口**是 `data_get(key)`；`x-auto-inject: true` 的字段已注入 system prompt，直接读 prompt，**不要** `read_file('/instance/data.json')` 直读。
- `data_delete(key)` 是整字段删除；想保留 schema 形态写空值用 `data_set(key, <empty value>)`。
- 切**展示层** phase 的方式是 emit 一张 `meta.phase = "<目标>"` 的卡片——runtime-derived 字段没有写入工具，别去找。

---

## 6. Sandbox 文件路径以 `/activity/skills/<id>/...` 为准

容器内 skill 目录是**扁平挂载**到 `/activity/skills/`，跟 manifest 的 `skill_sources = ["activities/<id>/skills/<id>-host"]` 写法**不一样**——容器内不带 `activities/<id>/` 前缀。

容器内访问路径模板：

| 想读什么 | 路径 |
|---|---|
| 本活动的 SKILL.md | `/activity/skills/<skill-name>/SKILL.md` |
| 本活动的 workflows / policies / references | `/activity/skills/<skill-name>/workflows/<name>.md` 等 |
| 本活动的 card_templates | `/activity/card_templates/<name>.json` |
| 共享 schemas | `/schema/activity-output.schema.json` |
| 用户记忆（read-only） | `/user/memory/AGENTS.md` |
| 实例工作区 | `/instance/workspace/...` (rw) |
| 实例 turn 历史 | `/instance/turns/<turn_id>/...` (ro) |

---

## 7. Turn boundary — 一条业务流水线必须同 turn 内完成

✅ progress 卡 + 终态卡都在同一 turn 内发完才停。如果先 emit 了一张 `card_emit_template(...)` 形式的 progress card 用来给用户展示进度，**继续工作**直到最终 emit 终态卡；progress 卡和终态卡会一起出现在 final 输出里。

✅ 只想让 progress 卡作过渡：emit 完终态卡后调 `card_retract(progress_card_id)` 把它撤掉。

✅ host SKILL.md 在多步流水线处明示 `## Turn boundary（HARD）` 段："phase X → Y → Z 必须同 turn 完成"，让 LLM 不会把中间态当终点。

> **多阶段活动等用户输入：用 `await_user(reason="...")` 软停**——它不把 instance 推向终态（status 仍是 `running`），只在下一 turn 的 system prompt 里把 reason 当 hint 注入。和 `mark_status` 互斥；任一被调过本轮就立刻结束，等下一 turn。

---

## 8. StrictModel 字段表

每个 block / 字段都是 pydantic **StrictModel**：只接受类定义里的字段，多写一个未定义字段会触发 `OutputValidationError`。设计模板前对照随包分发的 [`schemas/card-template.schema.json`](../schemas/card-template.schema.json) 对应 `$defs` 确认字段表（与运行时模型由 `check_schema_sync` 守卫一致）。

- 当前支持的 6 种 block：`MarkdownBlock` / `InfoBlock` (+ `InfoItem`) / `FormBlock` (+ `FormField`) / `ActionBlock` (+ `ActionItem`) / `ImageBlock` (+ `ImageItem`) / `AudioBlock` (+ `AudioItem`)；加上 `OutputCard` / `MinimalAICard` / `OutputArtifact`
- `FormField.input_type` 取值为 `text` / `textarea` / `number` / `file` / `audio` / `hidden` 之一（`audio` 为浏览器录音控件；`hidden` 不渲染输入控件，但提交时会把 `default_value` 一起序列化）；枚举式选择改用 `ActionBlock` 按钮组
- `hidden` 字段只能携带非敏感上下文 ID（如 `memory_id` / `record_id` / `assignment_id`），不是安全边界；不要把密钥、权限 token、隐私原文放进 hidden field，活动侧仍要校验提交 ID 的归属
- card-system 工具会在调用入参时按 pydantic 校验整个 card 对象；字段错了会即时 `ToolMessage(error=...)`，按报错改正参数 retry

---

## 8b. markdown content 内的字符串安全

写 `card_emit` / `card_emit_template` 的 markdown content 时，确保整个字段值能作为 JSON 字符串被解析：

- **引述 / 强调 / 对话引用统一用中文引号**（`「」` / `『』`）或 markdown backtick（`` ` ``），让 content 字符串里**不出现裸 ASCII 双引号**。
  ```json
  {"content": "你问我「关于 XX 有没有记过什么」，我就能..."}
  {"content": "你问我 `关于 XX 有没有记过什么`，我就能..."}
  ```
- 需要在 content 里展示包含 ASCII 双引号 / 反斜杠 / 字面换行的内容（代码示例、Windows 路径、raw regex 等），放进 markdown 代码块（三反引号）里——代码块内部不会被再尝试塞 JSON-unsafe 字符。

后果说明：content 里夹带未转义的 ASCII 双引号 / 反斜杠 / 字面换行会让 tool-call JSON 解析失败，整轮变 `invalid_tool_call`（错误信息形如 `Function card_emit arguments are not valid JSON. JSONDecodeError: Expecting ',' delimiter`）。LLM 看不到错误反馈，会反复 retry execute / read_file，最终触发 19s 后的 `zero-emit-fallback`，用户看到"AI 本轮未能给出有效回答"。

> 所有 LLM 都适用，DeepSeek 系列尤其需要注意——它倾向用 ASCII `"` 引中文关键词；SKILL.md 顶部明确"中文引述用「」" 一句话即可压住。

---

## 8c. Single-emit-then-stop（HARD）

适用场景：问候 / 闲聊 / welcome / intake / error fallback / final result 这类**已经有明确可见输出**的简单路径。流程严格三步：

1. 选定唯一输出卡片。
2. 调一次 `card_emit_template(...)` 或 `card_emit(...)`。
3. 工具成功后立即停止。

跟着这套流程：

- 同一信息用一张模板卡承载即可——它就是该内容的唯一载体，不必再手拼等价的 ad-hoc markdown 卡。
- 同一个 `card_emit_template(...)` 调用一次就停，不为"保险"再调。
- `card_retract(card_id)` 仅在刚发错、progress 卡收尾、或 tool error 后修正时使用；retract 后不要再重发同一张正确卡。
- 问候 / smalltalk fast path 不读 SKILL.md / policies / workflows / templates；fast path 所需变量直接 inline 在 AGENTS.md 或 host SKILL.md。

后果说明：fixed-template / site-template / anonymous card 的 retract→re-emit loop 真实 smoke trace 里都来自"第一张卡已经正确，但 LLM 继续检查 / 补发 / 撤回"。这会把一个 1-tool greeting turn 拉成几十秒，严重时触发 zero-emit retry 或交付 0 张卡。

并发说明：同一 turn 内多个 `data_set` / `data_append` 可以并行表达不同业务字段，runtime 工具层会做写入校验；**同一条可见输出路径**只 emit 一次。

验证：FreeDeepAgents 仓库的 `scripts/dev_smoke_card_system.py` 覆盖了 fixed-template、site-template 和 anonymous card 的 retract→emit 回归用例（仅在仓库里跑；外部用户的等价做法是 install + 跑一次真实 turn 看 trace 里的卡数）。改 host fast path 后跑一次确认问候类 turn 只产生预期卡片。

---

## 8d. 活动 @tool 参数 schema（DeepSeek strict 模式）

适用：写 `activities/<id>/tools.py::make_tools` 暴露的 @tool 函数时。

DeepSeek strict 模式（runtime 默认开启）会把 @tool 函数签名转成 JSON Schema 发给模型，并要求每个 `anyOf` 分支 / `array.items` 都含 `type` / `anyOf` / `$ref` 之一。下面三条是写 @tool 时必须遵守的形态规则。

### 规则 1：禁裸 `list` / `dict`；参数化容器合法，JSON-encoded `str` 是兼容性最稳的兜底

判定标准只有一条：**容器的 `items` 必须有确定 item 类型**。裸 `list` / `dict` 会被 pydantic 转成 `{"type":"array","items":{}}` —— 空 `items: {}` 没有 `type`，DeepSeek strict 报 `400 Invalid tool parameters schema`。给它一个 item 类型即可消除。

| 写法 | strict 转换后 `items` | strict 模式 |
|---|---|---|
| `items: list` / `dict`（裸） | `{}` | ❌ 拒（空 schema 无 type） |
| `items: list[str]` | `{"type":"string"}` | ✅ 接受 |
| `items: list[dict]` | `{"type":"object","additionalProperties":false}` | ✅ 接受（LangChain strict 自动补 `additionalProperties:false`，满足 DeepSeek「object 须 additionalProperties:false」规则） |
| `items: str = "[]"`（JSON 串） | `{"type":"string"}` | ✅ 接受 |

**两种合法写法，按场景选：**

```python
# 写法 A — 参数化容器（item 形状简单 / 想让模型看到结构时优先）
@tool("set_tags")
def set_tags_tool(tags: list[str]) -> dict:
    """...Args: tags: 标签列表..."""
    ...

# 写法 B — JSON-encoded str（item 形状复杂、含可选字段、或要跨模型最大兼容时）
@tool("set_brief")
def set_brief_tool(items: str = "[]") -> dict:
    """...Args: items: JSON-encoded list of per-topic records...."""
    parsed = json.loads(items)
    if not isinstance(parsed, list):
        raise AppError("items must be a JSON list", status_code=400)
    ...
```

写法 B 仍是**跨模型兼容性最稳**的选择：① DeepSeek strict 还禁用 `minItems`/`maxItems`/`minLength`/`maxLength` 且要求 object 所有属性 required —— 复杂 `list[dict[带可选字段]]` 经 strict 转换后会把可选字段强制 required，行为可能不符预期；② LLM 序列化 tool-call 时本来就把 list 表达成字符串，`json.loads + 手工校验`还原即可（本地 Python 调用记得 `json.dumps([...])`，写法 B 代码即完整模式）。用 `<package>/skills/activity-verify/scripts/strict-tool-schema-check.py` 对自己的 tools.py 跑一遍即可确认形态合法。

> 官方约束依据：[DeepSeek strict 工具调用](https://api-docs.deepseek.com/zh-cn/guides/tool_calls) —— 每个 object 须「所有属性 required + additionalProperties:false」，且不支持 min/max 长度与项数。

### 规则 2：参数类型保持单一；可选用 `str | None`

```python
def tool(topic_id: str, label: str = "") -> dict: ...   # 单一标量
def tool(memo: str | None = None) -> dict: ...          # 可选字符串
```

`X | None` 是允许的 Union 形态：pydantic 生成 `{"anyOf":[{"type":"X"},{"type":"null"}]}`，两个分支都有 `type`，DeepSeek 接受。其它 Union（`str | list`、`int | str` 等）会引入缺 `type` 的分支，把它收窄到单一类型再写，必要时函数内部手工分流。

### 规则 3：docstring `Args:` 段每个参数用自然语言展开字段

```python
"""
Args:
    items: JSON-encoded list of per-topic records. Each record is an
        object with keys topic_id (optional), topic_name, results
        (list of title/url/snippet objects), and error (optional).
"""
```

langchain 的 docstring 解析器会把 `Args:` 段里出现的 brace-style 对象（如 `{topic_id, name, results}`）当作新参数名扫，遇到函数签名里没有的就 `ValueError` 终止加载。把对象字段用句号 / 列表式英文展开即可绕过。

### 自查（package release 前跑一次）

用随包脚本，别手写：`python <package>/skills/activity-verify/scripts/strict-tool-schema-check.py --activity <id>`（无平台仓库时改用 `python <package>/testkit/fda_testkit.py activities/<id>`，它也查每个工具的 strict 形态）。全部 `ok` 才算干净——出 trace 时碰到 `BadRequestError: Invalid tool parameters schema : field 'anyOf'` 几乎都是上面三条规则之一没遵守。

---

## 9. 撤销 + 重做心智模型

LLM 发完卡片后可以撤回再重发，但要警惕**反复撤回让自己混乱**。指引：

- 只在确实察觉自己刚发错时调 `*_retract`，比如：
  - tool 返 error → 立刻 retract 错卡再补正确卡
  - emit 完 progress 卡 → 业务完成后 retract progress 卡 + emit 终态卡
  - 误填了字段 → retract + 重发
- 仅在有具体原因（错发 / progress 收尾 / tool error 修正）时调 `*_retract`；其余情况让卡片留在最终输出里。
- 跨 turn 撤回会被工具拒收（返 error），不要尝试。

---

## 10. 闲聊兜底（runtime 默认注入）

通用 runtime 在 card-system 模式下自动注入一条 fallback：用户输入与活动业务路由都不匹配时，emit 一张文本卡（`card_emit({type: "markdown", content: "..."})`）就停止，不调任何其他工具、不写业务数据。

如果你的活动认为某些"看似闲聊"的输入其实是业务信号（比如宠物类活动把"主人我累了"当作互动 trigger），在 host SKILL.md 里**显式声明**："本活动认为 X 是业务信号，不走闲聊兜底"，并把它编进对应 workflow。

---

## 11. host SKILL.md 推荐结构

完整可复制模板的**权威是 [references/host-skill-template.md](../references/host-skill-template.md)**（含路由表 / 状态段 / 卡片约定 / Turn boundary 骨架）。与本文相关的硬要求只有三条：host SKILL.md 顶部明示引用本 policy、卡片输出约定段含字面 `assignment_id` 表、多步流水线处有 `## Turn boundary（HARD）` 段。

---

## 自检（活动 release 前过一遍）

- [ ] host SKILL.md 顶部明示引用本 policy
- [ ] 卡片输出约定段含字面 assignment_id 表 + "不要自创"
- [ ] 业务数据规则段明示活动 @tools / `data_*` 写法 + runtime-derived 字段禁写清单
- [ ] 沙箱路径示例都是 `/activity/skills/...`（不是 `/activity/activities/...`）
- [ ] 有 `## Turn boundary（HARD）` 段（如果业务是多步流水线）
- [ ] 若有"看似闲聊实为业务信号"的输入，在 host SKILL.md 显式声明覆盖默认 smalltalk fallback
- [ ] 「card_emit markdown content 用「」或 backtick 而非 ASCII 引号」这条规则在 host SKILL.md 引用或重述（deepseek 模型尤其需要）
