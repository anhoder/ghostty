# Requirements: Ghostty 条件性快捷键配置

**Defined:** 2026-03-18
**Core Value:** 用户可以根据当前运行的程序、窗口标题或用户变量动态切换快捷键绑定

## v1 Requirements

### 配置语法 (CONF)

- [ ] **CONF-01**: 条件性快捷键使用 Ghostty 风格的配置语法
- [ ] **CONF-02**: 条件性快捷键语法与现有 keybind 语法一致扩展
- [ ] **CONF-03**: 后定义的条件性快捷键覆盖先定义的
- [ ] **CONF-04**: 条件性快捷键优先于无条件快捷键
- [ ] **CONF-05**: 不破坏任何现有快捷键配置的向后兼容性

### 进程名匹配 (PROC)

- [ ] **PROC-01**: 用户可以基于前台进程名称精确匹配配置快捷键
- [ ] **PROC-02**: 用户可以使用 glob 通配符模式匹配进程名称
- [ ] **PROC-03**: 进程名检测在 macOS 上正常工作
- [ ] **PROC-04**: 进程名检测在 Linux 上正常工作
- [ ] **PROC-05**: 按键路径上的进程检测不会引入可感知的延迟

### 窗口标题匹配 (TITL)

- [ ] **TITL-01**: 用户可以基于窗口标题精确匹配配置快捷键
- [ ] **TITL-02**: 用户可以使用 glob 通配符模式匹配窗口标题

### 用户变量匹配 (UVAR)

- [ ] **UVAR-01**: 用户可以基于用户变量的值配置条件快捷键
- [ ] **UVAR-02**: 终端程序可通过 OSC 1337 SetUserVar 设置用户变量
- [ ] **UVAR-03**: 用户变量在 Surface 级别存储和管理
- [ ] **UVAR-04**: 用户变量支持精确匹配和模式匹配

### 平台支持 (PLAT)

- [ ] **PLAT-01**: 所有条件匹配功能在 macOS 上正常工作
- [ ] **PLAT-02**: 所有条件匹配功能在 Linux 上正常工作

## v2 Requirements

### 高级功能

- **ADV-01**: 多条件 AND/OR 逻辑组合
- **ADV-02**: 条件驱动的自动 key table 激活/停用
- **ADV-03**: 配置文件中预定义 UserVar 初始值
- **ADV-04**: Shell integration prompt 状态作为条件维度

## Out of Scope

| Feature | Reason |
|---------|--------|
| 多条件 AND/OR 逻辑 | v1 复杂度过高，先验证单条件用户体验 |
| 其他配置项条件化（字体、颜色等） | 保持功能聚焦，快捷键是最核心需求 |
| 完全兼容 Kitty 语法 | 使用 Ghostty 原生风格，保持一致性 |
| GUI 配置界面 | 超出 Ghostty 配置模型范围 |
| 实时进程轮询监听 | 按键时惰性查询即可，避免性能浪费 |
| 条件驱动的自动 key table 激活 | 实现复杂，需要状态机管理，v2 考虑 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CONF-01 | Phase 1 | Pending |
| CONF-02 | Phase 1 | Pending |
| CONF-03 | Phase 1 | Pending |
| CONF-04 | Phase 1 | Pending |
| CONF-05 | Phase 1 | Pending |
| PROC-01 | Phase 2 | Pending |
| PROC-05 | Phase 2 | Pending |
| PROC-03 | Phase 3 | Pending |
| PROC-04 | Phase 3 | Pending |
| UVAR-01 | Phase 4 | Pending |
| UVAR-02 | Phase 4 | Pending |
| UVAR-03 | Phase 4 | Pending |
| UVAR-04 | Phase 4 | Pending |
| TITL-01 | Phase 5 | Pending |
| TITL-02 | Phase 5 | Pending |
| PROC-02 | Phase 5 | Pending |
| PLAT-01 | Phase 6 | Pending |
| PLAT-02 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-18*
*Last updated: 2026-03-18 after roadmap creation*
