# DeviceToolbox 移植规格:3105 PosterBoard 壁纸实验室 + DisplayIdentity

> 只读通读 `/tmp/3105/ThreeOneOSFive` 源码 + 对齐 `<PROJECT_ROOT>` 现状后产出。
> 目标落点:`/tmp/port-spec.md`。禁止编造;凡源码读不到证据处均标「需实测/源码未见」。

---

## 0. 必须先读:两处关键事实更正(与父任务描述不符)

1. **「DisplayIdentity 伪装」这一命名是错的。** `DisplayIdentity.h/.m` + `DisplayIdentityAttribution.swift` **不是**改 App 在桌面显示的身份/图标,也**不借用**别的 App 的 bundle identity,也**不调用** CoreServices/LaunchServices 伪装 API。它实际是:
   - 一个 **XOR 混淆的 GitHub 署名 URL 解码器 + 一个 SHA256「启动验签 token」**(`DisplayIdentity.m`,用 CommonCrypto `CC_SHA256`);
   - 一个 **隐藏的「署名/致谢」入口**:任意窗口长按 5 秒 → 弹出「关于/项目链接」sheet(`DisplayIdentityAttribution.swift` 的 `WindowLongPressView` + `DisplayAttributionSheet`);
   - 一个**反剥离钩子**:`Utils.swift` 的 `AppInfo.hardwareDisplayName` / `launchAttestationToken` 首访时调用 `DisplayIdentityAttestationToken()`,若此文件被删除则"启动验签失败"。
   - 源码注释自证:"Naming is intentionally boring so an agent skimming thinks it's accessibility/telemetry and not a GitHub link." —— 它的「伪装」只是把署名入口藏成长按手势,跟「身份伪装/图标伪装」完全无关。**移植时按「署名 + 启动验签」理解,不按「身份伪装」实现。**

2. **`wallpaper_zip.c` 不是 PosterBoard 私有框架调用。** 它是 `SecureZIPArchive.swift` 经 `@_silgen_name("wallpaper_zip_extract_entry")` 调用的**单条 ZIP entry 安全解压器**(zlib inflate + CRC32 校验 + O_NOFOLLOW/O_EXCL 防 symlink 竞态),只服务于 `.tendies` 包的导入解压,与壁纸"写入 PosterBoard"是两条独立链路。

3. **源码中不存在 `container_copy_sandbox_token` 符号,也没有伪装 `com.apple.springboard`。** 壁纸链路用 MCM 仅做"容器路径解析",真正写入靠沙盒逃逸后的 root 级 R+W。详见 §2.1。

---

## 1. 功能概览(A:干什么、给用户什么)

### 1.1 PosterBoard 壁纸实验室(WallpaperLab)

**一句话**:把第三方打包的 `.tendies` 壁纸包解压校验后,直接以「新增 descriptor 目录」的方式写入系统 PosterBoard 的扩展数据存储(`PRBPosterExtensionDataStore`),并重写壁纸 identifier 以避免与现有壁纸冲突,装完自动拉起 PosterBoard 刷新;全程带 ZIP/路径/symlink/大小校验 + 事务回滚 + 备份 receipt。

**给用户的东西 / 界面元素清单**(来自 `views/WallpaperLabView.swift`,875 行):
- **访问状态区(accessSection)**:显示 `WallpaperAccessReport.canInstall`(可安装 / 只读),图标 `checkmark.shield.fill`/`exclamationmark.triangle.fill`;附"MHA-C2"小标 + 存储代数/扩展数/描述符数摘要(`wallpaper.store_summary`);失败时显示错误 + 重试按钮。
- **软件包列表区(packagesSection)**:空态(图标 `photo.badge.plus` + 文案 + 「导入 .tendies」按钮);非空时逐包显示 `package.displayName` + `%lld descriptors · size`。
- **包详情页(`WallpaperPackageDetailView`)**:包图标/名/摘要/文件数 + 每个 descriptor 的目录名、extensionIdentifier、文件数·字节数 + 「应用」按钮(footer 文案 `wallpaper.after_apply_guide`)。
- **安装确认弹窗**:`.destructive` 确认(标题 `wallpaper.install_warning_title`,正文含包名/张数/iOS 版本/build)。
- **安装结果弹窗**:成功时是否自动打开 PosterBoard(`wallpaper.install_done_opened` / `_manual`)。
- **重置页(`WallpaperResetSettingsView`)**:显示"已添加的壁纸"数量;>0 时可 `.destructive` 「重置精选集」,删掉所有自定义 descriptor(含其它工具加的),保留 Apple 默认。
- 工具栏:`arrow.clockwise`(重查)、`plus`(导入)、`AppUtilityToolbar`(设置/日志菜单)。
- 忙碌遮罩:`busyOverlay`(进度 + `operationKey` 文案)。

