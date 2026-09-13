import Foundation

/// UserDefaults 键名常量,统一管理避免散落硬编码字符串。
enum AppStorageKeys {
    /// 是否已同意免责声明(首次启动流程)
    static let disclaimerAccepted = "disclaimerAccepted"
    /// 是否已完成首次引导
    static let hasSeenOnboarding = "hasSeenOnboarding"
    /// 最近一次设备检测时间(存 timeIntervalSince1970)
    static let lastDeviceScanDate = "lastDeviceScanDate"
    /// 本地兼容性数据库缓存版本号
    static let compatibilityCacheVersion = "compatibilityCacheVersion"
    /// 是否已提示过低功耗模式
    static let lowPowerModeNotified = "lowPowerModeNotified"
    /// 全应用折叠玻璃特效开关(FoldEffectEngine)
    static let foldEffectEnabled = "foldEffectEnabled"
}
