import Foundation

/// Feature Flags 编辑器服务:读写 /var/preferences/FeatureFlags/Global.plist。
/// 门禁:读取可在逃逸前尝试(文件若可读);写入需逃逸激活并 elevate 到 root。
/// 保留既有键,仅改目标 category/flag;原子写复用 MobileGestaltService.writeFileAtomically。
enum FeatureFlagsService: Sendable {

    static let globalFlagsPath = "/var/preferences/FeatureFlags/Global.plist"

    /// 单个 flag 预设定义(社区已知,实验性)。
    struct FlagDefinition: Identifiable, Hashable, Sendable {
        let category: String
        let key: String
        let titleKey: String
        let experimental: Bool
        var id: String { "\(category).\(key)" }
    }

    struct FlagGroup: Identifiable, Hashable, Sendable {
        let category: String
        let titleKey: String
        let flags: [FlagDefinition]
        var id: String { category }
    }

    /// 内置开关预设。flag 名来源:Nugget 社区资料(非 Apple 文档);Siri/SiriUI 为社区广泛引用的键,
    /// 其余三个类别为社区相关 flag 名,实际值形状/键名可能因版本而异,请自行核对。
    static let catalog: [FlagGroup] = [
        FlagGroup(category: "Siri", titleKey: "featureflags.group.siri", flags: [
            FlagDefinition(category: "Siri", key: "sae_override", titleKey: "featureflags.flag.siri.sae_override", experimental: true),
            FlagDefinition(category: "Siri", key: "assistant_engine_override", titleKey: "featureflags.flag.siri.assistant_engine_override", experimental: true),
        ]),
        FlagGroup(category: "SiriUI", titleKey: "featureflags.group.siriui", flags: [
            FlagDefinition(category: "SiriUI", key: "sae", titleKey: "featureflags.flag.siriui.sae", experimental: true),
        ]),
        FlagGroup(category: "PrivateCloudCompute", titleKey: "featureflags.group.pcc", flags: [
            FlagDefinition(category: "PrivateCloudCompute", key: "com.apple.privatecloudcompute.override", titleKey: "featureflags.flag.pcc.override", experimental: true),
        ]),
        FlagGroup(category: "TextComposer", titleKey: "featureflags.group.textcomposer", flags: [
            FlagDefinition(category: "TextComposer", key: "text_composer_override", titleKey: "featureflags.flag.textcomposer.override", experimental: true),
        ]),
        FlagGroup(category: "SiriNL", titleKey: "featureflags.group.sirinl", flags: [
            FlagDefinition(category: "SiriNL", key: "siri_nl_override", titleKey: "featureflags.flag.sirinl.override", experimental: true),
        ]),
    ]

    /// 是否可用(模拟器恒 false)。
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    // MARK: - 读

    /// 读取全局 flags 字典(category → flag → value)。可逃逸前尝试;失败/不存在返 nil。
    /// 注意:同步调用,NSDictionary 不跨 actor。
    static func readGlobal() -> [String: [String: Any]]? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let data = MobileGestaltService.readFileData(globalFlagsPath) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: [String: Any]] else { return nil }
        return plist
        #endif
    }

    /// 读取单个 flag 的布尔值(不存在默认 false)。
    static func currentBool(category: String, flag: String) -> Bool {
        readGlobal()?[category]?[flag] as? Bool ?? false
    }

    // MARK: - 写

    /// 写入单个 flag,保留其余所有既有键。需 root(调用方先 elevate)。
    static func writeFlag(category: String, flag: String, value: Any) throws {
        #if targetEnvironment(simulator)
        throw FeatureFlagsError.unavailable
        #else
        let root = readRootDictionary() ?? NSMutableDictionary()
        let existing = root[category] as? NSDictionary
        let cat = NSMutableDictionary(dictionary: existing ?? [:])
        cat[flag] = value
        root[category] = cat
        let out = try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)

        let dir = (globalFlagsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let original = MobileGestaltService.readFileData(globalFlagsPath)
        if FileManager.default.fileExists(atPath: globalFlagsPath) {
            try MobileGestaltService.writeFileAtomically(out, to: globalFlagsPath, original: original)
        } else {
            try out.write(to: URL(fileURLWithPath: globalFlagsPath), options: .atomic)
        }
        #endif
    }

    /// 切换布尔值,返回新值。
    @discardableResult
    static func toggle(category: String, flag: String) throws -> Bool {
        let newValue = !currentBool(category: category, flag: flag)
        try writeFlag(category: category, flag: flag, value: newValue)
        return newValue
    }

    // MARK: - 内部

    private static func readRootDictionary() -> NSMutableDictionary? {
        guard let data = MobileGestaltService.readFileData(globalFlagsPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary
        else { return nil }
        return NSMutableDictionary(dictionary: plist)
    }
}

/// Feature Flags 错误。
enum FeatureFlagsError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "模拟器不可用 · Simulator unavailable"
        }
    }
}