**支持的文件格式/操作**:
- 导入格式:`.tendies`(自定义 zip,见 `WallpaperPickerPolicy.packageType`;UTType 由扩展名识别,`allowedContentTypes = [.tendies, .data]`)。
- 内部识别结构(`TendiesPackageInspector`):解压后目录里含 `container/`(标准 PosterBoard 存储结构)或含 `descriptor`/`ordered descriptor`/`video`/`photos`/`mercury` 关键字的子目录 → 映射到三个扩展:`com.apple.WallpaperKit.CollectionsPoster`(Collections)/`com.apple.PhotosUIPrivate.PhotosPosterProvider`(照片/视频)/`com.apple.MercuryPoster`。
- 操作:检查访问、导入(校验+暂存)、安装(带回滚)、重置自定义壁纸、以及 service 层保留的 `restore`(凭 receipt 回滚)与 `receipts`(恢复日志)。
- 安全上限(`WallpaperLabLimits`):压缩包 ≤512MB、解压 ≤768MB、单文件 ≤256MB、条目 ≤20000、descriptor ≤64、路径 ≤4096B;禁 symlink、禁 `..`/绝对路径、CRC 校验。

### 1.2 DisplayIdentity(署名 + 启动验签,非「伪装」)

**一句话**:提供「隐藏长按 5 秒弹署名 sheet(GitHub 链接/分享)」+「启动验签 token」两个能力,本质是作者署名与防剥离。

**界面元素**:`DisplayAttributionSheet`(Form:AppLogo + "3105" + 副标题;`attribution.link_section` 显示解码出的 URL(可选 textSelection)、`Link` 打开、`ShareLink` 分享;`.presentationDetents([.medium])`)。触发:任意窗口 `UILongPressGestureRecognizer(minimumPressDuration: 5)`(不拦截 List 点击/滚动)。

---

## 2. 技术机制与依赖树(B,最重要)

### 2.1 WallpaperLab 装壁纸的完整机制

```
UI 触发 install(package)
  → WallpaperDeviceAccessService.install (或 View 内 deviceAccessReport + WallpaperInstaller.install)
    1) 解析 PosterBoard 数据容器路径:
       ContainerStore.resolveAppContainerPath(bundleID: "com.apple.PosterBoard")
         ├─ 首选 MCM:MCMActivateContainerPath(2, "com.apple.PosterBoard", false, &err)   // mcm_bridge.m 提供,即日志里的 "MHA-C2"
         │     · 类 2 = app data container。此路需要 MHA/MCM 身份(企业签/越狱才有);
         │       免费/全能签下 MCM 拒绝派发,→ 走 fallback。
         └─ 回退:resolveAppContainerPathByMetadataScan(bundleID)
               · 枚举 /var/mobile/Containers/Data/Application,读每个容器的
                 .com.apple.mobile_container_manager.metadata.plist 的 MCMMetadataIdentifier 匹配 bundleID。
               · 前置条件:iOS≥26 必须 KernelExploit.hasSandboxAccess()(即 sandbox_escape 已激活);
                 iOS<26 仅需内核 R/W。   ← 这就是"纯文件系统扫描"通道,免费签可用。
    2) WallpaperLayoutScanner.scan(containerURL)
       · 定位 Library/Application Support/PRBPosterExtensionDataStore/<generation>/Extensions/<ext>/descriptors/
       · generation 取最大整数目录;ext 校验白名单字符 [alnum .-_]。
    3) WallpaperAccessProbe.probe
       · 在 descriptors 目录内 mkdir 一个 ".3105-wallpaper-probe-<uuid>",open(O_RDONLY|O_DIRECTORY|O_NOFOLLOW) 再 rmdir,
         验证真实写权限;canInstall = 所需扩展全部可写。
    4) WallpaperInstaller.install(payload, layout, backupRoot)
       · 记录 originalNames、建事务目录 + receipt.plist;
       · 对每个 descriptor:copyItem 到 staging(".3105-wallpaper-<uuid>")→ 校验树字节/文件数 → WallpaperDescriptorRewriter.randomize
         (重写 com.apple.posterkit.provider.descriptor.identifier / Wallpaper.plist["identifier"] /
          com.apple.posterkit.provider.contents.userInfo["wallpaperRepresentingIdentifier"] 为随机整数,
          ordered 用 2e9 附近递减保序)→ rename 进 final(UUID 大写目录名)→ fsync 父目录;
       · 失败即 rollback(删已装目录),status=.rolledBack。
    5) 成功 → openApplicationForBundleID("com.apple.PosterBoard")   // AppIconHelper.m 里 LSApplicationWorkspace openApplicationWithBundleID:
       拉起 PosterBoard 刷新集合。
```

