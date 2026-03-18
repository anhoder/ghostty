# Codebase Structure

**分析日期:** 2026-03-18

## 目录布局

```
ghostty/
├── src/                    # Zig 源代码（核心实现）
├── macos/                  # macOS SwiftUI 应用
├── pkg/                    # 第三方依赖包
├── include/                # C 头文件（libghostty API）
├── example/                # 示例代码和演示
├── test/                   # 测试和模糊测试
├── po/                     # 翻译文件（国际化）
├── dist/                   # 分发脚本和资源
├── nix/                    # Nix 构建配置
├── flatpak/                # Flatpak 打包配置
├── snap/                   # Snap 打包配置
├── images/                 # 图标和图像资源
├── vendor/                 # 供应商代码
├── build.zig               # Zig 构建配置
└── build.zig.zon           # Zig 依赖清单
```

## 目录用途

### `src/` - 核心源代码

**用途:** Ghostty 的主要 Zig 实现
**包含:** 终端模拟、渲染、字体、配置、应用逻辑
**关键文件:**
- `main_ghostty.zig` - Ghostty 应用入口
- `main_c.zig` - libghostty C API 入口
- `lib_vt.zig` - libghostty-vt 公共 API
- `App.zig` - 主应用结构
- `Surface.zig` - 终端 Surface 实现
- `Command.zig` - 命令处理

**子目录:**
- `terminal/` - 终端模拟核心（VT 解析、状态管理）
- `renderer/` - 渲染后端（Metal、OpenGL、WebGL）
- `font/` - 字体系统（发现、加载、整形）
- `apprt/` - 应用运行时抽象（GTK、嵌入式）
- `config/` - 配置系统
- `cli/` - CLI 工具实现
- `input/` - 输入处理
- `os/` - OS 特定功能
- `build/` - 构建系统代码
- `datastruct/` - 数据结构
- `unicode/` - Unicode 处理
- `crash/` - 崩溃报告
- `inspector/` - 调试检查器
- `benchmark/` - 性能基准测试

### `macos/` - macOS 原生应用

**用途:** SwiftUI 原生 macOS 应用
**包含:** Swift 代码、Xcode 项目、资源
**关键目录:**
- `Sources/Ghostty/` - 主应用逻辑
- `Sources/Features/` - 功能模块（设置、主题等）
- `Sources/Helpers/` - 辅助工具和扩展
- `Sources/App/` - 应用入口
- `Assets.xcassets/` - 应用资源
- `Ghostty.xcodeproj/` - Xcode 项目

### `pkg/` - 第三方包

**用途:** 外部依赖和绑定
**包含:** C 库包装器、供应商代码
**示例:**
- `libxml2/` - XML 解析库
- `macos/` - macOS 特定绑定

### `include/` - C 头文件

**用途:** libghostty 公共 C API
**包含:** C 头文件供外部使用
**关键文件:**
- `ghostty.h` - 主 C API 头文件

### `example/` - 示例代码

**用途:** 演示 libghostty 使用
**包含:** C 和 Zig 示例程序
**示例:**
- `c-vt/` - C VT 解析器示例
- `zig-vt/` - Zig VT 解析器示例
- `zig-formatter/` - Zig 格式化器示例
- `wasm-*/` - WebAssembly 示例

### `test/` - 测试

**用途:** 测试套件
**包含:** 单元测试、集成测试、模糊测试
**子目录:**
- `fuzz-libghostty/` - libghostty 模糊测试

### `po/` - 翻译文件

**用途:** 国际化和本地化
**包含:** .po 翻译文件
**格式:** GNU gettext

### `dist/` - 分发资源

**用途:** 打包和分发脚本
**包含:** 平台特定的分发配置
**子目录:**
- `linux/` - Linux 分发文件
- `macos/` - macOS 分发文件
- `windows/` - Windows 分发文件
- `doxygen/` - 文档生成配置

### `nix/`, `flatpak/`, `snap/` - 打包配置

**用途:** 各种 Linux 打包格式
**包含:** 构建配置和元数据

## 关键文件位置

### 入口点

