import Foundation
import Darwin

/// MobileGestalt / eligibilityd 文件操作层(纯文件,无私有 API 调用)。
///
/// 事实来源(键名/路径,非代码搬运): leminlimez/Nugget、rooootdev/mond、misaka26、
/// f1shy-dev gist、icedmoca gist、Nugget issue #1073 —— 已获沙盒逃逸/root 后写入。
///
/// 关键文件(等价 /private/var/...):
/// - MobileGestalt 缓存: /var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist
///   · 缓存自带完整性字段(CacheUUID/CacheVersion/CacheData),只能「读本机 → 改 CacheExtra → 同 inode 原地写回」,不可整体替换。
/// - AI 资格表: /var/db/eligibilityd/eligibility.plist(GREYMATTER = Apple Intelligence 域)
///
/// 写入通道:
/// 1. 沙盒逃逸(sandbox_escape)后: 以 mobile 身份可写 gestalt 缓存;eligibility 属 root,需先 root 提权。
/// 2. bad_query(mond 同源,27.0b1–4): 换取 mobilegestaltcache 容器 sandbox extension,仅 gestalt 可写。
enum MobileGestaltService {

    // MARK: - 路径与键

    static let gestaltCachePath =
        "/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static let eligibilityPath = "/var/db/eligibilityd/eligibility.plist"

    /// 混淆键(功能性事实): ProductType / HardwareModel / HardwarePlatform / 生成式模型能力 / 地区。
    enum GestaltKey {
        static let productType = "h9jDsbgj7xIVeIQ8S3/X3Q"
        static let productTypeAlt = "0+nc/Udy4WNG8S+Q7a/s1A"
        static let hardwareModel = "oYicEKzVTz4/CxxE05pEgQ"
        static let hardwarePlatform = "5pYKlGnYYBzGvAlIU8RjEQ"
        static let generativeModel = "A62OafQ85EJAiiqKn4agtg"   // DeviceSupportsGenerativeModelSystems
        static let regionCode = "h63QSdBCiT/z0WU6rdQv6Q"
        static let regionInfo = "zHeENZu+wbg7PUprwNwBWg"
    }

    /// iOS 26.x 起的明文 AI 能力键。
    enum PlainAICacheKeys {
        static let allowedDevice = "AppleIntelligenceAllowedDevice"
        static let supportedDevice = "AppleIntelligenceSupportedDevice"
        static let minimumRAM = "AppleIntelligenceMinimumRAM"
    }

    private static let cacheExtraKey = "CacheExtra"

    // MARK: - 基础读写(可逃逸前调用:缓存文件对普通 App 可读)

    /// 读取本机 gestalt 缓存原始字节(读无需逃逸;失败返 nil)。
    static func readGestaltData() -> Data? {
        FileManager.default.contents(atPath: gestaltCachePath)
    }

