import XCTest
@testable import DeviceToolbox

/// AIEnablePolicy 版本×机型矩阵单测(纯判定,模拟器可跑)。
final class AIEnablePolicyTests: XCTestCase {

    private func verdict(_ model: String, _ v: (Int, Int, Int), build: String? = nil, sim: Bool = false) -> AIEnablePolicy.Verdict {
        AIEnablePolicy.verdict(model: model, major: v.0, minor: v.1, patch: v.2, build: build, isSimulator: sim)
    }

    // MARK: - 官方硬件白名单

    func testOfficialAISupportModels() {
        XCTAssertTrue(AIEnablePolicy.isOfficialAISupport(model: "iPhone16,1"))   // 15 Pro
        XCTAssertTrue(AIEnablePolicy.isOfficialAISupport(model: "iPhone16,2"))   // 15 Pro Max
        XCTAssertTrue(AIEnablePolicy.isOfficialAISupport(model: "iPhone17,3"))   // 16
        XCTAssertTrue(AIEnablePolicy.isOfficialAISupport(model: "iPhone18,1"))   // 17 Pro
        XCTAssertTrue(AIEnablePolicy.isOfficialAISupport(model: "iPad13,4"))     // M1 iPad Pro
        XCTAssertTrue(AIEnablePolicy.isOfficialAISupport(model: "iPad16,1"))     // mini A17 Pro
        XCTAssertFalse(AIEnablePolicy.isOfficialAISupport(model: "iPhone15,4"))  // 15 (A16)
        XCTAssertFalse(AIEnablePolicy.isOfficialAISupport(model: "iPhone15,5"))  // 15 Plus (A16)
        XCTAssertFalse(AIEnablePolicy.isOfficialAISupport(model: "iPhone14,8"))  // SE 3
    }

    // MARK: - 版本窗口

    func testSimulatorUnavailable() {
        let v = verdict("iPhone16,1", (26, 0, 0), sim: true)
        XCTAssertEqual(v.target, .unavailable)
        XCTAssertFalse(v.isActionable)
    }

    func testNoAIFrameworkBefore181() {
        XCTAssertEqual(verdict("iPhone16,1", (17, 5, 0)).target, .unavailable)   // 17.x 无 AI
        XCTAssertEqual(verdict("iPhone15,4", (18, 0, 0)).target, .unavailable)   // 18.0 无 AI
    }

    func testHardwareSpoofDeadOn181StableForA16() {
        // ≤A16 + 18.1 正式版(服务端断言)
        XCTAssertEqual(verdict("iPhone15,5", (18, 1, 0)).target, .unavailable)
        // ≤A16 + 18.5
        XCTAssertEqual(verdict("iPhone15,5", (18, 5, 0)).target, .unavailable)
    }

    func testRegionUnlockOn18xOfficialHardware() {
        let v = verdict("iPhone16,1", (18, 5, 0))
        XCTAssertEqual(v.target, .regionUnlock)
        XCTAssertFalse(v.experimental)
        XCTAssertTrue(v.requiresEscape)
        XCTAssertTrue(v.isActionable)
    }

    func testHardwareSpoofWindow26dot0ForA16() {
        let v = verdict("iPhone15,5", (26, 0, 0))
        XCTAssertEqual(v.target, .hardwareSpoof)
        XCTAssertTrue(v.experimental)
        XCTAssertTrue(v.requiresEscape)
        XCTAssertTrue(v.isActionable)
    }

    func testKernelWindowStopsAt261() {
        // 内核链 17.0–26.0.x;26.1 无通道
        XCTAssertEqual(verdict("iPhone15,5", (26, 1, 0)).target, .unavailable)
        XCTAssertEqual(verdict("iPhone16,1", (26, 1, 0)).target, .unavailable)
        XCTAssertEqual(verdict("iPhone16,1", (26, 6, 1)).target, .unavailable)
    }

    func testRegionUnlockOn26dot0OfficialHardware() {
        let v = verdict("iPhone16,1", (26, 0, 0))
        XCTAssertEqual(v.target, .regionUnlock)
        XCTAssertFalse(v.experimental)
        XCTAssertTrue(v.requiresEscape)
    }

    func testBadQueryRouteOn27Beta1to4() {
        // 27.0 b1(build 命中)→ AI 硬件:实验性地区解锁,不需内核逃逸(走 bad_query)
        let v = verdict("iPhone16,1", (27, 0, 0), build: "24A5355q")
        XCTAssertEqual(v.target, .regionUnlock)
        XCTAssertTrue(v.experimental)
        XCTAssertFalse(v.requiresEscape)
        XCTAssertTrue(v.isActionable)
    }

    func test27BetaA16HardwareUnavailable() {
        // mond 已知问题:27 b1-4 AI 伪装在 ≤A16 失效
        XCTAssertEqual(verdict("iPhone15,5", (27, 0, 0), build: "24A5355q").target, .unavailable)
    }

    func test27StableOrUnknownBuildUnavailable() {
        XCTAssertEqual(verdict("iPhone16,1", (27, 0, 0), build: "24B0000x").target, .unavailable)
        XCTAssertEqual(verdict("iPhone16,1", (27, 5, 0), build: nil).target, .unavailable)
    }
}