**Ghostty 应用:**
- `src/main_ghostty.zig` - 主应用入口
- `src/main.zig` - 通用入口点路由器
- `macos/Sources/App/` - macOS SwiftUI 入口

**库:**
- `src/lib_vt.zig` - libghostty-vt API
- `src/main_c.zig` - libghostty C API
- `include/ghostty.h` - C 头文件

**CLI 工具:**
- `src/cli.zig` - CLI 入口点
- `src/cli/*.zig` - 各个 CLI 命令

### 配置

**构建配置:**
- `build.zig` - Zig 构建脚本
- `build.zig.zon` - Zig 依赖清单
- `src/build_config.zig` - 构建配置选项

**应用配置:**
- `src/config/Config.zig` - 主配置结构
- `src/config/file_load.zig` - 配置文件加载

**平台配置:**
- `.editorconfig` - 编辑器配置
- `.clang-format` - C/C++ 格式化
- `typos.toml` - 拼写检查配置

### 核心逻辑

**终端模拟:**
- `src/terminal/Terminal.zig` - 主终端结构
- `src/terminal/Parser.zig` - VT 序列解析器
- `src/terminal/Screen.zig` - 屏幕管理
- `src/terminal/Page.zig` - 页面管理

**渲染:**
- `src/renderer/generic.zig` - 通用渲染器
- `src/renderer/Metal.zig` - Metal 渲染器
- `src/renderer/OpenGL.zig` - OpenGL 渲染器
- `src/renderer/Thread.zig` - 渲染线程

**应用:**
- `src/App.zig` - 应用管理
- `src/Surface.zig` - Surface 管理
- `src/Command.zig` - 命令处理

### 测试

**单元测试:**
- 与源文件同目录（Zig 约定）
- 使用 `test` 块

**模糊测试:**
- `test/fuzz-libghostty/` - 模糊测试套件

## 命名约定

### 文件

**Zig 文件:**
- `PascalCase.zig` - 主要类型/结构（如 `Terminal.zig`, `Surface.zig`）
- `snake_case.zig` - 模块/功能（如 `lib_vt.zig`, `main_ghostty.zig`）
- `main_*.zig` - 入口点文件

**Swift 文件:**
- `PascalCase.swift` - 类型和视图
- 遵循 Swift 标准约定

**C 文件:**
- `snake_case.c` / `snake_case.h` - C 源文件和头文件

### 目录

**小写加连字符或下划线:**
- `terminal/` - 功能模块
- `shell-integration/` - 带连字符的名称
- 通常使用小写

### 函数

**Zig:**
- `camelCase` - 公共函数
- `snake_case` - 内部/私有函数（约定）

**Swift:**
- `camelCase` - 标准 Swift 约定

### 变量

**Zig:**
- `snake_case` - 局部变量
- `SCREAMING_SNAKE_CASE` - 常量

**Swift:**
- `camelCase` - 标准 Swift 约定

### 类型

**Zig:**
- `PascalCase` - 结构体、枚举、联合
- 示例: `Terminal`, `Surface`, `Renderer`

**Swift:**
- `PascalCase` - 类、结构体、枚举、协议

## 添加新代码的位置

### 新功能

**终端功能（VT 序列、模式）:**
- 主要代码: `src/terminal/`
- 解析器更新: `src/terminal/Parser.zig`
- 命令处理: `src/terminal/Terminal.zig` 或相关文件
- 测试: 与实现文件同目录的 `test` 块

**渲染功能:**
- 主要代码: `src/renderer/`
- 通用逻辑: `src/renderer/generic.zig`
- 后端特定: `src/renderer/Metal.zig` 或 `OpenGL.zig`
- 着色器: `src/renderer/shaders/`

**UI 功能:**
- macOS: `macos/Sources/Features/` 或 `macos/Sources/Ghostty/`
- GTK: `src/apprt/gtk/`
- 通用: `src/apprt/`

**配置选项:**
- 定义: `src/config/Config.zig`
- 解析: `src/config/file_load.zig`
- 验证: `src/config/Config.zig` 中的验证逻辑

### 新组件/模块

**核心模块:**
- 实现: `src/<module_name>/`
- 入口: `src/<module_name>.zig` 或 `src/<module_name>/main.zig`
- 示例: `src/font/`, `src/terminal/`

