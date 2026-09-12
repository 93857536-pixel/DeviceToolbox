import XCTest
import Foundation
@testable import DeviceToolbox

/// 解析/模型/兼容库单元测试(纯内存,不依赖真机、不依赖 bundle)。
/// fixture 全部使用内嵌 JSON 字符串。
final class DeviceInfoParsingTests: XCTestCase {

    // MARK: - 模型解码

    func testDecodeDeviceInfo() throws {
        let info = try JSONDecoder().decode(DeviceInfo.self, from: Data(deviceInfoJSON.utf8))

        XCTAssertEqual(info.hardware.model, "iPhone")
        XCTAssertEqual(info.hardware.machineIdentifier, "iPhone17,1")
        XCTAssertEqual(info.hardware.marketingName, "iPhone 16 Pro")
        XCTAssertEqual(info.hardware.totalRAMBytes, 8589934592)
        XCTAssertEqual(info.hardware.processorCount, 6)

        XCTAssertEqual(info.software.systemName, "iOS")
        XCTAssertEqual(info.software.systemVersion, "17.5")
        XCTAssertNil(info.software.buildNumber)
        XCTAssertEqual(info.software.preferredLanguages, ["zh-Hans-CN", "en"])

        XCTAssertEqual(info.storage.totalBytes, 256000000000)
        XCTAssertEqual(info.storage.freeBytes, 128000000000)
        XCTAssertEqual(info.storage.usedBytes, 128000000000)
        XCTAssertEqual(info.storage.isReadonly, false)

        XCTAssertEqual(info.battery.state, BatteryState.charging)
        XCTAssertEqual(info.battery.level, 0.85)
        XCTAssertEqual(info.battery.isMonitoringEnabled, true)
        XCTAssertEqual(info.battery.isLowPowerModeEnabled, false)

        XCTAssertEqual(info.screen.widthPoints, 393)
        XCTAssertEqual(info.screen.maximumFramesPerSecond, 120)
        XCTAssertEqual(info.screen.refreshRateDescription, "约 120 Hz")

        XCTAssertEqual(info.network.status, NetworkStatus.satisfied)
        XCTAssertEqual(info.network.interfaceType, NetworkInterfaceType.wifi)
        XCTAssertEqual(info.network.interfaceNames, ["en0"])
        XCTAssertEqual(info.network.supportsIPv4, true)
        XCTAssertEqual(info.network.supportsIPv6, true)

        XCTAssertEqual(info.system.cpuArchitecture, "arm64")
        XCTAssertEqual(info.system.machineIdentifier, "iPhone17,1")
        XCTAssertEqual(info.system.hostname, "iPhone")
    }

    func testDecodeCompatibilityItem() throws {
        let item = try JSONDecoder().decode(CompatibilityItem.self, from: Data(itemJSON("10.0", "").utf8))

        XCTAssertEqual(item.id, "test-feature")
        XCTAssertEqual(item.name, "测试功能")
        XCTAssertEqual(item.feature, "test-feature")
        XCTAssertEqual(item.status, CapabilityStatus.supported)
        XCTAssertEqual(item.devices, ["iPhone17,1"])
        XCTAssertEqual(item.requiresPermission, false)
        XCTAssertEqual(item.actions.count, 1)
        XCTAssertEqual(item.actions.first?.type, "test" as String?)
        XCTAssertEqual(item.actions.first?.title, "测试" as String?)
        XCTAssertEqual(item.actions.first?.value, "" as String?)
    }

    // MARK: - 版本解析

    func testVersionParsing() throws {
        let item = try JSONDecoder().decode(CompatibilityItem.self, from: Data(itemJSON("15.0", "").utf8))
        XCTAssertEqual(item.minimumVersion?.majorVersion, 15)
        XCTAssertEqual(item.minimumVersion?.minorVersion, 0)
        XCTAssertEqual(item.minimumVersion?.patchVersion, 0)
        XCTAssertNil(item.maximumVersion)
    }

    // MARK: - 设备适用性

