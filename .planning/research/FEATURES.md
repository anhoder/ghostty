# Feature Research

**Domain:** 终端模拟器条件性快捷键配置
**Researched:** 2026-03-18
**Confidence:** HIGH (基于源码分析 + 竞品文档)

## Feature Landscape

### Table Stakes (用户期望的基础功能)

用户假设这些功能存在。缺少任何一项 = 功能感觉不完整。

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| 基于进程名的条件匹配 | 这是最直接的"vim vs shell"用例。用户在 WezTerm 中通过 `get_foreground_process_name()` 已经熟悉此模式 | HIGH | 需要 PTY 进程组查询；Ghostty 已有 `getpgid` 和 `killPid` 基础，但无 `get_process_name` 实现 |
| 条件绑定语法集成进现有 keybind 语法 | 用户不想维护独立配置文件或学习全新 DSL；所有其他选项应延伸现有 `keybind =` 语法 | MEDIUM | Ghostty keybind 语法已支持 prefixes (`all:`, `global:`, `unconsumed:`, `performable:`)，这是同一扩展点 |
| 条件快捷键优先于无条件快捷键 | 符合用户直觉；特殊情况覆盖通用情况与所有现代系统行为一致 | LOW | 已在 `Binding.zig` 层有优先级逻辑，需要在条件评估时扩展 |
| 后定义的条件覆盖先定义的条件 | 标准配置文件覆盖语义；用户期望配置按从上至下顺序生效 | LOW | 与现有 keybind 覆盖行为一致（Config.zig 文档明确说明） |
| 基于窗口标题的条件匹配 | 某些工具（tmux、screen、远程 SSH 会话）无法通过进程名区分，但会设置自定义标题 | MEDIUM | Ghostty 已有完整的 title 跟踪（Surface.zig），问题是如何从 keybind 评估阶段访问它 |

### Differentiators (竞争优势)

区分本产品的功能。不是必需的，但有价值。

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| 基于 UserVar 的条件匹配（OSC 1337） | 终端应用可以通过 `OSC 1337;SetUserVar=name=value` 设置任意上下文变量，供 shell integration 脚本控制。比进程名更精细，且应用可控 | HIGH | iTerm2 原创设计。Ghostty 已在 `iterm2.zig` 中解析 `SetUserVar` 但标记为 "unimplemented"；这是天然扩展点 |
| 配置文件中预定义 UserVar 初始值 | 用户可以在配置文件中设置变量初始值，不必等到 shell 发送 OSC 序列就能激活规则 | MEDIUM | 需要在 Surface 初始化时注入变量；对离线配置和测试有价值 |
| 精确和 glob/正则模式双重匹配 | `process = vim` 匹配精确名，`process = nvim*` 匹配 neovim 变体 | MEDIUM | 核心灵活性；Ghostty 已依赖 Oniguruma 正则库，可重用 |
| 条件匹配配合 key tables 工作 | 当特定进程运行时自动激活/停用 key table，而不需用户手动触发 | HIGH | 目前 key tables 只能通过 keybind action 激活（`activate_key_table:<name>`）；条件性自动激活是质的飞跃 |
| 与 shell integration 联动的 prompt 状态感知 | shell integration 已能检测"正在等待输入 vs 正在执行命令"；这可用作条件维度 | HIGH | Ghostty 有 `shell_integration.zig`，但将 shell 状态暴露给 keybind 评估需要新增状态通道 |

### Anti-Features (常被请求但会产生问题的功能)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| 多条件 AND/OR 逻辑组合 | 用户希望"vim 模式 AND 暗色主题 = 特殊绑定" | v1 复杂度爆炸：需要完整的布尔表达式解析器；条件类型之间的语义交互难以测试；大多数用户实际上不需要它 | v1 只支持单条件；多条件可在 v2 引入，先验证单条件用户体验 |
| 兼容 Kitty `when_focus_on` 语法 | 部分用户从 Kitty 迁移，希望配置直接可用 | Kitty 自身文档显示 `when_focus_on` 不是正式特性；Ghostty 风格语法更清晰，更易维护 | 使用 Ghostty 原生 prefix 语法；提供迁移指南 |
| 实时进程监听（polling/event 驱动） | 用户希望快捷键"即时"跟随前台进程切换，无延迟 | 每次按键都查询进程名会增加延迟；定时轮询会浪费 CPU；PTY 不提供前台进程变更事件 | 按键时惰性查询一次（lazy evaluation）；对延迟要求严格的场景用 UserVar（应用主动通知） |
| 跨所有配置项的条件化（字体/颜色等条件化） | "vim 时用不同字体" 看起来很酷 | 范围失控；条件字体切换需要完整字体重新加载；与现有 conditional.zig（仅支持 theme/os）设计冲突 | 保持 v1 仅针对 keybind；字体/颜色的条件化通过 OSC 序列由应用自身控制更合适 |
| GUI 可视化配置界面 | 非技术用户友好 | 超出 Ghostty 当前配置模型范围；Ghostty 刻意选择纯文本配置 | 文档清晰 + 示例配置文件就足够了 |

