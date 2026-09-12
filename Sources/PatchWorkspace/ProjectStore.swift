import Foundation

// MARK: - 项目库索引条目

/// 项目库索引条目(列表展示用的明文元数据,避免为列出列表而解密私密包)。
struct ProjectIndexEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { projectID }
    let projectID: UUID
    let name: String
    let author: String
    let isPrivate: Bool
    let createdAt: Date
    let updatedAt: Date
    let targetRootName: String
    let origin: PatchProjectOrigin?
    let filename: String
    let ruleCount: Int

    init(
        projectID: UUID,
        name: String,
        author: String,
        isPrivate: Bool,
        createdAt: Date,
        updatedAt: Date,
        targetRootName: String,
        origin: PatchProjectOrigin?,
        filename: String,
        ruleCount: Int
    ) {
        self.projectID = projectID
        self.name = name
        self.author = author
        self.isPrivate = isPrivate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.targetRootName = targetRootName
        self.origin = origin
        self.filename = filename
        self.ruleCount = ruleCount
    }
}

// MARK: - 项目库

/// 项目库持久化层:Documents/Patches/Projects/*.dtbp + index.json。
/// 包体经 `PatchPackageCodec` 编码(含 replacementData 文件内容)。
struct ProjectStore: Sendable {
    let projectsRoot: URL

    init(projectsRoot: URL = ProjectStore.defaultProjectsRoot()) {
        self.projectsRoot = projectsRoot
    }

    static func defaultProjectsRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Patches/Projects", isDirectory: true)
    }

    // MARK: - 路径

    var indexURL: URL {
        projectsRoot.appendingPathComponent("index.json", isDirectory: false)
    }

    private func packageURL(filename: String) -> URL {
        projectsRoot.appendingPathComponent(filename, isDirectory: false)
    }

    // MARK: - 读

    func list() -> [ProjectIndexEntry] {
        (try? readIndex()) ?? []
    }

    func entry(id: UUID) -> ProjectIndexEntry? {
        list().first { $0.projectID == id }
    }

    /// 解码单个项目(私密项目需传入密码)。
    func load(id: UUID, password: String?) throws -> PatchProject {
        guard let entry = entry(id: id) else {
            throw PatchWorkspaceError.notFound
        }
        let data = try Data(contentsOf: packageURL(filename: entry.filename))
        return try PatchPackageCodec.decodePackage(data, password: password).project
    }

    // MARK: - 写

    /// 保存项目:编码为 DTBP 并落盘,同步更新索引。私密项目需密码。
    func save(_ project: PatchProject, password: String?) throws {
        let data = try PatchPackageCodec.encodePackage(project: project, password: password)
        let filename = "\(project.id.uuidString).dtbp"
        do {
            try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
            try data.write(to: packageURL(filename: filename), options: .atomic)
        } catch {
            throw PatchWorkspaceError.writeFailed
        }
        var index = (try? readIndex()) ?? []
        index.removeAll { $0.projectID == project.id }
        index.append(ProjectIndexEntry(
            projectID: project.id,
            name: project.name,
            author: project.author,
            isPrivate: project.isPrivate,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            targetRootName: project.targetRootName,
            origin: project.origin,
            filename: filename,
            ruleCount: project.rules.count
        ))
        try writeIndex(index)
    }

    func delete(id: UUID) throws {
        var index = (try? readIndex()) ?? []
        guard let entry = index.first(where: { $0.projectID == id }) else {
            return
        }
        try? FileManager.default.removeItem(at: packageURL(filename: entry.filename))
        index.removeAll { $0.projectID == id }
        try writeIndex(index)
    }

    // MARK: - 索引持久化

    private func readIndex() throws -> [ProjectIndexEntry] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        return try jsonDecoder().decode([ProjectIndexEntry].self, from: data)
    }

    private func writeIndex(_ entries: [ProjectIndexEntry]) throws {
        do {
            try jsonEncoder().encode(entries).write(to: indexURL, options: .atomic)
        } catch {
            throw PatchWorkspaceError.writeFailed
        }
    }

    private func jsonEncoder() -> JSONEncoder {
        JSONEncoder()
    }

    private func jsonDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
