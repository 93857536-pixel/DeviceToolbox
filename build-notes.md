# build-notes — DeviceToolbox UI 层构建记录

> 子代理 B(UI 层)构建验证笔记。记录真实构建结果、剩余错误分类与自验手段。
> 生成时间:2026-09-05

## 0. 环境事实

- `xcode-select -p` = `/Applications/Xcode-beta.app/Contents/Developer`(已是 Xcode 27 beta,无需切换)
- 构建均 `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
- Swift 6.4 / SWIFT_VERSION 6.0 / iOS 17.0 / xcodegen 2.46.0(`/opt/homebrew/bin/xcodegen`)

## 1. xcodegen 结果

```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at .../DeviceToolbox.xcodeproj
```

成功。3 个 target(DeviceToolbox / DeviceToolboxTests / DeviceToolboxUITests)均已生成。

## 2. xcodebuild 结果(失败,EXIT_CODE=65)

命令:
```
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/tmp-dd build
```

结论:**BUILD FAILED**。剩余错误分两类,均非 UI 层代码错误:

### 2.1 锚点文件 Models/CompatibilityItem.swift(Swift 6 语言模式编译错误,禁止修改)

```
Sources/Models/CompatibilityItem.swift:72:1: error: extension outside of file declaring
struct 'OperatingSystemVersion' prevents automatic synthesis of '==' for protocol 'Equatable'
```

原因:`extension OperatingSystemVersion: @retroactive Comparable` 只实现了 `<` 未显式实现 `==`,
Swift 6 语言模式禁止从声明类型之外的文件自动合成 `==`。该文件是磁盘已有只读锚点(契约 §0/§1 禁止 B 修改)。
**主会话整合时需修复**:在该 extension 内显式补一个 `==` 实现即可(自验时已在
`build/stubs/CompatibilityItemFixed.swift` 验证该修法可消除此错误)。

### 2.2 服务层缺失(并行子代理 A 未落盘,契约要求记录、不补写)

以下类型/符号均来自契约 §2 的 `Sources/Services/*`,当前目录不存在,故编译报 "cannot find":

| 缺失符号 | 引用位置(UI 层) |
|---|---|
| `DeviceInfoService` | HomeViewModel / DeviceViewModel / ToolViewModel |
| `CapabilityService` | HomeViewModel / FeatureViewModel |
| `SystemInfoService` | FeatureViewModel |
| `CompatibilityStore` | FeatureViewModel |
| `DiagnosticsService` / `PingResult` | ToolViewModel / NetworkDiagnoseView |
| `AppPermission` / `AppPermissionStatus` / `PermissionService` | ToolViewModel / ToolsView |
| `URLSchemeService` / `SchemeActionResult` | FeatureDetailView |

代表性错误原文:
```
Sources/ViewModels/HomeViewModel.swift:19:37: error: cannot find 'DeviceInfoService' in scope
Sources/ViewModels/ToolViewModel.swift:10:47: error: cannot find type 'PingResult' in scope
Sources/ViewModels/FeatureViewModel.swift:29:26: error: cannot find 'CompatibilityStore' in scope
```

按契约「双写禁令」,未自行创建/修改 `Sources/Services/` 下任何文件。

## 3. UI 层自验(已通过)

由于 Services 缺失 + 锚点 Equatable 错误,无法整工程编译。为自验 UI 层类型正确性,采取以下手段
(全部产物位于 `build/`,不进入 `Sources/`,不影响交付):

1. **语法级**:28 个 `.swift` 文件全部 `xcrun swiftc -parse` 通过(0 失败)。
2. **类型级**:用 `build/stubs/ServicesStub.swift`(签名与契约 §2 严格一致) +
   `build/stubs/CompatibilityItemFixed.swift`(锚点副本 + 显式 `==`)替代缺失服务与锚点 Equatable 问题,
   对全部 Core/Models/UI 文件执行 `swiftc -typecheck` → **EXIT=0,零错误零警告**。
3. **资源级**:
   - `xcrun actool` 编译 `Assets.xcassets` → 成功产出 `AppIcon60x60@2x.png`/`AppIcon76x76@2x~ipad.png`/`Assets.car`。
   - `plutil -lint` 校验 `zh-Hans.lproj`/`en.lproj` Localizable.strings → 均 OK。
   - `Sources/Resources/Info.plist` 已由 xcodegen 生成,含 6 个权限 usage description + `UILaunchScreen: {}`。

结论:UI 层代码本身类型正确;待 A 的服务层落盘 + 主会话修复锚点 `==` 后,工程应可整体编译通过。

## 4. 修错轮数(≤6)

| 轮次 | 问题 | 处理 |
|---|---|---|
| 1 | 对非 throws 方法冗余 `try` / `async let` 并发写法 | 改为顺序 `await`,去除 try |
| 2 | `Dictionary(_:uniquingKeysWith:)` 因服务缺失导致 Key 无法推断 | 改为显式 `[String: CapabilityResult]` for 循环 |
| 3 | `FeatureItem` 未遵循 `Hashable`(锚点类型),不能用 `NavigationLink(value:)` | 改用 destination-based `NavigationLink` |
| 4 | `ToolViewModel.defaultHosts` MainActor 隔离的静态属性被 nonisolated 默认参数引用(Swift 6 error) | 标记为 `nonisolated static let` |

剩余错误(锚点 `==`、Services 缺失)非 UI 层职责,按契约记录不修。

---

## 5. 服务层(A)落盘后的整合构建记录(2026-09-05 晚)

> 子代理 A(服务层)完成 `Sources/Services/*`(10 文件)+ `Sources/Resources/compatibility_db.json`
> + `Tests/DeviceToolboxTests/*`(2 文件)后的真实构建结果。

### 5.1 锚点 Equatable 问题现状(已解决)

`Sources/Models/CompatibilityItem.swift` 的 `@retroactive Comparable` 扩展已补上显式 `==` 实现
(第 73 行 `public static func ==`),B 在 §2.1 记录的
`extension outside of file ... prevents automatic synthesis of '=='` 错误**不再复现**。

A 的验证:对 `Core + Models + Services` 全部文件 `xcrun swiftc -typecheck -swift-version 6` →
**EXIT=0,零错误零警告**。

### 5.2 整工程 xcodebuild 结果:BUILD SUCCEEDED ✅

```
xcodegen generate  → 成功(3 target)
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/tmp-dd-a build
→ ** BUILD SUCCEEDED **
```

说明:服务层落盘后整 App(含 UI 层全部 Views/ViewModels/App)首次**编译通过**,无 Swift 编译错误。

### 5.3 服务层自检

- 12 个新 `.swift` 文件(10 Services + 2 Tests)全部 `xcrun swiftc -parse` 通过。
- 10 Services `-typecheck -swift-version 6` 通过(零错误零警告,已消除 3 处初始 warning:
  `CLLocationManager.authorizationStatus()` 弃用、`CNAuthorizationStatus` 缺 `.limited` 分支、`String(cString:)` 弃用)。
- 2 测试文件经「最小 DeviceToolbox 模块(Core+Models+Services,`-enable-testing`)」+
  XCTest 框架 `-typecheck` 通过(EXIT=0)。

### 5.4 新发现:测试 target 无法 code sign(project.yml 配置缺失,属 B 职责)

`xcodebuild test` 失败(EXIT=65),错误原文:

```
error: Cannot code sign because the target does not have an Info.plist file and one is not being
generated automatically. Apply an Info.plist file to the target using the INFOPLIST_FILE build
setting or generate one automatically by setting the GENERATE_INFOPLIST_FILE build setting to YES
(recommended). (in target 'DeviceToolboxTests' ...)
error: Cannot code sign because the target does not have an Info.plist file and one is not being
generated automatically. ... (in target 'DeviceToolboxUITests' ...)
```

原因:project.yml 的 `DeviceToolboxTests` / `DeviceToolboxUITests` 两个 target 未设置
`GENERATE_INFOPLIST_FILE: YES`(或 `INFOPLIST_FILE`)。属 B 归属的 `project.yml`(A 契约禁止修改)。
**主会话整合时修复**:给两个测试 target 补 `GENERATE_INFOPLIST_FILE: YES` 即可跑单元测试。

因此:A 的 2 个单元测试已通过类型级自检,但**未实际执行**(被上述 code sign 配置缺失阻断),如实标注。
