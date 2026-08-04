# Reference — 实例资源生命周期（创建、引用、读取与删除）

> 平台级能力，不绑定活动。这里的“资源”是实例内所有持久化文件，不只图片和上传文件。

## 一个身份模型，多种来源

所有来源都返回并持久化 `resource_ref`；来源不同只会得到不同 `kind`，读取和删除使用同一组 helper。

| 来源 | 创建/取得方式 | `resource_ref.kind` |
|---|---|---|
| Static Preview 用户上传 | `POST api/upload` | `upload` |
| handler / 系统生成的原始字节 | `ctx.save_resource(content=..., content_type=...)` | `upload` |
| Agent 会话附件 | `ctx.get_turn_resource(file_id)` | `turn_file` |
| 模型生成图、图片编辑、TTS | 工具返回的 `artifact.resource_ref` | `artifact` |
| 文档转换、截断 Markdown、普通文件产物 | artifact 返回值或历史记录里的 `resource_ref` | `artifact` |

新活动的业务数据只保存完整 `resource_ref`。URL 是展示兜底，不是资源身份；不要拼 OSS key、磁盘路径，
也不要只保存 `upload_name` / `artifact_id`。

```python
# 对话附件直接复用原文件，不复制第二份 upload。
resource = ctx.get_turn_resource(file_id)
record = {
    "resource_ref": resource["resource_ref"],
    "file_url": resource["url"],
    "content_type": resource["content_type"],
}

# 活动或系统自己产生的字节。
saved = ctx.save_resource(content=document_bytes, content_type="application/pdf")
record = {"resource_ref": saved["resource_ref"], "file_url": saved["url"]}
```

图像生成、编辑、TTS 和文档转换已经注册为 artifact，不需要再复制到 uploads 才能管理。直接保存工具返回的
`resource_ref`；只有业务确实产生了一组新字节时才调用 `save_resource`。

## Preview 字段投影

新活动把资源身份保存在业务数据里，并在 DSL 或 handler 响应中用字段级 `resource_refs` 指明 URL 要写回哪里：

```python
photo = {
    "src": record.get("url", ""),
    "alt": record.get("title", ""),
    "resource_refs": {"src": record["resource_ref"]},
}
```

字段名开放：`src`、`photo`、`cover_url` 等活动私有直属字段都可以；key 不是 JSONPath，目标字段必须已存在，且不能是协议字段 `resource_ref` / `resource_refs`。Go 只在当前访问平面鉴权后把这些字段投影成 public URL，SPA 不区分资源来自 upload、turn_file 还是 artifact。

为了兼容历史数据，FDA 的 Preview 出站 walker 也会扫描任意直属字符串字段：值完整匹配 `/v1/...` 或 `/preview/.../uploads/...` canonical 资源 URL 时，自动补出对应 `resource_refs[field]`。这个规则同时覆盖 bootstrap DSL、full-mode DSL SSE 和 handler JSON；不匹配的外部 URL、普通文本保持原样。若数据只存了 ref 而没有 canonical URL，必须像上例一样显式写字段映射。

## 统一读取与删除

```python
content = ctx.read_resource(resource_ref)
result = ctx.delete_resource(resource_ref=resource_ref, purge_origins=True)
```

`read_resource(ref)` 对当前实例的 `upload`、`turn_file`、`artifact` 返回字节；不可读时返回 `None`。
`delete_resource` 只接受完整引用，并由 ctx 强制绑定当前 `activity_type_id + activity_id`：

| 参数 | 含义 |
|---|---|
| `resource_ref` | 当前实例的完整资源引用 |
| `purge_origins` | 仅对曾从 turn 文件复制出的 upload 有意义；同时回收其冗余来源。直接使用 `turn_file` 的新活动通常不需要它 |

典型返回：

```jsonc
{
  "ok": true,
  "deleted": true,
  "pending": false,
  "resource_ref": {"kind": "artifact", "activity_type_id": "…", "activity_id": "…", "artifact_id": "…"},
  "reclaimed_bytes": 12345
}
```

逻辑墓碑先于物理回收提交。对象存储暂时失败时返回 `pending: true`，平台保留删除坐标并由统一 GC 重试；
历史元数据仍可展示，但内容读取返回 410。活动可显示“业务记录已删除，文件清理中”，不能因此恢复业务对象。

## 活动负责零引用判断

平台不解释活动私有数据，也不知道一个资源是否仍被草稿、记忆、页面或展览引用。零引用判断必须在活动层完成：

1. 业务变更前收集可能失去引用的完整 `resource_ref`。
2. 原子提交删除、替换或移动引用。
3. 扫描该实例所有仍存活的业务对象，建立当前引用集合。
4. 只对已不在集合中的候选调用 `ctx.delete_resource(...)`。
5. 删除异常或 `pending: true` 只记清理待办，不回滚业务提交。

```python
import json
from app.card_system import data_store

def identity(ref: dict) -> str:
    return json.dumps(ref, ensure_ascii=False, sort_keys=True)

before = {identity(ref): ref for ref in resource_refs(removed_or_replaced)}
schema = data_store.load_data_schema(ctx.activity_dir)

def commit(current: dict) -> tuple[dict, set[str]]:
    updated = apply_business_change(current)
    live = {identity(ref) for ref in resource_refs(updated)}
    return updated, live

live = data_store.update_data(ctx.instance_dir, schema, commit)

cleanup = []
for key in sorted(before.keys() - live):
    try:
        cleanup.append(ctx.delete_resource(resource_ref=before[key]))
    except Exception as exc:
        cleanup.append({"resource_ref": before[key], "deleted": False, "pending": True, "error": str(exc)})
```

同一引用可能出现在多个业务对象中，所以不能因为删除一条记录就立即删文件。草稿转正式记录通常只是引用迁移。

## 安全与管理边界

- ctx 已绑定当前实例；跨实例的 `resource_ref` 返回 403。
- 平台从登记记录解析并校验真实 OSS key / 本地路径，不接受调用方提供物理位置。
- `upload`、`turn_file`、`artifact` 都保留可枚举元数据和删除墓碑；实例硬删除会覆盖活跃资源与待重试资源。
- 重复删除幂等；`turn_trace` 不是活动可删除的文件资源。
- 删除能力不代替业务授权。多人活动仍须先用 `ctx.user_id` 校验谁有权删除业务对象。

对终端用户只展示“文件/图片/录音”等业务概念，不需要暴露 SPA、Agent 或 artifact 的内部来源差异。