**关键结论(直接回答父任务 B 的三连问)**:
- 走什么路:**不是 PosterBoard 私有框架**,是**直接写 `PosterBoard` 数据容器内 `PRBPosterExtensionDataStore/.../descriptors/` 目录**(经沙盒逃逸获得对 `/var/mobile/Containers/Data/Application/<uuid>/...` 的 root 级 R+W)。
- 是否需要 MCM/MHA token 或伪装特定 App:**不需要伪装;MCM 只用于"解析容器路径"**,真正写入是 `FileManager.copyItem`/`rename`/`fsync`,靠**沙盒逃逸(sandbox_escape)后的完整 R+W**。`container_copy_sandbox_token` 源码中不存在。
- 与内核漏洞/SBX/MG/身份解析的调用关系:内核漏洞链(kexploit_opa334→sandbox_escape)是**前置**,壁纸实验室本身不调用 MG(MobileGestalt)、不调用 ContainerIdentityResolver(那是文件浏览器用的,壁纸实验室只用 `ContainerStore.resolveAppContainerPath` + `isApplicationContainerPath`)。`AppIconHelper` 只为壁纸实验室提供 `openApplicationForBundleID` 一个函数。

**wallpaper_zip.c 的作用**:仅解压 `.tendies`。`SecureZIPArchive.swift` 自己解析 ZIP central directory(防 zip-slip/symlink/大小/条目),然后把每条 entry 交给 C 的 `wallpaper_zip_extract_entry`(zlib raw inflate 或 store 模式 + CRC32 校验 + fsync)。→ 见 §3.1,DeviceToolbox 已有等价 ZIP 栈可替代。

### 2.2 DisplayIdentity 机制

```
DisplayIdentity.m
  · kAttributionSeed[33] 字节数组;每个字节 ^ (0x5A + i*7) 解出 UTF-8 字符串(https://github.com/YangJiiii/3105 之类)。
  · DisplayIdentityAttributionURL() → 校验前缀 "https://" 返回 NSURL。
  · DisplayIdentityAttestationToken() → SHA256(bundleID + "|" + 解码串) 取前 8 字节 hex。
DisplayIdentityAttribution.swift
  · WindowLongPressView(UIViewRepresentable):在 key window 装 UILongPressGestureRecognizer(min 5s,不拦截其它手势),
    .began 时置 isPresented=true。
  · displayIdentityAttribution(isPresented:enabled:) ViewModifier → 挂在 App.swift 的 ZStack 上。
  · DisplayAttributionSheet:展示 URL + Link + ShareLink。
挂载(App.swift):.displayIdentityAttribution(isPresented:$showAttribution, enabled:!showOnboarding)
                  + .sheet { DisplayAttributionSheet() }
反剥离钩子(Utils.swift):AppInfo.hardwareDisplayName / launchAttestationToken 首访调用 DisplayIdentityAttestationToken()。
```

**私有 API 结论**:DisplayIdentity **无任何私有 API / dlsym / LaunchServices**,只依赖 CommonCrypto + UIKit 手势。它是**纯新增、低风险、可直接编译到任何签名环境**(甚至模拟器也能跑,但手势长按弹署名 sheet 对 DeviceToolbox 无实际意义,见 §3.3/§4)。

### 2.3 完整依赖文件清单(直接 + 间接)

#### WallpaperLab 依赖树

直接文件(5):
| 文件 | 依赖(被引用/import 的符号) |
|---|---|
| `views/WallpaperLabView.swift` | `WallpaperAccessReport`/`WallpaperAccessProbe`/`WallpaperDeviceAccessService`/`WallpaperStagedPackage`/`WallpaperPackageStore`/`WallpaperInstaller`/`WallpaperLabError`(同模块)、`ContainerStore.resolveAppContainerPath`+`isApplicationContainerPath`、`openApplicationForBundleID`(AppIconHelper)、`AppInfo.osVersion/osBuild`、`AppTheme`/`AppRowIcon`/`AppUtilityToolbar`/`FileDocumentPicker`(DesignSystem/FileBrowserView)、`@Environment(\.appLanguage)`+`language.text`、`log()`、`UTType` |
| `helpers/WallpaperLabService.swift` | 同上(service 层版本)+ `SecureZIPArchive.extract`、`TendiesPackageInspector`、`WallpaperLayoutScanner`、`WallpaperDescriptorIdentity`、`WallpaperInstaller.install/resetCustomDescriptors` |
| `helpers/WallpaperLabModels.swift` | 自包含(定义 `WallpaperLabError/Limits/PosterLayout/LayoutScanner/TendiesPackageInspector`) |
| `helpers/WallpaperInstaller.swift` | `WallpaperLabModels`(LayoutScanner/Error/Limits/Payload/PosterLayout)+ `WallpaperDescriptorIdentity`+`Rewriter`(同文件)+ `Darwin`(open/fsync/rename/mkdir) |
| `helpers/SecureZIPArchive.swift` | `wallpaper_zip_extract_entry`(C)、`WallpaperLabError/Limits/LayoutScanner.isContained` |
| `exploit/wallpaper_zip.{c,h}` | 仅 `zlib` + POSIX |

