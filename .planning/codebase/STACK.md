# 技术栈

**分析日期:** 2026-03-18

## 语言

**主要语言:**
- Zig 0.15.2+ - 核心应用程序和库实现
- 版本要求: 最低 0.15.2
- 项目版本: 1.3.2-dev

**辅助语言:**
- C - 供应商库集成 (GLAD, STB, AFL++)
- C++ - SIMD 优化模块 (`src/simd/*.cpp`)
- Objective-C - macOS 平台特定代码 (`macos/Sources/Helpers/*.m`)

## 运行时

**环境:**
- Zig 0.15.2 或更高版本

**包管理器:**
- Zig 构建系统 (build.zig)
- 依赖通过 `build.zig.zon.txt` 管理
- 锁文件: 使用 Zig 包管理器

## 框架

**核心:**
- Zig 标准库 - 基础功能
- libxev - 事件循环库
- vaxis - TUI 框架

**GUI 运行时:**
- GTK4 - Linux GUI 后端
- gtk4-layer-shell 1.1.0 - Wayland 层 shell 支持
- macOS 原生 (Cocoa/AppKit) - macOS GUI 后端
- Wayland - Linux Wayland 协议支持
- X11 - Linux X11 支持

**渲染:**
- Metal - macOS 图形 API (`src/renderer/Metal.zig`)
- OpenGL - 跨平台图形 API (`src/renderer/OpenGL.zig`)
- WebGL - Web 平台渲染 (`src/renderer/WebGL.zig`)

**测试:**
- Zig 内置测试框架 - 单元测试
- Valgrind - 内存泄漏检测
- 测试命令: `zig build test`, `zig build test-valgrind`

**构建/开发:**
- Zig 构建系统 - 主构建工具
- Xcode - macOS 应用打包 (`macos/project.pbxproj`)
- Make - 辅助构建任务 (`Makefile`)

## 关键依赖

**图形和渲染:**
- freetype - 字体光栅化
- harfbuzz 11.0.0 - 文本整形
- fontconfig 2.14.2 - 字体配置
- libpng - PNG 图像处理
- glslang - GLSL 着色器编译
- spirv_cross - SPIR-V 交叉编译
- GLAD - OpenGL 加载器 (`vendor/glad`)

**字体:**
- JetBrainsMono 2.304 - 默认等宽字体
- NerdFontsSymbolsOnly 3.4.0 - 图标字体

**UI 和窗口:**
- gobject - GObject 类型系统
- wayland-protocols - Wayland 协议定义
- plasma_wayland_protocols - KDE Plasma Wayland 扩展

**性能优化:**
- highway - SIMD 抽象库 (`pkg/highway`)
- simdutf - SIMD UTF 验证 (`pkg/simdutf`)
- wuffs - 安全的图像解码

**文本处理:**
- oniguruma - 正则表达式引擎
- utfcpp - UTF-8/16/32 处理
- libxml2 2.11.5 - XML 解析

**图像和图形:**
- zigimg - Zig 图像处理库
- z2d 0.10.0 - 2D 图形库
- pixels - 像素操作库
- Dear ImGui 1.92.5-docking - 调试 UI (`pkg/dcimgui`)

**崩溃报告:**
- sentry - 错误跟踪和崩溃报告
- breakpad - 崩溃转储生成

**其他:**
- zlib - 压缩库
- gettext 0.24 - 国际化 (i18n)
- ghostty-themes - 主题集合
- zf - 模糊查找器
- uucode 0.2.0 - UU 编码/解码

**Zig 特定库:**
- zig_objc - Objective-C 互操作
- zig_js - JavaScript 互操作
- zig_wayland - Wayland 协议绑定

## 配置

**环境:**
- 通过 Zig 构建系统配置
- 构建选项在 `src/build/Config.zig` 中定义
- 支持多种编译时接口选择

**构建:**
- `build.zig` - 主构建配置
- `build.zig.zon.txt` - 依赖声明
- `src/build/*.zig` - 模块化构建脚本
- 支持的构建目标: macOS, Linux (GTK/Wayland/X11), Web (WASM)

**构建选项:**
- `-Doptimize` - 优化模式
- `-Dtarget` - 目标平台
- `-Dapp_runtime` - 应用运行时 (none/gtk/macos/browser/embedded)
- `-Drenderer` - 渲染后端 (opengl/metal/webgl)
- `-Dfont_backend` - 字体后端 (freetype)
- `-Dx11` - 启用 X11 支持
- `-Dwayland` - 启用 Wayland 支持
- `-Dsentry` - 启用 Sentry 崩溃报告
- `-Dsimd` - 启用 SIMD 优化
- `-Di18n` - 启用国际化

## 平台要求

**开发:**
- Zig 0.15.2 或更高版本
- macOS: Xcode (用于 macOS 应用构建)
- Linux: GTK4 开发库 (用于 GTK 后端)
- OpenGL 或 Metal 支持的图形驱动

**生产:**
- macOS: 原生 macOS 应用包
- Linux: GTK4 运行时, Wayland/X11
- 支持 Flatpak 和 Snap 打包
- Web: WebAssembly 目标

## 供应商库

**vendor/:**
- `glad/` - OpenGL 加载器
- `nerd-fonts/` - Nerd Fonts 符号

**pkg/:**
- 24+ 个打包的依赖项
- 包括字体、图形、UI 和系统库
- 每个包都有自己的构建集成

---

*技术栈分析: 2026-03-18*
