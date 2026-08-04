# 活动开发指南：从 Static Preview SPA 发起标准 Agent Turn

本文面向 FDA / FreeDeepAgents 活动开发者。它说明活动自己的 SPA 如何通过按钮或表单启动一次与聊天输入等价的 Agent turn，并正确处理结构化输入、历史、状态、SSE、幂等和恢复。

## 什么时候使用

| SPA 操作 | 推荐通路 |
|---|---|
| 收藏、改名、切换音色、保存表单、删除条目 | 活动 handler，确定性写 `data.json` |
| 一个 handler/tool 内的窄幅文本生成、JSON 结构化或 vision 辅助步骤 | `ctx.llm`（不是完整 Agent turn） |
| 写文章、生成故事、分析材料、生成图片、调用多个工具 | Preview Agent Turn |
| 需要模型理解、Skills、规划或多个 tools | Preview Agent Turn |

不要用 `handlers.py` + `ctx.llm` 重造完整 Agent loop。`ctx.llm` 只适合一个
handler/tool 内边界明确的补充调用；需要 Skills、规划、多工具、卡片/产物提交或标准
turn 历史时用 Preview Agent Turn。后者会复用标准模型、Skills、tools、Docker
sandbox、trace、额度和计费过程。窄幅调用见 [ctx-llm.md](ctx-llm.md)。

该能力面向带 `dsl_builder_module` 和 `site/` 的 Static Preview 活动。

## 数据归属

一次 Preview Agent Turn 会形成：

```text
turns/{turn_id}/input.json
  SPA 提交的不可变结构化输入，进入 history

turns/{turn_id}/status.json
  queued / running / completed / failed / cancelled

turns/{turn_id}/trace.jsonl
  标准 Agent trace

turns/{turn_id}/output.json
  Agent 最终提交的简短卡片、产物引用和 memory

instance/data.json
  活动自己的请求、业务阶段和最终业务结果
```

平台只理解通用 turn 生命周期。`writing`、`illustrating`、`synthesizing_audio` 等业务阶段必须保存在活动 typed-KV 中，由活动 DSL/SPA 呈现。

建议 Agent 最终只发一张简短总结卡。完整故事、报告、图片列表等大结果继续放在 `data.json` 和 artifacts 中。

## 推荐调用顺序

```text
用户点击提交
  → SPA 生成 request_id + Idempotency-Key
  → 活动 handler 保存业务参数、request_id、Idempotency-Key
  → POST api/agent/turns，只提交 request_id
  → 平台立即返回 turn_id
  → 活动 handler 将 turn_id 绑定回 request
  → Agent 按 action_id 路由并读取业务请求
  → tools 写业务阶段和最终结果
  → Agent 发一张简短完成卡
  → SPA 刷新 DSL 并打开结果
```

提交 Agent 前就要保存幂等 key。这样即使 SPA 在收到 `turn_id` 前断线，刷新后仍可以用原 key 和原请求重交；平台会返回原 turn，不会创建第二个。

## 1. 声明 Action allowlist

在活动根目录创建 `preview_actions.json`：

```json
{
  "actions": [
    {
      "id": "bedtime.generate_story",
      "versions": ["1"],
      "exclusive": true,
      "payload_schema": {
        "type": "object",
        "required": ["request_id"],
        "properties": {
          "request_id": {
            "type": "string",
            "minLength": 1,
            "maxLength": 128
          }
        },
        "additionalProperties": false
      }
    }
  ]
}
```

- `id`：稳定、小写，只能包含小写字母、数字、点、下划线和短横线。
- `versions`：当前接受的输入协议版本。
- `exclusive`：为 `true` 时，同实例只允许一个 Preview turn 处于 `queued/running`。
- `payload_schema`：平台在启动 Agent 前校验的 JSON Schema。

声明文件只能描述输入面，不能包含 Prompt、生成流程或业务阶段；业务行为必须留在活动 Skills。

Payload 优先只传业务请求引用：

```json
{"request_id": "story_request_123"}
```

不要把完整偏好同时放在 payload 和 `data.json`，否则会产生两个事实源。先由 handler 持久化业务参数，再让 Agent 按 `request_id` 读取。

## 2. 在 typed-KV 中保存请求

以下仅为通用示例，字段名由活动决定：