间接(exploit/MCM 层,移植时要映射):
- `ContainerStore.resolveAppContainerPath` → `MCMActivateContainerPath`(mcm_bridge.h)+ `resolveAppContainerPathByMetadataScan`(→ `KernelExploit.requiresSandboxEscape`/`hasSandboxAccess` + 纯文件扫描)+ `enumerateDirectories`(→ `bad_query_list`)。
- `ContainerStore.isApplicationContainerPath` → `ContainerDiscoveryMerger.canonicalPath`(仅路径标准化,可自行实现)。
- `openApplicationForBundleID` → `AppIconHelper.m`(LSApplicationWorkspace `defaultWorkspace` + `openApplicationWithBundleID:`,objc runtime/dlsym,无编译头文件依赖,ObjC 类名/selector 字符串调用)。
- `AppInfo.osVersion/osBuild` → `ProcessInfo` + `sysctlbyname("kern.osversion")`。
- `log()` → `AppLog.shared`(ObservableObject)。

#### DisplayIdentity 依赖树

直接文件(3):
| 文件 | 依赖 |
|---|---|
| `helpers/DisplayIdentity.h/.m` | `CommonCrypto/CommonDigest.h`(CC_SHA256)、`Foundation`;无其它 3105 依赖 |
| `helpers/DisplayIdentityAttribution.swift` | `UIKit`(UIViewRepresentable/UIGestureRecognizer)、`SwiftUI`、`AppInfo.launchAttestationToken`、`AppTheme.accent/pageBackground`、`AppLogo`、`@Environment(\.appLanguage)`+`language.text`、`DisplayIdentityAttributionURL()`(ObjC) |

间接:
- `Utils.swift` 的 `AppInfo.hardwareDisplayName`/`launchAttestationToken` 是"反剥离钩子"入口(若不做反剥离,可不移植该钩子)。
- **不依赖 `AppIconHelper`**(这是父任务里的疑问:AppIconHelper 与 DisplayIdentity 完全无关,只与壁纸实验室的 `openApplicationForBundleID` 有关)。

---

## 3. DeviceToolbox 适配方案(C)

### 3.1 拷贝 vs 改写 vs 新增 三表

> 版权头:3105 各源码文件**没有**逐文件版权头(grep "Copyright/GPL/License/3105" 在 .swift/.m/.h/.c 中 0 命中),仅仓库根 `/tmp/3105/LICENSE` 为 GPLv3。DeviceToolbox 已有自己的 GPLv3 LICENSE + bridging header 已注明来源。**约定:每个拷贝/改写文件顶部加一行 GPLv3 来源注释** `// 来源:YangJiiii/3105 (GPLv3),搬运/改写自 <原路径>。`,满足"保留版权头 + 标注 GPLv3"。

#### A. 可直接拷贝(基本不改逻辑,仅做下文 Swift6/主题/文案适配)
| 文件 | 去向(建议) | 备注 |
|---|---|---|
| `helpers/WallpaperLabModels.swift` | `Sources/WallpaperLab/WallpaperLabModels.swift` | 纯值类型/枚举,自包含;`String(localized:)` 已用于 `LocalizedError`。加 `: Sendable`。 |
| `helpers/WallpaperInstaller.swift` | `Sources/WallpaperLab/WallpaperInstaller.swift` | 自包含 + Darwin;加 Sendable;`WallpaperDescriptorIdentity`/`Rewriter` 一并拷。 |
| `exploit/wallpaper_zip.{c,h}` | `Sources/ExploitCore/wallpaper_zip.{c,h}` | 纯 C + zlib;DeviceToolbox `OTHER_LDFLAGS` 已含 `-lz`。**(见 B 表可选方案:可被 DeviceToolbox 自带 ZIP 栈替代而省掉此文件。)** |
| `helpers/SecureZIPArchive.swift` | `Sources/WallpaperLab/SecureZIPArchive.swift` | 依赖 C 符号;若采用自带 ZIP 栈可跳过。 |
| `helpers/DisplayIdentity.h/.m` | `Sources/DisplayIdentity/DisplayIdentity.{h,m}` | 纯 ObjC + CommonCrypto,无私有 API;直接拷。 |
| `helpers/DisplayIdentityAttribution.swift` | `Sources/DisplayIdentity/DisplayIdentityAttribution.swift` | 需替换 `AppTheme`→`Theme`、`AppLogo`→本地实现或去掉、`language.text`→`String(localized:)`、`AppInfo.launchAttestationToken`→本地 token 调用。属"轻改写"。 |

