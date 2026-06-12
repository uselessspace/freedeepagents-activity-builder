# Changelog — freedeepagents-activity-builder

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
- 随包附 `docs/feedback/v0.4.1-audit-findings.md`（本轮 4 维复扫的存档记录）。

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
