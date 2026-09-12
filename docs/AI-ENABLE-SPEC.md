# DeviceToolbox · Apple Intelligence 在机强开集成设计 spec-part2

> 调研对象:mond(iOS 27.0 b1–4)、EnsWilde(iOS 26.2b1)、misaka26 / Nugget 7.2(iOS 26.x)、MisakaX/Nugget(iOS 16–18)、3105(已集成)。
> 结论以**已读源码**为准;标注「需实测」处为无真机验证、不可下定论的部分。全文不复制任何 AGPLv3 代码,只提炼事实(路径/键名/机制)与设计。

---

## 0. 一句话结论

- iOS 26.x 与 27.0b1–4 在机强开的**落点**都是同一套两个文件:
  1. MobileGestalt 缓存:`/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist`
  2. AI 资格表:`/var/db/eligibilityd/eligibility.plist`(GREYMATTER = Apple Intelligence 域)
- 获得**写权限**的手段在 26 与 27 不同:
  - **27.0b1–4(mond)**:在机 `bad_query`(containermanager 沙盒查询漏洞,forcequit)或 `cmg`(MCM bug 类,johnny)→ 换出 mobilegestaltcache 的 sandbox extension → 直接 `open(O_RDWR)` 覆盖。**全程在机、无需 PC**。
  - **26.x(misaka26 / Nugget 7.2)**:PC 侧 SparseRestore 路径逃逸写文件(需 PC 与 pairing),非在机漏洞链。
- DeviceToolbox **已经拥有**在机写这两类文件所需的一切:`bad_query.c` + `mcm_bridge.m`(ExploitCore,源自 3105 GPLv3)就是 mond 同款 MCM 逃逸;`sandbox_escape()`/`sandbox_access_is_active()`/`kexploit_opa334()` 提供内核级兜底。因此 AI 强开可**纯在机**实现,这是本模块相对 misaka26/Nugget 的独特价值。

---

## A. iOS 26.x / 27.0b1–4 在机强开完整机制与文件操作清单

### A.1 目标文件(已多方交叉印证)

| 用途 | 路径 | 写入内容 | 来源 |
|---|---|---|---|
| MobileGestalt 缓存 | `/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist`(=`/private/var/...`,`/var`→`/private/var` 同一文件) | 改 `CacheExtra` 里的 AI 能力键 + `ProductType` 伪装 | mond `TweakPaths.gestalt`、Nugget `basic_plist_locations.py`(`mga`)、apple-intelligence 18.1 指南、EnsWilde `onDeviceMGPath`(字节混淆后同一路径) |
| AI 资格(eligibilityd) | `/var/db/eligibilityd/eligibility.plist` | `OS_ELIGIBILITY_DOMAIN_GREYMATTER` + `OS_ELIGIBILITY_DOMAIN_CALCIUM` | Nugget `eligibility_tweak.py::AITweak`、apple-intelligence 18.1 指南、EnsWilde `Resources/eligibility.plist` |
| 地区/EU 资格(OSEligibility,别混淆) | `/var/db/os_eligibility/eligibility.plist` + OSEligibility MobileAsset `Config.plist`(两个 asset 哈希路径) | 地区枚举改写 | Nugget `eligibility_tweak.py::EligibilityTweak`(EU Enabler) |

> 注意区分两套 eligibility:**`/var/db/eligibilityd/eligibility.plist` 管 AI 资格(GREYMATTER)**;`/var/db/os_eligibility/eligibility.plist` 管地区/EU(OSEligibility 框架)。任务描述里两条路径都对,但 AI 强开只写前者 + gestalt;国行地区锁需要同时动 gestalt 的 RegionCode + 前者。

### A.2 写入权限(在机,27.0b1–4 的 mond 实测机制)

mond 提供两种方法,默认 `bad_query`:

