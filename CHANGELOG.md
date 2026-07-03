# Changelog — freedeepagents-activity-builder

## 0.4.14 (2026-06-29)

补 `ctx.user_name` 作者文档：调用者显示名，来自 `X-FDA-User-Name` 头（percent-decoded），仅用于界面展示 / 署名；身份校验、归属鉴权、配额管理仍须用 `ctx.user_id`；best-effort，头缺席时为 `None`，使用前须判空（平台 commit 8fa5f580，2026-06-23 上线）。

- **`references/user-upload.md`**：在「归属：平台不管业务」一节的 `ctx.user_id` 说明后紧接补充 `ctx.user_name` 三要点注记。

## 0.4.13 (2026-06-29)

新增 `activity-review` skill——编码阶段的语义级 Agent 质量自审，由在场编码 agent 执行，
专抓确定性 verifier 查不出的"逻辑冲突"（指令自相矛盾、卡片编排不成立、承诺↔能力错配）。

- **`skills/activity-review/`**：新独立工具（家族第 4 个：verify 查契约 → review 看自洽 →
  smoke 验运行）。非阻塞、不调外部服务、不做发布门槛；只对照活动**自身声明的意图** + 插件
  `policies/`，不引入外部"好活动"参照、不复判 verify 契约。`references/review-rubric.md`
  六维清单 + `examples/seed-defect-activity/` 验收 fixture（非可发布、勿入 `activities/`）。
- **`.claude-plugin/plugin.json`**：`skills[]` 登记 `skills/activity-review`（`.codex-plugin`
  目录扫描自动发现）。
- **根 `SKILL.md` / `INSTALL.md` / `README.md`**：按需工具清单补 `/activity-review`。
- **`skills/activity-builder/SKILL.md`**：Done Criteria 增加**可选** `/activity-review` 自审
  hand-off（明确非完工门禁、打包流程不依赖）。

## 0.4.12 (2026-06-29)

补齐 `FormField.input_type="hidden"` 的活动作者契约，并同步 builder schema。

- **`schemas/card-template.schema.json`**：`FormField.input_type` 枚举加入 `hidden`，与运行时
  `OutputCard` 模型保持一致。
- **`references/card-block-types.md` / `policies/llm-output-discipline.md`**：说明 `hidden` 字段
  不渲染输入控件，但表单提交时会把 `default_value` 一起序列化；适合携带非敏感上下文 ID
  （如 `memory_id` / `record_id` / `assignment_id`），不是安全边界，活动侧仍要校验归属。
- **`references/verifier-checks.md`**：更新卡片模板 schema 校验示例，避免把 `hidden` 误判成非法
  input type。

## 0.4.11 (2026-06-25)

补齐 `api/upload` 的跨平面回取说明，并让 `frontend-base` 覆盖 Go developer preview 挂载。

- **`references/user-upload.md`**：新增「`resource_ref` 端到端」配方，明确 `dsl_builder` 不投影、
  投影发生在 Go 预览代理；说明可投影字段闭集
  `read_url / file_url / image_url / thumbnail_url / audio_url / trace_url`，以及聚合对象的
  `resource_refs` 语义。
- **`frontend-base/src/lib/api-base.ts` / `asset-url.ts`**：除 `/preview/<aid>/<iid>/` 与
  `/dev/preview/<aid>/<iid>/` 外，支持
  `/api/v1/developer/activity-types/<aid>/activities/<iid>/preview/`，让 `apiUrl()` 与
  `resolveAssetUrl()` 在 Go developer proxy 下保持同一 preview 前缀。

## 0.4.10 (2026-06-25)

文档化一个**新的 turn 输入契约：`current_datetime`**（**纯文档**；注入由平台实现）。
LLM API 没有时钟、裸调用不知道"今天"，平台现在每轮在 turn 输入里注入 `current_datetime`
（墙上时钟 + 星期，时区由部署的 `ACTIVITY_CLOCK_TZ` 定、默认东八区）。活动要把用户的相对时间
（「昨天」「上周五」「去年」）解析成绝对日期，据此字段算即可，不要让模型自己猜今天。

- **`references/host-skill-template.md`**：「当前状态」节加 `current_datetime` 字段说明
  （来源 / 时区 / 用途：解析相对时间；不需要的活动可忽略）。

## 0.4.9 (2026-06-25)

把「handler 产出的图怎么落进 uploads」讲成**两条可选路径**，让活动开发者按交互模型自己选
（**纯文档**；两条路平台都支持）。区别只在**字节何时落盘**：**A 即时**（`ctx.save_upload`，
生成即落、返回 uploads URL）适合生成即定稿 / 非交互流程；**B 延迟提交**（handler 返回图片
字节如 base64 data URL、前端本地预览，用户**确认**时才走 `api/upload` 落盘）适合交互式编辑器
——编辑期是纯页面草稿，换图 / 重生成 / 放弃都不触碰存储、不产孤儿。

- **`references/image-tools.md`**：原「把 handler 产出的图变成『用户上传』」一节改写为
  「把 handler 产出的图落进 uploads —— 两条路，按交互模型选」：加 A/B 对比表（落盘时机 /
  handler 返回 / 预览来源 / 孤儿 / 典型场景）+ B 路径代码示例；A 的 `ctx.save_upload` /
  `ctx.read_upload` 签名表保留。URL 示例由写死 `/preview/...` 改为挂载无关的 `<preview-root>/...`。
- **`references/user-upload.md`**：handler 写入命名空间的交叉引用同步为「A 即时 / B 延迟提交」两条路。

## 0.4.8 (2026-06-25)

图像 capability 的 **handler / SPA 用法补全**（**纯文档**；运行时能力在平台侧实现）。
`image_edit` 现在也暴露 ctx helper（此前只有 `image_generate`），预览页可不经 agent turn
直接修复 / 改图；新增 `source_upload`（用预览页上传产物作 `image_edit` 的 source）与
`ctx.save_upload` / `ctx.read_upload`（把 handler 产出的图写进 / 读回「用户上传」命名空间，
与 `POST api/upload` 同形）。