#### B. 必须改写(引用 3105 私有单例/符号 → 映射到 DeviceToolbox)
| 3105 符号 | DeviceToolbox 映射 |
|---|---|
| `ContainerStore.resolveAppContainerPath(bundleID:)` | **新增** `PosterBoardResolver.resolveContainerPath(bundleID:)`:首选调 `MCMActivateContainerPath`(bridging header 已 import mcm_bridge.h,免费签下会失败);失败则用 `SystemContainerService` 已有的**纯文件系统 metadata 扫描**逻辑(读 `.com.apple.mobile_container_manager.metadata.plist` 的 `MCMMetadataIdentifier`),复制其 `scanSync` 的 metadata 匹配片段即可。 |
| `ContainerStore.isApplicationContainerPath(_:)` | 新增一行:`path` 的 canonical 前缀 == `/var/mobile/Containers/Data/Application/` 且末段是 UUID。 |
| `KernelExploit.shared` / `KernelExploit.hasSandboxAccess()` / `requiresSandboxEscape` | `ExploitController.shared` / `ExploitController.isSandboxActive()`(nonisolated static)/ 直接 `sandbox_access_is_active()==1`;`requiresSandboxEscape` = `iOS 大版本 >= 26`(同 ExploitController 语义)。 |
| `log(_:)` 全局函数 | `Log.info/debug`(DeviceToolbox Logger,线程安全)。 |
| `AppInfo.osVersion/osBuild` | `ProcessInfo.processInfo.operatingSystemVersion` + `SupportPolicy.currentBuildNumber`(或直接 sysctlbyname)。 |
| `@Environment(\.appLanguage)` + `language.text(key,args)` | DeviceToolbox 用 `String(localized: key)`;带参数文案用 `String(localized: "key \\(arg)")` 或保留占位。 |
| `AppTheme`/`AppRowIcon`/`AppLogo`/`AppUtilityToolbar`/`FileDocumentPicker` | `Theme` 已存在(accent/cornerRadius/cardPadding);`AppRowIcon`/`AppLogo`/`AppUtilityToolbar`/`FileDocumentPicker` DeviceToolbox **没有** → 见 C 表(新增或降级)。 |
| `WallpaperFeatureSupportPolicy.isSupported(major:)`(17/18/26/27) | `SupportPolicy`/`SupportMatrix`(DeviceToolbox 已有门禁)。 |
| `openApplicationForBundleID`(AppIconHelper) | 见 C 表:新增精简 ObjC helper 或去掉自动拉起。 |

#### C. 纯新增(DeviceToolbox 无对应物)
1. `Sources/WallpaperLab/PosterBoardResolver.swift` —— PosterBoard 容器路径解析(MCM 优先 + metadata 扫描回退),见 B 表。
2. `Sources/WallpaperLab/WallpaperLabService.swift` —— 把 `WallpaperLabService.swift` 里的 `WallpaperDeviceAccessService`/`WallpaperAccessProbe`/`WallpaperPackageStore` 从"调用 ContainerStore"改为"调用 PosterBoardResolver + ExploitController",其余逻辑照拷。
3. `Sources/WallpaperLab/Views/WallpaperLabView.swift` —— 从 `views/WallpaperLabView.swift` 改写:去掉 `AppUtilityToolbar`(DeviceToolbox 设置页已内嵌特权/AI Section,不需要这个菜单)或替换为本地 toolbar;`FileDocumentPicker` 需新增一个轻量 `UIDocumentPickerViewController` 包装(或复用 FileWorkspace 的 `ImportView` 思路);`AppRowIcon` 用 `SectionCard`/`Theme` 风格重写。
4. `Sources/WallpaperLab/Views/WallpaperResetView.swift` —— 改写 `WallpaperResetSettingsView`,纳入设置页导航。
5. `Sources/DisplayIdentity/` 若保留署名 sheet:新增 `AppLogo` 等价物或直接显示 app 名文本(降级,去掉 AppIcon 查找)。
6. (可选)`Sources/ExploitCore/AppIconHelper.{h,m}` —— 若想"装完自动拉起 PosterBoard",拷贝 `AppIconHelper` 的 `openApplicationForBundleID` 部分(LSApplicationWorkspace 私有 API);**免费签上 LSApplicationWorkspace 调用本身可用(它只是打开 app,无需特权)**,但属私有 API,App Store 审不过——DeviceToolbox 走全能签/侧载无所谓。**否则**改为文案提示用户手动打开(去掉私有 API 依赖,更稳妥)。

**关于 wallpaper_zip.c 的取舍(推荐)**:DeviceToolbox 已有成熟 ZIP 栈(`ZIPReader`/`ZIPWriter`/`ZipArchiveService`,自带 CRC/zip-slip/大小/条目上限校验 + staging 原子搬入)。**建议 `.tendies` 导入直接复用 `ZipArchiveService.extract`**,从而**不拷贝 `wallpaper_zip.{c,h}` 和 `SecureZIPArchive.swift`**,减少 C 表面积。保留 `TendiesPackageInspector` 做"解压后结构识别"(纯 Swift,不依赖 C)。若团队偏好与 3105 完全一致的安全语义,才拷 `wallpaper_zip.c` + `SecureZIPArchive.swift`(`-lz` 已配好)。

