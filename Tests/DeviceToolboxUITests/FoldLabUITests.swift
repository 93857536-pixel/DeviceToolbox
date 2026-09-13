import XCTest

/// UI 测试:折叠玻璃实验室 —— 验证入口存在、页面可进入、效果与控制项渲染。
final class FoldLabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动 → 实验 Tab(index 4)→ 进入「折叠玻璃实验室」→ 校验效果区/控制区与手动滑杆。
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

        // 实验 Tab(index 3):两个实验室入口 + 全应用特效开关收编在此
        tabBar.buttons.element(boundBy: 3).tap()

        // 入口卡片(常显):滚动到可见再点副标题(卡片整体是可点区域)
        let subtitle = app.staticTexts["转动手机,看界面透过倾斜玻璃窗"].firstMatch
        for _ in 0..<6 where !subtitle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(subtitle.waitForExistence(timeout: 8), "实验页应有折叠玻璃实验室入口")
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

    /// 回归:全应用折叠特效开启(且角度非零)后,当前页整棵子树被
    /// compositingGroup 压平 + 透视位移,页内那个关闭开关点不到
    /// (命中测试污染)→ "开了就关不掉"死锁(用户实测报告)。
    /// 根级逃生按钮套在 TabView 外层 overlay(不在任何 glassFold 子树内),
    /// 必须始终可点;点它之后特效关闭、按钮消失。
    ///
    /// 开启路径用 `-enableFoldEffect` launch argument(persist=false,确定性),
    /// 不依赖"点页内开关"——那条路径本身就会被玻璃压平污染,正是死锁现场。
    func testGlobalFoldEffectEscapeButtonRecoversDeadlock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetDisclaimer", "-enableFoldEffect"]
        app.launch()

        let acceptButton = app.buttons["disclaimer.accept"]
        if acceptButton.waitForExistence(timeout: 10) {
            acceptButton.tap()
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "应进入主界面")

        // 特效已由 launch argument 开启:根级逃生按钮此刻就应可见
        // (挂在 TabView 外层,不受任何 glassFold 影响)。
        let escape = app.buttons["关闭折叠特效"].firstMatch
        XCTAssertTrue(escape.waitForExistence(timeout: 8), "特效开启时应出现根级逃生按钮")

        // 实验 Tab(index 3)→ 进折叠玻璃实验室页
        tabBar.buttons.element(boundBy: 3).tap()
        let subtitle = app.staticTexts["转动手机,看界面透过倾斜玻璃窗"].firstMatch
        for _ in 0..<6 where !subtitle.isHittable {
            app.swipeUp()
        }
        subtitle.tap()
        XCTAssertTrue(
            app.navigationBars["折叠玻璃实验室"].waitForExistence(timeout: 8),
            "应进入折叠玻璃实验室"
        )

        // 把手动角度拉到非零:此刻特效已开,currentAngle ≠ 0,玻璃效果
        // **真的**套在当前整页上(死锁场景的最小复现条件)。
        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 8), "应有手动角度滑杆")
        slider.adjust(toNormalizedSliderPosition: 0.85)
        // 玻璃生效后稍候,让 layerEffect 栅格化落地
        Thread.sleep(forTimeInterval: 1.5)

        // 整页已玻璃化:页内开关点不到(死锁),但根级逃生按钮必须仍可点。
        for _ in 0..<10 where !escape.isHittable {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(escape.isHittable, "逃生按钮必须在整页玻璃化状态下可点")
        escape.tap()

        // 关掉了:逃生按钮消失
        var escapeGone = false
        for _ in 0..<30 {
            if !escape.exists {
                escapeGone = true
                break
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(escapeGone, "点逃生按钮后特效应关闭、按钮消失")
    }
}