- **`references/image-tools.md`**：「Static Preview / SPA 图像按钮」段覆盖 `ctx.image_generate`
  + `ctx.image_edit` 两个 helper；新增「改图：编辑预览页上传的照片（`source_upload`）」与
  「把 handler 产出的图变成『用户上传』（`save_upload`/`read_upload`）」两节；source 引用表
  加 `source_upload`（共 6 种引用方式）。删去「只有 image_generate 暴露 ctx helper」的旧注。
- **`references/user-upload.md`**：补 handler 经 `ctx.save_upload` 写入上传命名空间的说明。

## 0.4.7 (2026-06-23)

生图新增**火山引擎方舟 Doubao/Seedream** 后端。开发者契约：`image_generate_model` /
`image_edit_model` 现在既可填 Wanxiang 模型（`wan2.x-*`）也可填 Doubao 模型
（`doubao-seedream-*`），平台**按模型名自动路由**到对应后端——活动只挑模型，不配
provider、不碰 key。generate 与 edit（图生图）都按各自模型字段路由。**纯文档**（运行时
能力在平台侧实现，凭证由运维在服务端配置）。

- **`references/runtime-config.md`**：`image_generate_model` / `image_edit_model` 说明
  改为「Wanxiang 或 Doubao，按模型名路由」，加 Doubao 示例。
- **`references/image-tools.md`**：「活动级模型覆盖」加「模型即后端」段 + Doubao 示例 +
  Seedream 尺寸提示（倾向更大 size）。

## 0.4.6 (2026-06-23)

补齐**终端用户在预览页里上传 + 持久化自己的图像 / 录音**这条平台能力的开发者契约
（绘本工坊自己读绘本录音、记忆档案馆传照片）。平台早已提供 `POST api/upload`，但插件此前
未把它讲成一条契约级能力，开发者不知道可以用。**纯文档。**

口径仍遵循「只讲契约、不展开运行时 / 平台机制」：写端点、格式、大小、持久化保证、归属分工与降级，
不讲对象存储 / Go URL 投影 / 计费等内部链路。

- **新增 `references/user-upload.md`**：`POST <preview-root>/api/upload`（`multipart` 单
  `file` 字段，用 `apiUrl('upload')`、走原生 `fetch`+`FormData` 而非强制 JSON 的 `request()`）；
  允许格式 = 图像 `png/jpeg/webp/gif` + 音频 `wav/webm/mp4/mpeg/ogg`（浏览器 `MediaRecorder` 的
  `audio/webm;codecs=opus`、`audio/mp4` 直接可传，无需前端转码；HTML/SVG/JS 一律拒）；返回
  `{url, resource_ref, sha256, content_type, byte_size}`，`url` 为 **opaque（默认可能 redirect、
  别解析、别假设同源）**，内容寻址幂等；回取用 `resolveAssetUrl()`、`?proxy=true` 可同源拉字节；
  与产物同级耐久、随实例硬删清除；**归属分工**——平台只存字节发 ref，"谁传的 / 放哪"由 handler
  用 `ctx.user_id` 写进 `data.json`；录音可直接喂 `tts_generate(reference_audio=…)` 克隆朗读。