    /// 从缓存解析 CacheExtra(NSDictionary 仅限同步使用,不跨 actor)。
    static func cacheExtra(from data: Data) -> NSMutableDictionary? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary,
              let extra = plist[cacheExtraKey] as? NSDictionary
        else { return nil }
        return NSMutableDictionary(dictionary: extra)
    }

    /// 当前 RegionInfo(如 LL/A、CH/A);读不到返回 nil。
    static func currentRegionInfo(from data: Data) -> String? {
        cacheExtra(from: data)?[GestaltKey.regionInfo] as? String
    }

    // MARK: - 备份 / 恢复

    private static var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AIEnable", isDirectory: true)
    }

    static var backupFileURL: URL {
        backupDirectory.appendingPathComponent("SavedGestalt.plist")
    }

    /// 首次写入前把原始 gestalt 备份到 Application Support(幂等:已存在则跳过)。
    @discardableResult
    static func backupGestalt(data: Data) throws -> URL {
        let dir = backupDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = backupFileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    /// 读取已备份的原始内容(供恢复/回滚)。
    static func readBackupData() -> Data? {
        FileManager.default.contents(atPath: backupFileURL.path)
    }

    static func hasBackup() -> Bool {
        FileManager.default.fileExists(atPath: backupFileURL.path)
    }

    // MARK: - CacheExtra 补丁构建(纯数据,无副作用)

    /// 型号伪装目标(3105 Gestalt 编辑器 model_spoof 语义;机型三键值表为功能性事实,
    /// 对照 Nugget generate_mga 表: ProductType/HardwareModel/HardwarePlatform)。
    struct ModelSpoofTarget: Sendable, Identifiable, Equatable {
        let id: String            // ProductType,如 iPhone16,1
        let name: String          // 展示名
        let hardwareModel: String // D83AP 等
        let hardwarePlatform: String // t8130 等
        let experimental: Bool
    }

    static let spoofCatalog: [ModelSpoofTarget] = [
        ModelSpoofTarget(id: "iPhone16,1", name: "iPhone 15 Pro", hardwareModel: "D83AP", hardwarePlatform: "t8130", experimental: false),
        ModelSpoofTarget(id: "iPhone16,2", name: "iPhone 15 Pro Max", hardwareModel: "D84AP", hardwarePlatform: "t8130", experimental: false),
        ModelSpoofTarget(id: "iPhone17,3", name: "iPhone 16", hardwareModel: "D47AP", hardwarePlatform: "t8140", experimental: false),
        ModelSpoofTarget(id: "iPhone17,4", name: "iPhone 16 Plus", hardwareModel: "D48AP", hardwarePlatform: "t8140", experimental: false),
        ModelSpoofTarget(id: "iPhone17,1", name: "iPhone 16 Pro", hardwareModel: "D93AP", hardwarePlatform: "t8140", experimental: false),
        ModelSpoofTarget(id: "iPhone17,2", name: "iPhone 16 Pro Max", hardwareModel: "D94AP", hardwarePlatform: "t8140", experimental: false),
        ModelSpoofTarget(id: "iPhone18,3", name: "iPhone 17", hardwareModel: "V57AP", hardwarePlatform: "t8150", experimental: true),
    ]

    static func patchedGestaltData(original: Data, spoof: ModelSpoofTarget) throws -> (data: Data, changed: Bool) {
        guard let plist = try? PropertyListSerialization.propertyList(from: original, options: [], format: nil) as? NSDictionary else {
            throw AIEnableError.gestaltParseFailed
        }
        let root = NSMutableDictionary(dictionary: plist)
        let extra = NSMutableDictionary(dictionary: plist[cacheExtraKey] as? NSDictionary ?? [:])

        func setValue(_ v: Any, forKey key: String) {
            if let old = extra[key], (old as AnyObject).isEqual(v) { return }
            extra[key] = v
        }

        setValue(spoof.id, forKey: GestaltKey.productType)
        setValue(spoof.id, forKey: GestaltKey.productTypeAlt)
        setValue(spoof.hardwareModel, forKey: GestaltKey.hardwareModel)
        setValue(spoof.hardwarePlatform, forKey: GestaltKey.hardwarePlatform)

        root[cacheExtraKey] = extra
        let out = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        return (out, true)
    }

    /// 按目标改写 CacheExtra,返回(新全量 plist 数据, 是否发生变更)。
    static func patchedGestaltData(original: Data, target: AIEnablePolicy.Target) throws -> (data: Data, changed: Bool) {
        guard let plist = try? PropertyListSerialization.propertyList(from: original, options: [], format: nil) as? NSDictionary else {
            throw AIEnableError.gestaltParseFailed
        }
        let root = NSMutableDictionary(dictionary: plist)
        let extra = NSMutableDictionary(dictionary: plist[cacheExtraKey] as? NSDictionary ?? [:])

        var changed = false

        func setValue(_ v: Any, forKey key: String) {
            if let old = extra[key], (old as AnyObject).isEqual(v) { return }
            extra[key] = v
            changed = true
        }

        switch target {
        case .hardwareSpoof:
            // 26.x 明文键 + 18.1 时代混淆键(超集,均写)
            setValue(true, forKey: PlainAICacheKeys.allowedDevice)
            setValue(true, forKey: PlainAICacheKeys.supportedDevice)
            setValue(6, forKey: PlainAICacheKeys.minimumRAM)
            setValue(1, forKey: GestaltKey.generativeModel)
            // 三键联动伪装 iPhone 16 Pro 档(15 Pro): ProductType + HardwareModel + HardwarePlatform
            setValue("iPhone16,1", forKey: GestaltKey.productType)
            setValue("iPhone16,1", forKey: GestaltKey.productTypeAlt)
            setValue("D83AP", forKey: GestaltKey.hardwareModel)
            setValue("t8130", forKey: GestaltKey.hardwarePlatform)
        case .regionUnlock:
            // 国行 CH/A → 美区 SKU。LL/A 设备重复写入幂等无害。
            setValue("US", forKey: GestaltKey.regionCode)
            setValue("LL/A", forKey: GestaltKey.regionInfo)
        case .official, .unavailable:
            break
        }

        guard changed else {
            return (original, false)
        }
        root[cacheExtraKey] = extra
        let out = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
        return (out, true)
    }

    // MARK: - eligibility 模板(GREYMATTER + CALCIUM,字段结构为功能性事实)

    static func makeEligibilityData(languages: [String] = ["en"]) throws -> Data {
        let root: [String: Any] = [
            "OS_ELIGIBILITY_DOMAIN_CALCIUM": [
                "os_eligibility_answer_source_t": 1,
                "os_eligibility_answer_t": 2,
                "status": ["OS_ELIGIBILITY_INPUT_CHINA_CELLULAR": 2],
            ],
            "OS_ELIGIBILITY_DOMAIN_GREYMATTER": [
                "os_eligibility_answer_source_t": 1,
                "os_eligibility_answer_t": 4,
                "context": [
                    "OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES": languages,
                ],
                "status": [
                    "OS_ELIGIBILITY_INPUT_DEVICE_LANGUAGE": 3,
                    "OS_ELIGIBILITY_INPUT_DEVICE_REGION_CODE": 3,
                    "OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE": 3,
                    "OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM": 3,
                    "OS_ELIGIBILITY_INPUT_SHARED_IPAD": 3,
                    "OS_ELIGIBILITY_INPUT_SIRI_LANGUAGE": 3,
                ],
            ],
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    // MARK: - 写入(同 inode 原子写:open → ftruncate → write → fsync → 回读校验 → 失败回滚)

    /// 对既有文件做同 inode 原子覆写。original 供失败回滚。
    static func writeFileAtomically(_ data: Data, to path: String, original: Data?) throws {
        let fd = Darwin.open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            throw AIEnableError.fileOpenFailed(path: path, errno: errno)
        }
        defer { Darwin.close(fd) }

        let ok = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress, raw.count > 0 else { return false }
            guard Darwin.ftruncate(fd, 0) == 0 else { return false }
            let written = Darwin.pwrite(fd, base, raw.count, 0)
            guard written == raw.count else { return false }
            Darwin.fsync(fd)
            var verify = [UInt8](repeating: 0, count: raw.count)
            let n = Darwin.pread(fd, &verify, raw.count, 0)
            guard n == raw.count else { return false }
            let expected = UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: raw.count)
            return verify.elementsEqual(expected)
        }

        if !ok {
            // 回滚到原始内容
            if let original {
                _ = original.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
                    guard let base = raw.baseAddress else { return false }
                    Darwin.ftruncate(fd, 0)
                    return Darwin.pwrite(fd, base, raw.count, 0) == raw.count
                }
            }
            throw AIEnableError.atomicWriteFailed(path: path)
        }
    }

    /// 写入 eligibility 表并设 root:wheel 0644(需 root 身份;失败抛错由调用方决定是否降级)。
    static func writeEligibilityFile(data: Data) throws {
        try writeFileAtomically(data, to: eligibilityPath, original: readFileData(eligibilityPath))
        let attrs: [FileAttributeKey: Any] = [
            .ownerAccountID: 0,
            .groupOwnerAccountID: 0,
            .posixPermissions: 0o644,
        ]
        try? FileManager.default.setAttributes(attrs, ofItemAtPath: eligibilityPath)
    }

    static func readFileData(_ path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    // MARK: - 通道探测

    /// 当前 euid(0 = 已 root)。
    static var currentUID: uid_t { Darwin.geteuid() }
    static var isRoot: Bool { currentUID == 0 }

    /// 用 bad_query 换取 mobilegestaltcache 容器 extension(bad_query.c,mond 同源;返回需持有的句柄,用完 release)。
    /// 需要路径参数以通过 lstat 存在性检查;"/" 恒存在。
    static func badQueryGrantGestalt() -> Int64? {
        var handle: Int64 = -1
        "/".withCString { cs in
            handle = bad_query(UnsafeMutablePointer(mutating: cs), false, nil, false)
        }
        return handle >= 0 ? handle : nil
    }

    static func badQueryRelease(_ handle: Int64) {
        bad_query_release(handle)
    }

    // MARK: - 恢复

    /// 从备份恢复 gestalt(覆盖写,原地同 inode)。
    static func restoreGestaltFromBackup() throws {
        guard let backup = readBackupData() else {
            throw AIEnableError.noBackup
        }
        let original = readGestaltData()
        try writeFileAtomically(backup, to: gestaltCachePath, original: original)
    }
}

/// AI 强开模块错误(带中文描述,直接可展示)。
enum AIEnableError: LocalizedError {
    case gestaltParseFailed
    case fileOpenFailed(path: String, errno: Int32)
    case atomicWriteFailed(path: String)
    case noBackup
    case escapeRequired
    case rootRequired

    var errorDescription: String? {
        switch self {
        case .gestaltParseFailed: return "MobileGestalt 缓存解析失败"
        case .fileOpenFailed(let path, let code): return "无法打开 \(path)(errno=\(code))"
        case .atomicWriteFailed(let path): return "写入失败且回滚完成:\(path)"
        case .noBackup: return "无备份文件,无法恢复"
        case .escapeRequired: return "沙盒逃逸未激活"
        case .rootRequired: return "需要 root 权限(当前通道不支持)"
        }
    }
}
