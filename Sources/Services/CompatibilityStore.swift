import Foundation

/// 本地 JSON 兼容性数据库加载与查询(纯数据,不绑 MainActor)。
/// 供 FeatureViewModel / CapabilityService 读取;单元测试经 init(url:) 注入。
final class CompatibilityStore: Sendable {
    /// bundle 内置库;文件缺失或解码失败时回退为空库(不 crash)。
    static let bundled: CompatibilityStore = {
        guard let url = Bundle.main.url(forResource: "compatibility_db", withExtension: "json") else {
            return CompatibilityStore(items: [])
        }
        if let store = try? CompatibilityStore(url: url) {
            return store
        }
        return CompatibilityStore(items: [])
    }()

    private let items: [CompatibilityItem]

    /// 从指定 URL 解码;解码失败 throw(单元测试注入用)。
    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        self.items = try JSONDecoder().decode([CompatibilityItem].self, from: data)
    }

    private init(items: [CompatibilityItem]) {
        self.items = items
    }

    /// 返回全部条目(缓存后)。
    func allItems() -> [CompatibilityItem] {
        items
    }

    /// 按 feature 字段查询单条;找不到返回 nil。
    func item(feature: String) -> CompatibilityItem? {
        items.first { $0.feature == feature }
    }
}