- **交叉链接**：`workflows/04-derive-frontend.md`（SPA api/* 面）、`references/tts-tools.md`
  （`reference_audio` 录音来源）、`skills/activity-builder/SKILL.md`（static-preview 阅读清单）。

## 0.4.5 (2026-06-23)

补齐 Static Preview 活动的 **生图 handler-first 用法**说明（0.4.4 TTS 喇叭按钮的生图对应版）。
平台早已在 ctx 上提供 `ctx.image_generate`（仅 `image_generate` capability 声明时存在），但插件
此前只教 turn 内 `@tool`，缺"预览页直接生图"这条路。**纯文档**。

口径原则：面向活动开发者只讲**契约**（怎么声明、调什么、返回什么形状、怎么降级、约束是什么），
不展开运行时 / 背后平台的实现机制（URL 投影、计费链路、内部计数器等）——那些对开发者既不可操作、
也是冗余上下文。

- **`references/image-tools.md`**：新增 *Static Preview / SPA 生图按钮* 章节。声明
  `image_generate` capability + `handlers_module` → `handlers.py` 里 `getattr(ctx,
  "image_generate", None)` 判空 → `ctx.image_generate(prompt=…, size=…, store="auto")` →
  取 `result["artifacts"][0]["file_url"]`，失败回 `{"ok": False, "error": …}`，写 typed-KV 后
  `ctx.notify_dsl_update()`；前端 `apiUrl('<handler>')`、直接用返回的 `image_url`、不硬编码
  `/v1/...`。约束：每次 handler 调用累计受 `IMAGE_GEN_MAX_PER_TURN`、失败不占名额、超额优雅降级；
  计费归因平台自理。范例引「婚礼爱情档案」`image_helpers.py`。
- **`policies/capabilities.md`**：「用法」段补"同一 capability，两类入口"——`image_generate` /
  `tts_generate` 声明后同时可用 turn `@tool` 与 `ctx.*` helper；`image_edit` / `read_document`
  仅 turn `@tool`；`ctx.image_generate` 仍由 `manifest.capabilities` 门控（区别于无条件注入的
  `ctx.llm`）。
- **`references/ctx-llm.md`**：选型表拆行——主 turn 生成/编辑图片（`@tool`）vs 预览页按钮直连生图
  （`ctx.image_generate`）。
- **`references/tts-tools.md`**：喇叭按钮的资产 URL 说明改为开发者口径"直接用返回的 `audio_url`、
  不硬编码 `/v1/...`、平台保证当前预览环境可访问"，不再描述内部改写 / 投影机制。
- **同口径清理既有泄露点**（非本次新增，一并降到契约高度）：
  - `references/ctx-llm.md`「计费与归因」段 → 「计费、归因与限额」：只讲"平台自理、活动不传身份参数、
    不碰 provider key、无 per-call 上限、`timeout` 语义"，删 LiteLLM spend log / Go token /
    `custom_auth` / `spend_logs_metadata` / media-proxy sidecar 等内部链路。
  - `policies/capabilities.md`「工作机制」内部流程图（`runner._build_capability_tools` /
    `create_image_provider` / `make_image_generate_tool` / `trace.log`）→ 契约级「优雅降级」：
    声明 ≠ 一定可用，turn 内 LLM 看不到工具自然降级、handler 里 `getattr(ctx,…,None)` 判空降级；
    并软化同段 `ImageSourceResolver` 类名引用。
  - `references/ctx-llm.md` 模型路由 / 排错表：去掉"网关开 / 关、hard mode、LiteLLM `config.yaml`、
    Go token、provider key"等措辞，改为"模型名写法随部署而定、拿不准用默认、必要时找运维确认"。
  - `examples/static-preview.md` 边界句：`runtime carries no sidecar services` → 描述活动自身
    "只含静态资源、不自带后端服务"。
  - 全量 grep 复扫确认开发者侧文档（references / policies / examples / workflows / schemas /
    templates）已无运行时 / Go 平台内部词。
- **版本**：Codex / Claude plugin manifest 0.4.4 → **0.4.5**。

## 0.4.4 (2026-06-22)

补齐 Static Preview 活动的 **TTS handler-first 用法**说明，面向"前端喇叭按钮朗读"这类即时交互。

- **`references/tts-tools.md`**：新增 Static Preview / SPA 喇叭按钮章节。明确不要用 `[TTS]`
  标记驱动一轮 turn，也不要在前端硬编码 `/v1/...`；应在 `manifest.capabilities` 声明
  `tts_generate`，声明 `handlers_module`，在 `handlers.py` 里通过 `ctx.tts_generate(text=..., store="auto")`
  合成，并由前端 POST 当前预览根路径下的 `api/tts`。
- **`frontend-base/src/lib/api-base.ts`**：注释同步到当前 `/preview/...` 与
  `/dev/preview/...` 预览挂载口径；模板本身已经动态解析当前 preview 根路径，避免深层 SPA
  子路由把 `./api/tts` 解析到错误位置。
- **版本**：Codex / Claude plugin manifest 0.4.3 → **0.4.4**。

## 0.4.3 (2026-06-17)

跟进 runtime 新增的 **`image_edit` 多图输入**能力（runtime commit `00298b40`：`image_edit`
从"恰好 1 张 source"扩成"1..N 张有序 source"，wan2.x 的融合 / 多参考 / 局部编辑全靠
prompt 表达、不需 mask 或角色字段）。**本次是文档同步**——补齐插件对该能力的契约描述；
runtime 行为以源码为准（`app/tools/image_edit.py` `sources` 参数 + `app/image_sources.py`
`resolve_many` + `app/settings.py` `IMAGE_EDIT_MAX_SOURCES` 默认 5）。

- **`references/image-tools.md`**：`image_edit` 签名加 `sources: list[str] | None`；"source 二选一"
  规则（`sources` 多图 vs 4 个单数参数恰 1 个，整体互斥；`sources` 有序，图1=sources[0]）；
  成功返回补 `source_kinds` / `source_refs`（仅 `len(sources)>1` 时出现）；失败返回补
  `too many source images` / `pass either sources … not both`；重要约束补多图节（每张各自
  受字节上限 + SSRF，计费按产出）；Image Source 表加 `sources` 行（前缀自动识别）；选源伪
  逻辑加多图首分支；env 表加 `IMAGE_EDIT_MAX_SOURCES`（默认 5，模型上限 9）；诊断表加 3 行。
- **`workflows/03-image-tooling.md`**：决策树加 step 0「本轮需要 2+ 张输入图（融合 / 多参考）→
  `image_edit(sources=[…])`」机械接线分支。
- **`examples/card-image.md`**：Flow 第 2 步注明多图用有序 `sources=[…]`。
- **不动** `references/runtime-config.md` / `schemas/runtime.schema.json`：`IMAGE_EDIT_MAX_SOURCES`
  是运维 env、不是 `runtime.json` 字段（`ALLOWED_RUNTIME_FIELDS` 无此键），放进去会语义错位。
  verifier 无 image-param 规则，亦无需改。

## 0.4.2 (2026-06-12)

外部活动开发者 round-4 反馈（针对 0.4.1；round-3 的 23 项实测 CLOSED 20 / PARTIAL 3 /
OPEN 0）：5 项残留/漂移 + 1 个新问题，逐条闭环。**全部为文档 / 口径修复，无运行时或
schema 行为变化**——已核 runtime 源码，行为本就正确，缺的是文档把它说清楚。

### 修了 0.4.1 自己的"声明 vs 实物"漂移（P1）

- **CHANGELOG 承诺随包的 `docs/feedback/v0.4.1-audit-findings.md` 实际未入包**（外部 114
  文件机扫确认无 `docs/`，本仓库 `find` 复核一致）——这恰是 0.4.1 宣称要消灭的 bug 类。
  4 维复扫存档属过程产物、本不该入包，故**删除该声明行**（不补文件）。

### 文档口径补全（PARTIAL 残口收尾）

- **`references/image-tools.md` 失败配额语义对称**（P3）：runtime 两侧本就对称——
  `app/tools/image_gen.py` 与 `app/tools/tts_gen.py` 失败都走 `rollback_reserved()`——
  但只有 `tts-tools.md` 写了"失败回滚配额"。image 失败节补对称句：失败**不占**
  `IMAGE_GEN_MAX_PER_TURN`、generate / edit 共享计数器同语义。
- **`policies/output-protocol.md`「两个 phase 命名空间」补三点**（Q9，把口径从
  `host-skill-template.md` 的括号注提升为权威，据 `app/card_system/state_derivation.py`）：
  ① derived phase 派生改写为准确的 **carry-forward** 语义（本轮无卡声明 `meta.phase` 时
  沿用上一轮、不清空），纠正原"每轮整体覆写"的误导措辞；② 补 derived phase **初始值**
  （首个声明 phase / runtime 传入的 `default_phase`，否则 `None`）；③ 补**分歧裁决**——
  两份 phase 不一致时工具守卫 / 路由以 typed-KV 业务 phase 为准，host SKILL 据此路由是
  对的。`references/host-skill-template.md` 同步加一行路由权威指针。
- **`schemas/README.md` 新增「Bundle 与 runtime 版本窗口」节**（Q10）：明确创作期
  （bundled schema + verifier）vs 加载期（runtime `app.models`，最终权威）分工、bundle
  落后 / 领先各自行为、安装重装的校验侧，以及"插件包与目标 runtime release 同档 pin"建议。

### 新问题：legacy `activity_id` 改名安全窗口（verifier W8）

- **`references/manifest-fields.md` 新增改名安全窗口子节**：区分改*值*（slug，断路由 /
  实例目录）与改*键名*（`activity_id` → `activity_type_id`，安全前向迁移）。据 runtime
  `ActivityManifest.normalize_legacy_activity_id`（`mode="before"`）说明 `activity_type_id`
  是 canonical、`activity_id` 是加载前归一化的**永久兼容别名**（当前无 sunset、不会自动
  升 ERROR）；实例数据按 slug **值**而非 manifest **键名**关联，故改键名**无需平台侧
  配合、不必重建实例**。唯一前提：目标 runtime 已把 `activity_type_id` 作 canonical
  （当前 runtime 即是；本仓库 runtime 未打版本 tag，不确定生产版本时先在目标 runtime
  验证一个改名后的 manifest 能加载再批量改）。

### 交接物增强（Q11）

- **`workflows/06-verify-and-ship.md` 的 Ship Verification 块**加可选
  `Suggested smoke inputs:` 行（随包指定必测路径，如"大纲 turn 同 turn 出封面"这类历史
  事故线），并明示 maintainer runtime smoke / fda-logs 回传**可按需重复**、已发
  `fda-dev` token 时开发者用共享 dev runtime 自助复跑是等价替代。

### 版本

- `plugin.json`（claude + codex）+ `schemas/README.md` Bundle version 0.4.1 → **0.4.2**
  （`check_schema_sync.py` 的版本行提醒据此对齐）。

## 0.4.1 (2026-06-12)

0.4.0 后的全维度复扫（4 个并行审计 + 实跑 scaffold→verifier→testkit→pack）发现的
正确性漂移、引导断点与残余冗余，逐条修复。**新手可走通度 7→预期 9。**

### 修了会教错人的（P0）

- **`tools/activity_verifier.py` 静默假通过**（改工具代码）：在错误目录运行会扫到 0 个
  活动却 exit 0、零输出——终局门禁的证据可以是假的。现在成功时打印
  `scanned N activities: E ERROR, W WARNING`；**N=0 时告警并 exit 2**。
- **`references/image-tools.md` 把 URL allowlist 语义写反**（安全相关）：核对
  `app/image_sources.py` 后更正——空 allowlist = **default deny**（不是"仅查 scheme"），
  非空 = **hostname 精确匹配**（不是前缀）。
- **`references/card-system-tools.md` 的 `artifact_emit` 描述错**：核对运行时后更正——
  参数是 JSON-encoded `str`（非 dict）；`artifact_id` 缺失时 runtime **自动生成**（非
  reject）；真正必填只有 `title` + path/content/url 三选一；`kind` 默认 markdown。
  终态"互斥"表述放宽为真实的 allowlist 语义（await_user 可升级 mark_status）。
- **tts/image "失败计入 per-turn 上限"与实现相反**：失败实际走 `rollback_reserved()`
  回滚配额。**同步修正运行时 `_FAILURE_HINT` 字符串**（`app/tools/tts_gen.py` +
  `image_gen.py`，假事实的源头）与 `tts-tools.md`。
- **两份漏扫的 0.4.0-前旧文件**：`policies/manifest-allowed-fields.md` 字段清单过期
  （12/16，缺 `read_document` 等）→ 降级为指向 `manifest-fields.md` 的指针 + 保留独特的
  "新字段该放哪"路由表；`references/store-mode-table.md` 的 OutputArtifact 示例用了非
  schema 字段且缺必填 `title`、还残留 JSON-Patch 旧 state 协议 → 重写为 schema 合法形态
  + typed-KV 写法 + 现行 sandbox 路径。
- **Ship Verification 两套互斥模板 + 完工口径矛盾**：packager 改为指向 workflow 06 的
  单一块格式，并采纳 06 的 deferred 规则（外部开发者无 runtime 时 verifier+testkit 即可
  完工，运行时步骤记 "deferred to maintainer"，不是 blocker）。

### 引导断点（P1）

- **`activity-editor` 悬空引用 ×4** → 全部改指 `activity-builder`（该 skill 不存在）。
- **`<package>` / `<project-root>` 占位符**首屏即用却定义太晚 → README + INSTALL +
  workflow 02 首次出现处补一句话定义，并说清 scaffold/verifier 在 `<project-root>` 跑。
- INSTALL Verify 命令改用 `<package>/...` + 显式 `<project-root>` 参数。
- classifier 输出契约的 `runtime_mode` 补来源说明（由 frontend_axis 映射）。
- `output.schema.json`（scaffold 自带的 `$ref` 占位）补"自动生成、勿手改"说明。
- `setup-runtime.sh` 标注为平台仓库/安装侧步骤，外部开发者显式豁免（04 + 06）。
- `verifier-checks.md` 补齐源码实有但漏列的 4 个 ERROR（文件完整性 / id mismatch /
  相对导入 / skill-loading 完整性）+ 2 个 WARNING（deprecated id / baseline 缺失）。
- 计数 / TOC 修正：workflow 02 "5→6 artifacts"、README classifier 字段 4→6、
  diagnostician "E1-E10"→"E-classes"、manifest-fields 补 catalog 字段正文节、
  card-block-types TOC 补 OutputCard、04 的失效 `.tpl` 示例、card-typed-kv 补 `x-auto-inject`。

### 第二轮去重 + 残件（P2/P3）

- workflow 03 的 store 表 / per-turn quota / tool-return shape 全是 reference 权威的
  重述 → 收敛为指针（store 语义第三份拷贝消除，~40 行）。
- llm-output-discipline §8d 内联自查脚本 → 指向随包脚本（~15 行）。
- activity-smoke 的 fda-dev flag 逐条解释 + rate-limit 数值 → 收敛指向 dev-agent-cli.md。
- 删 `workflows/01-brief-and-classify.md`（0 入链孤儿；07 的 "01-06" 改 "02-06"）。
- 哲学残件：删 multi-store 的 "Reference implementation" 节（指真实活动当范本）；
  "汤底" → "谜底/评分细则"；`bedtime-*` 示例 ID → 中性占位符；3 处 legacy
  `activity_id` 示例 → `activity_type_id`。
- 删 `references/classification-table.md`（仅 1 处入链；triggers 已由 classifier
  Axes、implementation 已由 classifier Rules + workflow 02 覆盖）；独有的
  "no half-preview" 约束并入 classifier。
- activity-frontend 的 Implementation Guidance：通用视觉栈的 polish budget /
  motion 范例 / 截图细节收敛为指向 workflow 05 的指针（保留测试契约要求的
  自包含栈提及）。

## 0.4.0 (2026-06-11)

全包契约优先重设计 + 提示词精简。核心裁决：**FDA 活动没有"最佳实践"**——平台对活动只有
三条硬契约（卡片渲染得出来 / 工具调用得生效 / Web 产物接得准），满足契约设计完全自由。

### ⚠️ Breaking：Classification 输出契约变化

- **`closest_existing_activity` 字段彻底删除**（`references/closest-existing-activity.md`
  一并删除）。理由：必填"最接近的现有活动"+ 下游 source-read 类比，等于制度化地让新活动
  从抄旧活动开始，收敛设计空间；且该表中 5 个被引用的"标杆活动"实际已不存在（品味型引导
  会随仓库演化变成幻觉，契约由 verifier 守护不会）。新活动从 Brief 直接设计，分类只决定
  交付哪些文件。

### 契约优先重设计

- **根 SKILL.md 重写（81→48 行）**：开场即"形态速查表"（四行对号入座 → 中性示例直达）+
  名词速查 + 显式设计自由声明；boundary / final gate 压成指针。
- **全包清除真实活动名作设计参照**（47 处逐一判别）：examples 的 "real reference" 行改为
  "示意契约形状，设计随你"；host-skill-template "首推标杆"清单替换为设计自由声明；
  "标杆 / 范本 / the X pattern"语言清零。保留的 8 处均为事实类（bug 历史 / 修复代码指针 /
  CLI 输出样例）。
- 顺带修复：examples / closest 表 / workflows / diagnostician 中 5 个**已不存在活动**
  （shoucai-tongzi / grand-decision / family-tree / virtual-pet / gift-advisor）的失效引用。

### 提示词精简（guardrail 收敛 + 双语分工 + 去重）

- **单一权威源收敛**：runtime boundary → `policies/runtime-boundary.md`；final gate →
  packager + smoke；`policies/no-rationalization.md`（12 行）删除、内联进 06 工作流 Step 5；
  orchestrator 34→15 行（保留 Codex 自路由链）；README boundary 段压成指针。
- **9 个 skill 双语分工**：中文"何时用"块统一为一行"触发 + 下一跳"，删与英文正文 /
  description 的三重复述；frontmatter 双语 description 不动（触发匹配需要）。
- **output-protocol ↔ llm-output-discipline 划分工**（合计 511→432 行）：前者 = transport /
  汇编契约权威；后者 = 纯 LLM 侧踩坑（§3/§5/§11 与开头工具清单改指针，节号保持稳定，
  §1/§4/§8b/§8c/§8d 锚点不变）。
- **references 去重**：store 三档语义权威收敛到 `store-mode-table.md`（image/tts 各留指针，
  消除 `/v1` 代理论证的 5 处重复）；card-system-tools ↔ card-block-types 划界（工具签名 vs
  block schema，"关键模式/Turn boundary"改指针+三条高频要点）；ctx-llm credential 节改指针。
- **8 个百行参考文档加目录（TOC）**：image-tools / card-block-types / card-system-tools /
  data-store-tools / manifest-fields / python-dependencies / dev-agent-cli / ctx-llm——
  partial read 也能看到全貌（官方 skill 最佳实践）。
- **顺带修复三处文档漂移**：host-skill-template 与 data-store-tools 踩坑表的旧 §8d 口径
  （0.2.8 放宽前的"一律 JSON-encoded str"）、manifest-fields capabilities 枚举缺
  `read_document`。

## 0.3.2 (2026-06-11)

外部开发者 round-3 反馈（针对 0.3.1）的 P0/P1 项：补齐 credential 硬检查的修复路径文档，
裁决并修复 testkit `update_data` 契约偏差。

### P0 — `references/ctx-llm.md`（round-3 B1 / Q1–Q4 的正式答案）

credential 硬检查（0.3.0 起）的指定修复路径 `ctx.llm` 此前在包内零文档。新增
`references/ctx-llm.md`，完整覆盖：

- **签名**：`ctx.llm.chat(...)` / `chat_json(...)` / `vision(...)`，全部同步、
  出错返回 `None` 不抛异常（Q1）。
- **VL 看图**：`vision(prompt=..., image_urls=[...])` 接受 `data:<mime>;base64,...`
  与 http(s) URL，是平台认可的"图片 → 结构化文本"路径（Q2）。
- **模型路由**：不读 `manifest.model` / `graph_model`；默认平台 `ACTIVITY_DEFAULT_MODEL`，
  按调用传 `model=` 指定（网关别名 / `provider:model`）——"主模型纯文本、VL 单独指定"
  是设计内用法（Q3）。
- **计费归因**：网关链路 bearer = 本请求 Go token，spend 主体 = 实例 id，附
  `fda_user_id` / `fda_activity_slug`；无独立 per-turn 上限；`timeout=` 与
  `llm_timeout_seconds` 无关（Q4）。
- **选型表**：文本层抽取 → `read_document`、看图 → `vision`、文生图/语音 → capability
  工具、主对话 → runtime（兼答 Q5 的 read_document 定位——其详档
  `references/document-tools.md` 已随 0.3.1 后的 docs 提交存在）。
- **规则口径**：credential 检查禁的是"直连平台代为计费的 LLM/媒体 provider"，
  非 provider 的第三方 HTTP（财经数据源、抓网页素材）不受影响；检查仅在包验收时
  静态执行，不影响已部署实例（Q6/Q7）。

索引挂载：`workflows/02-author-backend.md`（tools.py 创作段）、
`policies/capabilities.md`（"不是 capability 的能力"注记）、verifier 报错文案
直接指向 `references/ctx-llm.md`。

### P1 — testkit `update_data` 契约裁决 + 修复（round-3 B2 / Q8）

**裁决：dict 与 `(dict, side_info)` tuple 都合法。** 平台真实实现
（`app/card_system/data_store.py`）明确接受两种返回（dict → side_info 为 None）。
纯 dict 返回的活动（如反馈方的 ootd-advisor）是契约内用法，不是侥幸。

修复 testkit 一侧：`fda_testkit.py` 的 `update_data` stub 从 tuple-only 解包改为
镜像平台语义——dict 直接写入、2-tuple 拆 side_info、其余 arity / 非 dict 载荷
报 `AppError`（与平台同款报错）。消灭"恰 2 键 dict 被解包成键名、静默写坏数据"
的事故面。新增平台仓库回归测试 `tests/test_fda_testkit.py` 锁两侧一致。

### 配套

- `FakeCtx` 增加 `llm` 属性（恒 `None`，与无 settings 的最小 runtime ctx 一致）：
  活动的 None 降级分支在离线测试里自动被测；测 LLM 分支时给 `ctx.llm` 挂鸭子类型
  fake 即可（ctx-llm.md 附示例）。testkit README 同步两处契约描述。

### B3 文档收尾批（round-3 B3 全部 9 条）

1. `workflows/02-author-backend.md` 红线清单的 §8d 描述从旧口径（"plain scalar
   params, JSON-encoded strings"）改为 0.2.8 裁决后口径（禁裸 `list`/`dict`；
   参数化容器合法；JSON-encoded `str` 是跨模型最稳兜底），并附自查脚本指引。
2. `skills/activity-packager/SKILL.md`：Required Checks + Ship Verification 模板
   补 `testkit:` 行，与 06 工作流"verifier + testkit 永远必填"对齐。
3. `skills/activity-verify/SKILL.md`：纠正"两项检查都需平台 venv"——Check 1
   （verifier）实为纯 AST 静态、任意 Python ≥3.10 即可；解释器指引收窄到 Check 2；
   补"无平台仓库用 testkit 替代 Check 2"路径与 Ship Verification 的 testkit 必填说明。
4. phase 裁决同步补全：`workflows/03-image-tooling.md` 的"`phase` 不是 escape
   hatch"加限定语（只针对 runtime 派生那份；typed-KV 业务 phase 合法且推荐）；
   scaffold 模板 host SKILL 加 typed-KV 命名空间注脚（含"模板卡不带 meta.phase
   也合法"）。
5. 硬检查 "6a" 与软警告 "6a" 同号撞车：软警告改为 `W1–W7` 前缀编号（W6/W7 即旧
   6/6a），表头注明历史对应关系。
6. 权威残尾清理：`card-block-types.md` 两处 `app/models.py` 指向改为随包分发的
   `schemas/card-template.schema.json`；ActionItem `action_type`"完整取值见下表"
   改为真实语义（自由字符串、无封闭枚举；自带 chat 前端对所有 action 统一按
   `payload.input_text` → `payload.text` → `label` 点击发送，`input_text` 是唯一有
   约定语义的取值）；`card-system-tools.md` 权威从外部不可达的 GitHub 链接改为
   "随包分发权威 = 本文 + schemas，平台源头路径仅供维护者对照"；"10 工具"计数
   统一为 11（含 `await_user`，scaffold 模板同步）。同款不可达 GitHub 链接在
   `data-store-tools.md` / `output-validation.md` / `multi-store-tool-design.md`
   一并按同口径清理（反馈未点名但属同一问题类）。
7. README 包结构树补 `testkit/`、`examples/` 与 verify / smoke / diagnostician
   三个 skill，并补一段三个独立工具 skill 的导览。
8. 工具链 Python 版本下限入册（INSTALL.md 新增 per-tool 矩阵）：verifier ≥3.10
   （3.9 现在启动即清晰报错退出而非 `AttributeError` 半途崩——`main()` 加了版本守卫）、
   testkit ≥3.9（自身零三方依赖；`tools.py` 的 langchain_core 任意 0.3.x 即可）、
   strict-tool-schema-check 与 check_schema_sync 需平台仓库 venv。verifier-checks.md
   与 testkit README 同步声明。
9. scaffold 产物断链指针修复：`templates/activity-template/requirements.txt` 与
   模板两个 SKILL 的 `references/...`、`policies/...` 裸指针改为 `<package>/...`
   约定（注明 = 本地插件安装目录）；`scaffold-backend.sh` 的 `skill/...` 指针改用
   `$PACKAGE_ROOT` 展开为真实路径，Next steps 补 testkit 冒烟一步。

### B1 收尾 — verifier 检查全量入册（round-3 B1 其余两缺口）

- **CHANGELOG 补记**：credential 硬检查在 0.3.0 条目下补记（含迁移指引与影响面
  说明——只拦包验收、不影响已部署实例），见下方 0.3.0 的 ⚠️ 段。
- **`references/verifier-checks.md` 对照表补全**：新增硬检查 #13 credential /
  provider 直连（触发模式、修复路径、口径与影响面）、#14 未声明三方 Python 依赖、
  #15 hidden-field 需显式 `sse_debug_view`、#16 卡片字段名启发式 lint（image
  `src/alt/caption`、artifact `file_url/byte_size/artifact_id`、image artifact
  `kind` 误用）。顺修 #2 capabilities 枚举漂移（补 `read_document`）。

## 0.3.1 (2026-06-10)

外部 Codex 审查（针对 0.3.0）发现的四个质量门禁缺口，逐条修复。

### P1 — verifier 白名单过期，误杀合法活动（真 bug）

- `ALLOWED_MANIFEST_FIELDS` 补 `sandbox_env`、`ALLOWED_CAPABILITIES` 补
  `read_document`——runtime（`app.models` + `app/runner`）和 `manifest.schema.json`
  早已支持，唯独 verifier 白名单滞后，会让新规范下的合法活动过不了门禁。修复后全量
  verifier 的 ERROR 从 7 → 6（`read-watch-log-3` 的 `sandbox_env` 误报消失）。
- `manifest.schema.json` 补 `enabled` / `sort_order`（catalog metadata，模型与 verifier
  都有、schema 漏了）。

### P4 — sync 守卫覆盖面太窄（P1 的根因）

- `check_schema_sync.py` 从「只守 card-template ↔ card 模型」扩展到守 **三方一致**：
  `app.models` ↔ 打包 schema ↔ verifier 白名单常量。新增比对
  `ALLOWED_MANIFEST_FIELDS` / `ALLOWED_CAPABILITIES` / `ALLOWED_RUNTIME_FIELDS`
  与模型、`manifest.schema.json` / `runtime.schema.json` properties 与模型、
  capabilities enum 与 `Literal`。这正是能自动拦住 P1 那类白名单漂移的守卫。
- pre-commit 触发面扩到 `activity_verifier.py` + manifest/runtime schema。

### P2 — placeholder 通配过宽（真 bug）

- verifier `_schema_check` 此前只要字符串含 `{{var}}` 就跳过类型校验，导致
  `blocks: "prefix {{blocks}}"`（渲染成字符串、但 schema 要数组）能误过、运行时炸。
  收窄为：**仅完整占位符** `^{{var}}$` 当作整值通配（渲染期可为任意类型）；
  **嵌入式**占位符按字符串处理——type 检查照跑（抓住数组/对象字段误用字符串），
  仅跳过 string 内容约束（enum/pattern/length，内容渲染期才知道）。与
  `card_templates.FULL_PLACEHOLDER_RE` 的渲染语义精确对齐。

### P3 — testkit 校验器弱于文档承诺

- `fda_testkit.py` 的 schema 校验器补齐 `const` / `minLength` / `maxLength` /
  `minItems` / `maxItems` / `minimum` / `maximum` / `exclusiveMinimum` /
  `exclusiveMaximum` / `multipleOf` / `pattern` / `uniqueItems` / `anyOf` /
  `oneOf` / `allOf` / `$ref`，与 `app/json_schema.py` 子集对齐，让 README
  「与 verifier 同子集」的承诺成立（此前 `minLength:3` 下 `"x"` 会被放行）。

## 0.3.0 (2026-06-10)

外部反馈第三批：把「权威可见 + 验收闭环」从规范承诺变成可机读、可本地运行的产物。

### ⚠️ credential / provider 直连硬检查（发布时漏记，2026-06-11 补记）

> 本条 0.3.0 发布时未写入 CHANGELOG，round-3 反馈指出后补记于此。它是一条会让
> 既有活动从 0 ERROR 变 ship-blocked 的新增 ERROR 级检查。

- **新增 `_verify_no_credential_access`**：静态 AST 检查活动 Python，ERROR 级拒绝
  import `app.settings`、调用 `get_settings()` / 触达 `._settings`、代码字符串引用
  平台 provider 密钥名（`DEEPSEEK_API_KEY` / `DASHSCOPE_API_KEY` / `OPENAI_API_KEY`）
  或 provider 域名（`api.deepseek.com` / `dashscope.aliyuncs.com`）——这些绕过
  LLM 网关计量与 cost-ledger 计费。
- **迁移指引**：LLM 调用（文本 / JSON / 看图）→ `ctx.llm`（`references/ctx-llm.md`，
  0.3.2 起提供）；图像 / TTS → `image_generate` / `tts_generate` capability 工具。
- **影响面**：检查只在包验收（verifier）时静态执行——**已部署实例不受影响、
  不存在失效时点**；存量活动在下次过 verifier 时被拦，按上行指引迁移即可。
  口径是"禁直连平台代为计费的 LLM/媒体 provider"，非 provider 的第三方 HTTP
  （财经数据源、抓网页素材等）不受此检查影响。

### 防漂移：schema ↔ runtime 同步守卫

- **`tools/check_schema_sync.py`**（新）：在平台仓库 / CI 里证明
  `schemas/card-template.schema.json` 与运行时 `app.models` 的每个 card block /
  item 模型逐字段一致（属性集 / 必填集 / `Literal` 枚举 / `additionalProperties:false`）。
  任何一侧改了另一侧没跟 → 硬失败并指名字段。已挂 `.pre-commit-config.yaml`
  （仅当 `app/models.py` 或 `card-template.schema.json` 变更时触发）。
- **schema bundle 版本化**：`schemas/README.md` 标注 `Bundle version`（随 plugin.json），
  同步脚本在版本行落后时给非阻塞提醒。外部开发者据此知道手上 schema 对应哪个插件版本。

### 官方 testkit（收编外部开发者自创的 mock-harness）

- **`testkit/fda_testkit.py`**（新，单文件零三方依赖）：stub 出
  `app.card_system.data_store`（临时实例 + 每次写入按 `data.schema.json` 真校验）
  与 `app.errors`，让**没有平台仓库**的外部开发者也能本地导入并运行自己的
  `tools.py::make_tools` 和 `dsl_builder.py::build`。
  - CLI：`python testkit/fda_testkit.py activities/<id>` —— 构建 make_tools、
    对每个工具查 strict-mode 形态、用种子实例跑 build 并验 JSON 可序列化。
  - pytest API：`load_make_tools(...)` / `activity_harness(...)`。
  - 已在 bedtime-story / ai-secretary / memory-archive / talk-starters
    （2–25 个工具不等）实测 smoke clean。
- `workflows/06-verify-and-ship.md`：新增 Step 3.5「本地 Python smoke」；放松强制
  门槛——verifier + testkit 两行**永远必填**（都无需平台仓库），运行时 E2E smoke
  在无 runtime 时显式标注「deferred to maintainer」，不再静默跳过。

### 文档：约束执行层级 + 整包安装

- `references/card-block-types.md`：顶部新增**约束执行层级图例**
  （🔴 pydantic 强制 / 🟡 verifier 强制 / ⚪ 仅约定），消除「所有『必须』被一视同仁
  打折扣」的问题；ImageItem 字段约束按层级标注。
- `INSTALL.md`：明确**必须整包安装**——skills 之间及对 policies/references/workflows/
  schemas/testkit 的 `../../` 跨引用只在完整包布局下有效，单独抽一个 skill 到
  `~/.claude/skills/` 会断链。Verify 段补上 testkit 命令。

## 0.2.8 (2026-06-10)

外部反馈第二批：行为对称化 / §8d 裁决 / 检查升级 / 负向提示词清扫。

### 平台行为（runtime）

- **ImageItem 与 AudioItem 对称**：`app/models.py` 的 `ImageItem.title` /
  `description` 改为可选（默认 `""`），契约与 `AudioItem` 一致——出图失败的
  graceful-degrade「传空串即可」对 image / audio 现在写法相同，无需条件分支。
  `schemas/card-template.schema.json` 与仓库根 `schemas/activity-output.schema.json`
  的 `ImageItem.required` 同步改为 `["read_url"]`。

### Verifier

- **doc-drift 检查升级到参数级**：`_verify_doc_tool_references` 现在比对文档里
  `activity_tool(kwarg=...)` 的关键字参数名与 tools.py 的 AST 签名，未声明的参数 →
  WARNING（单行调用才查、`**kwargs` 工具跳过、近零误报）。落地即抓出仓库两处真 drift：
  `save_nodebook(world_id=…)`（实为 `world_title`，正是外部反馈点名的漏网案例）、
  `fetch_financials(symbols=…)`（实为 `symbols_json`）。`references/verifier-checks.md`
  新增检查 6a 条目。

### 规范裁决

- **§8d 规则 1 放宽并对齐自查脚本**（`policies/llm-output-discipline.md`）：经
  LangChain strict 转换 + DeepSeek 官方 strict 约束验证，裁决为「禁裸 `list`/`dict`；
  参数化 `list[str]` / `list[dict]` 合法（LangChain 自动补 `additionalProperties:false`），
  JSON-encoded `str` 作为跨模型最稳兜底」。同步 `strict-tool-schema-check.py` 的修复提示
  与 `activities/bedtime-story/tools.py::_parse_snippets` 的过时注释（原称 strict 拒绝
  list[dict]，实际会通过）。
- **守卫错误 hint 规范**（`policies/tool-error-protocol.md` 新增章节 +
  `references/host-skill-template.md` 指引）：相位守卫拒绝时，`hint` 必须输出代码侧真理
  （当前 phase / 允许 phase / 可推进工具），文档引用只作补充——避免 hint 把 LLM 引向
  可能已漂移的文档导致死循环。

### 提示词/代码清扫（正向引导）

- 清除因老路径遗留的负向表述：`minio` 旧 store 关键字「已废弃/已硬切换」提示（4 处）、
  `use_card_system` opt-in 字段否定（4 处）、「OSS 不再保留本地副本」等历史对比，
  改写为正向陈述。verifier 代码里引用已退役 flag 的注释一并更新。仍必要的真红线
  （base64 禁内嵌、assignment_id 不自创、跨 turn 撤回禁止等）保留。诊断器 error-classes
  里对 `use_card_system` 的引用保留——它是帮迁移者定位报错的有效诊断信息。

## 0.2.7 (2026-06-10)

外部活动开发者对 v0.2.5 的系统性反馈（验收闭环 / 权威可见性 / 灰色地带）第一批响应。

### Verifier

- **新增硬检查 6a/6b：card-template / vars 的完整 JSON Schema 校验**。
  `card_templates/*.json` 按 `schemas/card-template.schema.json`、`*.vars.json` 按
  `schemas/card-vars.schema.json` 全量校验（内置零依赖 JSON Schema 子集校验器，
  vendored 自 runtime 的 `app/json_schema.py`；`{{var}}` 占位符按渲染期通配语义放行）。
  此前 verifier 对模板只做启发式字段 lint，`ImageItem` 写成 `url`/`alt`、FormField
  `input_type: "select"` 等 100% 现网必炸的模板能拿到 exit 0——现在均为 ERROR，
  报错带精确的 `$.card.blocks[i]…` 路径。
- `references/verifier-checks.md` 对照表新增 6a/6b 条目。

### Schemas

- `card-vars.schema.json` 对齐 runtime 真实接受的写法（修正 schema 漂移）：
  允许顶层 `$schema` / `additionalProperties`；变量 `type` 枚举补 `integer`；
  去掉 `minProperties: 1`（无变量模板的空 `properties` 合法）；显式列出
  `minLength` / `minItems` / `minimum` 等已在用的约束键。

### 规范裁决

- **「两个 phase 命名空间」**（`policies/output-protocol.md` 新增章节 +
  `references/card-system-tools.md` 同步）：runtime-derived `phase`（`instance.data`，
  7 个 runtime 字段，每轮从最后一张 emit 卡的 `meta.phase` 覆写派生）与 typed-KV
  业务 `phase`（活动自管）是互不干扰的两个存储。**在 `data.schema.json` 声明自己的
  `phase` 并用 @tools 直写推进，是合法且官方推荐的模式**（配工具相位守卫）；
  "不要写 phase" 红线只针对 `instance.data` 那份 derived 字段。

### 文档修正

- `skills/activity-builder/SKILL.md`：block 类型 5 → **6**（补 `audio`）。
- `references/subagents.md`：`write_todos` 启用名单改为指向权威命令
  （`grep -l write_todos activities/*/runtime.json`），修正失真的硬编码名单。
- `references/card-block-types.md`：ImageItem「必填非空」修正为真实执行层级
  （**存在性 = pydantic 强制；非空 = 仅约定**）；补充 image `read_url` 空串
  自动隐藏语义（与 AudioItem 对称）；ImageItem / AudioItem / OutputArtifact 的
  字段权威源从仓库内 `app/models.py` 改指随插件分发的 `schemas/*.json`。

### 随包修复（仓库内活动）

- 新校验落地即抓出 3 个潜伏的必炸模板（与外部反馈的现网事故同源）：
  `storybook.outline` / `storybook.progress`（ImageItem `url`/`alt` →
  `read_url`/`title`/`description`）、`knowledge-worldsmith.intake`
  （`input_type: "select"` → `text` + placeholder 列出可选值）。