**方法 1 — `bad_query`(forcequit 的 containermanager 沙盒查询漏洞)**
流程(`cmg` 之外的主路径,见 mond `helpers/sbx.swift` + `exploit/unsbx.swift`,与 3105 `exploit/bad_query.c` 完全同源):
1. `dlopen("/usr/lib/system/libsystem_containermanager.dylib")`;
2. `container_query_create()` → `container_query_set_class(query, 13)`(系统组容器类)→ `container_query_set_group_identifiers("systemgroup.com.apple.mobilegestaltcache")`;
3. `container_query_operation_set_part(query, 3)` + `container_query_operation_set_part_domain("../../../../../../../..<gestalt_dir>")`(路径穿越);
4. `container_query_operation_set_flags(query, 0x0000008000000000)`;
5. `container_query_get_single_result(query)` → `container_copy_sandbox_token(res)` → `sandbox_extension_consume(token)` → 返回一个**已激活的 sandbox extension 句柄**;
6. 之后用普通 `open(path, O_RDWR|O_CLOEXEC|O_NOFOLLOW)` 即可写该目录下的文件。

**方法 2 — `cmg`(johnny 的 MCM bug 类)**
`container_query_create` + `container_query_operation_set_flags((1<<32)|(1<<39))` + `container_object_sandbox_extension_activate(res, true)` 直接激活。mond 里 cmg 只解锁 MobileGestalt,不支持 PosterBoard/HouseArrest。

**mond 的写盘(`helpers/mg.swift::mg_write`)**
- **原子写(默认 `atomic_write=true`)**:`open(O_RDWR|O_CLOEXEC|O_NOFOLLOW)` → 读原始内容备份 → `ftruncate(fd,0)` → `write` → `fsync` → `lseek` 回读校验 → 失败则回滚写回原始内容。**同一 inode 原地写**。
- **非原子写(`atomic_write=false`)**:写 `.tmp` 再 `replaceItemAt`/`moveItem`。
- UI 文案明确:「Persist after reboot」= 同一 inode 原地写,寄望阻止 iOS 在重启时重建缓存;非原子替换则重启后可能被 mobilegestaltd 重建。

**是否需要 root/属主处理**:mond 不 `setuid`/`chown`,只靠 sandbox extension 获得读写能力,写的是 `mobile` 属组的共享系统组容器,普通 app 进程在 extension 激活后即可写。**不需要 root**;需要的是「逃逸后获得该系统组容器的 sandbox extension」。

**是否需要 respring/reboot**:mond 写入后弹「Respring」(`neon` 的 WKWebView 内存压力 respring,见 `utils.swift::respringDocument`);部分 tweak 需要 reboot。AI 下载模型场景需要**重启后联网等待**。

**重启后是否持久 / 失败模式**:
- mond 已知问题:「Tweaks may disappear on reboot」(mobilegestaltd 可能重建缓存,原子原地写只能「hopefully」阻止)。
- 「Disable Region restrictions may be broken on some versions/devices」。
- 「Apple Intelligence spoofing doesnt work on iPhone 15」(A16) — 关键失败模式,见 B.2 分析。
- 空/非法 plist 时 UI 强提示「Do not reboot」(会 bootloop)。

### A.3 gestalt 键集合(CacheExtra 内)

| 语义(反混淆名) | 混淆键(实际 plist 里的 key) | 值 | 来源 |
|---|---|---|---|
| ProductType | `h9jDsbgj7xIVeIQ8S3/X3Q` | 伪装机型字符串,如 `iPhone16,1` / `iPhone15,4` | Nugget `generate_mga.py`、mond、EnsWilde |
| RegionCode | `h63QSdBCiT/z0WU6rdQv6Q` | `"LL"`(国行解锁) | Nugget `generate_mga.py`、EnsWilde |
| RegionInfo | `zHeENZu+wbg7PUprwNwBWg` | `"LL/A"` | Nugget `generate_mga.py`、EnsWilde |
| (mond 另用) | `yK+xavymRGZ3xWc1tb8XDg` | `"LL/A"` | mond `region_info_key`(**与 Nugget 的 `zHeENZu...` 不一致,需实测哪条是 27 的真 RegionInfo**) |
| 生成式模型能力(18.1 时代) | `A62OafQ85EJAiiqKn4agtg` | `1`(DeviceSupportsGenerativeModelSystems) | 18.1 指南、mond「Apple Intelligence」tweak、EnsWilde |
| **26.x 新明文键** | `AppleIntelligenceAllowedDevice` | `1` | misaka26 / Nugget 7.2(gist icedmoca) |
| **26.x 新明文键** | `AppleIntelligenceSupportedDevice` | `1` | 同上 |
| **26.x 新明文键** | `AppleIntelligenceMinimumRAM` | `6`(GB) | 同上 |

