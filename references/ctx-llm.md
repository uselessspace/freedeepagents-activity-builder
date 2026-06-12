# Reference — `ctx.llm`（活动侧 side-channel LLM 调用）

`ctx.llm` 是 `make_tools(ctx)` / `make_handlers(ctx)` 收到的 ctx 对象上的**网关感知 LLM helper**。活动代码需要在工具 / handler 内部做一次性文本生成、JSON 结构化输出、或多模态看图分析时，一律走它——**不要自带 HTTP 客户端直连 provider、不要读任何 `*_API_KEY` 环境变量**（verifier 的 credential 硬检查会 ERROR 拦下，见文末）。

主对话（turn loop）不归它管：主模型由 runtime 按 `manifest.model` 驱动。`ctx.llm` 的定位是 *side-channel*——例如"生成漫画分镜文案""把场景图片转成结构化描述""离线总结一段记忆"这类工具内部的补充调用。

## Contents

- 启用方式（无需声明；None 判空）
- 方法签名：`chat` / `chat_json` / `vision`
- 错误语义（None 不抛异常）· 模型路由 · 计费与归因
- 选型表 · credential 检查（指针）· 离线测试 · 排错

---

## 启用方式

**无需任何声明。** 它不是 manifest capability——runtime 在两条生产路径（turn 工具路径、SPA handler 路径）构建 ctx 时总是注入。

唯一例外：极简测试 ctx（构建时没给 settings，如 testkit 的 `FakeCtx`）里 `ctx.llm` 是 `None`。因此**调用前必须判 None 并降级**：

```python
if ctx.llm is None:
    return {"error": "llm unavailable"}   # 或走纯规则 fallback
```

---

## 方法签名（全部同步调用）

### `ctx.llm.chat(...) -> str | None`

一次性 system+user 补全，返回文本内容。

```python
text = ctx.llm.chat(
    system="你是一个婚礼回忆整理助手……",
    user="把下面的对话整理成一段叙事：……",
    model=None,            # None → 平台默认模型；或 "deepseek:deepseek-v4-flash" / 网关别名
    max_tokens=1500,
    temperature=0.7,
    json_mode=False,       # True → response_format=json_object
    timeout=90.0,          # 本次调用的传输超时（秒）
)
```

### `ctx.llm.chat_json(...) -> dict | None`

`chat` 的 JSON 模式便捷封装：自动开 `json_mode`、剥 ` ```json ` 围栏、`json.loads` 成 dict。解析失败也返回 `None`。

```python
plan = ctx.llm.chat_json(
    system="输出 JSON：{\"pages\": [...]}",
    user=outline_text,
    max_tokens=2000,
)
if plan is None:
    ...  # 降级
```

### `ctx.llm.vision(...) -> str | None`

多模态补全：一段文本 prompt + 一张或多张图。**这是平台认可的"看图"路径**（场景图分析、扫描件理解、照片描述）。

```python
import base64

with open(image_path, "rb") as f:
    b64 = base64.b64encode(f.read()).decode("ascii")

