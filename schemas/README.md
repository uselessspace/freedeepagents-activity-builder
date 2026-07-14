# JSON Schemas

Canonical schemas for FreeDeepAgents activity files. Use them in your editor (VS Code: add `"json.schemas"` mapping in settings) or in CI to validate authored files.

**Bundle version: 0.4.15** — this schema bundle ships inside the plugin and tracks `.claude-plugin/plugin.json`. `tools/check_schema_sync.py` (run in the platform repo / CI) proves `card-template.schema.json` matches the runtime's `app.models` field-for-field, so an authored file that passes these schemas also passes the runtime's `OutputCard` validation at emit time.

| File | Validates |
|---|---|
| `manifest.schema.json` | `activities/<id>/manifest.json` (closed field whitelist; includes Static Preview + handlers + graph_model + sandbox_env + catalog metadata) |
| `runtime.schema.json` | `activities/<id>/runtime.json` (operational fields including `sse_debug_view`) |
| `card-template.schema.json` | `activities/<id>/card_templates/*.json` (`OutputCard` wrapper + 6 block types: markdown / info / form / action / image / audio) |
| `card-vars.schema.json` | `activities/<id>/card_templates/*.vars.json` (variable definitions for the template's placeholders) |
| `output-artifact.schema.json` | a single entry in `ActivityAgentOutput.artifacts[]` (image_generate / image_edit output shape) |

> These are the **authoring** schemas (referenced as `<package>/schemas/…` in the docs). The runtime **transport** schema `activity-output.schema.json` (the full `ActivityAgentOutput` sent to the frontend) lives at the repo root `schemas/` — it's runtime-maintained and read-only to activities, so it is intentionally not part of this authoring bundle.

## VS Code wiring

Add to `.vscode/settings.json` in your activity workspace:

```jsonc
{
  "json.schemas": [
    {
      "fileMatch": ["activities/*/manifest.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/manifest.schema.json"
    },
    {
      "fileMatch": ["activities/*/runtime.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/runtime.schema.json"
    },
    {
      "fileMatch": ["activities/*/card_templates/*.json", "!**/*.vars.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/card-template.schema.json"
    },
    {
      "fileMatch": ["activities/*/card_templates/*.vars.json"],
      "url": "./packages/freedeepagents-activity-builder/schemas/card-vars.schema.json"
    }
  ]
}
```

## Programmatic validation

```python
import json, jsonschema

schema = json.load(open("packages/freedeepagents-activity-builder/schemas/manifest.schema.json"))
manifest = json.load(open("activities/my-activity/manifest.json"))
jsonschema.validate(manifest, schema)
```

## Authority chain

The **`tools/activity_verifier.py`** in this package is the source of truth — it implements the same rules these schemas describe, plus cross-file checks (e.g. each card template has a sibling `.vars.json`). If a schema and the verifier disagree, the verifier wins; please file a bug.

## Bundle 与 runtime 版本窗口

两套 schema 各管一段：

- **创作期**（你本地）：`<package>/schemas/*` + `activity_verifier.py` 校验你写的文件，随插件版本走（当前 `Bundle version: 0.4.15`，见顶部）。
- **加载 / emit 期**（部署后）：平台 runtime 的 `app.models`（pydantic）才是最终权威——bundled schema 与 verifier 只是它的离线镜像，`check_schema_sync.py`（在平台仓库 / CI 跑）逐字段证明两者一致。**两者分歧时以 runtime 为准。**

当 bundle 与 runtime 版本不一致：

- **bundle 落后于 runtime**：runtime 可能已接受你的 schema 还不认识的新字段 → 本地 verifier 偏严，可能对一个 runtime 实际允许的字段误报 ERROR。`check_schema_sync.py` 在 `Bundle version` 行落后时给**非阻塞提醒**；把插件包升级到与目标 runtime 同档即可。
- **bundle 领先于 runtime**：你的新 schema 放行的字段，可能被较旧的 runtime 在加载期拒收。**按你将要部署的那个 runtime 版本来校验**，别只信本地更新的 schema 副本。
- **安装 / 重装**：`install-activity.sh` 解包后由目标 runtime 在加载期再校验一次；你本地跑的 verifier 始终是 bundle 版本的那套。

**Pin 建议**：把 activity-builder 插件包版本与你面向的平台 runtime release 绑定、一起升级；拿不准时，以"与目标 runtime 匹配的 verifier + runtime 本身"为准，而不是手上恰好更新的 schema 副本。