## Feature Dependencies

```
进程名条件匹配
    └──requires──> PTY 前台进程 PID 获取 (src/termio/Exec.zig 已有 getpgid)
                       └──requires──> PID → 进程名转换 (macOS: libproc/proc_name; Linux: /proc/[pid]/comm)

窗口标题条件匹配
    └──requires──> Surface.title 状态暴露给 keybind 评估器 (Surface.zig 已有 title 字段)

UserVar 条件匹配
    └──requires──> OSC 1337 SetUserVar 实现 (iterm2.zig 已解析但标记 unimplemented)
                       └──requires──> Surface 级 UserVar 存储 (HashMap<string, string>)

条件 keybind 语法解析
    └──requires──> Binding.zig 和 Config.zig keybind 解析器扩展

自动 key table 激活（通过条件）
    └──requires──> 条件匹配核心已完成
    └──enhances──> 现有 key tables 系统 (Surface.zig 已有 activate_key_table 实现)

UserVar 配置预定义
    └──requires──> OSC 1337 SetUserVar 实现
    └──enhances──> UserVar 条件匹配

Shell integration 状态感知
    └──requires──> shell_integration.zig prompt 状态向上传递
    └──enhances──> UserVar 或进程名条件匹配 (可作为独立维度)
```

### Dependency Notes

- **进程名匹配 requires PTY 进程 PID 获取:** Ghostty 已在 `src/termio/Exec.zig` 中通过 `getpgid()` 追踪子进程 PID，但尚无将 PID 转为进程名的代码路径。macOS 需用 `proc_pidinfo` / `libproc`；Linux 需读取 `/proc/[pid]/comm`。
- **窗口标题匹配 enhances 进程名匹配:** 两者都是"当前状态"的维度，可以共享同一评估框架，但实现独立。
- **UserVar 自动 key table 激活 enhances 现有 key tables:** 用户目前必须手动绑定 `activate_key_table:<name>` 到某个按键；条件性自动激活可让 key table 在后台响应应用状态自动切换。

## MVP Definition

### Launch With (v1)

最小可验证产品——验证概念所需的最小集合。

- [ ] 基于进程名的条件 keybind 语法 — 覆盖最核心的 vim/shell 用例，且进程名是静态的（不频繁变化），实现相对安全
- [ ] 精确匹配支持 — 进程名精确比较（`process = vim`）；正则留给 v1.x
- [ ] 条件 keybind 优先于无条件 keybind — 基础的优先级语义，缺少此则功能不实用
- [ ] 向后兼容保证 — 不破坏任何现有 keybind 配置；无条件 keybind 行为不变

### Add After Validation (v1.x)

核心功能可用后添加的功能。

- [ ] 窗口标题条件匹配 — 补充进程名无法覆盖的场景（tmux、SSH 内部应用）；触发条件：v1 发布后有用户反馈 tmux 场景不可用
- [ ] 进程名 glob/正则模式匹配 — `nvim*` 匹配 neovim 变体；触发条件：用户反馈精确匹配不够灵活
- [ ] UserVar 条件匹配 — 精细化控制；触发条件：有用户希望通过 shell integration 脚本控制条件
- [ ] OSC 1337 SetUserVar 实现 — UserVar 条件的前提；需在 v1.x 完成

### Future Consideration (v2+)

推迟到产品市场契合验证后的功能。

- [ ] 自动 key table 激活（基于条件） — 强大但实现复杂，需要状态机管理；在 v1 基础上收集用户需求后再设计
- [ ] 配置文件预定义 UserVar 初始值 — 锦上添花功能，先看 OSC 1337 SetUserVar 的使用率
- [ ] Shell integration prompt 状态感知 — 对 shell integration 子系统有较深耦合，范围大；待评估用户需求

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| 基于进程名的条件匹配（精确） | HIGH | HIGH | P1 |
| 条件 keybind 语法解析 | HIGH | MEDIUM | P1 |
| 条件优先级语义 | HIGH | LOW | P1 |
| 向后兼容保证 | HIGH | LOW | P1 |
| 基于窗口标题的条件匹配 | MEDIUM | MEDIUM | P2 |
| 进程名 glob/正则模式匹配 | MEDIUM | MEDIUM | P2 |
| UserVar 条件匹配 | MEDIUM | HIGH | P2 |
| OSC 1337 SetUserVar 实现 | MEDIUM | MEDIUM | P2 |
| 自动 key table 激活（条件驱动） | HIGH | HIGH | P3 |
| Shell integration 状态感知 | LOW | HIGH | P3 |
| 配置预定义 UserVar | LOW | LOW | P3 |