```json
{
  "generation_requests": [
    {
      "request_id": "story_request_123",
      "idempotency_key": "4f2a...",
      "turn_id": "",
      "status": "ready",
      "stage": "waiting_for_agent",
      "preferences": {
        "style": "治愈",
        "protagonist": "小狐狸",
        "length": "medium"
      },
      "result_id": ""
    }
  ]
}
```

通常提供两个确定性 handler：

1. `save_generation_request(...)`：保存参数、request ID 和幂等 key。
2. `bind_generation_turn(request_id, turn_id)`：受理成功后绑定平台 turn ID。

这些 handler 不调用 LLM，只做 schema 校验、原子写入和 `notify_dsl_update()`。幂等 key 建议标记为 `x-auto-inject:false`，无需进入 Agent prompt。

活动工具在执行期间写业务状态，例如：

```json
{"status":"generating","stage":"illustrating","result_id":""}
```

完成时写：

```json
{"status":"completed","stage":"done","result_id":"story_456"}
```

活动 `status/stage` 是业务状态；平台 `status.json` 的 `running/completed` 是 Agent 生命周期，二者不要混用。

## 3. SPA 提交

使用 frontend base 的 `apiUrl()`，不要硬编码 `/preview/...`、`/dev/preview/...` 或 Go 代理路径。

```ts
import { apiUrl } from './api-base'

type AcceptedAgentTurn = {
  accepted: true
  turn_id: string
  client_request_id: string
  status: 'queued' | 'running' | 'completed' | 'failed' | 'cancelled'
  idempotent_replay: boolean
}

type ResourceRef = {
  kind: 'upload'
  activity_type_id: string
  activity_id: string
  upload_name: string
}

export async function submitAgentTurn(args: {
  clientRequestId: string
  idempotencyKey: string
  actionId: string
  actionVersion: string
  payload: Record<string, unknown>
  displayText: string
  attachmentRefs?: ResourceRef[]
}): Promise<AcceptedAgentTurn> {
  const response = await fetch(apiUrl('/agent/turns'), {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': args.idempotencyKey,
    },
    body: JSON.stringify({
      client_request_id: args.clientRequestId,
      action: {
        id: args.actionId,
        version: args.actionVersion,
        payload: args.payload,
      },
      display_text: args.displayText,
      attachment_refs: args.attachmentRefs ?? [],
    }),
  })

  const body = await response.json()
  if (!response.ok) {
    throw Object.assign(new Error(body.detail ?? 'Agent turn submission failed'), {
      status: response.status,
      code: body.code,
      body,
    })
  }
  return body as AcceptedAgentTurn
}
```

### 将已上传录音附带到 Agent Turn

若 SPA 先用 [`user-upload.md`](user-upload.md) 上传了 `MediaRecorder` Blob，
可把响应里的 `resource_ref` 加入同一个 JSON 请求的顶层
`attachment_refs`。运行时只接受**当前活动、当前实例**且
`kind="upload"` 的引用，并在受理时复制为本轮私有文件：第一个为
`file_0`、第二个为 `file_1`。因此声明了 `asr` capability 的 Agent 可以
在该 turn 内调用 `transcribe_audio(source_file_id="file_0")`。

```ts
const recording = await uploadRecording(blob) // POST api/upload

await submitAgentTurn({
  clientRequestId: requestId,
  idempotencyKey,
  actionId: 'speech.process',
  actionVersion: '1',
  payload: { request_id: requestId },
  displayText: '处理刚录好的语音',
  attachmentRefs: [recording.resource_ref],
})
```

对应请求体：

```json
{
  "client_request_id": "request-123",
  "action": {"id": "speech.process", "version": "1", "payload": {"request_id": "request-123"}},
  "display_text": "处理刚录好的语音",
  "attachment_refs": [
    {"kind": "upload", "activity_type_id": "speech", "activity_id": "act_123", "upload_name": "<opaque>"}
  ]
}
```

`attachment_refs` 参与幂等请求体校验；重试必须携带完全相同的引用和
`Idempotency-Key`。每轮最多 8 个引用，顺序决定 `file_0`…`file_7`。不要传
URL、其他实例的 ref、artifact 或旧 turn 文件。
若只需要在 SPA 中立即得到文字、而不是启动 Agent，使用
[`preview-asr.md`](preview-asr.md)。

调用：