> 关键差异:18.1 用混淆键 `A62OafQ85EJAiiqKn4agtg`;26.x(misaka26/Nugget 7.2)用**可读明文键** `AppleIntelligenceAllowedDevice / SupportedDevice / MinimumRAM`。mond(iOS 27)仍只实现老的 `A62OafQ85EJAiiqKn4agtg`,这很可能是它在 iPhone 15(A16)上失效的原因之一(见 B.2)。

### A.4 eligibility 键(GREYMATTER = Apple Intelligence)

`/var/db/eligibilityd/eligibility.plist` 内(Nugget `AITweak` / EnsWilde `Resources/eligibility.plist` 结构一致):

```
OS_ELIGIBILITY_DOMAIN_GREYMATTER:
  os_eligibility_answer_source_t = 1
  os_eligibility_answer_t        = 4        // 4 = 已满足/eligible
  context.OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES = ["en", ...]
  status:
    OS_ELIGIBILITY_INPUT_DEVICE_LANGUAGE     = 3
    OS_ELIGIBILITY_INPUT_DEVICE_REGION_CODE  = 3
    OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE = 3
    OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM = 3   // 生成式模型系统输入
    OS_ELIGIBILITY_INPUT_SHARED_IPAD         = 3
    OS_ELIGIBILITY_INPUT_SIRI_LANGUAGE       = 3
OS_ELIGIBILITY_DOMAIN_CALCIUM:
  os_eligibility_answer_source_t = 1
  os_eligibility_answer_t        = 2
  status.OS_ELIGIBILITY_INPUT_CHINA_CELLULAR = 2   // 国行蜂窝限制绕过
```

### A.5 服务端断言(IntelligencePlatform)

搜索印证(gist `icedmoca` + misaka26 issues):
- 强开分「SPOOF → DOWNLOAD → 回退」三步:先伪装 ProductType(`iPhone16,1` 或 `iPhone15,4` 都能满足 15 系 `/v1/models` 端点),等模型下载,再回退 ProductType 保留能力键。
- `IntelligencePlatform` 守护进程对 `intelligence.apple.com/v1/models` 做**服务端断言**——这是 18.1 DB5 封掉老方法的原因,也是 26/27 能否成功的核心变量。**A16 是否真能过服务端断言,需实测**(26.1 iPhone 15 Plus 有成功报告;mond 在 27 的 iPhone 15 上报失效)。

---

## B. mond / EnsWilde 技术要点与借鉴/规避点

### B.1 mond(iOS 27.0 b1–4)
- 版本支持:27.0 dev b1–4 + public b1–2;≤26 不支持;dev b≥5 / public b≥3 不支持。
- 授权对象:`forcequit`(bad_query)、`0xjohnnydev`(MCM bug 类)、`jailbreak.party`(PartyUI/GestaltView/neon respring 实现)。
- 架构:SwiftUI + 私有 API(`dlopen`/`dlsym` containermanager & sandbox 库),`@AppStorage` 存 method/atomic_write/ignore_failure 等。
- 关键工程细节值得借鉴:
  1. **改前自动备份**:首次 `mg_load()` 就把当前 gestalt 拷到 App 的 Application Support 下 `SavedGestalt.plist`,`mg_revert()` 用它回滚(DeviceToolbox 应照做,并提供「恢复原始」)。
  2. **原子原地写 + 回读校验 + 失败回滚**(`mg_write`),避免写坏 gestalt 导致 bootloop。
  3. **respring**:neon 的 WKWebView 内存压力法,无需越狱。
  4. **keep-alive**:静音音频循环 + 0.5s Timer 保活后台进程(对「等下载」场景有用)。
  5. `container_query_set_class(13)` + `set_part(3)` + 路径穿越 `../../../../../../..<dir>` 这套参数即 3105 `bad_query.c` 里完全相同的实现,DeviceToolbox 的 `bad_query.c` 可直接复用 `grant_mg()` 的等价逻辑。

