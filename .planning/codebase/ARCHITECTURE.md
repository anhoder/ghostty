# 架构

**分析日期:** 2026-03-18

## 概述

Ghostty 是一个用 Zig 编写的跨平台终端模拟器，采用分层架构设计。核心终端模拟逻辑与平台特定的 UI 实现分离，通过 `libghostty` 和 `libghostty-vt` 库实现代码复用。架构支持多种渲染后端（Metal、OpenGL）和多种应用运行时（macOS SwiftUI、GTK、嵌入式）。

**核心特点:**
- 终端模拟核心与 UI 层解耦
- 多渲染器架构（Metal、OpenGL、WebGL）
- 平台原生 UI（macOS 使用 SwiftUI，Linux 使用 GTK）
- 可嵌入的 C API 库

## 主要组件

### 终端模拟层 (Terminal Emulation)

**`src/terminal/`** - 核心终端模拟引擎
- `Terminal.zig` - 主终端结构，管理字符网格和滚动缓冲区
- `Parser.zig` - VT 序列解析器
- `Screen.zig` / `ScreenSet.zig` - 屏幕管理（主屏幕/备用屏幕）
- `Page.zig` / `PageList.zig` - 页面和滚动缓冲区管理
- `osc/` - OSC（操作系统命令）序列处理
- `csi.zig` - CSI（控制序列引入）命令处理
- `sgr.zig` - SGR（选择图形再现）属性处理
- `ansi.zig` - ANSI 转义序列处理

**职责:**
- 解析和执行 VT 序列
- 维护终端状态（光标位置、属性、模式）
- 管理字符网格和滚动历史
- 处理字符集和编码

### 渲染层 (Rendering)

**`src/renderer/`** - 多后端渲染系统
- `generic.zig` - 通用渲染逻辑和接口
- `Metal.zig` + `metal/` - macOS Metal 渲染器
- `OpenGL.zig` + `opengl/` - Linux OpenGL 渲染器
- `WebGL.zig` - WebAssembly WebGL 渲染器
- `Thread.zig` - 渲染线程管理
- `cell.zig` / `row.zig` - 单元格和行渲染
- `image.zig` - 图像协议支持（Kitty、iTerm2）
- `shaders/` - 着色器代码

**职责:**
- 将终端网格渲染到屏幕
- 管理 GPU 资源和纹理
- 处理字体光栅化和文本整形
- 支持图像内联显示

### 字体系统 (Font System)

**`src/font/`** - 字体发现、加载和渲染
- `Collection.zig` - 字体集合管理
- `face.zig` / `DeferredFace.zig` - 字体面加载
- `discovery.zig` - 平台特定字体发现
- `Atlas.zig` - 字形纹理图集
- `CodepointResolver.zig` - 字符到字体映射
- `shaper/` - 文本整形（HarfBuzz 集成）
- `Metrics.zig` - 字体度量计算

**职责:**
- 发现和加载系统字体
- 字形光栅化和缓存
- 文本整形（连字、复杂脚本）
- 管理字体回退链

### 应用运行时层 (Application Runtime)

**`src/apprt/`** - 平台抽象层
- `runtime.zig` - 运行时接口定义
- `gtk.zig` + `gtk/` - GTK 实现（Linux）
- `embedded.zig` - 嵌入式运行时（macOS SwiftUI 使用）
- `action.zig` - 应用动作系统
- `surface.zig` - Surface 接口定义
- `ipc.zig` - 进程间通信

**macOS 原生实现:**
- `macos/Sources/` - SwiftUI 应用代码
- `macos/Sources/Ghostty/` - 主应用逻辑
- `macos/Sources/Features/` - 功能模块
- `macos/Sources/Helpers/` - 辅助工具

**职责:**
- 窗口和事件管理
- 平台特定 UI 元素
- 键盘和鼠标输入处理
- 菜单和快捷键

### Surface 层

**`src/Surface.zig`** - 终端 Surface 抽象
- 表示单个终端"小部件"
- 拥有 PTY 会话
- 协调终端、渲染器和输入
- 处理终端事件和消息

