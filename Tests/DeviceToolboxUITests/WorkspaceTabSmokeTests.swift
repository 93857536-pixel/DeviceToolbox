import XCTest

/// UI 测试:工作台 Tab 冒烟 —— 验证「文件」「补丁」两个新 Tab 可进入且内容渲染。
final class WorkspaceTabSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动(若显示免责声明则同意)→ 文件 Tab → 补丁 Tab → 设置 Tab 往返。
    func testWorkspaceTabsRender() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetDisclaimer"]
        app.launch()

        // 首次启动处理免责声明
        let acceptButton = app.buttons["disclaimer.accept"]
        if acceptButton.waitForExistence(timeout: 10) {
            acceptButton.tap()
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "应进入主界面")
        XCTAssertEqual(app.tabBars.buttons.count, 5, "主界面应有 5 个 Tab")

        // 文件 Tab(index 2):应出现「文件」导航标题或沙盒目录区
        app.tabBars.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(
            app.navigationBars["文件"].waitForExistence(timeout: 8)
                || app.staticTexts["沙盒目录"].waitForExistence(timeout: 8),
            "文件 Tab 应渲染工作台内容"
        )

        // 补丁 Tab(index 3):应出现「补丁」标题或项目库空态
        app.tabBars.buttons.element(boundBy: 3).tap()
        XCTAssertTrue(
            app.navigationBars["补丁"].waitForExistence(timeout: 8)
                || app.staticTexts["项目库"].waitForExistence(timeout: 8)
                || app.staticTexts["暂无补丁项目"].waitForExistence(timeout: 8),
            "补丁 Tab 应渲染项目库内容"
        )

        // 回首页(index 0)确认 tab 往返正常
        app.tabBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["首页"].waitForExistence(timeout: 8), "应能回到首页")
    }
}