### B.2 「iPhone 15 上 AI spoof 无效」原因推测(需实测)
1. **键位不对**:mond 在 27 仍写 18.1 时代的 `A62OafQ85EJAiiqKn4agtg`,而 26.x 起 Apple 用新明文键 `AppleIntelligenceAllowedDevice/SupportedDevice/MinimumRAM`。27 大概率沿用 26 的新键,老键不再被 IntelligencePlatform 读取。
2. **服务端断言**:`/v1/models` 会校验真实硬件(SEP/芯片代),A16 即便伪装 ProductType 也可能被服务端拒绝;26.1 的成功报告多发生在 A16 iPhone 15 Plus 且「多次尝试」才成,说明断言不稳定/有重试窗口。
3. **RAM 门槛**:`AppleIntelligenceMinimumRAM=6` 是硬门槛,A16 机型实际 6GB(iPhone 14 Pro/15 为 6GB)能满足,更早(A15 4–6GB 混)可能不满足 → 需实测。

### B.3 EnsWilde(iOS 26.2b1)
- 机制:复用 `itunesstored` + `bookassetd` 的 **SparseRestore/bookrestore** 路径逃逸,配合 Impactor 注入 pairing、AFC(`JITEnableContext.afcPushFile`)把 `ModifiedMobileGestalt.plist` 推成 `com.apple.MobileGestalt.plist`,再 patch `downloads.28.sqlitedb` 把 bookassetd 指向 localhost,杀/重启 daemon,等 syslog `Install-Mgr: Marking download as finished` 确认覆盖成功。
- 特点:**PC 辅助、非在机漏洞链**,iOS 26.2b1 特定。作者 YangJiiii(3105 同作者,用户已熟知其生态)。
- 借鉴点:它证明了 **26.x 在机 AI 强开用 gestalt 改 + eligibility 写这条路是通的**(尽管它走 PC restore);其 `bindingForAppleIntelligence()` 同样写 `A62OafQ85EJAiiqKn4agtg` 并同时准备 `eligibility.plist` + `FeatureFlags_Global.plist` 两份资源。
- 规避点:EnsWilde 是 AGPLv3(见 E),且 PC 辅助流程与 DeviceToolbox 的「纯在机」定位相悖 → 只借鉴「改哪些键 + 写哪些文件」的事实,不移植其 restore/daemon 编排。

---

## C. 版本 × 机型 × 目标矩阵

> 目标分三类:**H**=硬件强开(≤A16 伪装机型下载模型)、**R**=地区锁强开(硬件支持但国行 CH/A)、**O**=官方支持(无需强开)。
> 覆盖 DeviceToolbox 漏洞链支持的 17/18/26/27 全部版本。网格值:✅官方支持 / 🔧需强开 / ❌不可行 / ❓需实测。

| 机型桶(SoC) | iOS 17.x | iOS 18.0 | iOS 18.1b1–4 | iOS 18.1b5–18.7.1 | iOS 26.0–26.6.1 | iOS 27.0 b1–4 |
|---|---|---|---|---|---|---|
| **A17 Pro / A18 / A19**(15 Pro 及更新,M 系 iPad)非国行 | ❌ 无 AI 子系统 | ❌ 无 AI(18.1 才引入) | ✅ 官方(18.1 首版) | ✅ 官方 | ✅ 官方 | ✅ 官方 |
| 同上,**国行 CH/A** | ❌ | ❌ | 🔧R(eligibility 改 region) | 🔧R ❓(eligibility 写可能仍被服务端断言地区) | 🔧R(gestalt RegionCode→LL + CALCIUM 域) | 🔧R ❓(mond「Disable Region Restrictions」报部分失效) |
| **A16 及以下**(iPhone 15/15 Plus、14 系、SE 等) | ❌ | ❌ | 🔧H(18.1b4 老法可下载模型) | ❌(18.1 DB5 服务端封) | 🔧H ✅(26.1 iPhone 15 Plus 有成功报告;Nugget 7.2 明文键) | 🔧H ❓(mond 报 iPhone 15 失效;需换 26 明文键实测) |
| **A15 及以下** | ❌ | ❌ | ❓ | ❌ | ❓(RAM<6GB 大概率不过门槛) | ❓ |