**Priority key:**
- P1: 发布必须有
- P2: 应该有，尽快添加
- P3: 锦上添花，未来考虑

## Competitor Feature Analysis

| Feature | Kitty | WezTerm | iTerm2 | Alacritty | Our Approach |
|---------|-------|---------|--------|-----------|--------------|
| 条件性 keybind（进程名） | 无原生支持；需要 kittens 脚本或 watcher | 支持：`get_foreground_process_name()` + Lua 事件 | 无原生支持；通过 Profile 切换模拟（手动/OSC 1337 自动） | 无 | 原生配置语法，无需脚本 |
| 条件性 keybind（UserVar） | 无 | 支持：`get_user_vars()` + Lua 事件 | 原创：OSC 1337 SetUserVar → Profile 自动切换 | 无 | 参考 iTerm2 UserVar 机制，通过 OSC 1337 SetUserVar 实现 |
| 条件性 keybind（窗口标题） | 无原生支持 | 支持：`get_title()` + Lua 条件 | Profile 可基于 badge/title 自动切换 | 无 | 通过现有 Surface.title 字段实现 |
| 配置语法 | 基于文本 kitty.conf | Lua 脚本（灵活但复杂） | GUI + JSON Profile | TOML | Ghostty 风格 key=value，一致性好 |
| Modal key tables | 无 | 支持：key_tables + 堆栈 | 无 | 无 | 已有实现（Ghostty 1.3.0+）；条件性快捷键可与之协同 |
| Shell integration 感知 | 支持（prompt 检测） | 支持（通过 shell_integration 自定义） | 支持（丰富的 shell integration） | 无 | Ghostty 已有 shell_integration.zig；可扩展 |

### 关键洞察

1. **WezTerm 是最接近的竞品：** 通过 Lua 脚本 + `get_foreground_process_name()` 可以实现条件 keybind，但需要写 Lua 代码，门槛高。Ghostty 的机会是提供原生配置语法，零脚本。

2. **Kitty 没有此功能：** `when_focus_on` 不是 Kitty 的官方特性（文档中未找到），可能是某个早期讨论的功能名。PROJECT.md 提到类似 Kitty 的 `when_focus_on`，但实际上 Kitty 并未原生实现程序感知 keybind。Ghostty 有机会成为**首个原生支持此功能的主流终端**。

3. **iTerm2 通过 Profile 切换模拟条件 keybind：** iTerm2 让用户创建多个 Profile，每个有不同 keybind，再通过 OSC 1337 SetProfile 或 SetUserVar 自动切换。这是变通方案，不是优雅设计。Ghostty 应该提供更直接的语法。

4. **Alacritty 明确不支持：** Alacritty 设计哲学是"极简"，不会添加此功能。这是 Ghostty 的差异化机会。

5. **OSC 1337 SetUserVar 是生态系统标准：** iTerm2 发明了它，fish shell、neovim 等均有 UserVar 集成。Ghostty 虽然已解析了 `SetUserVar` OSC 序列（`iterm2.zig` 中有 enum 值），但标记为 "unimplemented"。实现它是连接整个 shell integration 生态的关键。

## Sources

- [Ghostty src/config/Config.zig](https://github.com/ghostty-org/ghostty) — keybind 文档（HIGH confidence，源码直接阅读）
- [Ghostty src/input/Binding.zig](https://github.com/ghostty-org/ghostty) — 绑定解析和标志（HIGH confidence）
- [Ghostty src/config/conditional.zig](https://github.com/ghostty-org/ghostty) — 现有条件系统（theme/os）（HIGH confidence）
- [Ghostty src/terminal/osc/parsers/iterm2.zig](https://github.com/ghostty-org/ghostty) — OSC 1337 解析，包含 SetUserVar（HIGH confidence）
- [WezTerm Pane API 文档](https://wezterm.org/config/lua/pane/) — get_foreground_process_name, get_user_vars（MEDIUM confidence，WebFetch 摘要）
- [WezTerm Key Tables 文档](https://wezterm.org/config/key-tables.html) — 堆栈式 key table 设计（MEDIUM confidence，WebFetch 摘要）
- [Kitty Shell Integration 文档](https://sw.kovidgoyal.net/kitty/shell-integration/) — 无原生程序感知 keybind（MEDIUM confidence，WebFetch 摘要）
- [Kitty Actions 文档](https://sw.kovidgoyal.net/kitty/actions/) — 无 when_focus_on（MEDIUM confidence，WebFetch 摘要）
- [iTerm2 Profile Keys 文档](https://iterm2.com/documentation-preferences-profiles-keys.html) — Profile-based 条件 keybind（MEDIUM confidence，WebSearch）

---
*Feature research for: Ghostty 条件性快捷键配置*
*Researched: 2026-03-18*