**职责:**
- 连接终端模拟和渲染
- 管理 PTY 生命周期
- 处理键盘/鼠标事件
- 协调配置更新

### 应用层

**`src/App.zig`** - 主应用结构
- 管理多个 Surface（窗口、标签、分割）
- 全局应用状态
- Surface 生命周期管理
- 焦点和事件路由

### 配置系统

**`src/config/`** - 配置管理
- `Config.zig` - 主配置结构
- `file_load.zig` - 配置文件加载
- `theme.zig` - 主题支持
- `key.zig` - 键绑定配置
- `CApi.zig` - C API 配置接口

### PTY 和 I/O

**`src/pty.zig`** - 伪终端管理
**`src/termio/`** - 终端 I/O 处理
- PTY 创建和管理
- 子进程生命周期
- I/O 线程管理
- Shell 集成

### CLI 工具

**`src/cli/`** - 命令行工具
- `action.zig` - 执行应用动作
- `new_window.zig` - 创建新窗口
- `list_fonts.zig` / `list_themes.zig` - 列表命令
- `edit_config.zig` - 配置编辑

### 库导出

**`src/lib_vt.zig`** - libghostty-vt 公共 API
- 导出终端模拟核心
- C 兼容接口
- 支持 Zig 和 C 消费者

**`src/main_c.zig`** - libghostty C API
- 完整终端模拟器库
- 用于嵌入到其他应用

## 组件关系

### 数据流（从输入到渲染）

```
用户输入 (键盘/鼠标)
    ↓
应用运行时 (apprt)
    ↓
Surface (事件处理)
    ↓
Terminal (状态更新) ← PTY (子进程输出)
    ↓
Renderer (GPU 渲染)
    ↓
屏幕显示
```

### 依赖方向

```
App
 ├─→ Surface (多个)
 │    ├─→ Terminal (终端状态)
 │    ├─→ Renderer (渲染)
 │    │    └─→ Font (字体系统)
 │    ├─→ PTY (伪终端)
 │    └─→ Config (配置)
 └─→ AppRuntime (平台抽象)
      ├─→ GTK (Linux)
      └─→ SwiftUI (macOS)
```

### 层次结构

1. **平台层** - macOS/GTK 原生 UI
2. **应用层** - App.zig（窗口管理）
3. **Surface 层** - Surface.zig（终端实例）
4. **核心层** - Terminal.zig（终端模拟）
5. **渲染层** - Renderer（GPU 渲染）
6. **系统层** - PTY、Font、Config

## 目录结构

```
ghostty/
├── src/                    # Zig 源代码
│   ├── terminal/          # 终端模拟核心
│   ├── renderer/          # 渲染后端
│   ├── font/              # 字体系统
│   ├── apprt/             # 应用运行时抽象
│   ├── config/            # 配置系统
│   ├── cli/               # CLI 工具
│   ├── input/             # 输入处理
│   ├── os/                # OS 特定功能
│   ├── App.zig            # 主应用
│   ├── Surface.zig        # 终端 Surface
│   ├── lib_vt.zig         # libghostty-vt API
│   └── main_*.zig         # 各种入口点
├── macos/                 # macOS SwiftUI 应用
│   └── Sources/
│       ├── Ghostty/       # 主应用代码
│       ├── Features/      # 功能模块
│       └── Helpers/       # 辅助工具
├── pkg/                   # 第三方包
├── include/               # C 头文件
├── example/               # 示例代码
├── test/                  # 测试
└── build.zig              # 构建配置
```

## 数据流

### 输入处理流程

1. **平台事件** → AppRuntime 捕获键盘/鼠标事件
2. **事件路由** → App 将事件路由到焦点 Surface
3. **输入处理** → Surface 处理输入，生成序列
4. **PTY 写入** → 序列写入 PTY（发送到 shell）
5. **终端更新** → 如果需要本地回显，更新 Terminal 状态

### 输出渲染流程