**核心结论:**
1. **iOS 17.x 一律 ❌**:Apple Intelligence 18.1 才引入,17 无框架,不存在强开。
2. **iOS 18.0 ❌、18.1b1–4 是老法的黄金窗口**,18.1 DB5 起服务端封死硬件强开,仅剩国行地区锁可尝试。
3. **iOS 26.x 是当前硬件强开的主战场**:misaka26/Nugget 7.2 用明文键 + ProductType 伪装 + GREYMATTER 资格,有 A16 成功案例;DeviceToolbox 的 26.0–26.6.1 门禁正好覆盖。
4. **iOS 27.0b1–4 可行但未定**:mond 只在机验证了「写 gestalt」这条通路(27 专用 bad_query/cmg),AI spoof 在 iPhone 15 失效,需换 26 明文键重试 → **最大不确定点**。
5. 国行地区锁(R)在 26/27 对 A17 Pro+ 设备是**低风险**路径(只动 region + eligibility,不伪装硬件、不下载非官方模型),建议作为首个落地目标。

---

## D. DeviceToolbox 集成设计

### D.1 设计原则(对齐现有代码风格)
- 复用 `SupportPolicy`(版本门禁)、`SupportMatrix`/`DeviceProbe`(芯片/机型)、`ExploitController`(单例状态机 + detached Task)、`SystemContainerService`(enum 静态方法 + `Task.detached`)、`bad_query.c`/`mcm_bridge.m`/`sandbox_escape`(写权限)。
- 模拟器一律禁用;Swift 6 严格并发(`@MainActor` 单例 + `nonisolated static` + `Task.detached`);**不改任何现有文件**;Sources 目录 xcodegen 自动包含,`project.yml` 无需改。
- **不复制 AGPLv3 代码**(mond/EnsWilde/Nugget),只重写事实(键名/路径/机制),写盘逻辑自写或复用已集成的 3105 GPLv3。

### D.2 新增文件清单与职责

```
Sources/SystemAccess/AIEnablePolicy.swift        —— enum,版本×机型×目标门禁(纯判定,可单测)
Sources/SystemAccess/MobileGestaltService.swift  —— enum 静态方法:读/写 gestalt、写 eligibility、备份/回滚
Sources/SystemAccess/AIEnableController.swift    —— @MainActor ObservableObject 单例:状态机与分步执行
Sources/Views/Settings/AIEnableView.swift        —— UI 入口(设置页「特权引擎」旁新增 Section 或工具页入口)
Sources/Resources/en.lproj/Localizable.strings   —— 追加 aienable.* 键(仅幂等追加)
Sources/Resources/zh-Hans.lproj/Localizable.strings —— 同上
Tests/DeviceToolboxTests/AIEnablePolicyTests.swift —— 矩阵单测(可选,建议)
```

### D.3 API 签名草案

