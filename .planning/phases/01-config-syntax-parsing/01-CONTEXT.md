# Phase 1: Config Syntax & Parsing - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

扩展 keybind 解析器以支持条件语法 `[condition=value]`，建立 Condition 数据模型和 ConditionSet 存储。用户可以在配置文件中写条件性快捷键，Ghostty 正常加载且现有配置不受影响。本阶段不涉及运行时求值。

</domain>

<decisions>
## Implementation Decisions

### 条件字段语法
- 条件类型和值之间用等号分隔：`[process=vim]`
- UserVar 条件中变量名和值用冒号分隔：`[var=in_vim:1]`
- 条件部分 `]` 和触发键之间无分隔符：`[process=vim]ctrl+w=close_surface`
- 条件在 flags 前面：`[process=vim]global:ctrl+w=close_surface`
- 完整语法示例：
  - `keybind = [process=vim]ctrl+w=close_surface`
  - `keybind = [title=vim: main.zig]ctrl+s=write_scrollback_file`
  - `keybind = [var=in_vim:1]ctrl+w=close_surface`
  - `keybind = [process=vim]global:ctrl+w=close_surface`

### 错误处理
- 畸形条件（`[process=]`、`[=vim]`、`[]`）复用现有 `InvalidFormat` 错误
- 未知条件类型（`[unknown=foo]`）严格报错，不静默忽略
- 未关闭方括号（`[process=vim`）报错
- v1 只允许单条件，多条件并列（`[process=vim][title=foo]`）报错

### 解析范围
- Phase 1 解析器识别全部三种条件类型：`process`、`title`、`var`
- Condition 数据结构使用 tagged union：`.process = "vim"`, `.title = "main.zig"`, `.var_ = .{ .name = "in_vim", .value = "1" }`
- Phase 1 只存储精确匹配值，glob 通配符解析留给 Phase 5
- 运行时求值在 Phase 2 实现

### Claude's Discretion
- Condition 解析在 `parseFlags` 之前还是独立函数中提取
- ConditionSet 的具体内部数据结构（hashmap 策略等）
- 测试用例的具体组织方式

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Binding.Parser.parseFlags()`: 已有前缀解析模式（`all:`, `global:` 等），条件解析可在其之前插入
- `Binding.Parser.init()`: 主解析入口，需要扩展以处理 `[...]` 前缀
- `Binding.Error`: 现有 `InvalidFormat`/`InvalidAction` 错误类型可复用

### Established Patterns
- 前缀解析模式：`parseFlags()` 循环匹配 `prefix:` 并推进索引，条件解析可采用类似模式
- Iterator 模式：`SequenceIterator` 用于 `a>b>c` 序列解析
- Tagged union：`Trigger.Key` 和 `Action` 都使用 tagged union，Condition 应遵循同样模式
- 测试模式：`parseSingle()` helper + `testing.expectEqual` 进行断言

### Integration Points
- `Binding` struct：新增 `condition: ?Condition` 字段
- `Set.parseAndPut()`：需要处理带条件的绑定存储
- `Config.Keybinds.parseCLI()`：条件解析在此层或 `Parser.init()` 层触发
- 新文件 `src/input/Condition.zig`：Condition tagged union 定义

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-config-syntax-parsing*
*Context gathered: 2026-03-18*
