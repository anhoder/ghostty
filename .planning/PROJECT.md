# Ghostty 条件性快捷键配置

## What This Is

为 Ghostty 终端模拟器添加条件性快捷键配置功能，允许用户根据当前运行的程序、窗口标题或用户变量动态切换快捷键绑定。类似 Kitty 的 `when_focus_on` 功能，但使用 Ghostty 风格的配置语法。

## Core Value

用户可以在不同程序（如 vim、shell）中使用不同的快捷键绑定，无需手动切换配置文件或重启终端。

## Requirements

### Validated

- ✓ Ghostty 支持基础快捷键配置 — existing
- ✓ 终端可以检测当前运行的进程 — existing
- ✓ 配置系统支持键值对解析 — existing

### Active

- [ ] 支持基于进程名称的条件匹配（精确匹配和模式匹配）
- [ ] 支持基于窗口标题的条件匹配（精确匹配和模式匹配）
- [ ] 支持基于用户变量（UserVar）的条件匹配
- [ ] 用户变量可通过转义序列设置（如 OSC 1337）
- [ ] 用户变量可在配置文件中预定义
- [ ] 条件性快捷键优先于无条件快捷键
- [ ] 后定义的快捷键覆盖先定义的快捷键
- [ ] 使用 Ghostty 风格的配置语法

### Out of Scope

- 其他配置项的条件化（仅实现快捷键） — 保持功能聚焦
- 完全兼容 Kitty 配置语法 — 使用 Ghostty 原生风格
- 多条件组合（AND/OR 逻辑） — v1 保持简单

## Context

**现有架构:**
- Ghostty 使用 Zig 编写，分层架构
- 配置系统位于 `src/config/`
- 快捷键处理在应用运行时层 `src/apprt/`
- 进程信息可通过 PTY 会话获取

**技术环境:**
- Zig 0.15.2+
- 跨平台支持（macOS、Linux）
- 配置文件格式：键值对

**用户场景:**
用户在 vim 中编辑时需要一套快捷键，在 shell 中需要另一套。例如：
- vim 中：Cmd+W 关闭 buffer
- shell 中：Cmd+W 关闭标签页

## Constraints

- **技术栈**: 必须使用 Zig 实现，遵循现有代码模式
- **兼容性**: 不能破坏现有快捷键配置的向后兼容性
- **性能**: 条件检查不能显著影响按键响应延迟
- **平台**: 必须在 macOS 和 Linux 上都能工作

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| 仅支持快捷键条件化 | 保持 v1 范围可控，快捷键是最常见需求 | — Pending |
| Ghostty 风格语法 | 保持配置一致性，避免混淆 | — Pending |
| 条件优先于无条件 | 符合用户直觉，特殊情况覆盖通用情况 | — Pending |
| 支持精确和模式匹配 | 提供灵活性，满足不同用户需求 | — Pending |

---
*Last updated: 2026-03-18 after initialization*