```swift
// AIEnablePolicy.swift —— 纯判定,参数可注入以便单测
enum AIEnablePolicy {
    enum Target: String, Sendable {
        case official        // 官方支持,无需强开
        case regionUnlock    // 硬件支持,国行地区锁
        case hardwareSpoof   // A16 及以下,需伪装机型下载模型
        case unavailable     // 不可行
    }
    struct Verdict: Equatable, Sendable {
        let target: Target
        let note: String
        var isActionable: Bool { target != .unavailable && target != .official }
    }
    /// model = hw.machine(如 iPhone15,5);build 仅对 27.0 生效
    static func verdict(model: String,
                        major: Int, minor: Int, patch: Int,
                        build: String?, isSimulator: Bool) -> Verdict
    /// 官方支持 AI 的机型白名单(A17 Pro 起)
    static func isOfficialAISupport(model: String) -> Bool
    /// 强开允许的伪装目标(按当前 iOS 选)
    static func spoofTargets(major: Int, minor: Int) -> [String]
}

// MobileGestaltService.swift —— enum 静态方法 + Task.detached(Sendable 输入)
enum MobileGestaltService {
    static let gestaltPath = "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static let eligibilityPath = "/var/db/eligibilityd/eligibility.plist"

    /// 逃逸后写权限探测(复用 bad_query 或 MCMActivateContainer 后 open O_RDWR 试写)
    static func ensureWriteAccess() async throws -> Bool
    /// 读当前 gestalt 缓存为 NSDictionary(失败返 nil)
    static func readGestalt() async -> NSDictionary?
    /// 备份当前 gestalt 到 App Application Support,返回备份路径
    static func backupGestalt() async throws -> URL
    /// 原子写(同 inode:open+ftruncate+write+fsync+回读校验+失败回滚)
    static func writeGestalt(_ dict: NSDictionary, atomic: Bool) async throws
    /// 恢复备份
    static func restoreBackup() async throws
    /// 写 GREYMATTER+CALCIUM eligibility
    static func writeAIEligibility(languages: [String]) async throws
}

// AIEnableController.swift —— 仿 ExploitController
@MainActor
final class AIEnableController: ObservableObject {
    enum State: Equatable { case idle, running, active, failed(String) }
    static let shared = AIEnableController()
    @Published private(set) var state: State = .idle

    /// 分步执行:校验逃逸→备份→写 gestalt(AI 键+可选 ProductType 伪装)→写 eligibility→提示 respring/reboot
    func run(verdict: AIEnablePolicy.Verdict) { ... }   // 内部 Task.detached 跑 C 链 + 文件 I/O
    func reset() { ... }
    nonisolated static func isEscapeActive() -> Bool   // 复用 ExploitController.isSandboxActive()
}
```

### D.4 执行状态机(分步,便于 UI 展示与中断)

```
idle → running:
  1. 前置:ExploitController.isSandboxActive() == true(否则引导先跑特权引擎)
  2. MobileGestaltService.backupGestalt()(首次备份)
  3. readGestalt → 改 CacheExtra:
       hardwareSpoof: A62OafQ85EJAiiqKn4agtg=1 + AppleIntelligenceAllowedDevice/SupportedDevice=1 + MinimumRAM=6 + ProductType=spoofTarget
       regionUnlock:  RegionCode→"LL" + RegionInfo→"LL/A"(CALCIUM/GREYMATTER 由 eligibility 写)
  4. writeGestalt(atomic=true)
  5. writeAIEligibility(languages:["en"])
  6. → active,提示:respring 或 reboot + 联网等待下载(hardwareSpoof 才需下载模型;regionUnlock 只需 respring)
→ failed(msg) 任一步失败;提供「恢复原始」入口(restoreBackup)
```

### D.5 UI 入口
- 建议放在 **设置页 `privilege.title` Section 之后**新增 `aienable.title` Section(与「特权引擎」同页,复用 `ExploitController.shared` 状态),`AIEnableView`:
  - 展示 `AIEnablePolicy.verdict(...)` 结果(官方支持/地区锁/硬件强开/不可行 + note)。
  - 按钮「开始强开」→ `AIEnableController.shared.run(verdict)`,带确认 dialog(同 `privilege.run.confirm` 风格,强调 bootloop 风险)。
  - 分步进度 + 失败态 + 「恢复原始 gestalt」按钮。
- 文案双语键清单(追加,前缀 `aienable.*`):

```
aienable.title          = Apple Intelligence 强开 / Apple Intelligence Enable
aienable.state.idle     = 待机 / Idle
aienable.state.running  = 执行中… / Running…
aienable.state.active   = 已写入(请重启并联网等待下载) / Written (reboot & wait)
aienable.state.failed   = 失败 / Failed
aienable.verdict.official     = 官方支持,无需强开 / Officially supported
aienable.verdict.region       = 硬件支持,地区锁(国行) / Region-locked
aienable.verdict.hardware     = 硬件不支持,需伪装机型 / Hardware unsupported
aienable.verdict.unavailable  = 此版本不可行 / Not available
aienable.run.trigger    = 开始强开 / Start
aienable.run.confirm    = 修改 MobileGestalt 有极小概率导致设备无法启动,请先备份。仅支持矩阵内设备。继续? / Modifying MobileGestalt may brick the device. Continue?
aienable.step.backup    = 备份 gestalt / Backing up
aienable.step.write     = 写入 gestalt / Writing
aienable.step.eligibility = 写入资格表 / Writing eligibility
aienable.step.escape    = 校验逃逸 / Verifying escape
aienable.restore        = 恢复原始 gestalt / Restore original
aienable.escape.missing = 请先启动特权引擎(沙盒逃逸)/ Start the privilege engine first
```