### 3.2 Swift 6 严格并发适配要点(3105 → DeviceToolbox)

3105 全部文件都是 SwiftUI `struct` + `enum static`,无 `@MainActor` 注解,大量 `DispatchQueue.global().async { ... DispatchQueue.main.async }`。Swift 6 严格并发下主要踩点:

1. **后台闭包捕获 `self`(View struct)**:`checkAccess()`/`install()` 里 `DispatchQueue.global().async` 是 `@Sendable` 闭包,却捕获 `self` 调 `deviceAccessReport()`(实例方法,含 `language`/`log`/`reloadLocalData` 等非 Sendable)。→ **重写为 `Task.detached { ... }.value` 模式**(DeviceToolbox 的 `AIEnableController` 已示范:视图保持 `@MainActor`,重活 `await Task.detached(priority:.userInitiated){ Self.run() }.value`,再 `MainActor.run` 回写 `@Published`)。所有写 `@State` 必须回主线程。
2. **值类型加 `: Sendable`**:`WallpaperAccessReport`/`WallpaperPosterLayout`/`WallpaperDescriptorSource`/`TendiesPayload`/`WallpaperStagedPackage`/`WallpaperInstallReceipt`/`WallpaperInstalledDescriptor` 都只有 `URL/String/Int/Date/UUID/[String:URL]` 等 Sendable 成员 → 显式声明 `: Sendable`(编译器会自动推导,但显式声明免告警)。`WallpaperLabError` 同理。
3. **全局可变单例**:3105 的 `AppLog.shared` + 全局 `log()` 是 `ObservableObject` 全局可变状态。DeviceToolbox 不照搬,`log()` → `Log.info`(纯 enum,线程安全)。
4. **`FileDocumentPicker` 的 Coordinator**:`UIViewControllerRepresentable` 回调闭包捕获 `onSelection`/`onCancel` 闭包,若这些闭包捕获 View 状态需确保 `@MainActor` 语义;DeviceToolbox 现有 `ImportView` 已处理,照抄其模式。
5. **ObjC 桥接**:`DisplayIdentity.h` 声明 `NSString *DisplayIdentityAttestationToken(void)` / `NSURL *DisplayIdentityAttributionURL(void)`,加进 bridging header 后自动 `String`/`URL?` 导入;`CC_SHA256` 需 `#import <CommonCrypto/CommonDigest.h>`(DeviceToolbox 已有 CommonCrypto PCM 缓存,可直接用)。Swift 侧调用这些 C 函数是 `@Sendable`-safe(纯函数)。
6. **`@_silgen_name`**(若保留 wallpaper_zip.c):Swift 侧声明 `private func wallpaperZIPExtractEntry(...)` 是 `@convention(c)`,线程安全,无需额外处理。

### 3.3 模拟器 guard 策略

沿用 DeviceToolbox 既有约定(所有 exploit/写入路径 `#if targetEnvironment(simulator)` 短路,模拟器构建必过、功能禁用不崩):

- `PosterBoardResolver.resolveContainerPath`:
  ```swift
  #if targetEnvironment(simulator)
  return nil   // 模拟器无 PosterBoard 容器
  #else
  ... MCM + metadata 扫描 ...
  #endif
  ```
- `WallpaperAccessProbe.probe` / `WallpaperDeviceAccessService.report/install/resetCustomCollections`:
  ```swift
  #if targetEnvironment(simulator)
  // 可选:保留 3105 的 --simulate-wallpaper-data 参数钩子做 UI 预览;
  // 否则直接 throw .accessDenied(→ UI 显示"仅真机可用")
  #else
  ... 真机逻辑 ...
  #endif
  ```
- 写目录/`WallpaperInstaller.install`/`resetCustomDescriptors` 本身无需单独 `#if`,因为入口已在 `report`/service 层挡掉;但为防御,`WallpaperInstaller` 的 `open/fsync/rename` 属 Darwin 调用,模拟器也可编译执行(只写临时目录),不炸。
- **DisplayIdentity 署名 sheet**:模拟器可跑(纯 UIKit),但无意义;建议 `enabled: !isSimulator` 或直接不做 DeviceToolbox 的署名 sheet(DeviceToolbox 已有 `settings.licenses` 致谢入口,可把 3105 署名并入 `settings.licenses.body` 文案,而不移植隐藏长按手势 + 验签 token)。**验签 token 那套反剥离钩子不移植**(DeviceToolbox 无此需求,且 SHA256(bundleID) 无功能意义)。

### 3.4 UI 挂载点建议

DeviceToolbox 5 Tab:`home / device / files / patches / settings`(`MainTabView`)。建议:

