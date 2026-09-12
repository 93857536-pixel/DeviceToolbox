# DeviceToolbox — iOS 设备诊断工具箱 · 工程规格 v1.0

## 0. 项目定位与铁律(子代理必读)

**定位**: iOS 系统诊断、设备信息检测、系统能力检测、个性化工具箱。全部功能仅使用 Apple **公开 API / 公开 URL Scheme**。

**绝对禁止(违反即返工)**: 越狱、提权、Kernel/PAC/PPL/AMFI 绕过、Code Signing 绕过、Sandbox Escape、TCC 绕过、Secure Enclave 攻击、修改系统安全边界、访问私有 API、漏洞利用代码。凡公开 API 无法实现的功能 → UI 显示「Apple 未向第三方 App 开放此功能」+ 限制原因,禁止 hack。

**铁律**:
1. 禁改路径: 文件结构严格按下方目录树;已有文件只增改不重排
2. 依赖禁令: **零第三方依赖**(纯 SwiftUI + Foundation + 系统框架)
3. 版本 pin: SWIFT_VERSION 6.0, iOS deployment target 17.0, iPhone 竖屏为主(支持横屏)
4. 不许假装成功: 编译不过就如实报错,不许删代码绕过
5. 全部 UI 文案中英双语(中文默认,英文跟随系统) —— 用 String(localized:) / Localizable.xcstrings 或 .strings
6. 修错轮数上限 6,剩余错误原文写 build-notes.md
7. 主色橙色 #FF9500,白色/浅灰背景,圆角卡片,支持深色模式
8. 只用 SwiftUI + async/await,@MainActor 隔离 ViewModel

## 1. 目录树(每个文件一行职责)

项目根: <PROJECT_ROOT>

```
project.yml                      # xcodegen: target DeviceToolbox(iOS app)+DeviceToolboxTests(unit)+DeviceToolboxUITests(ui)
README.md                        # 项目说明、构建说明、安装限制、安全边界声明(最后交付时写)
docs/ARCHITECTURE.md             # 架构说明
Sources/
  DeviceToolboxApp.swift         # @main, WindowGroup; 根视图按免责声明状态切换
  Core/
    Theme.swift                  # 橙色主色 Color 扩展、圆角常量、卡片组件样式
    AppStorageKeys.swift         # UserDefaults key 常量(disclaimerAccepted 等)
    Logger.swift                 # 简单日志系统(print + 可选文件)
    DeviceCapability.swift       # 能力检测结果模型: 状态枚举 supported/partial/unsupported/unknown
  Models/
    DeviceInfo.swift             # 设备信息聚合模型(Hardware/Software/Storage/Battery/Screen/Network 分组)
    CompatibilityItem.swift      # 兼容性数据库条目模型
    FeatureItem.swift            # 功能中心条目模型(名称/图标/状态/最低iOS/说明/URLScheme?)
  Services/
    DeviceInfoService.swift      # 设备信息采集: UIDevice, ProcessInfo, FileManager, UIScreen, UIDevice.battery, NSLocale
    BatteryService.swift         # 电池: UIDevice.batteryLevel/state(+UIDevice.isBatteryMonitoringEnabled)
    StorageService.swift         # 存储: FileManager.attributesOfFileSystem
    NetworkService.swift         # 网络: NWPathMonitor 接口状态/类型, 获取网络接口名
    CapabilityService.swift      # 能力检测: 对照兼容性库+运行时探测(公开API)
    PermissionService.swift      # 权限状态: 各类公开权限(CLLocation/相机/麦克风/通知/相册等)用对应框架 API 查 authorizationStatus
    URLSchemeService.swift       # 设置快捷入口: UIApplication.open 公开 scheme(wifi/蓝牙/蜂窝/通知/隐私/定位/电池/存储/App设置)
    DiagnosticsService.swift     # 诊断: 连通性(URLSession ping 公开站点), DNS(解析 host), 延迟测量
    CompatibilityStore.swift     # 本地 JSON 兼容性数据库加载+查询(bundle 内 compatibility_db.json)
    SystemInfoService.swift      # CPU 架构(Machine Identifier 经 uname/sysctl 公开接口), 运行环境(模拟器/真机)
  ViewModels/
    RootViewModel.swift          # @MainActor ObservableObject: 免责声明状态、当前设备信息加载状态
    HomeViewModel.swift          # 首页聚合: 设备型号/iOS版本/能力统计/进度
    DeviceViewModel.swift        # 设备详情
    FeatureViewModel.swift       # 功能中心列表+筛选
    ToolViewModel.swift          # 工具页诊断执行状态
  Views/
    Root/MainTabView.swift       # TabView 5 Tab: 首页/设备/功能/工具/设置
    Root/DisclaimerView.swift    # 免责声明页(首次启动,同意按钮/退出,存 UserDefaults)
    Home/HomeView.swift          # 首页: 设备卡片(型号/iOS/兼容性)+能力进度条+快捷卡片+底部Tab由MainTabView提供
    Device/DeviceView.swift      # 设备详情: 分组列表(硬件/软件/存储/电池/屏幕/网络/系统)
    Features/FeaturesView.swift  # 功能中心: 列表+状态徽章(✓/△/×/?)
    Features/FeatureDetailView.swift # 功能详情: 名称/当前设备/系统/兼容状态/说明/打开·测试按钮/不支持原因
    Tools/ToolsView.swift        # 工具: 系统诊断/网络诊断/存储/电池/权限检查/环境检测
    Tools/NetworkDiagnoseView.swift # 网络连通/DNS/延迟测试结果
    Settings/SettingsView.swift  # 设置: 关于/免责声明/隐私/开源许可/检查更新/清除缓存/重新检测/重置免责声明
    Components/
      StatCard.swift             # 圆角信息卡(标题+值+详情)
      BadgeView.swift            # 状态徽章 ✓支持/△部分/×不支持/?未知
      ProgressBarView.swift      # 能力进度条
      SectionCard.swift          # 分组卡片容器
      FeatureRowView.swift       # 功能行(图标+名称+状态)
  Resources/
    Assets.xcassets              # AppIcon + AccentColor(橙)
    compatibility_db.json        # 本地兼容性数据库(见 §5)
    Localizable.xcstrings        # 中英文案(或 en.lproj/zh-Hans.lproj Localizable.strings)
Tests/
  DeviceToolboxTests/
    DeviceInfoParsingTests.swift # 解析/模型/兼容库单元测试(不依赖真机)
    CompatibilityTests.swift     # 兼容性库查询测试
  DeviceToolboxUITests/
    DisclaimerUITests.swift      # UI 测试: 首次启动出免责声明→同意→进主界面
```