**平台特定:**
- macOS: `macos/Sources/<FeatureName>/`
- GTK: `src/apprt/gtk/`
- OS 通用: `src/os/`

### 工具函数

**通用工具:**
- 数据结构: `src/datastruct/`
- Unicode: `src/unicode/`
- 数学: `src/math.zig`
- 快速内存操作: `src/fastmem.zig`

**平台特定工具:**
- OS 工具: `src/os/`
- macOS 辅助: `macos/Sources/Helpers/`

### CLI 命令

**新命令:**
- 实现: `src/cli/<command_name>.zig`
- 注册: `src/cli.zig` 中添加命令
- 示例: `src/cli/list_fonts.zig`, `src/cli/new_window.zig`

### 测试

**单元测试:**
- 位置: 与被测试代码同文件
- 格式: `test "description" { ... }`

**集成测试:**
- 位置: `test/` 目录
- 独立测试程序

**模糊测试:**
- 位置: `test/fuzz-libghostty/src/`
- 命名: `fuzz_<target>.zig`

### 示例

**新示例:**
- C 示例: `example/c-<name>/`
- Zig 示例: `example/zig-<name>/`
- WASM 示例: `example/wasm-<name>/`
- 包含 `build.zig` 和源代码

## 特殊目录

### `.planning/` - 规划文档

**用途:** GSD 命令生成的规划文档
**生成:** 自动生成
**提交:** 是

### `.claude/` - Claude AI 配置

**用途:** Claude AI 助手配置
**生成:** 手动创建
**提交:** 否（用户特定）

### `.agents/` - AI 代理命令

**用途:** AI 辅助开发的预定义命令
**生成:** 手动创建
**提交:** 是

### `zig-out/` - 构建输出

**用途:** Zig 构建系统输出
**生成:** 构建时自动生成
**提交:** 否

### `zig-cache/` - 构建缓存

**用途:** Zig 构建缓存
**生成:** 构建时自动生成
**提交:** 否

### `.git/` - Git 仓库

**用途:** Git 版本控制
**生成:** Git 自动管理
**提交:** 否

## 构建产物位置

**Zig 构建输出:**
- `zig-out/bin/` - 可执行文件
- `zig-out/lib/` - 库文件
- `zig-out/share/` - 共享资源（man 页面、主题等）

**macOS 应用:**
- `zig-out/bin/Ghostty.app` - macOS 应用包

**文档:**
- `zig-out/share/man/` - Man 页面
- `zig-out/share/doc/` - 文档

## 资源文件位置

**主题:**
- 源: 内嵌在代码中或外部文件
- 安装: `zig-out/share/ghostty/themes/`

**Shell 集成:**
- 源: `src/shell-integration/`
- 安装: `zig-out/share/ghostty/shell-integration/`

**Terminfo:**
- 源: `src/terminfo/`
- 安装: `zig-out/share/terminfo/`

**图标:**
- 源: `images/`
- macOS: `macos/Assets.xcassets/`
- Linux: 安装到标准位置

## 导入路径模式

**Zig 导入:**
```zig
// 标准库
const std = @import("std");

// 构建选项
const build_options = @import("build_options");

// 相对导入（同目录或子目录）
const Terminal = @import("Terminal.zig");
const parser = @import("parser.zig");

// 模块导入（从 src/ 根）
const terminal = @import("terminal/main.zig");
const renderer = @import("renderer.zig");

// 包导入
const oni = @import("oniguruma");
```

**Swift 导入:**
```swift
// 框架
import SwiftUI
import Combine

// 本地模块（自动）
// Swift 包管理器处理
```

## 文档位置

**开发文档:**
- `README.md` - 项目概述
- `HACKING.md` - 开发指南
- `CONTRIBUTING.md` - 贡献指南
- `AGENTS.md` - AI 代理指南

**API 文档:**
- Zig: 代码中的文档注释（`///`）
- C API: `include/ghostty.h` 中的注释
- 生成: Doxygen（配置在 `Doxyfile`）

**用户文档:**
- 在线: https://ghostty.org/docs
- Man 页面: 从代码生成

---

*结构分析: 2026-03-18*