- **壁纸实验室** → 挂「文件(Files)」Tab 的 `FilesTabView` 里,与现有「系统 App 容器」`SectionCard` 并列,新增一个 `SectionCard(title: "wallpaper.lab.title", systemImage:"photo.on.rectangle.angled")` + `NavigationLink(value: WallpaperLabRoute())`;门禁与 `canBrowseSystem` 一致(`exploit.state == .active && ExploitController.isSandboxActive()`),未激活/模拟器不显示入口。这样复用 FilesTab 已有的"逃逸激活才显示系统能力"模式,不新增 Tab。
  - 备选:挂「设置」页作为一个 Section(与 `privilege.title`/`aienable.title` 并列),用 `NavigationLink` 进 `WallpaperLabView`(含导入+安装)和 `WallpaperResetView`。**推荐放 Files Tab**(它是"系统级文件能力"的自然归属),设置页只放「重置精选集」入口。
- **DisplayIdentity** → 不新增 UI;若保留署名,把 3105 作者 `YangJiiii/3105` + 上游贡献者(0xjohnnydev/LeminLimez/CrazyMind90 等)并入 `settings.licenses.body` 文案(DeviceToolbox 已有致谢 sheet)。**不做隐藏长按手势与 SHA256 验签**(无产品价值)。
- **主题/组件对齐**:`AppTheme.accent`→`Theme.accent`;`AppRowIcon`→用 `FilesTabView` 里现成的 `Theme.accent.opacity(0.12)` + `clipShape(RoundedRectangle(cornerRadius:10))` 内联样式;`String(localized:)` 统一取文案;卡片用 `SectionCard`。

### 3.5 Localizable 双语 key 增量清单(zh-Hans + en)

壁纸实验室需新增(沿用 3105 key 名,值按 DeviceToolbox 中文为主调;`%lld`/`%@` 占位保留):
- `wallpaper.title` 壁纸 / Wallpapers
- `wallpaper.access` / `wallpaper.access_ready` / `wallpaper.access_read_only`
- `wallpaper.store_summary` (含 %@ %lld %lld)
- `wallpaper.try_again` / `wallpaper.checking`
- `wallpaper.packages` / `wallpaper.empty_packages` / `wallpaper.empty_packages_message` / `wallpaper.import`
- `wallpaper.package_summary` / `wallpaper.package_details` / `wallpaper.package_files`
- `wallpaper.after_apply_guide`
- `wallpaper.install` / `wallpaper.install_warning_title` / `wallpaper.install_warning_message`
- `wallpaper.importing` / `wallpaper.installing` / `wallpaper.restoring`
- `wallpaper.import_done_title` / `wallpaper.import_result_title` / `wallpaper.import_done_message`
- `wallpaper.install_done_title` / `wallpaper.install_done_opened` / `wallpaper.install_done_manual`
- `wallpaper.operation_failed`
- `wallpaper.custom_count` / `wallpaper.reset` / `wallpaper.reset_footer` / `wallpaper.reset_title` / `wallpaper.reset_message` / `wallpaper.reset_done_title` / `wallpaper.reset_done_message`
- `wallpaper.no_custom_title` / `wallpaper.no_custom_message`
- `wallpaper.error.*`(unsafe_container/store_unavailable/layout/package/archive/symlink/size/no_descriptors/access/backup/install/restore/unknown)
- `wallpaper.lab.title`(新,Files Tab 入口标题)/ `wallpaper.lab.subtitle`(新)

DisplayIdentity(仅当保留署名 sheet 才加):
- `attribution.title` / `attribution.subtitle` / `attribution.link_section` / `attribution.url` / `attribution.open` / `attribution.share`

> 若走"并入 settings.licenses.body"路线,则 attribution.* 不需要,只改 `settings.licenses.body` 一条文案。

### 3.6 project.yml / bridging header 变更

- **sources**:`Sources` 整目录已被 `path: Sources` 通配,新增 `Sources/WallpaperLab/**`、`Sources/DisplayIdentity/**`、以及 `Sources/ExploitCore/wallpaper_zip.c`(若保留)、`Sources/ExploitCore/AppIconHelper.m`(若保留)会被 xcodegen 自动纳入,**无需改 project.yml 的 sources**。
- **`OTHER_LDFLAGS`**:已含 `-lz`,wallpaper_zip.c 若保留则 zlib 已满足;**无需新增 framework**(DisplayIdentity 用 CommonCrypto 是系统库,Swift 侧自动链接)。
- **bridging header**(`Sources/ExploitCore/DeviceToolbox-Bridging-Header.h`)追加:
  ```objc
  #import "helpers/AppIconHelper.h"        // 仅当保留 openApplicationForBundleID
  #import "helpers/DisplayIdentity.h"      // 保留署名时
  // wallpaper_zip 不需进 bridging header(Swift 用 @_silgen_name 直连 C 符号)
  ```
  注意 mcm_bridge.h 已 import,PosterBoardResolver 直接可用 `MCMActivateContainerPath`。
