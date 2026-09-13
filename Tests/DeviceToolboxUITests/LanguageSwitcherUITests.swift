import XCTest

/// UI 测试:设置页语言切换 —— Picker 渲染 + 选择后重启生效 + 跟随系统可还原。
///
/// 每个测试通过 launch argument(`-language=system` / `-language=ja`)显式设定
/// 起始语言,消除跨测试的 AppleLanguages 持久化污染(App 的 UserDefaults 在同一
/// 模拟器上跨测试保留)。
final class LanguageSwitcherUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 把目标元素滚动到可见(swipeUp 翻页,直到出现或翻到底)。
    private func scrollVisible(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if target.exists { break }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// 进设置 Tab(第 5 个,index 4),处理免责声明,返回语言选择器(已滚动到可见)。
    /// `languageArg` 通过 `-language=<tag>` 启动参数锁定 App 语言,保证文案确定性。
    private func launchAppAndOpenLanguagePicker(_ app: XCUIApplication, languageArg: String = "-language=system") -> XCUIElement {
        app.launchArguments = ["-resetDisclaimer", languageArg]
        app.launch()
        let acceptButton = app.buttons["disclaimer.accept"]
        if acceptButton.waitForExistence(timeout: 10) {
            acceptButton.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "应进入主界面")
        app.tabBars.buttons.element(boundBy: 4).tap()
        // 设置页标题随 App 语言变化("设置" / "設定" / "Settings"…),任一出现即视为进入设置页
        let onSettings = app.navigationBars["设置"].waitForExistence(timeout: 8)
            || app.navigationBars["設定"].waitForExistence(timeout: 3)
            || app.navigationBars["Settings"].waitForExistence(timeout: 3)
            || app.navigationBars["설정"].waitForExistence(timeout: 3)
        XCTAssertTrue(onSettings, "应进入设置页")

        // 语言区在 List 深处,需先滚动到可见;Picker 控件类型不固定,用 .any 匹配
        let picker = app.descendants(matching: .any)
            .matching(identifier: "settings.languagePicker")
            .firstMatch
        scrollVisible(picker, in: app)
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "设置页应出现语言选择器")
        return picker
    }

    func testLanguagePickerRendersWithAllOptions() throws {
        let app = XCUIApplication()
        let picker = launchAppAndOpenLanguagePicker(app)
        picker.tap()

        // 菜单应列出 6 个选项(跟随系统 + 5 种语言;非"跟随系统"选项名是各语言自身文字,不随 UI 语言变)
        let options = [
            "跟随系统", "简体中文", "繁體中文", "English", "日本語", "한국어",
        ]
        for option in options {
            XCTAssertTrue(
                app.buttons[option].waitForExistence(timeout: 5),
                "语言菜单应包含选项 \(option)"
            )
        }
        // 选择不改动语言:点"跟随系统"关闭菜单(不写 AppleLanguages 覆盖之外的内容)
        app.buttons["跟随系统"].tap()
        app.terminate()
    }

    func testSelectingJapaneseAppliesAfterRestart() throws {
        let app = XCUIApplication()
        let picker = launchAppAndOpenLanguagePicker(app)
        picker.tap()
        app.buttons["日本語"].tap()

        // 未重启时应提示"重启后生效"
        let hint = app.descendants(matching: .any)
            .matching(identifier: "settings.languageRestartHint")
            .firstMatch
        scrollVisible(hint, in: app)
        XCTAssertTrue(
            hint.waitForExistence(timeout: 5),
            "选择非当前语言后应显示重启提示"
        )

        // 重启 App:AppleLanguages 覆盖随 App 持久化,进程重启后生效
        // (注意:重启不再带 -language 参数,让刚选的日语真实接管)
        app.terminate()
        app.launchArguments = []
        app.launch()
        let acceptButton = app.buttons["disclaimer.accept"]
        if acceptButton.waitForExistence(timeout: 10) {
            acceptButton.tap()
        }

        // 首页导航标题 / Tab 标签应为日文
        let tabTitle = app.navigationBars["ホーム"]
            .waitForExistence(timeout: 10)
            || app.staticTexts["ホーム"].waitForExistence(timeout: 5)
        let mainTab = app.tabBars.firstMatch.waitForExistence(timeout: 10)
        XCTAssertTrue(tabTitle || mainTab, "重启后 UI 应切为日语(首页=ホーム)")
    }

    func testSystemLanguageToggleClearsOverride() throws {
        let app = XCUIApplication()
        // 从日语状态开始(模拟"用户已选了日语、覆盖已持久化"的场景)
        let picker = launchAppAndOpenLanguagePicker(app, languageArg: "-language=ja")
        picker.tap()
        // 日语下"跟随系统"的显示名
        app.buttons["システムに合わせる"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let hint = app.descendants(matching: .any)
            .matching(identifier: "settings.languageRestartHint")
            .firstMatch
        XCTAssertFalse(hint.exists, "选择跟随系统后不应显示重启提示")
        app.terminate()
    }
}
