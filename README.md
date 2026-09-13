# DeviceToolbox — iOS 侧载特权工具箱

iOS 侧载(企业签)场景下的设备特权工具箱:内核漏洞链逃逸、系统容器访问、整机文件读写、壁纸实验室、AI 强制开启、型号伪装、清理工具、操作日志。**基于 Swift 6 + SwiftUI,GPLv3 许可**,ExploitCore 与壁纸实验室核心搬运自 [YangJiiii/3105](https://github.com/YangJiiii/3105)(GPLv3)。

> ⚠️ **本项目仅面向 iOS 研究 / 教育用途,请遵守所在地法律法规。未经授权的入侵他人设备在多数地区属违法行为。使用者自担全部风险。**

---

## 功能模块

| 模块 | 说明 |
|---|---|
| 首页 | 设备卡片(型号/iOS/SoC/模拟器识别)+ 能力探针进度 + 快捷入口 |
| 设备详情 | 硬件/软件/存储/电池/屏幕/网络/系统 7 组信息 |
| 功能中心 | 20+ 项系统能力兼容性检测,状态徽章 ✓/△/×/? |
| 特权引擎 | 3105 内核漏洞链(kexploit_opa334 + sandbox_escape + bad_query),运行时探针报真实状态;能力入口常显 |
| 系统容器 | 容器级文件访问/扫描(MCM 通道),企业签含容器 entitlements 时可用 |
| 整机文件 | 任意路径文件浏览,自动提权(依赖特权引擎) |
| 壁纸实验室 | 系统壁纸安装/解析(3105 移植) |
| 折叠玻璃实验室 | 磨砂玻璃折叠动画:转动手机,界面透过一块倾斜玻璃窗透视渲染(Metal layerEffect + CoreMotion),模拟器自动切手动滑杆模式 |
| AI 强开 | 写 MobileGestalt/eligibility 开启 AI 能力,自动备份+原子写+可恢复 |
| 型号伪装 | 修改 gestalt/eligibility 设备型号标识,备份可回滚 |
| 清理器 | 缓存/日志清理工具页 |
| 补丁工作区 | 补丁包导入/编辑/仓库管理(支持密码保护补丁) |
| 操作日志 | 全部高危操作留痕;设置页可导出/清除 |
| 日志上传 | 操作日志页「上传日志」按钮:仅在你明确点击时,把本页日志 + 最少设备上下文(iOS 版本/机型/应用版本/语言)发到维护者服务器(linminhao.top);**绝不自动上传,不收集 IMEI/IDFA/位置/账号等任何个人数据** |

### 版本窗口(重要,请以实测为准)

- 内核链真实可用窗口:**iOS 17.0 – 26.0.x**(运行时 guard `< 26.1`)
- iOS 26.1+/27 beta:内核链不可用,容器级能力取决于**签名身份**(企业签含容器 entitlements 可用;免费个人签 MCM 恒被拒)
- 各版本行为差异请通过 Issue 反馈,维护者会逐步更新兼容性数据库

---

## 构建

要求:macOS + Xcode(Swift 6,iOS 17+ SDK,建议 Xcode 15+/27 beta 已验证)+ [xcodegen](https://github.com/yonaskolb/XcodeGen)。零第三方依赖。

```bash
git clone https://github.com/93857536-pixel/DeviceToolbox && cd DeviceToolbox
xcodegen generate

# 模拟器编译
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer  # 仅 beta 用户
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DD build

# 未签名 Release(产出未签名 .app,供企业签工具自签)
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/DD-ipa \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

### 安装(侧载)

构建产物为**未签名 IPA**,需自行签名安装:

1. 全能签(AltSign)等工具做企业签名(含容器 entitlements 时能力更多),或
2. 免费开发者账号 7 天签名(部分容器通道受限)

注意 App 伪装为 `com.apple.mobile.MobileHouseArrest` bundle ID(MCM/MHA 容器通道需要,见 `project.yml` 注释)。

### 测试

```bash
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DD \
  test -only-testing:DeviceToolboxTests
```

---

## 🐞 Bug 反馈(征集)

**维护者当前没有真机可以复现测试**,所有真机行为(尤其是特权引擎在各 iOS 版本/签名身份下的表现)都需要依靠使用者反馈:

- 请通过 [GitHub Issues](https://github.com/93857536-pixel/DeviceToolbox/issues) 报告 bug
- 报告时请附上:设备型号、iOS 版本(含 build)、签名方式(企业签/个人签)、复现步骤
- 日志:可直接点 App 内「操作日志」页的**「上传日志」按钮**发送到维护者服务器(仅手动触发,只含日志条目与最少设备信息,不含个人数据),或在 Issue 里贴出「操作日志」页导出的文本
- 兼容性数据库会随反馈持续更新

## ⚖️ 免责声明

1. 本项目**未经真机全量测试**,功能在不同 iOS 版本与签名身份下行为可能不一致,一切以你的设备实测为准。
2. 写系统文件(MobileGestalt/eligibility 等)操作虽内置备份+原子写+回滚入口,但**仍存在设备无法启动(bootloop)的风险**,操作前请自行备份数据。
3. 内核漏洞链用于**研究/教育**目的,请勿用于违法用途,由此产生的一切后果由使用者自行承担。
4. 使用本软件意味着你已理解并同意:维护者不对设备损坏、数据丢失、账号风险负任何责任。
5. **日志上传是可选且需手动触发**:操作日志页的「上传日志」按钮点击后,仅会把该页显示的日志条目与最少设备上下文(iOS 版本、机型、应用版本、语言)发送到维护者服务器(linminhao.top)。本软件**不自动上传日志、不收集任何个人数据**(IMEI、IDFA、位置、账号标识均不涉及)。你可以选择不使用此按钮。

## 许可

**GPLv3**(完整文本见 `LICENSE`)。ExploitCore 与壁纸实验室核心代码搬运自 [YangJiiii/3105](https://github.com/YangJiiii/3105)(GPLv3),相关源文件顶部已标注来源。折叠玻璃实验室(`Sources/FoldEffect/`)效果设计借鉴 [elijah-semyonov/DuoLikeAnimation](https://github.com/elijah-semyonov/DuoLikeAnimation)(MIT License),为重新实现而非直接拷贝,文件头部已标注来源。
