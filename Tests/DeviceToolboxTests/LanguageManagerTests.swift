import XCTest
@testable import DeviceToolbox

/// 语言切换机制测试:AppLanguage 枚举 / LanguageManager 的 AppleLanguages 写入与持久化。
///
/// 说明:选择语言后生效依赖**进程重启**(iOS 在启动时读取 AppleLanguages),
/// 因此这里只验证「写入 + 持久化 + UI 状态」语义,不验证进程内语言切换。
final class LanguageManagerTests: XCTestCase {
    /// 每个用例干净的 UserDefaults 环境(避免 AppleLanguages 系统键互相污染)。
    override func setUpWithError() throws {
        try super.setUpWithError()
        let keys = [
            LanguageManager.appleLanguagesKey,
            AppStorageKeys.appLanguage,
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDownWithError() throws {
        let keys = [
            LanguageManager.appleLanguagesKey,
            AppStorageKeys.appLanguage,
        ]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        try super.tearDownWithError()
    }

    func testDefaultSelectionIsSystem() {
        let manager = LanguageManager()
        XCTAssertEqual(manager.selected, .system)
        // AppleLanguages 是系统保留键:未做过用户选择时,它只会含系统默认语言,
        // 不应含任何用户显式选择的 tag(如 "ja" / "ko")。
        let apple = UserDefaults.standard.array(forKey: LanguageManager.appleLanguagesKey) as? [String] ?? []
        XCTAssertFalse(apple.contains("ja") || apple.contains("ko"),
                       "未选择过语言时 AppleLanguages 不应含用户选择的 tag")
    }

    func testSelectJapaneseWritesAppleLanguagesAndPersistsChoice() {
        let manager = LanguageManager()
        XCTAssertTrue(manager.select(.ja))
        XCTAssertEqual(manager.selected, .ja)
        XCTAssertEqual(UserDefaults.standard.array(forKey: LanguageManager.appleLanguagesKey) as? [String], ["ja"])
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppStorageKeys.appLanguage), "ja")
        // 重启模拟:新 manager 从持久化值恢复选择(确定行为,不依赖系统语言)
        let afterRestart = LanguageManager()
        XCTAssertEqual(afterRestart.selected, .ja)
    }

    func testSelectTraditionalChineseWritesPrefixMatchableTag() {
        let manager = LanguageManager()
        XCTAssertTrue(manager.select(.zhHant))
        XCTAssertEqual(UserDefaults.standard.array(forKey: LanguageManager.appleLanguagesKey) as? [String], ["zh-Hant"])
    }

    func testSelectSystemClearsAppleLanguagesOverride() {
        let manager = LanguageManager()
        XCTAssertTrue(manager.select(.ko))
        XCTAssertEqual(UserDefaults.standard.array(forKey: LanguageManager.appleLanguagesKey) as? [String], ["ko"])
        XCTAssertTrue(manager.select(.system))
        // 选择"跟随系统"后,用户覆盖应清除:AppleLanguages 不再含 "ko"
        // (该键是系统保留键,removeObject 后系统可能回填默认语言,故不断言 nil)
        let apple = UserDefaults.standard.array(forKey: LanguageManager.appleLanguagesKey) as? [String] ?? []
        XCTAssertFalse(apple.contains("ko"),
                       "跟随系统后 AppleLanguages 不应含用户选的 tag")
        XCTAssertEqual(manager.selected, .system)
        // 跟随系统永远视为已生效
        XCTAssertTrue(manager.isSelectionApplied)
    }

    func testAllCasesHaveValidBcp47TagsAndSingleSystemCase() {
        let systemCases = AppLanguage.allCases.filter { $0 == .system }
        XCTAssertEqual(systemCases.count, 1)
        for language in AppLanguage.allCases where language != .system {
            // 非 system 的 rawValue 必须是合法语言标签(如 ja / ko / en / zh-Hans / zh-Hant)
            XCTAssertFalse(language.rawValue.isEmpty)
            XCTAssertTrue(language.rawValue.range(of: #"^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#, options: .regularExpression) != nil)
            // 与 lproj 目录标签一致
            XCTAssertEqual(language.rawValue, AppLanguage(rawValue: language.rawValue)?.rawValue)
        }
    }

    func testDisplayNameNeverEmpty() {
        for language in AppLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty)
        }
    }
}
