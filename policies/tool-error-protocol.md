# Policy — 活动工具错误返回协议（advisory）

适用：写 `activities/<id>/tools.py::make_tools` 暴露的 @tool 函数时。
本文档是**约定（advisory）**，不是 verifier 硬门禁——它统一活动 @tool 返回 dict 的形状，
让 LLM 一眼就能判断"成功 / 降级 / 失败"，不必为每个活动重新猜。

> 这条协议只管**活动 @tool 自己构造并返回的 dict**。card-system 工具
> （`card_emit` / `data_set` / `image_generate` 等）的返回形状由 runtime 决定，
> 见 [output-protocol.md](output-protocol.md) 与 [llm-output-discipline.md](llm-output-discipline.md)。

---

## 为什么需要它

历史上活动作者写错误返回的风格各不相同：

- 有的失败返回 `{"ok": True, "warning": ...}`（缺 `error`）
- 有的失败返回 `{"error": ..., "hint": ...}`
- 有的降级（部分可用）也只返回 `{"ok": True, "warning": ...}`

最危险的是第三种：**`ok: True` 同时带 `warning`**。LLM 默认读到 `ok: True`
就当成功，把 `warning` 当噪声忽略，于是"降级"被误判为"完全成功"，
后续流程基于不完整数据继续推进。

统一成下面三种 shape 之一即可消除这种歧义。

---

## 三种返回 shape

### Shape 1：完全成功

```python
return {"ok": True, <result fields>}
```

### Shape 2：降级成功（部分能用 + 警告）

```python
return {
    "ok": True,
    <result fields>,        # 仍然带可用的部分结果
    "degraded": True,       # 关键：显式标记"虽然 ok 但不完整"
    "warning": "<人话说明哪里 degraded>",
}
```

**不要**写 `{"ok": True, "warning": ...}` 而不带 `degraded: True`——
那正是会让 LLM 把降级当成功的写法。`degraded: True` 是给 LLM 的明确信号：
"结果能用，但你要知道它不完整，必要时提示用户或走补救路径。"

### Shape 3：失败

```python
return {
    "error": "<出了什么错>",
    "hint": "<给 LLM 的下一步指引>",   # 强烈建议
}
```

**不要**在失败时省掉 `error`。即使你额外带了 `ok: False`，也以 `error` 为准——
LLM 优先看 `error` 字段判定失败。

---

## `hint` 字段怎么写

`hint` 是失败/降级时给 LLM 的"下一步"指引，写好它能省下大量无效重试。

- **主语永远是 LLM**："Do X" / "Avoid Y"，不是描述系统状态。
- **给具体下一步**：重试 / 换 prompt / 跳过这条 / 等用户 / emit 一张失败卡。
- **明确是否该重试**。配额、网络这类**暂时性**失败，明说"本轮不要重试"——
  连续重试通常只会再次撞同一个限额。参考平台 `image_generate` / `tts_generate`
  失败 hint 的措辞（`app/tools/image_gen.py` `_FAILURE_HINT`）。
- **保持领域无关性的边界**：活动自己的 @tool 可以引用本活动的卡片/字段名；
  但不要假设调用方一定会按某种固定方式补救——把"建议"写成"指引"而非"命令"。

---

## 守卫类错误的 hint：输出代码侧真理，别只指向文档

多阶段活动常给 @tool 加**相位守卫**（"当前 phase 不对就拒绝调用"）。守卫拒绝时的 `hint`
有一条硬规则：**hint 必须直接说出运行时的真相，而不是把 LLM 引去读某份文档。**

为什么：守卫拒绝意味着 LLM 当前的世界模型已经和运行时不一致了。如果此时 hint 只说
"去看 SKILL.md 的路由表"，而那份路由表恰好就是 LLM 刚刚照着做、却被守卫拒掉的东西，
LLM 会照原样再试一遍 → 再被拒 → 死循环。**对 AI 开发者平台，错误消息本身就是运行时规范**——
它要携带文档无法实时反映的状态。

守卫 hint 至少包含三项代码侧事实：

```python
raise AppError(
    f"can't call fetch_financials in phase {current!r}",
    hint=(
        f"current phase = {current}; "                     # 1. 现在在哪
        f"this tool needs phase ∈ {sorted(ALLOWED)}; "     # 2. 本工具要求什么
        f"from {current} you can call: {advanceable(current)}"  # 3. 现在能往前走的工具
    ),
)
```

- **当前 phase**：直接读出来填进去，别让 LLM 猜。
- **本工具允许的 phase**：从守卫用的常量（如 `ALLOWED`）取，保证和实际判定逻辑同源。
- **从当前 phase 能推进的工具**：给 LLM 一条可走的出路，而不是只告诉它"此路不通"。

文档引用（"细节见 SKILL.md 第 X 节"）只能作为**补充**，不能作为 hint 的主体。理由很简单：
代码侧常量永远和守卫判定一致；文档可能漂移。让 hint 复述真理源，LLM 才能自我纠偏而非空转。

---

## 自动检查（verifier 支持的部分）

verifier **不会**静态扫描"每个 @tool 的返回 dict 是否带 `degraded` / `hint`"——
返回点往往分散、dict 常常动态拼装（先 `result = {...}` 再 `result["hint"] = ...`），
静态分析判不准，强行做只会刷出一堆假阳性。这部分靠 code review + 本协议自觉遵守。

verifier **会**自动查的是相关的一类真实事故——**文档里用 call 语法引用了 tools.py
不存在的工具**（`_verify_doc_tool_references`）：

- 扫 `activities/<id>/AGENTS.md` 和 `skills/**/*.md` 里所有 `` `tool_name(` `` 形式的调用引用
- 跟 `tools.py::make_tools` 实际导出的 @tool 名对比
- 文档提到、代码没有 → WARNING（LLM 会去调一个不存在的工具，拿到 404 再重试，烧 token）

它只查 **call 语法**（`` `foo(` ``）这种"LLM 应当调用它"的明确信号，
不查表格/散文里裸反引号的工具名（如工具一览表里的 `` `save_intake` ``），以保持精确、近零误报。

同一检查还做**参数级比对**：文档里 `activity_tool(kwarg=...)` 用了该工具签名里不存在的关键字
（如 `save_nodebook(world_id=...)` 而真实参数是 `world_title`）→ WARNING。strict tool-call 模式会在
运行时拒收未知参数，这类"文档教错参数名"的 drift 以前能静默通过。单行调用才查、`**kwargs` 工具跳过。

---

## 迁移建议（现有活动）

本协议是 advisory，现有活动**按需逐步迁移**，不强制一次性改完。优先级最高的一类：

- 把降级路径里的 `{"ok": True, "warning": ...}` 补上 `"degraded": True`。
  例如 `knowledge-worldsmith` 的 `search_topic` / `fetch_source` / `extract_document`
  在外部检索/解析失败时返回 `ok: True + warning`，应加 `degraded: True`，
  避免 LLM 把"检索失败、退回纯 LLM 知识"当成"检索成功"。

新活动从一开始就遵循三种 shape 即可。

---

## See also

- [output-protocol.md](output-protocol.md) — card-system 输出协议（runtime 汇编侧）
- [llm-output-discipline.md](llm-output-discipline.md) — 工具调用纪律 + 常踩坑
- [multi-store-tool-design.md](multi-store-tool-design.md) — 多 store @tool 的设计
