import XCTest
import Foundation
@testable import DeviceToolbox

/// 兼容性库查询测试:经 init(url:) 注入内嵌 JSON,不依赖 bundle / 真机。
final class CompatibilityTests: XCTestCase {

    // MARK: - 加载

    func testLoadAllItems() throws {
        let store = try makeStore(sampleJSON)
        XCTAssertEqual(store.allItems().count, 3)
    }

    func testItemByFeature() throws {
        let store = try makeStore(sampleJSON)
        let item = store.item(feature: "face-id")
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.id, "face-id")
        XCTAssertEqual(item?.status, CapabilityStatus.supported)
        XCTAssertEqual(item?.requiresPermission, true)
    }

    func testMissingFeatureReturnsNil() throws {
        let store = try makeStore(sampleJSON)
        XCTAssertNil(store.item(feature: "nonexistent"))
    }

    // MARK: - 状态分布

    func testStatusCoverage() throws {
        let store = try makeStore(sampleJSON)
        let items = store.allItems()
        let statuses = Set(items.map(\.status))
        XCTAssertTrue(statuses.contains(.supported))
        XCTAssertTrue(statuses.contains(.unsupported))
    }

    // MARK: - 失败路径

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try makeStore("not-json"))
    }

    func testMissingFileThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("definitely-missing-\(UUID().uuidString).json")
        XCTAssertThrowsError(try CompatibilityStore(url: url))
    }

    // MARK: - helpers

    private func makeStore(_ json: String) throws -> CompatibilityStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compat-test-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return try CompatibilityStore(url: url)
    }

    private let sampleJSON = """
    [
      {
        "id": "battery",
        "name": "电池状态读取",
        "feature": "battery",
        "minimumIOS": "10.0",
        "maximumIOS": "",
        "devices": [],
        "status": "supported",
        "requiresPermission": false,
        "detail": "通过 UIDevice 公开 API 读取电量与充电状态",
        "actions": [{"type": "test", "title": "测试", "value": ""}]
      },
      {
        "id": "face-id",
        "name": "面容 ID",
        "feature": "face-id",
        "minimumIOS": "11.0",
        "maximumIOS": "",
        "devices": [],
        "status": "supported",
        "requiresPermission": true,
        "detail": "经 LocalAuthentication 公开 API 检测面容 ID 是否可用",
        "actions": []
      },
      {
        "id": "build-number",
        "name": "系统 Build 号",
        "feature": "build-number",
        "minimumIOS": "1.0",
        "maximumIOS": "",
        "devices": [],
        "status": "unsupported",
        "requiresPermission": false,
        "detail": "Apple 未向第三方 App 开放 Build Number 读取",
        "actions": []
      }
    ]
    """
}
