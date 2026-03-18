# 入口点

**分析日期:** 2026-03-18

## 主入口

**主程序入口:**
- `src/main.zig` - 根据构建配置选择实际入口点
  - 通过 `build_config.exe_entrypoint` 枚举选择不同的 main 函数
  - 默认入口: `src/main_ghostty.zig`

**Ghostty 应用入口:**
- `src/main_ghostty.zig` - Ghostty 终端应用的主入口点
  - `pub fn main() !MainReturn` - 主函数
  - 初始化全局状态 (`global.zig`)
  - 解析 CLI 参数和动作
  - 如果有 CLI 动作则执行并退出
  - 否则创建 GUI 应用并启动事件循环

**执行流程:**
1. 初始化全局状态 (`state.init()`)
2. 检测并执行 CLI 动作 (如果指定了 `+action`)
3. 创建 `App` 实例 (`App.create()`)
4. 初始化应用运行时 (`apprt.App.init()`)
5. 启动 GUI 事件循环 (`app_runtime.run()`)

## CLI 命令

**CLI 动作系统:**
- 位置: `src/cli/action.zig`
- 调用方式: `ghostty +<action> [flags]`
- 动作检测: `action.detectArgs()` 解析以 `+` 开头的参数

**可用 CLI 动作** (定义在 `src/cli/ghostty.zig`):

| 动作 | 文件 | 用途 |
|------|------|------|
| `+version` | `src/cli/version.zig` | 输出版本信息 |
| `+help` | `src/cli/help.zig` | 显示帮助信息 |
| `+list-fonts` | `src/cli/list_fonts.zig` | 列出可用字体 |
| `+list-keybinds` | `src/cli/list_keybinds.zig` | 列出键绑定 |
| `+list-themes` | `src/cli/list_themes.zig` | 列出可用主题 |
| `+list-colors` | `src/cli/list_colors.zig` | 列出命名 RGB 颜色 |
| `+list-actions` | `src/cli/list_actions.zig` | 列出键绑定动作 |
| `+ssh-cache` | `src/cli/ssh_cache.zig` | 管理 SSH terminfo 缓存 |
| `+edit-config` | `src/cli/edit_config.zig` | 在编辑器中编辑配置文件 |
| `+show-config` | `src/cli/show_config.zig` | 输出当前配置到 stdout |
| `+explain-config` | `src/cli/explain_config.zig` | 解释单个配置选项 |
| `+validate-config` | `src/cli/validate_config.zig` | 验证配置文件 |
| `+show-face` | `src/cli/show_face.zig` | 显示字体加载信息 |
| `+crash-report` | `src/cli/crash_report.zig` | 管理崩溃报告 |
| `+boo` | `src/cli/boo.zig` | 彩蛋命令 |
| `+new-window` | `src/cli/new_window.zig` | 通过 IPC 打开新窗口 |

**特殊参数:**
- `--version` - 等同于 `+version`
- `--help` / `-h` - 等同于 `+help`
- `-e` - 停止解析动作，用于执行命令

## API 端点

**C API (嵌入式接口):**
- 位置: `src/main_c.zig`
- 用途: 将 Ghostty 嵌入到其他应用程序中
- 主要用于 macOS 应用嵌入
- 导出的 API:
  - 配置 API (`config.zig` 的 CApi)
  - 应用运行时 API (`apprt.runtime.CAPI`)
  - 基准测试 API (`benchmark/main.zig` 的 CApi)

**libghostty-vt (VT 库):**
- 位置: `src/lib_vt.zig`
- 用途: 独立的终端仿真库
- 公共 API 包括:
  - `Terminal` - 终端核心
  - `Parser` - VT 序列解析器
  - `Screen` / `ScreenSet` - 屏幕管理
  - `Page` / `PageList` - 页面管理
  - `input` - 输入编码 (键盘、鼠标、粘贴)
  - `formatter` - 格式化输出
  - `color` / `sgr` - 颜色和样式
  - `osc` / `dcs` / `apc` - 控制序列

## 公共接口

**Zig 模块导出:**
- `build.zig` 定义了 `GhosttyZig` 模块
- 为 Zig 消费者提供 libghostty 接口

**构建入口点:**
- `build.zig` - Zig 构建系统入口
  - `pub fn build(b: *std.Build)` - 构建配置
  - 定义构建步骤: `run`, `test`, `lib-vt`, `dist` 等

**其他入口点:**
- `src/main_bench.zig` - 基准测试入口
- `src/main_build_data.zig` - 构建数据生成
- `src/main_wasm.zig` - WebAssembly 入口
- `src/main_gen.zig` - 代码生成工具
- `src/build/mdgen/main_ghostty_1.zig` - man 页面生成 (ghostty.1)
- `src/build/mdgen/main_ghostty_5.zig` - man 页面生成 (ghostty.5)
- `src/build/webgen/main_config.zig` - Web 配置文档生成
- `src/build/webgen/main_actions.zig` - Web 动作文档生成
- `src/build/webgen/main_commands.zig` - Web 命令文档生成

## 执行流程

**GUI 应用启动流程:**

```
main() [src/main_ghostty.zig]
  ↓
state.init() [初始化全局状态]
  ↓
检测 CLI 动作?
  ├─ 是 → action.run() → 退出
  └─ 否 ↓
App.create() [创建应用实例]
  ↓
apprt.App.init() [初始化应用运行时]
  ↓
app_runtime.run() [启动 GUI 事件循环]
```

**CLI 动作执行流程:**

```
main() [src/main_ghostty.zig]
  ↓
state.init() [解析参数，检测动作]
  ↓
state.action.run() [执行动作]
  ↓
Action.runMain() [调用具体动作实现]
  ↓
posix.exit() [退出并返回状态码]
```

**应用运行时层:**
- `src/apprt.zig` - 应用运行时抽象
- 根据平台选择不同实现:
  - macOS: `src/apprt/macos/`
  - GTK: `src/apprt/gtk/`
  - Embedded: `src/apprt/embedded/`

**核心组件初始化:**
1. `App` (`src/App.zig`) - 应用状态管理
2. `Surface` (`src/Surface.zig`) - 终端表面/窗口
3. `Terminal` (`src/terminal/`) - 终端仿真核心
4. `Renderer` (`src/renderer.zig`) - 渲染引擎
5. `Font` (`src/font/`) - 字体管理

**进程启动:**
- `src/Command.zig` - 子进程管理
  - 用于启动 shell 和其他命令
  - 支持 PTY 附加
  - 提供 pre_exec 和 post_fork 钩子

---

*入口点分析: 2026-03-18*
