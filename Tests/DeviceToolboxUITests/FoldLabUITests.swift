import XCTest

/// UI 测试:折叠玻璃实验室 —— 验证入口存在、页面可进入、效果与控制项渲染。
final class FoldLabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动 → 文件 Tab → 进入「折叠玻璃实验室」→ 校验效果区/控制区与手动滑杆。
    /// 模拟器无姿态传感器,应自动落手动模式(即出现滑杆且可调)。
    func testFoldLabRendersAndControlsWork() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetDisclaimer"]
        app.launch()

        let acceptButton = app.buttons["disclaimer.accept"]
        if acceptButton.waitForExistence(timeout: 10) {
            acceptButton.tap()
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "应进入主界面")

        // 文件 Tab(index 2)
        tabBar.buttons.element(boundBy: 2).tap()

        // 入口卡片(常显):滚动到可见再点副标题(卡片整体是可点区域)
        let subtitle = app.staticTexts["转动手机,看界面透过倾斜玻璃窗"].firstMatch
        for _ in 0..<6 where !subtitle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(subtitle.waitForExistence(timeout: 8), "文件页应有折叠玻璃实验室入口")
        subtitle.tap()

        // 页面标题
        XCTAssertTrue(app.navigationBars["折叠玻璃实验室"].waitForExistence(timeout: 8), "应进入折叠玻璃实验室")

        // 效果区与实时倾角读数
        XCTAssertTrue(app.staticTexts["效果"].waitForExistence(timeout: 8), "应有效果分区")
        XCTAssertTrue(app.staticTexts["实时倾角"].waitForExistence(timeout: 8), "应有实时倾角读数")

        // 模拟器下应给出「无姿态传感器」提示并落手动模式
        XCTAssertTrue(
            app.staticTexts["当前设备无姿态传感器(模拟器),已自动切手动模式。"].waitForExistence(timeout: 8),
            "模拟器应提示无传感器并切手动模式"
        )

        // 控制区滑杆可用:调整后倾角读数应发生变化
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 8), "应有手动角度滑杆")
        slider.adjust(toNormalizedSliderPosition: 0.85)

        let angleLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '°'")).firstMatch
        XCTAssertTrue(angleLabel.waitForExistence(timeout: 8), "倾角读数应存在")
        XCTAssertFalse(angleLabel.label.hasPrefix("+0.0"), "拖动滑杆后倾角读数应变化")
    }
}
