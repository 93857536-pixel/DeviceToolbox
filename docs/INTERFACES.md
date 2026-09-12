# DeviceToolbox 接口契约 v1(子代理并行协作用)

> 本文件是 A(服务层)与 B(UI 层)两个并行子代理的**共享契约**。
> 两份子代理必须先完整阅读本文件 + `docs/SPEC.md`,再动手。
> 磁盘已存在文件(Core/*.swift 4 个 + Models/*.swift 3 个)是**只读锚点**:读它对齐类型,禁止修改。

## 0. 环境事实(双方一致)

- 项目根: `<PROJECT_ROOT>`
- Swift 6.4,零第三方依赖,SWIFT_VERSION 6.0,iOS deployment target 17.0
- Xcode 27 beta: `/Applications/Xcode-beta.app`。构建前若 `xcode-select -p` 不是它,用
  `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`(不要 sudo 全局切)
- xcodegen: `/opt/homebrew/bin/xcodegen`
- 已存在(勿动): `Sources/Core/{Theme,AppStorageKeys,Logger,DeviceCapability}.swift`,
  `Sources/Models/{DeviceInfo,CompatibilityItem,FeatureItem}.swift`

## 1. 文件归属表(谁写谁,严禁越界)

| 归属 | 文件 | 说明 |
|---|---|---|
| A | `Sources/Services/*.swift` × 10 | 类名/签名见 §2,唯一契约 |
| A | `Sources/Resources/compatibility_db.json` | 结构与 `CompatibilityItem` 严格对齐(见 §3) |
| A | `Tests/DeviceToolboxTests/{DeviceInfoParsingTests,CompatibilityTests}.swift` | 纯单元测试,不依赖真机;fixture 用内嵌字符串,不依赖 bundle |
| B | `project.yml` | 3 targets;Info.plist 加权限描述(见 §4);resources 含 `Sources/Resources/` 下全部(Assets.xcassets、compatibility_db.json、*.lproj) |
| B | `Sources/DeviceToolboxApp.swift` | @main,免责声明态切换 |
| B | `Sources/ViewModels/*.swift` × 6 | 类名见 §5,内部状态自由设计 |
| B | `Sources/Views/**` 全部 | 13 View + 5 Component,见 SPEC §1 目录树 |
| B | `Sources/Resources/Assets.xcassets` | AppIcon(纯橙 #FF9500 单尺寸 1024,本机工具离屏生成)+ AccentColor |
| B | `Sources/Resources/en.lproj` + `zh-Hans.lproj` | `Localizable.strings`,developmentLanguage zh-Hans |
| B | `Tests/DeviceToolboxUITests/DisclaimerUITests.swift` | 首次启动免责声明→同意→进主界面 |
| B | `docs/ARCHITECTURE.md` | 架构说明(短) |

**双写禁令**: B 禁止创建/修改 `Sources/Services/` 任何文件(即使编译报"找不到 DeviceInfoService")——
那是 A 并行在写。编译错误如实记入 `build-notes.md`,主会话整合时统一处理。
A 禁止修改 B 归属的任何文件;A 只新增 `Sources/Services/`、`Sources/Resources/compatibility_db.json`、
`Tests/DeviceToolboxTests/` 下文件。目录不存在就 `mkdir -p`,目录创建无害。

## 2. Services 公开契约(A 实现,B 按此调用,签名不可改)

全部 `@MainActor final class`(除 CompatibilityStore)。方法与磁盘 Models 精确对齐。

```swift
// SystemInfoService.swift —— 系统层
@MainActor final class SystemInfoService {
    func collect() -> SystemInfo
    // SystemInfo: cpuArchitecture(sysctlbyname hw.machine + hw.optional.arm64 → "arm64"/"x86_64"),
    // isSimulator(#if targetEnvironment(simulator)), machineIdentifier(hw.machine),
    // kernelVersion(uname,失败 nil), hostname(ProcessInfo.hostName)
}

// StorageService.swift —— 存储
@MainActor final class StorageService {
    func collect() -> StorageInfo
    // FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory());used = total - free
}

// BatteryService.swift —— 电池
@MainActor final class BatteryService {
    func collect() -> BatteryInfo
    // UIDevice.current.isBatteryMonitoringEnabled 先置 true;level(0...1,取不到 nil)、
    // state 映射 BatteryState(charging/full/unplugged/unknown)、ProcessInfo.isLowPowerModeEnabled
}

// NetworkService.swift —— 网络(公开 NWPathMonitor,一次性采样)
@MainActor final class NetworkService {
    func collect() async -> NetworkInfo
    // 创建 NWPathMonitor(默认 queue),start 后等第一次 pathUpdateHandler(用 withCheckedContinuation),
    // 采样后 cancel。status/interfaceType/interfaceNames/isExpensive/isConstrained/supportsIPv4/supportsIPv6
    // 全映射自 NWPath 公开属性。别把 monitor 留着不 cancel。
}

// DeviceInfoService.swift —— 全量聚合
@MainActor final class DeviceInfoService {
    func collect() async -> DeviceInfo
    // Hardware: UIDevice.model + marketingName(内置映射表: iPhone17,x/iPad 常见机型;映射不到回退 machineIdentifier)
    // Software: systemName/systemVersion/versionString(ProcessInfo.operatingSystemVersionString)、
    //   buildNumber **恒 nil**(Apple 未开放,注释说明)、systemUptime、NSLocale/首选语言
    // Screen: UIScreen.main bounds/scale/nativeBounds/nativeScale/brightness;
    //   maximumFramesPerSecond 仅 iOS 15.4+(CADisplayLink.maximumFramesPerSecond),否则 nil,
    //   refreshRateDescription = "约 X Hz" / "无法检测"
    // 其余委托: StorageService / BatteryService / NetworkService / SystemInfoService
}

// DiagnosticsService.swift —— 诊断(网络连通/DNS/延迟)
@MainActor final class DiagnosticsService {
    func ping(host: String, timeout: TimeInterval = 8) async -> PingResult
    // URLSession 一次 GET(https://host,忽略证书细节不用),记 statusCode 与耗时 ms
    func resolveDNS(host: String) async -> [String]
    // 公开 POSIX getaddrinfo + inet_ntop,包在 Task.detached 里避免阻塞主线程;失败返回 []
    func averageLatency(host: String, attempts: Int = 3) async -> Double?
}
struct PingResult: Identifiable, Sendable, Equatable {
    let id = UUID()
    let host: String
    let statusCode: Int?        // 无响应 nil
    let latencyMs: Double?      // 请求耗时 ms
    let resolvedIPs: [String]   // DNS 解析结果,可能 []
    let errorDescription: String?
}

// PermissionService.swift —— 权限状态(只读,绝不触发授权弹窗)
enum AppPermission: String, CaseIterable, Sendable {
    case location, camera, microphone, notifications, photos, contacts, bluetooth, faceID
}
enum AppPermissionStatus: String, Sendable {
    case notDetermined, denied, restricted, authorized, limited, unavailable   // limited 仅相册
}
@MainActor enum PermissionService {
    static func status(of permission: AppPermission) -> AppPermissionStatus
    // 用对应公开框架 authorizationStatus / 能力探测:
    // location→CLLocationManager.authorizationStatus(不 requestWhenInUse!) camera/microphone→AVCaptureDevice
    // notifications→UNUserNotificationCenter(注意:同步读不到,用 async + continuation 或返回 .notDetermined 兜底并在注释说明)
    // photos→PHPhotoLibrary.authorizationStatus(for: .readWrite) contacts→CNContactStore
    // bluetooth→CBManager.authorization faceID→LAContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)(填 usage 见 §4)
    // 拿不到/未声明 usage 的状态→.unavailable
}

// URLSchemeService.swift —— 设置快捷入口(全公开 scheme,诚实失败)
struct SchemeActionResult: Sendable, Equatable {
    let succeeded: Bool
    let message: String        // 成功/失败中文文案(与 UI 文案一致走 Localizable 的键,见 §5 说明)
}
@MainActor final class URLSchemeService {
    static func openAppSettings() async -> SchemeActionResult
    // UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    static func openPreferences(root: String) async -> SchemeActionResult
    // App-Prefs:root=WIFI 等;iOS 10+ 第三方可能失效 → open 返回 false 时 message =
    // "系统未允许跳转到该设置页,请手动前往"(键名见 §5)
}

// CompatibilityStore.swift —— 兼容性库(纯数据,不绑 MainActor)
final class CompatibilityStore {
    static let bundled: CompatibilityStore   // Bundle.main 读 compatibility_db.json;文件缺失→allItems() 返回 [],不 crash
    init(url: URL) throws                    // 单元测试注入用(解码失败 throw)
    func allItems() -> [CompatibilityItem]   // 缓存后返回
    func item(feature: String) -> CompatibilityItem?
}

// CapabilityService.swift —— 能力评估(数据库条目 × 运行时探测)
@MainActor final class CapabilityService {
    func evaluate() async -> [CapabilityResult]
    // 输入: CompatibilityStore.bundled.allItems()
    // 逐条: minimumIOS/maximumIOS 用 CompatibilityItem.isSupported(by: ProcessInfo 当前 OS) 判定;
    //   applies(to: machineIdentifier) 判定设备;requiresPermission=true 的项叠加权限状态
    //   (notDetermined/denied → partial? 设计自定但需诚实: 未授权≠不支持,文案写清楚)
    // 输出 CapabilityResult(id/name/status/detail/requiresPermission) —— 类型在
    //   Sources/Core/DeviceCapability.swift 已定义,直接复用
}
```

## 3. compatibility_db.json 结构(A 写,20±5 条)

数组,每条与 `CompatibilityItem` 字段一一对应(该类型在磁盘 Models 已存在,status 直接 decode `CapabilityStatus`):

```json
[{ "id":"battery","name":"电池状态读取","feature":"battery","minimumIOS":"10.0","maximumIOS":"",
   "devices":[],"status":"supported","requiresPermission":false,
   "detail":"通过 UIDevice 公开 API 读取电量与充电状态","actions":[{"type":"open","title":"查看","value":""}] }]
```

- 覆盖: 电池、屏幕刷新率、Build号(**unsupported**,Apple 未开放)、面容ID、触控ID、NFC、5G、eSIM、
  灵动岛(iOS 16+,设备限定)、常亮显示、相机、麦克风、定位、通知、相册、蓝牙、无线充电、反向充电、
  空间音频、辅助触控等,三类状态都要有;`status` 只允许 supported/partial/unsupported
- actions 的 type ∈ open/test/settings,title/value 可空
- 无法运行时探测、纯 Apple 未开放项 → unsupported + detail 写原因(诚实)

## 4. project.yml 要点(B 写,SPEC §3 为准,补充如下)

- targets: DeviceToolbox(iOS app, sources [Sources], deploymentTarget 17.0) /
  DeviceToolboxTests(unit-test, sources [Tests/DeviceToolboxTests], 依赖 DeviceToolbox) /
  DeviceToolboxUITests(ui-testing, sources [Tests/DeviceToolboxUITests])
- `DEVELOPMENT_TEAM: (你的 Apple Team ID,或直接无签名构建)`,`PRODUCT_BUNDLE_IDENTIFIER: com.linminhao.DeviceToolbox`,
  `SWIFT_VERSION: 6.0`,TARGETED_DEVICE_FAMILY "1",ASSETCATALOG_COMPILER_APPICON_NAME AppIcon
- **Info.plist properties 必须含**(只声明,默认不触发,SPEC 模块 8):
  `NSCameraUsageDescription`、`NSMicrophoneUsageDescription`、`NSLocationWhenInUseUsageDescription`、
  `NSPhotoLibraryUsageDescription`、`NSBluetoothAlwaysUsageDescription`、`NSFaceIDUsageDescription`(中英双语短句)
  + `UILaunchScreen: {}` + CFBundleDisplayName(用 `$(PRODUCT_NAME)` 默认或直接 "DeviceToolbox")
- options: `developmentLanguage: "zh-Hans"`(中文默认,英文跟随系统)
- resources: `Sources/Resources` 整个目录(Assets.xcassets + compatibility_db.json + *.lproj 都进 app target);
  测试 target 不需要 json(A 的测试用内嵌 fixture)
- xcodegen 在**每次构建前**重新 generate(新文件才会进工程)

## 5. ViewModels(B 写,类名固定,内部自由)

文件与类名(SPEC §1 目录树): RootViewModel / HomeViewModel / DeviceViewModel /
FeatureViewModel / ToolViewModel(每个文件一个 @MainActor ObservableObject)。

- 约束: Services 调用**必须用 §2 签名**;UI 文案全部经 `String(localized:)`,键放进 en/zh-Hans 两个
  `Localizable.strings`(developmentLanguage zh-Hans 让中文默认)。**§2 文案键**至少含:
  `settings.jump.denied`(系统未允许跳转到该设置页,请手动前往)、`settings.open`(打开系统设置)。
  其余文案键你自定,保持中英双语成对。
- 状态字段名、方法名、依赖注入方式自由设计(UI 也是你写,自洽即可)。
- RootViewModel 必须提供免责声明态(SPEC 模块 1): UserDefaults 键用磁盘已有
  `AppStorageKeys.disclaimerAccepted`;提供 accept 与 reset。
- HomeViewModel 至少暴露: 设备摘要(型号/iOS/能力支持统计 x/y)、能力进度(0...1)、加载态、reload()。
- FeatureViewModel: 功能列表(来源 CompatibilityStore + CapabilityService.evaluate 汇总),支持筛选状态。
- ToolViewModel: 诊断任务执行状态(ping/dns/延迟,调用 DiagnosticsService)。

## 6. 构建与汇报

- A 自检: 每个新 .swift 文件 `xcrun swiftc -parse <file>`(语法级);无法整工程编译(Xcode 工程在 B 手里),
  **如实标注** "语法解析通过,未整工程编译"。
- B: `xcodegen generate` → `xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/tmp-dd build`,修错 ≤6 轮,
  剩余错误原文写入 `build-notes.md`;若因 A 的 Services 尚未落盘而报错 → 记入 build-notes.md,不自行补写 Services。
- 汇报格式(SPEC §5): 文件清单 / 构建结果原文 / 测试数 / 已知问题(诚实) / 未编译必须显式标注。
