# Prompt conflict catalog — 历史反向样例

这些写法曾经看似可用，但与当前 FDA 契约冲突。Review 必须查“有没有”，不是把它们复制进活动。

| 反向样例（不要写） | 冲突原因 | 当前写法 |
|---|---|---|
| AGENTS、host skill、前端各自处理 greeting/smalltalk | 多个路由权威会产生不同卡片与副作用 | AGENTS 保持薄；意图/相位只由 host skill 路由，纯 UI 帮助留在 SPA |
| “每轮都发结果卡”，同时某分支要求零输出 | 两条指令不能同时成立 | 明确条件与例外，或让所有分支各自指定可见结果 |
| 所有卡片都必须模板化，同时允许任意临时卡 | 约束互斥 | 固定业务卡用模板；真正一次性短提示才允许 ad-hoc card |
| 把 `ctx.llm`、upload、handler、Preview Agent Turn 写入 capabilities | 它们不是 manifest capability | capabilities 只取五项白名单；交互表面单独分类 |
| 声明 capability 后假设工具一定存在 | provider 可能关闭或缺配置 | Prompt 与 handler 都提供 unavailable/degraded 路径，不虚报成功 |
| handler 调 `read_document` 或 `ctx.transcribe_audio` | 当前没有这两个 ctx helper | 文档走 Agent turn `read_document`；ASR 走 Agent `file_0` 或 SPA `POST api/asr` |
| SPA 把 upload URL 直接传给 `transcribe_audio` | 工具只接受本轮私有文件 ID | 同实例 upload `resource_ref` 放入 Agent Turn `attachment_refs`，第一项成为 `file_0` |
| SPA 直接 ASR 时传 `user_id`、计费参数或 provider key | 身份与计费由可信 preview 请求上下文归属 | multipart 只传音频与业务允许字段，沿用 Go/FDA 注入身份 |
| 为确定性写入也启动 Agent Turn，或在 handler 里旁路实现完整 Agent | 表面选错，重复成本/规则会漂移 | 确定性读写走 handler；需要 Skills、规划、多工具时走 Preview Agent Turn |
| handler 与 Agent tool 各复制一套同名业务规则 | 校验、状态迁移迟早漂移 | 提取纯业务函数，tool 与 handler 做薄适配 |
| 把 `tools_module` 当作所有 Static Preview 的必选项 | 只读 DSL 或 handler-only SPA 不需要 Agent tools | `dsl_builder_module` 必选；tools/handlers/preview_actions 按分类选用 |
| 假设上传前必须已有聊天 turn | 成功 upload/handler/direct ASR 本身会创建并归属实例交互 | 不制造 bootstrap turn；只读页面/DSL 仍不创建空实例 |
| 保存 `storage_key`、`sandbox_path` 或 presigned URL 作为业务身份 | 这些是部署位置或短期地址 | 保存 `resource_ref` / `artifact_id`，渲染使用返回的 opaque URL |
| “放进 Markdown code fence 就不用 JSON 转义” | 工具参数本身仍经过 JSON | 先产生正确字符串，再按 JSON 规则转义；代码围栏只影响显示 |
| 通用 `app/` 理解某活动 DSL，或禁止活动 SPA 理解自己的 DSL | 混淆共享前端与活动前端边界 | 通用 UI 只懂共享协议；`activities/<type>/site/` 可懂自己的私有 DSL |
| side effect 失败仍返回 `ok: true` 且无 degraded/warnings | 形成不完整 fanout 的假成功 | 每个副作用隔离；主写成功但附属失败时显式 `degraded` + `warnings` |
| 修一个错误时顺手改多个无关策略 | 无法判断哪项修复有效，易引入新冲突 | 一次处理一个因果类；同类机械实例可批量修 |

反例不是静态字符串黑名单。若活动确实需要不同设计，必须写清唯一权威、条件、失败语义和能力表面，并能从 Brief 到结果形成完整链路。
