import XCTest
@testable import DeviceToolbox

/// 特权引擎支持矩阵测试:版本×芯片判定逻辑(纯内存,注入参数)。
final class PrivilegeMatrixTests: XCTestCase {
    private func verdict(_ major: Int, _ minor: Int, _ patch: Int,
                         soc: DeviceProbe.SoCFamily, sim: Bool = false) -> SupportMatrix.Verdict {
        SupportMatrix.verdict(
            soC: soc,
            iosVersion: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch),
            isSimulator: sim
        )
    }

    // MARK: - DarkSword 验证档

    func testDarkSwordVerifiediOS17() {
        let v = verdict(17, 5, 0, soc: .a14)
        XCTAssertEqual(v.chain, .darksword)
        XCTAssertEqual(v.tier, .verified)
        XCTAssertTrue(v.isSupported)
    }

    func testDarkSwordVerifiediOS18_7_1() {
        let v = verdict(18, 7, 1, soc: .a15)
        XCTAssertEqual(v.chain, .darksword)
        XCTAssertEqual(v.tier, .verified)
    }

    func testDarkSwordVerifiediOS26_0_1() {
        let v = verdict(26, 0, 1, soc: .a16)
        XCTAssertEqual(v.chain, .darksword)
        XCTAssertEqual(v.tier, .verified)
    }

    func testiOS26_1IsClaimed() {
        let v = verdict(26, 1, 0, soc: .a14)
        XCTAssertEqual(v.chain, .darksword)
        XCTAssertEqual(v.tier, .claimed)
    }

    // MARK: - 封堵/无链档

    func testiOS18_7_2Patched() {
        let v = verdict(18, 7, 2, soc: .a14)
        XCTAssertEqual(v.chain, .none)
        XCTAssertFalse(v.isSupported)
    }

    func testiOS26_2NoChain() {
        let v = verdict(26, 2, 0, soc: .a14)
        XCTAssertEqual(v.chain, .none)
    }

    func testiOS27NoChain() {
        let v = verdict(27, 0, 0, soc: .a14)
        XCTAssertEqual(v.chain, .none)
    }

    func testiOS15Experimental() {
        let v = verdict(16, 6, 0, soc: .a13)
        XCTAssertEqual(v.chain, .darksword)
        XCTAssertEqual(v.tier, .experimental)
    }

    // MARK: - 芯片硬排除

    func testA19ExcludedEverywhere() {
        XCTAssertEqual(verdict(17, 0, 0, soc: .a19).chain, .none)
        XCTAssertEqual(verdict(26, 0, 0, soc: .a19).chain, .none)
        XCTAssertFalse(verdict(18, 5, 0, soc: .a19).isSupported)
    }

    func testM5ExcludedEverywhere() {
        XCTAssertEqual(verdict(26, 0, 1, soc: .m5).chain, .none)
    }

    func testUnknownSoCNotMatched() {
        XCTAssertEqual(verdict(18, 5, 0, soc: .unknown).chain, .none)
    }

    func testSimulatorAlwaysUnsupported() {
        let v = verdict(26, 5, 0, soc: .a18, sim: true)
        XCTAssertEqual(v.chain, .none)
        XCTAssertFalse(v.isSupported)
    }

    // MARK: - SoC 识别映射

    func testSoCMapping() {
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPhone15,4"), .a17)
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPhone16,2"), .a18)
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPhone18,2"), .a19)
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPhone14,6"), .a15)
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPhone11,8"), .a12)
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPad8,1"), .a12)
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPad17,1"), .m4)
        XCTAssertEqual(DeviceProbe.socFamily(model: "iPad18,1"), .m5)
        XCTAssertEqual(DeviceProbe.socFamily(model: "x86_64"), .unknown)
        XCTAssertEqual(DeviceProbe.socFamily(model: "UnknownThing"), .unknown)
    }
}
