# `frontend-base/` — 派生模板

这个目录是新活动前端工程的**派生源**，本身**不是**可运行项目（不会被运行时挂载）。

## 怎么用

```bash
bash <package>/tools/derive-frontend.sh <activity-id> --name "<English Name>" --accent "#7c4dff"
```

`<package>` 是本插件根目录（仓库内典型路径 `packages/freedeepagents-activity-builder/`）。脚本会：

1. 校验 `<activity-id>` 满足 `^[a-z][a-z0-9-]{1,30}$`
2. `cp -r <package>/frontend-base/ activities/<activity-id>/site/`
3. 把所有 `.tpl` 文件去后缀，并替换 token：
   - `{{ACTIVITY_ID}}` → 活动 id
   - `{{ACTIVITY_NAME}}` → English short name
   - `{{ACTIVITY_TITLE}}` → 浏览器 title
   - `{{ACCENT_COLOR}}` → 主题色
4. 在生成的 `README.md` 写上 `frontend-base/` 的 git SHA 作为来源记录
5. 输出 Static Preview manifest 提示（`dsl_builder_module` / 可选 `tools_module`）

## 共享模块（不修改）

派生后的项目不应该改这些文件——改它们意味着回到 `frontend-base/` 改源然后让所有派生项目同步。参见 [`policies/dont-touch-frontend-base.md`](../policies/dont-touch-frontend-base.md)。

| 文件 | 提供 |
|---|---|
| `src/lib/http.ts` | `request<T>()` HTTP 助手 + `JsonError` 类 |
| `src/lib/api-base.ts` | `BASE_PREFIX`、`BASE`、`apiUrl()` |
| `src/lib/asset-url.ts` | `resolveAssetUrl()` |
| `src/hooks/useApi.ts` | `{ data, error, loading, retry }` |
| `src/hooks/useDsl.ts` | Static Preview DSL fetch + SSE 订阅 |
| `src/components/{ErrorBoundary,LoadingSpinner,ApiErrorBanner}.tsx` | 通用 UI 原语 |

## 活动定制（你写）

| 文件 | 用途 |
|---|---|
| `src/lib/types.ts` | 你的领域类型 |
| `src/lib/api-client.ts` | 调 Static Preview `/api/dsl.json` / `/api/dsl/stream` |
| `src/lib/mock-dsl.ts` | 本地 Vite dev 的 mock DSL |
| `src/components/...` | 你的业务 UI |
| `src/hooks/...` | 你的业务 hooks |

## 与现有前端活动的关系

- 新活动 → 用上面的 derive 命令从 `frontend-base/` 派生
- 改老活动的 `site/` → 直接在该活动目录里改，不要回头"重构成 base 风格"，避免回归风险
- 新前端默认目标是 **Static Preview**：构建 `site/dist/`，由 runtime 静态服务

## Tailwind 默认 ON

派生项目已经配好 Tailwind v4（`@tailwindcss/vite` 插件 + `@import "tailwindcss"`）。如果活动想要纯 CSS：删 `src/styles/index.css` 的 `@import "tailwindcss";` 并从 `package.json` 卸 tailwind 相关依赖即可。