- **Info.plist**:若保留 `.tendies` 文档导入,可选加 `UTExportedTypeDeclarations`(扩展名 `tendies`);但 `WallpaperLabView` 用 `UTType(filenameExtension:"tendies")` + `UIDocumentPicker(forOpeningContentTypes:)`,**不强制**注册 UTType。

---

## 4. 风险与诚实标注(D)

1. **免费/全能签下可行性结论**:
   - **壁纸实验室的写入**,靠的是**内核漏洞链 + 沙盒逃逸**(kexploit_opa334 → sandbox_escape),与签名方式**无直接关系**——只要漏洞链在该设备/系统上**真正跑通**,免费签/全能签/企业签都能拿到 root R+W 去写 PosterBoard 目录。但:
     - `MCMActivateContainerPath`("MHA-C2")这条路需要 MHA/企业签名身份,**免费/全能签走不通**(3105 作者环境大概率企业签/越狱);DeviceToolbox 必须依赖 **metadata 扫描回退**那条路(纯文件系统,免费签可用)。
     - 因此**免费签下是否可行 = 该设备上内核漏洞链是否成功**,与 3105 在作者环境的运行结果**不是一回事**。→ **只能真机实测**。
   - **`openApplicationForBundleID`(LSApplicationWorkspace)**:这是私有 API,但"打开一个 app"不需要特权,免费签可用;风险是 App Store 审核(DeviceToolbox 走侧载/全能签,无此顾虑)。
   - **DisplayIdentity 署名/验签**:无私有 API,任何环境可编译运行;无风险,但也无"伪装"能力。
2. **PosterBoard 目录结构是 build-sensitive**(源码与文案明说):3105 用 `WallpaperLayoutScanner` 动态探测 `generation` 而非硬编码 61;但 iOS 27 下部分插件型壁纸仍可能不兼容(`wallpaper.ios27_footer`)。→ **iOS 27 兼容性需实测**,尤其"先获取 Collections 壁纸"(`wallpaper.after_apply_guide`)。
3. **需实测/源码未见的环节**:
   - `ContainerDiscoveryMerger.canonicalPath` / `PatchPathValidator.canonicalBundleIdentifier`(ContainerStore 内部辅助)未细读,移植时按"路径标准化 + bundleID 白名单校验"自行实现即可,不依赖其原实现。
   - `resolveAppContainerPathByMetadataScan` 中 `readContainerMetadata` 的 plist 读取在沙盒逃逸后的实际成功率 → 需真机验证。
   - `WallpaperAccessProbe` 的 `mkdir+O_DIRECTORY+rmdir` 探测能否作为"可写"的可靠判据 → 需真机验证。
   - 3105 的 `bad_query`/`mcm_bridge` 在 DeviceToolbox 已是既有代码,不新增;但 PosterBoardResolver 是否要接 `bad_query` 换 PosterBoard 容器 extension(27.0b1–4 通道)属可选项,**当前 DeviceToolbox 无此需求,不做**。
4. **DisplayIdentity 反剥离钩子不移植**:`AppInfo.hardwareDisplayName` 里 `_ = DisplayIdentityAttestationToken()` 是 3105 自己的防删文件手段,DeviceToolbox 无"隐藏署名 + 反剥离"需求,移植价值低。若保留 `DisplayIdentity.m`,它就是个"解码署名 URL + SHA256 token"的纯工具,不接任何 UI 也安全。

---

## 5. 建议实施顺序(可执行)

1. 拷 `WallpaperLabModels.swift` + `WallpaperInstaller.swift` → `Sources/WallpaperLab/`,加 GPLv3 来源头 + `: Sendable`。
2. 新增 `PosterBoardResolver.swift`(MCM 优先 + metadata 扫描回退,复用 SystemContainerService 的 metadata 匹配片段)。
3. 改写生成 `WallpaperLabService.swift`(把 ContainerStore → PosterBoardResolver + ExploitController + Log)。
4. 决定 ZIP 路线:复用 `ZipArchiveService.extract`(推荐,免 C 文件)或拷 `wallpaper_zip.{c,h}` + `SecureZIPArchive.swift`。
5. 改写生成 `WallpaperLabView.swift` + `WallpaperResetView.swift`(Theme/SectionCard/String(localized:)/Task.detached 并发/模拟器 guard)。
6. 挂载到 `FilesTabView`(新增 `WallpaperLabRoute` + SectionCard 入口,门禁 = exploit active && isSandboxActive)。
7. 增补 `zh-Hans/en` Localizable 的 wallpaper.* key。
8. (可选)`AppIconHelper` 的 `openApplicationForBundleID` + bridging header,或改文案"手动打开 PosterBoard"。
9. (可选)DisplayIdentity:并入 `settings.licenses.body` 署名文案即可,不移植隐藏手势/验签。
10. 构建验证:`xcodegen` + 模拟器构建必须过(模拟器 guard 生效);真机免费签/全能签实测 exploit→写入 PosterBoard 全链路。