text = ctx.llm.vision(
    prompt="提取这页场景图里的实体和关系，输出要点列表。",
    image_urls=[f"data:image/png;base64,{b64}"],   # data URL 或 http(s) URL 均可
    system=None,
    model="qwen-vl-plus",   # 默认值；网关开启时按网关别名解析
    max_tokens=2048,
    temperature=0.7,
    timeout=90.0,
)
```

`image_urls` 每个元素是 OpenAI `image_url` 取值：`data:<mime>;base64,<...>`（调用方自己编码字节）或公网 http(s) URL。多图 = 列表里放多个。

---

## 错误语义：返回 `None`，不抛异常

误配置（没有可用 endpoint/key）、网络错误、HTTP 非 2xx、超时——**全部返回 `None`**。调用方必须有降级路径（返回错误提示、走纯规则逻辑、跳过该增强步骤）。不要假设重试能救活：先把 `None` 当成"这条路今天不可用"。

---

## 模型路由

- `ctx.llm` **不读** `manifest.model` / `manifest.graph_model`。不传 `model=` 时用平台默认模型（`ACTIVITY_DEFAULT_MODEL`，当前默认 `deepseek:deepseek-v4-flash`）。
- 按调用传 `model=` 即可换模型——这正是"主模型纯文本、VL 单独指定"的设计内用法：
  - **网关开启时**（生产/hard mode）：模型名按 LiteLLM 网关别名解析（如 `qwen-vl-plus`）；`provider:` 前缀会被剥掉只留模型名。
  - **网关关闭时**（本地直连，过渡期）：`"deepseek:xxx"` 路由 deepseek，`"dashscope:xxx"` 或裸名路由 dashscope 兼容端点。
- `vision()` 的 `model` 默认就是 `qwen-vl-plus`，通常不用动。

---

## 计费与归因

网关链路上每次调用都带完整归因，LiteLLM spend log 自动记账：

- **bearer**：本次请求经验证的 Go token（hard mode；LiteLLM `custom_auth` 复核），dev 环境回落到平台网关 key。活动代码**接触不到任何 provider key**。
- **spend 主体**：`user` = 活动实例 id；`spend_logs_metadata` 附 `fda_user_id`（终端用户）+ `fda_activity_slug`（活动类型）。
- **media 同理**：`image_generate` / `tts_generate` 工具经 media-proxy sidecar，转发同一 Go token 计账。

限额相关的事实：

- `ctx.llm` 当前**没有独立的 per-turn 调用次数上限**（图像/TTS 有各自的 per-turn 计数器）。成本治理在网关侧（LiteLLM 预算/限速），不在活动侧。
- `timeout=` 是本次 HTTP 调用自己的超时，**与 `runtime.json` 的 `llm_timeout_seconds` 无关**（后者管主 turn loop 的模型调用）。注意工具整体耗时仍占用 turn 的墙钟时间，长链路请自行控制调用次数。

---

## 选型表：哪条路做哪件事

| 需求 | 正确路径 |
|---|---|
| 主对话 / 卡片输出 | runtime turn loop（`manifest.model`），不用自己调 |
| 工具内一次性文本生成 / JSON 结构化 | `ctx.llm.chat` / `ctx.llm.chat_json` |
| 看图（场景图、扫描件、照片理解） | `ctx.llm.vision` |
| 文本层文档抽取（PDF/Word/PPT/Excel/HTML/CSV/JSON → Markdown） | `read_document` capability（见 [document-tools.md](document-tools.md)）——有文字层就别走 VL |
| 文生图 / 图生图 | `image_generate` / `image_edit` capability（见 [image-tools.md](image-tools.md)） |
| 文本转语音 | `tts_generate` capability（见 [tts-tools.md](tts-tools.md)） |

经验法则：文档**有文字层**用 `read_document`（便宜、确定性强）；**纯图像内容**（扫描件、手绘、场景图）才用 `vision`。两者可以组合：先 `read_document` 拿正文，对嵌入图片单独 `vision`。

---

## 与 credential 硬检查的关系

触发模式、口径边界（只禁平台代为计费的 provider，非 provider 第三方 HTTP 不受限）、影响面（只拦包验收、不影响已部署实例）的**权威是 [verifier-checks.md](verifier-checks.md) hard check #13**。被拦下的修复路径就是本文：LLM → `ctx.llm`，媒体 → capability 工具。

---

## 离线测试（testkit）

testkit 的 `FakeCtx.llm` 是 `None`——你的降级分支会被自动测到。要测 LLM 依赖分支，在 pytest 里给 ctx 挂一个鸭子类型的 fake（只需实现你用到的方法）：

```python
class FakeLLM:
    def chat(self, **kw):
        return "canned reply"
    def chat_json(self, **kw):
        return {"pages": []}
    def vision(self, **kw):
        return "scene: two people, sunset"

with activity_harness(activity_dir) as ctx:
    ctx.llm = FakeLLM()
    tools = {t.name: t for t in make_tools(ctx)}
    ...
```

---

## 排错：为什么返回 `None`

| 现象 | 常见原因 |
|---|---|
| 永远 `None`，trace 无 LLM 痕迹 | ctx 没拿到 settings（测试 ctx）→ `ctx.llm is None`，先判空 |
| 网关模式下 `None` | 模型名不是网关别名（让平台运维确认 LiteLLM `config.yaml` 里有该 `model_name`）；或 Go token 失效（401） |
| 直连模式下 `None` | 平台未配该 provider 的 key（过渡期配置），或模型名拼错 |
| `chat_json` 为 `None` 但 `chat` 正常 | 模型输出不是合法 JSON——加强 system 里的格式约束，或降 temperature |
| 偶发 `None` | 传输超时——调大 `timeout=`，或缩小 `max_tokens` / 输入体积 |