1. **PTY 读取** → I/O 线程从 PTY 读取数据
2. **序列解析** → Terminal.Parser 解析 VT 序列
3. **状态更新** → Terminal 更新字符网格和属性
4. **渲染请求** → Surface 通知 Renderer 需要重绘
5. **GPU 渲染** → Renderer 使用 Metal/OpenGL 渲染
6. **字形查找** → Font 系统提供字形纹理
7. **屏幕显示** → 帧缓冲区呈现到窗口

### 配置更新流程

1. **配置加载** → Config 从文件加载设置
2. **配置分发** → App 将配置传播到所有 Surface
3. **组件更新** → Surface 更新 Terminal、Renderer、Font
4. **重新渲染** → 触发完整重绘以应用新设置

## 关键抽象

### Terminal

**目的:** 表示终端模拟器的核心状态
**位置:** `src/terminal/Terminal.zig`
**模式:** 状态机 + 命令模式

终端维护：
- 字符网格（当前屏幕）
- 滚动缓冲区（历史）
- 光标状态和属性
- 模式标志（应用光标键、括号粘贴等）
- 屏幕集（主/备用）

### Surface

**目的:** 表示单个终端实例（窗口/标签/分割）
**位置:** `src/Surface.zig`
**模式:** 协调器/门面

Surface 协调：
- Terminal（状态）
- Renderer（显示）
- PTY（I/O）
- Config（设置）
- Input（事件）

### Renderer

**目的:** 抽象 GPU 渲染实现
**位置:** `src/renderer/generic.zig`
**模式:** 策略模式

实现：
- Metal（macOS）
- OpenGL（Linux）
- WebGL（WebAssembly）

### AppRuntime

**目的:** 抽象平台特定的应用功能
**位置:** `src/apprt/runtime.zig`
**模式:** 适配器模式

实现：
- GTK（Linux）
- Embedded（macOS SwiftUI 使用）
- None（无头模式）

## 入口点

### Ghostty 应用

**位置:** `src/main_ghostty.zig`
**触发:** 用户启动 Ghostty
**职责:**
- 初始化应用
- 加载配置
- 创建初始窗口
- 启动主事件循环

### libghostty-vt

**位置:** `src/lib_vt.zig`
**触发:** C/Zig 代码导入库
**职责:**
- 导出终端模拟 API
- 提供 VT 解析器
- 提供终端状态管理

### libghostty (C API)

**位置:** `src/main_c.zig`
**触发:** C 代码链接库
**职责:**
- 完整终端模拟器 C API
- 用于嵌入到其他应用（如 macOS 应用）

### CLI 工具

**位置:** `src/cli.zig`
**触发:** `ghostty +<command>` 命令
**职责:**
- 执行实用命令
- 与运行中的实例通信（IPC）
- 配置管理

## 错误处理

**策略:** 分层错误处理

**终端层:**
- 解析错误 → 忽略无效序列，记录警告
- 状态错误 → 回退到安全默认值

**渲染层:**
- GPU 错误 → 回退到软件渲染或降级功能
- 字体错误 → 使用回退字体

**应用层:**
- 配置错误 → 使用默认值，显示警告
- PTY 错误 → 显示错误消息，关闭 Surface
- 崩溃 → 生成崩溃报告到 `~/.local/state/ghostty/crash`

**日志:**
- 使用 Zig 标准日志框架
- 作用域日志（`.terminal`, `.renderer`, `.font` 等）
- 可配置日志级别

## 跨领域关注点

**日志:**
- Zig `std.log` 框架
- 作用域日志记录器
- 输出到 stderr 或系统日志

**验证:**
- 配置验证在加载时进行
- 输入验证在 Surface 层
- VT 序列验证在 Parser 中

**认证:**
- 不适用（本地应用）

**国际化:**
- `src/os/i18n.zig` - 国际化支持
- `po/` - 翻译文件
- GTK 使用 gettext

**性能优化:**
- 专用 I/O 线程（低抖动）
- 专用渲染线程
- 字形纹理图集缓存
- SIMD 优化（`src/simd/`）
- 增量渲染（仅重绘脏区域）

**并发:**
- 主线程：UI 和事件处理
- I/O 线程：PTY 读写
- 渲染线程：GPU 渲染
- 使用消息传递（Mailbox）进行线程通信

---

*架构分析: 2026-03-18*
