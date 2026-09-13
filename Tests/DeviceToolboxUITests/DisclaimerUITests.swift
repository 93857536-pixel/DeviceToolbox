import XCTest

/// UI 测试:首次启动免责声明流程。
/// 依赖 App 入口对 `-resetDisclaimer` launch argument 的处理(见 DeviceToolboxApp.init),
/// 该参数会在启动时清除 UserDefaults 中的免责声明同意状态,稳定复现首次启动。
final class DisclaimerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 首次启动 → 显示免责声明 → 同意 → 进入主界面(6 Tab)。
    func testFirstLaunchShowsDisclaimerThenMainUI() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetDisclaimer"]
        app.launch()

        // 1. 首次启动应显示免责声明的同意按钮
        let acceptButton = app.buttons["disclaimer.accept"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 10), "首次启动应显示免责声明")

        // 2. 点击「同意」
        acceptButton.tap()

        // 3. 同意后进入主界面,出现 6 个 Tab
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "同意后应进入主界面")
        XCTAssertEqual(app.tabBars.buttons.count, 5, "主界面应有 5 个 Tab")
    }
}
