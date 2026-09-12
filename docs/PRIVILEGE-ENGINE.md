# DeviceToolbox 特权引擎(Privilege Engine)规划

版本 0.1 | 2026-09-05 | 目标: 让安装 DeviceToolbox 的设备按"系统版本 × 芯片"自动匹配可用漏洞链,解锁跨应用能力(容器访问/清理/补丁)

## 1. 能力架构(三层)

```
[UI 层]  Files/Patches/Cleaner 需特权时调用 PrivilegeKit
[特权层] PrivilegeKit: KernelAccess 状态机 + SupportMatrix(版本×芯片→链) + 链执行器
[漏洞层] kexploit(C/ObjC): DarkSword 系(15–26.0.1) + 未来新链
```
激活后能力: 任意 app 容器浏览/替换(补丁真正对第三方生效)、跨 app Cleaner、MHA-C2 容器解析。
沙盒逃逸成功后文件操作走 FileManager(现有 FileWorkspace 服务复用,仅路径注入来源变化)。

## 2. 支持矩阵(2026-09-05, 基于 GitHub 公开生态调研)

### 主链: DarkSword (CVE-2025-43520, VFS cluster_write_contig 竞态, Apple 已封于 26.3/18.7.3)
| 档位 | iOS 范围 | 依据 | 状态 |
|---|---|---|---|
| 已验证档 | 17.0 – 18.7.1 | lara (rooootdev, AGPL-3.0) 支持表 | 可移植参考 |
| 已验证档 | 26.0 – 26.0.1 | lara/ClearSword | 可移植参考 |
| 声称档 | 26.1 | 3105 offsets.m 含 26.1 | 需真机验证 |
| 声称档 | 26.2 – 27 beta | 3105 README 声称 (26.0–26.6.1/27b) | 存疑, 无公开 offsets 证据 |

硬排除: M5 / A19 芯片(含 iPhone 17 全系, MIE 机制); iOS 18.7.2+ / 26.1+(无公开 offsets)。
iOS 15–16.x: DarkSword/ClearSword 理论覆盖(需 offsets 调), 另有 kfd 系(16.0–16.6.1 部分)可作次级链。

### 芯片 → 可用性
- A12–A18(iPhone XS–16 系 / SE2/3): DarkSword 可用(17.0–18.7.1 / 26.0–26.0.1)
- A19(iPhone 17 全系): MIE 免疫, 不可用
- M1–M4(iPad): 部分可用(lara 提示 M 系需调 t1sz_boot offset, YMMV)
- M5(iPad Pro 2026): MIE 免疫, 不可用

## 3. 移植源与许可(必须决策)

| 源 | 许可 | 内容 | 传染性影响 |
|---|---|---|---|
| 3105 (YangJiiii) /tmp/3105 | GPL-3.0 | DarkSword 移植 (kexploit_opa334.m, pe_v2 from DarkSword-RCE) + MHA/mcm_bridge + 容器全套 | 引入源码 → DeviceToolbox 整体 GPL-3.0 开源 |
| lara (rooootdev) | AGPL-3.0 | DarkSword 工具箱 | 更严(网络服务也传染), 不优先 |
| ClearSword (theRealClarity) | 待查 | DarkSword C 重实现, 测试 15–26.0.1 | 参考 |

**决定待用户确认**: P1 引入 3105 的 kexploit/exploit 层后, 工程整体 GPL-3.0, 需发布源码。
P0(本次)不引入 GPL 源码, 只做纯 Swift 探测/矩阵/状态机, 无传染。

## 4. 目录规划

```
Sources/Privilege/SupportMatrix.swift   — 版本×芯片→链 判定 (纯数据+逻辑)
Sources/Privilege/KernelAccess.swift    — 状态机: inactive→probing→supported/unsupported→running(exploit 桩)
Sources/Privilege/DeviceProbe.swift     — 型号/芯片族探测 (公开 API: ProcessInfo + sysctl hw.machine)
Sources/Privilege/ExploitRunner.swift   — P1: 桥接 kexploit C 层 (P0 为桩, 模拟器返回 unsupported)
(未来) Sources/Privilege/kexploit/     — P1 从 3105 移植 (GPL, 整仓 LICENSE 切换)
```

## 5. 阶段

- P0(本次): 矩阵+探测+状态机+UI 状态页+单测 —— 模拟器可完整验证
- P1: GPL 决策 → 移植 3105 kexploit/exploit 层 → 真机(A12–A18 + iOS ≤26.0.1)验证 —— 需测试设备
- P2: 特权后能力打通: Cleaner 跨 app、Patch 目标到任意容器、MHA 容器浏览
- P3: 持续跟进新公开链(26.1+ / A19 破 MIE)更新矩阵

## 6. 诚实边界(写进产品文案)

无法覆盖: iOS 26.1+ / 18.7.2+ / 27(无公开链); A19/M5 芯片(MIE)。探测到不支持时 UI 明示"此设备暂无可用公开漏洞", 不做假支持。