```ts
const requestId = `story_request_${crypto.randomUUID()}`
const idempotencyKey = crypto.randomUUID()

await saveStoryRequest({
  requestId,
  idempotencyKey,
  style: '治愈',
  protagonist: '小狐狸',
  length: 'medium',
})

const accepted = await submitAgentTurn({
  clientRequestId: requestId,
  idempotencyKey,
  actionId: 'bedtime.generate_story',
  actionVersion: '1',
  payload: { request_id: requestId },
  displayText: '今晚想听：治愈 · 小狐狸 · 中篇',
})

await bindStoryTurn(requestId, accepted.turn_id)
```

同一个逻辑请求重试时必须复用完全相同的 client request ID、Idempotency-Key、action、payload 和 display text。相同 key 的请求体发生变化会返回冲突。

## 4. Skill 路由

Agent 会收到：

```json
{
  "input": {
    "kind": "preview_action",
    "display_text": "今晚想听：治愈 · 小狐狸 · 中篇",
    "preview_action": {
      "id": "bedtime.generate_story",
      "version": "1",
      "payload": {"request_id": "story_request_123"}
    },
    "text": "今晚想听：治愈 · 小狐狸 · 中篇"
  },
  "text": "今晚想听：治愈 · 小狐狸 · 中篇"
}
```

新活动只按 `input.kind` 和 `input.preview_action` 路由；不要把顶层 transport
字段当作活动 authoring contract，也不要从 `display_text` 反推结构化 payload。

在 host Skill 中明确路由：

```markdown
## Preview Action 路由

当 input.kind == "preview_action"：

- action.id == "bedtime.generate_story"
  1. 校验 version == "1"。
  2. 读取 payload.request_id。
  3. 用活动数据工具读取对应请求；不存在则发错误卡并停止。
  4. 不从 display_text 重新猜偏好，以保存的请求为事实源。
  5. 执行正常生成工作流。
  6. 先持久化 result_id，最后只发一张简短完成卡。

未知 action 不调用业务工具，发安全错误卡后停止。
```

不要把完整流程堆进 `AGENTS.md`；它只做薄路由，细节继续放在 Skill supporting files。

## 5. 查询状态与刷新恢复

```ts
type AgentTurnStatus = {
  turn_id: string
  client_request_id: string | null
  source: 'chat_message' | 'preview_action'
  action_id: string | null
  status: 'queued' | 'running' | 'completed' | 'failed' | 'cancelled'
  created_at: string
  started_at: string | null
  finished_at: string | null
  error: { code: string; message: string } | null
  trace_url: string | null
}

async function getAgentTurn(turnId: string): Promise<AgentTurnStatus> {
  const response = await fetch(apiUrl(`/agent/turns/${encodeURIComponent(turnId)}`), {
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  })
  if (!response.ok) throw new Error(`get agent turn: ${response.status}`)
  return response.json()
}
```

恢复规则：

```text
从 DSL/data 读取 request
  → 有 turn_id：GET status
      queued/running → 恢复生成界面
      completed      → 刷新 DSL，打开 result_id
      failed         → 展示错误，允许新 key 重试
      cancelled      → 恢复可提交状态

  → request 已保存但 turn_id 为空：
      用已保存的原 key 和原请求再次 POST
      平台返回原 turn_id
      补做 bind handler
```

## 6. 监听 `agent_turn` SSE

在现有 `api/dsl/stream` EventSource 上增加监听，不要建立第二条连接：

```ts
const source = new EventSource(apiUrl('/dsl/stream'))

source.onmessage = (event) => {
  applyDsl(JSON.parse(event.data))
}

source.addEventListener('agent_turn', (event) => {
  const turn = JSON.parse(event.data) as AgentTurnStatus
  if (turn.turn_id !== currentTurnId) return

  if (turn.status === 'queued' || turn.status === 'running') {
    showGenerating(turn.status)
  } else if (turn.status === 'completed') {
    void refreshDsl()
  } else {
    showTurnError(turn.error)
  }
})
```

平台先原子写 `status.json`，再发送 SSE。SSE 只是实时通知，不保证页面离线期间重放；页面初始化必须依赖 GET 和活动数据恢复。

## 7. History 形状

Preview turn 会在标准 history 中留下：

```json
{
  "input": {
    "turn_id": "turn_123",
    "input_type": "preview_action",
    "display_text": "今晚想听：治愈 · 小狐狸 · 中篇",
    "preview_action": {
      "id": "bedtime.generate_story",
      "version": "1",
      "payload": {"request_id": "story_request_123"}
    },
    "text": "今晚想听：治愈 · 小狐狸 · 中篇"
  },
  "turn_status": {
    "status": "completed",
    "started_at": "...",
    "finished_at": "...",
    "error": null
  },
  "output": {},
  "cards": [],
  "artifacts": [],
  "duration_ms": 83000,
  "completed": true,
  "trace_url": "..."
}
```

