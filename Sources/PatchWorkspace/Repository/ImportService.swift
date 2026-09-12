import Foundation

// MARK: - 仓库导入服务

/// 下载仓库包 → 解码(DTBP / 3105)→ 记录来源 → 导入项目库。
enum RepositoryImportService {
    static func importPackage(
        from entry: RepositoryIndexEntry,
        source: RepositorySource,
        repository: RepositoryStore,
        projectStore: ProjectStore,
        password: String? = nil
    ) async throws -> PatchProject {
        let data = try await repository.download(entry)

        var project: PatchProject
        switch PatchPackageCodec.detectFormat(data) {
        case .dtbp:
            project = try PatchPackageCodec.decodePackage(data, password: password).project
        case .legacy3105:
            project = try PatchPackageCodec.import3105Package(
                data,
                password: password,
                origin: PatchProjectOrigin(
                    repositoryName: source.name,
                    repositoryURL: source.baseURL.absoluteString,
                    packageIdentifier: entry.id
                )
            )
        case nil:
            throw RepositoryError.importFailed
        }

        if project.origin == nil {
            project.origin = PatchProjectOrigin(
                repositoryName: source.name,
                repositoryURL: source.baseURL.absoluteString,
                packageIdentifier: entry.id
            )
        }

        do {
            try projectStore.save(project, password: password)
        } catch {
            throw RepositoryError.importFailed
        }
        return project
    }
}
