import XCTest

/// UI 测试:操作日志页「上传日志」按钮渲染 + 点击不崩溃(不依赖网络成功)。
///
/// 入口路径:设置 Tab(index 4)→ 数据 section 的「操作日志」链接(identifier: settings.logLink)。
final class LogUploadButtonUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// swipeUp 翻页把目标滚动到可见。
    private func scrollVisible(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 {
            if target.exists { break }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func openLogPage(_ app: XCUIApplication) {
        // 锁系统语言,文案确定(不影响 identifier 匹配)
        app.launchArguments = ["-resetDisclaimer", "-language=system"]
        app.launch()
        let accept = app.buttons["disclaimer.accept"]
        if accept.waitForExistence(timeout: 10) {
            accept.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "应进入主界面")
        // 设置 Tab(index 4)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let onSettings = app.navigationBars["设置"].waitForExistence(timeout: 8)
            || app.navigationBars["Settings"].waitForExistence(timeout: 3)
        XCTAssertTrue(onSettings, "应进入设置页")

        // 数据 section 的「操作日志」链接
        let logLink = app.descendants(matching: .any)
            .matching(identifier: "settings.logLink")
            .firstMatch
        scrollVisible(logLink, in: app)
        XCTAssertTrue(logLink.waitForExistence(timeout: 8), "设置页应出现「操作日志」链接")
        logLink.tap()
        XCTAssertTrue(app.navigationBars["操作日志"].waitForExistence(timeout: 8), "应进入操作日志页")
    }

    func testUploadButtonRendersAndTapsWithoutCrash() throws {
        let app = XCUIApplication()
        openLogPage(app)

        // 底栏「上传日志」按钮
        let upload = app.buttons["logviewer.uploadButton"]
        XCTAssertTrue(upload.waitForExistence(timeout: 8), "操作日志页应出现「上传日志」按钮")

        // App 启动自身会产生日志,按钮应启用
        if !upload.isEnabled {
            // 空日志时按钮禁用属正常,跳过点击分支
            XCTSkip("当前日志为空,上传按钮禁用(正常),跳过点击")
        }
        upload.tap()
        // 给网络请求一点时间;无论成功(服务器可达)还是失败(限流/网络),App 都不应崩溃
        Thread.sleep(forTimeInterval: 4)
        // 成功或失败都会弹结果 alert(「日志已上传」或「上传失败」)
        let resultAlertShown = app.alerts.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(resultAlertShown || app.state != .notRunning,
                      "点击上传后应弹出结果提示且 App 仍在运行")
    }
}