    func testAppliesToDevice() throws {
        let item = try JSONDecoder().decode(CompatibilityItem.self, from: Data(itemJSON("15.0", "").utf8))
        XCTAssertTrue(item.applies(to: nil))
        XCTAssertTrue(item.applies(to: "iPhone17,1"))
        XCTAssertFalse(item.applies(to: "iPhone12,1"))
    }

    // MARK: - 系统版本支持判定

    func testIsSupportedByOSVersion() throws {
        let item = try JSONDecoder().decode(CompatibilityItem.self, from: Data(itemJSON("15.0", "16.0").utf8))

        XCTAssertFalse(item.isSupported(by: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)))
        XCTAssertTrue(item.isSupported(by: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)))
        XCTAssertTrue(item.isSupported(by: OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)))
        XCTAssertFalse(item.isSupported(by: OperatingSystemVersion(majorVersion: 16, minorVersion: 1, patchVersion: 0)))
    }

    // MARK: - 状态枚举解码

    func testCapabilityStatusDecoding() throws {
        XCTAssertEqual(try decodeStatus("supported"), CapabilityStatus.supported)
        XCTAssertEqual(try decodeStatus("partial"), CapabilityStatus.partial)
        XCTAssertEqual(try decodeStatus("unsupported"), CapabilityStatus.unsupported)
        XCTAssertThrowsError(try decodeStatus("banana"))
    }

    // MARK: - fixtures

    private func itemJSON(_ minimum: String, _ maximum: String) -> String {
        return """
        {
          "id": "test-feature",
          "name": "测试功能",
          "feature": "test-feature",
          "minimumIOS": "\(minimum)",
          "maximumIOS": "\(maximum)",
          "devices": ["iPhone17,1"],
          "status": "supported",
          "requiresPermission": false,
          "detail": "测试说明",
          "actions": [{"type": "test", "title": "测试", "value": ""}]
        }
        """
    }

    private func decodeStatus(_ raw: String) throws -> CapabilityStatus {
        let wrapper = try JSONDecoder().decode(StatusWrapper.self, from: Data("{\"status\":\"\(raw)\"}".utf8))
        return wrapper.status
    }

    private struct StatusWrapper: Codable {
        let status: CapabilityStatus
    }

    private let deviceInfoJSON = """
    {
      "hardware": {
        "model": "iPhone",
        "machineIdentifier": "iPhone17,1",
        "marketingName": "iPhone 16 Pro",
        "deviceType": "iPhone",
        "totalRAMBytes": 8589934592,
        "processorCount": 6,
        "activeProcessorCount": 6
      },
      "software": {
        "systemName": "iOS",
        "systemVersion": "17.5",
        "versionString": "Version 17.5 (Build 21F79)",
        "buildNumber": null,
        "systemUptime": 12345.67,
        "localeIdentifier": "zh_Hans_CN",
        "preferredLanguages": ["zh-Hans-CN", "en"]
      },
      "storage": {
        "totalBytes": 256000000000,
        "freeBytes": 128000000000,
        "usedBytes": 128000000000,
        "isReadonly": false
      },
      "battery": {
        "level": 0.85,
        "state": "charging",
        "isMonitoringEnabled": true,
        "isLowPowerModeEnabled": false
      },
      "screen": {
        "widthPoints": 393,
        "heightPoints": 852,
        "scale": 3,
        "nativeWidth": 1179,
        "nativeHeight": 2556,
        "nativeScale": 3,
        "brightness": 0.5,
        "maximumFramesPerSecond": 120,
        "refreshRateDescription": "约 120 Hz"
      },
      "network": {
        "status": "satisfied",
        "interfaceType": "wifi",
        "interfaceNames": ["en0"],
        "isExpensive": false,
        "isConstrained": false,
        "supportsIPv4": true,
        "supportsIPv6": true
      },
      "system": {
        "cpuArchitecture": "arm64",
        "isSimulator": false,
        "machineIdentifier": "iPhone17,1",
        "kernelVersion": "Darwin 24.5.0 arm64",
        "hostname": "iPhone"
      }
    }
    """
}