## 2. 功能模块清单(全部公开 API)

### 模块 1 首次启动免责声明
- 未同意: 全屏 DisclaimerView,不可跳过; 点「我已阅读并同意」→ UserDefaults(disclaimerAccepted=true)→ MainTabView
- 不同意选项: 退出按钮(仅提示可退出,不强制 exit(0) 以免审核问题 → 显示"可手动退出")
- 同意后重启不再显示; 设置页可重置该状态(重置后下次启动再显示)

### 模块 2 设备检测(DeviceInfoService + 分组)
- 型号: UIDevice.current.model + machine identifier(uname, sysctlbyname("hw.machine"))
- iOS 版本: ProcessInfo.operatingSystemVersionString + systemUptime
- Build: 公开渠道不可得 → 显示"Apple 未向第三方 App 开放"(诚实)
- CPU 架构: 经 sysctlbyname hw.machine + hw.optional.arm64 判断 arm64
- 存储: FileManager 总/可用/已用
- 内存: ProcessInfo.physicalMemory(总); 可用内存经公开 API 不可得 → 诚实标注
- 电池: UIDevice.isBatteryMonitoringEnabled + batteryLevel(0-1) + batteryState(charging/full/unplugged/unknown)
- 屏幕: UIScreen.main.bounds 尺寸 + scale + nativeBounds/nativeScale; 刷新率公开 API 在 iOS 15.4+ 经 CADisplayLink.maximumFramesPerSecond(公开) → 显示"约 X Hz",否则 "无法检测"
- 运行环境: #if targetEnvironment(simulator) → 模拟器, else 真机
- 网络接口信息: NWPathMonitor(公开) → wifi/cellular/其他

### 模块 3 系统兼容性中心
- CompatibilityStore 加载 compatibility_db.json
- 每功能行: 名称/状态徽章(✓△×?)/最低iOS/设备支持/原因/所需权限
- 点击 → FeatureDetailView

### 模块 4 功能中心(5 Tab 结构)
- Tab1 首页: 设备卡片(型号/iOS版本/兼容性)+ 能力进度条(百分比)+ 快捷功能卡片(系统诊断/个性化工具/设备信息/网络诊断/电池诊断/系统工具) + [检查系统能力][重新检测] 按钮
- Tab2 设备: 模块2 的分组详情
- Tab3 功能: 功能列表(来源兼容库+本地功能)
- Tab4 工具: 诊断工具集
- Tab5 设置: 模块设置列表

### 模块 5 智能兼容性数据库(本地 JSON)
```json
[
  { "id":"battery", "name":"电池状态读取","feature":"battery","minimumIOS":"10.0","maximumIOS":"",
    "devices":[],"status":"supported","requiresPermission":false,
    "detail":"通过 UIDevice 公开 API 读取电量与充电状态","actions":[{"type":"open"}] },
  { "id":"refresh-rate","name":"屏幕刷新率","feature":"screen-refresh","minimumIOS":"15.4","maximumIOS":"",
    "devices":[],"status":"partial","requiresPermission":false,
    "detail":"iOS 15.4+ 经 CADisplayLink.maximumFramesPerSecond 可读,部分机型返回 120","actions":[] },
  { "id":"machine-build","name":"系统 Build 号","feature":"build-number","minimumIOS":"1.0","maximumIOS":"",
    "devices":[],"status":"unsupported","requiresPermission":false,
    "detail":"Apple 未向第三方 App 开放 Build Number 读取","actions":[] }
]
```
状态枚举: supported / partial / unsupported / unknown(数据库里写 supported/partial/unsupported,程序可补 unknown)