`display_text` 用于聊天区展示；`preview_action` 是机器输入审计记录；`cards/artifacts` 是标准 Agent 输出。history 不复制整个活动 DSL 或 `data.json`。

## 8. 聊天区完成消息

Preview turn 的完成卡不仅进入 FDA history。平台启用 Agent-message outbox 后，FDA
会把本轮最终的 `card_item` / `artifact_item` 完整快照可靠投递给 Go：

- 用户态 Preview：Go 在当前活动中创建一条新的 Agent 消息并广播 `message`；
- 开发态 Preview：Go 向当前调试实例的持续事件流广播 `agent.message`；
- 投递失败不会回滚已经完成的活动 turn，FDA outbox 会重试或等待 Go 补偿拉取；
- 活动不需要、也不允许从 handler 直接调用 Go 消息接口。

业务写作、生图、TTS 等中间进度仍留在 SPA。聊天区只接收最终简短卡片或失败结果，
不要为每个业务阶段 emit 一条聊天消息。

## 9. 幂等、并发和错误

- 相同 key + 完全相同请求：返回原 `turn_id`，`idempotent_replay=true`。
- 相同 key + 不同请求：`409 idempotency_conflict`。
- 幂等记录至少保留 24 小时。
- `exclusive=true` 且已有 `queued/running` turn：`409 turn_already_running`，响应携带 `active_turn_id`。

| HTTP | code | 处理方式 |
|---|---|---|
| 400 | `invalid_idempotency_key` | 修正或补充 key |
| 404 | `preview_actions_not_configured` | 增加声明文件 |
| 409 | `idempotency_conflict` | 不得复用该 key 提交新内容 |
| 409 | `turn_already_running` | 恢复 `active_turn_id` |
| 422 | `invalid_preview_turn_request` | 修正请求体 |
| 422 | `preview_action_not_allowed` | 修正 action ID/version |
| 422 | `preview_action_payload_invalid` | 修正 payload |
| 429 | `turn_admission_limited` | 稍后用同 key 重试 |

真正重试一次新的业务任务时使用新 Idempotency-Key，并在活动数据中记录它重试自哪个 request/turn。不要自动无限重试整个 Agent turn、图片或音频。

## 10. 完成卡

完成卡只需要：

1. 告知完成或失败。
2. 给一句简短摘要。
3. 提供打开 SPA 结果所需的通用资源 ID/metadata。

示例：

```text
《月光下的小狐狸》已经准备好了，故事、插画和朗读都已放进今晚的阅读器。
```

必须先持久化业务结果，再 emit 完成卡；否则 history 显示完成时，SPA 可能找不到结果。

## 11. 验收清单

- [ ] 活动根存在合法 `preview_actions.json`。
- [ ] payload 只传请求引用，没有复制完整业务参数。
- [ ] `data.schema.json` 能保存 request、幂等 key、turn ID、业务阶段和 result ID。
- [ ] handler 能保存请求并绑定 turn ID，且不调用 LLM。
- [ ] host Skill 按 `input.kind/action.id/version` 路由。
- [ ] 未知 action 有安全失败路径。
- [ ] SPA 使用 `apiUrl()`，没有硬编码代理路径。
- [ ] 网络重试复用完全相同的 key 和请求体。
- [ ] 对 `turn_already_running` 恢复现有 turn。
- [ ] 同时支持 SSE 实时更新和 GET 刷新恢复。
- [ ] 连点两次只生成一个结果。
- [ ] 关闭 SPA 后 turn 仍完成，重新打开能恢复。
- [ ] history 包含结构化 input、turn_status 和简短 output。
- [ ] 用户态完成后，Go 聊天历史中只有一条与 `turn_id` 对应的 Agent 完成消息。
- [ ] trace、图片、TTS 和模型调用属于同一 turn。
- [ ] activity verifier 通过。

## 当前可靠性边界

当前实现保证浏览器关闭、SSE 断开或请求方停止读取后，已受理 turn 仍在当前 runtime 进程中执行。

当前不保证 runtime 进程或宿主机器异常退出后自动恢复。跨进程恢复需要平台后续提供持久化任务队列、租约与 orphan-turn reconciliation。
