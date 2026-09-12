import Combine
import Foundation

/// 功能中心状态:兼容性库条目 × 运行时能力评估 → 功能列表,支持按状态筛选。
@MainActor
final class FeatureViewModel: ObservableObject {
    @Published private(set) var items: [FeatureItem] = []
    @Published private(set) var isLoading = false
    @Published var filterStatus: CapabilityStatus? = nil

    private let capabilityService = CapabilityService()

    /// 按当前筛选状态过滤后的功能列表。
    var filteredItems: [FeatureItem] {
        guard let filterStatus else { return items }
        return items.filter { $0.status == filterStatus }
    }

    /// 各状态数量(用于筛选标签)。
    func count(of status: CapabilityStatus) -> Int {
        items.count(where: { $0.status == status })
    }

    /// 加载:兼容性库全量条目 + CapabilityService 运行时评估合并。
    func load() async {
        isLoading = true
        defer { isLoading = false }

        let storeItems = CompatibilityStore.bundled.allItems()
        let evaluated = await capabilityService.evaluate()
        var evaluatedByID: [String: CapabilityResult] = [:]
        for result in evaluated {
            if evaluatedByID[result.id] == nil {
                evaluatedByID[result.id] = result
            }
        }

        // 设备标识符用于 applies(to:) 判定。
        let machineIdentifier = SystemInfoService().collect().machineIdentifier

        items = storeItems.map { item in
            let result = evaluatedByID[item.id]
            return FeatureItem(
                id: item.id,
                name: item.name,
                icon: Self.icon(for: item.feature),
                status: result?.status ?? item.status,
                minimumIOS: item.minimumIOS,
                detail: result?.detail ?? item.detail,
                urlScheme: nil,
                requiresPermission: item.requiresPermission,
                source: .database,
                isApplicable: item.applies(to: machineIdentifier)
            )
        }
    }

    /// 功能键 → SF Symbol 图标名(UI 层映射,与兼容库 feature 键对齐)。
    static func icon(for feature: String) -> String {
        switch feature {
        case "battery": return "battery.100"
        case "screen-refresh": return "gauge.with.dots.needle.50percent"
        case "build-number": return "number.circle"
        case "face-id": return "faceid"
        case "touch-id": return "touchid"
        case "nfc": return "wave.3.right"
        case "5g": return "antenna.radiowaves.left.and.right"
        case "esim": return "simcard.2"
        case "dynamic-island": return "capsule.portrait"
        case "always-on-display": return "display"
        case "camera": return "camera"
        case "microphone": return "mic"
        case "location": return "location"
        case "notifications": return "bell"
        case "photos": return "photo"
        case "contacts": return "person.crop.circle"
        case "bluetooth": return "bluetooth"
        case "wireless-charging": return "battery.100.bolt"
        case "reverse-charging": return "bolt.batteryblock"
        case "spatial-audio": return "airpods.max"
        case "assistive-touch": return "hand.tap"
        default: return "square.grid.2x2"
        }
    }
}