### 模块 6 UI 规范
- 主色 #FF9500(orange); 背景 systemGroupedBackground; 卡片白/深色 secondarySystemGroupedBackground
- 圆角 16; 卡片内边距 16
- 状态颜色: ✓绿 #34C759 / △橙 #FF9500 / ×红 #FF3B30 / ?灰
- 图标: SF Symbols
- Tab 图标: 首页 house / 设备 iphone / 功能 square.grid.2x2 / 工具 wrench.and.screwdriver / 设置 gearshape
- 顶部大标题(首页用 .large navigationTitle 或自定义)
- 支持 Dynamic Type(用系统字体,不固定字号)、VoiceOver(label 明确)
- 横竖屏: 用系统布局自适应,不锁死方向

### 模块 7 设置快捷入口(URLSchemeService, 全公开 scheme)
- Wi-Fi: App-Prefs:root=WIFI(注: 从 iOS 10 起多数 settings 深链在第三方 App 失效 → 诚实显示"可能无法直接跳转,请手动前往设置"并提供可用的 UIApplication.openSettingsURLString(App 自身设置))
- 方案: 每个入口尝试 open; 同时提供「打开系统设置」通用按钮(openSettingsURLString 一定可用)
- 按钮回调统一 report 成功/失败,失败文案 "系统未允许跳转到该设置页,请手动前往"

### 模块 8 诊断工具
- 网络连通性: URLSession dataTask 到 https://www.apple.com 与 https://www.baidu.com, 记录状态码/耗时
- DNS: 用 NWResolver 或简单的 ProcessInfo 不可行 → 用 URLSession 解析 host(或公开的 dns-sd 不引入) → 显示解析到的 IP(经 URL 的 host 解析); 诚实标注
- 延迟: 连续 3 次请求测平均耗时
- 存储检测/电池查看/能力检测/环境检测/权限检查: 调用对应 Service
- 权限检查: CLLocationManager.authorizationStatus(需 Info.plist 描述) 等 —— 只读状态不请求授权(部分需在 Info.plist 加 usage description,加但默认不触发)

### 模块 9 设置页
关于(App 版本/最低iOS)、免责声明(重看)、隐私说明(静态文本:不采集上传任何数据)、开源许可(静态)、检查更新(显示"请前往 App Store/开发者渠道获取最新版"),清除缓存(清 UserDefaults 非必要项+说明)、重新进行设备检测、重置免责声明确认状态

## 3. 工程配置(project.yml 要点)
- xcodegen 生成; 勿手改 pbxproj
- targets:
  - DeviceToolbox: application iOS, sources [Sources], deploymentTarget 17.0
    settings: PRODUCT_BUNDLE_IDENTIFIER com.linminhao.DeviceToolbox, SWIFT_VERSION 6.0, CODE_SIGN_STYLE Automatic, DEVELOPMENT_TEAM (你的 Apple Team ID), ASSETCATALOG_COMPILER_APPICON_NAME AppIcon, TARGETED_DEVICE_FAMILY "1,2"(iPhone+iPad) 或 "1"(仅iPhone,规格默认iPhone优先可含iPad——用 "1")
    info: Info.plist properties(UIApplicationSceneManifest 由 SwiftUI 自动? xcodegen 需 UILaunchScreen {}, CFBundleDisplayName DeviceToolbox/设备工具箱)
  - DeviceToolboxTests: bundle.unit-test iOS, sources [Tests/DeviceToolboxTests], 依赖 target DeviceToolbox
  - DeviceToolboxUITests: bundle.ui-testing, sources [Tests/DeviceToolboxUITests]
- scheme 自动生成(shared)

## 4. 构建与测试命令(严格照用)
```bash
cd <PROJECT_ROOT>
xcodegen generate
# 模拟器编译
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
# 单元测试
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath build/DerivedData test
# Release 产物(未签名思路)
xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO archive
```
注意: 本机 Xcode 27 beta 位于 /Applications/Xcode-beta.app; 若 xcodebuild 找不到先 `sudo xcode-select -s /Applications/Xcode-beta.app`
子代理在自己域内跑 build 用独立 derivedDataPath, 如 build/tmp-dd

## 5. 汇报格式(子代理交付)
1. 文件清单(新增/修改)
2. 构建结果原文(最后一条 BUILD/error 输出)
3. 测试数与结果(如跑了)
4. 已知问题/未实现项(诚实)
5. 本机未编译必须显式标注
