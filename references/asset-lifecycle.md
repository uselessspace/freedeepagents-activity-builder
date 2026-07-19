# Reference — 实例资产生命周期（上传、引用与删除）

> 平台级能力，不绑定活动。适用于 Static Preview 上传、Agent 会话附件，以及 handler 生成后写入 uploads 的图像/音频。

## 一个模型，两条入口

终端用户可能从两个入口提供媒体，但活动最终都应把它们归一化为当前实例的上传资产：

| 来源 | 归一化方式 | 结果 |
|---|---|---|
| SPA / 草稿箱上传 | `POST api/upload` | `{asset_id, upload_name, url, resource_ref, ...}` |
| Agent 会话附件 | `ctx.promote_turn_file(file_id)` | 同形的结构化资产句柄 |
| handler 生成或编辑后的字节 | `ctx.save_upload(content=..., content_type=...)` | uploads 资产句柄 |

`asset_id` 当前等于内容寻址的 `upload_name`（`<sha256>.<ext>`），但业务代码应把它当 opaque ID，
不要自己拼 OSS key、本地路径或跨实例 URL。新活动优先保存 `resource_ref` + `asset_id`；`url` 只作
显示/旧客户端兜底。

```python
# Agent turn 的 files[] 里拿 file_id；不要只保存会话临时 URL。
asset = ctx.promote_turn_file(file_id)
record = {
    "asset_id": asset["asset_id"],
    "resource_ref": asset["resource_ref"],
    "image_url": asset["url"],
}
```

旧的 `ctx.publish_uploaded_file(file_id)` 仍返回 URL，但没有结构化资产句柄；需要完整生命周期的新活动
应使用 `ctx.promote_turn_file(file_id)`。

## 删除能力

handler / activity tool 可调用：

```python
result = ctx.delete_asset(
    upload_name=asset_id,
    purge_origin=True,
)
```

| 参数 | 含义 |
|---|---|
| `upload_name` | 当前实例的内容寻址资产名；不要传 URL、OSS key 或路径 |
| `purge_origin` | 若资产由 Agent 会话附件提升而来，同时清除来源附件字节；历史仍保留文件名和“内容已删除”墓碑 |

典型返回：

```jsonc
{
  "ok": true,
  "deleted": true,
  "pending": false,
  "upload_name": "<sha256>.png",
  "reclaimed_bytes": 12345,
  "origins_deleted": 1
}
```

对象存储暂时失败时通常返回 `pending: true`，平台保留 GC 墓碑并在后续删除/重试时继续处理。活动可把
它显示为“业务记录已删除，文件清理中”，不要因此恢复已经删除的草稿或业务对象。

## 活动必须负责引用判断

平台只保证“调用者只能删除当前 `activity_type_id + activity_id` 实例登记的资产”，不理解活动私有
数据，也不会替活动判断一张图是否仍被草稿、记忆、页面或展览引用。**零引用判断属于活动业务。**

正确顺序：

1. 在业务变更前收集可能失去引用的 `asset_id`。
2. 原子提交业务数据变更（删除草稿、替换图片、删除记录等）。
3. 扫描该实例所有仍存活的业务对象，汇总当前引用集合。
4. 仅对候选集合中不再出现的资产调用 `ctx.delete_asset(...)`。
5. 删除异常或 `pending: true` 只记为清理待办，不能回滚第 2 步。

```python
before_candidates = upload_names(removed_or_replaced_object)
ctx.set_data(new_data)  # 先完成业务提交

live_refs = upload_names(ctx.get_data() or {})
cleanup = []
for name in sorted(before_candidates - live_refs):
    try:
        cleanup.append(ctx.delete_asset(upload_name=name, purge_origin=True))
    except Exception as exc:
        cleanup.append({"upload_name": name, "deleted": False, "pending": True, "error": str(exc)})
```

内容寻址会让相同字节复用同一个 `asset_id`，所以不能按“删除了一条记录”直接删文件；必须扫描完整
实例引用。把草稿整理成正式记录只是**引用迁移**，不是零引用，也不应删除资产。

## 安全边界

- `ctx.delete_asset` 已绑定当前活动类型和实例；活动不能指定别的实例。
- 平台从当前实例注册表解析真实对象存储 key，并校验 canonical key；不接受任意 OSS key/path。
- 重复删除是幂等的；已删除或不存在的当前实例资产不会越界影响其他实例。
- 实例硬删除仍会清除活跃资产和 GC 墓碑中的待删对象。
- `delete_asset` 不是用户授权模型。若活动有多人协作，handler 仍须用 `ctx.user_id` 执行业务权限校验。

## 交互建议

对终端用户保持一个“图片/录音”概念即可，不要暴露 SPA 上传和 Agent 会话提升这两条内部通道。
删除草稿时可以返回并展示：

- `assets_reclaimed`：本次确认回收的资产数；
- `reclaimed_bytes`：确认回收的字节数；
- `cleanup_pending`：仍在 GC 重试的资产数。