### D.6 复用映射(DeviceToolbox 现有 → 本模块)
| 需求 | 现有资产 |
|---|---|
| 在机获得 mobilegestaltcache 写权限 | `bad_query.c`(grant_mg 等价)、`mcm_bridge.m`(MCMActivateContainer)、`sandbox_escape()` |
| 逃逸激活判定 | `ExploitController.isSandboxActive()` / `sandbox_access_is_active()` |
| 版本门禁 | `SupportPolicy.isSupportedCurrentDevice()` |
| 机型/SoC | `DeviceProbe.modelIdentifier` / `socFamily` |
| 状态机模板 | `ExploitController`(idle/running/active/failed + 持久化) |
| 文件扫描风格 | `SystemContainerService`(enum 静态方法 + Task.detached) |

---

## E. 许可审计

| 仓库 | 许可证 | 与 DeviceToolbox(GPLv3)关系 |
|---|---|---|
| 3105 / ThreeOneOSFive | **GPLv3** | ✅ 已集成,可继续复用(ExploitCore 即其源码) |
| mond (rooootdev) | **AGPLv3**(`LICENSE` 首行「GNU AFFERO」) | ⚠️ 更严格:AGPL 带网络条款,并入 GPLv3 会强制整体 AGPLv3。**禁止复制其代码**,只提炼事实(路径/键名/机制) |
| EnsWilde (YangJiiii) | **AGPLv3** | ⚠️ 同上,禁止复制代码 |
| Nugget (leminlimez) | **AGPLv3**(`LICENSE` 首行「GNU AFFERO」) | ⚠️ 同上(注意 MisakaX 组合 LICENSE 里把 leminlimez 列在 MIT,存在 relicense 不一致,以仓库自身 LICENSE 为准=AGPL) |
| MisakaX (straight-tamago) | **MIT**(多作者:little_34306 / straight-tamago / leminlimez / JJTech0130) | ✅ 宽松,可带署名复用代码 |

**审计结论/动作:**
1. **键名、路径、文件格式、机制原理是事实,不受版权保护**,可直接写进 DeviceToolbox。
2. `eligibility.plist` 的 GREYMATTER/CALCIUM 键结构是数据事实,但**应全新生成**,不要直接拷 Nugget/EnsWilde 的资源文件(AGPL)。
3. 写盘/逃逸/编排逻辑全部基于已集成的 3105(GPLv3)+ 自写;如需参考 mond 的 `mg_write` 原子写,应以「重新实现」方式(其思路本身可借鉴,代码不抄)。
4. 开源发布时的 `THIRD_PARTY_NOTICES` 需新增:mond/EnsWilde/Nugget 为「事实调研来源(未引入代码)」,misaka26 为「MIT 参考」,3105 保持现有 GPLv3 声明。

---

## 附:最大不确定点(需真机实测清单)

1. **27.0b1–4 的 AI 明文键**:26 的 `AppleIntelligenceAllowedDevice/SupportedDevice/MinimumRAM` 是否在 27 生效,以及 27 下 region 解锁是否可用(mond 自报两项失效)。
2. **服务端断言强度**:IntelligencePlatform 对 `intelligence.apple.com/v1/models` 的校验是否拦死 A16,26.1 的成功是稳定复现还是概率事件。
3. **重启持久性**:gestalt 原子原地写能否扛过 26/27 的 mobilegestaltd 缓存重建(mond 报「tweaks may disappear on reboot」)。
4. **eligibilityd 是否重启即重算**:`/var/db/eligibilityd/eligibility.plist` 在 26/27 是否被守护进程用服务端/本地输入覆盖。
5. **mond 的 RegionInfo 键歧义**:`yK+xavymRGZ3xWc1tb8XDg`(mond)vs `zHeENZu+wbg7PUprwNwBWg`(Nugget/EnsWilde),哪条是 27 真 RegionInfo。
