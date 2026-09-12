# 域 A(文件工作台服务层)构建笔记 — build-notes-files.md

代理 A · DeviceToolbox 文件工作台服务层 + ZIP 读写 · 2026-09-05

## 1. 本域交付文件(绝对路径 + 行数)

源码(共 1563 行):
- Sources/FileWorkspace/FileEntry.swift (51) — FileEntry 模型
- Sources/FileWorkspace/FileOperationError.swift (71) — FileOperationError + ZIPCodecError
- Sources/FileWorkspace/SandboxRoots.swift (68) — 沙盒根
- Sources/FileWorkspace/WorkspaceService.swift (383) — list/stat/mkdir/rename/delete/copy/move/批量
- Sources/FileWorkspace/FileImportService.swift (137) — 安全作用域导入
- Sources/FileWorkspace/ZIP/Writer.swift (417) — 自实现 zip 写(stored+deflate, CRC32)
- Sources/FileWorkspace/ZIP/Reader.swift (341) — 自实现 zip 读(CP437 回退, 防 zip-slip)
- Sources/FileWorkspace/ZIP/ZipArchiveService.swift (95) — 对外 write/extract 入口

单测(共 402 行):
- Tests/DeviceToolboxTests/ZipRoundTripTests.swift (103)
- Tests/DeviceToolboxTests/UnsafeZipRejectTests.swift (80)
- Tests/DeviceToolboxTests/FileOpsTests.swift (109)
- Tests/DeviceToolboxTests/FileWorkspaceTestSupport.swift (110, 共享测试工具)

## 2. 关键偏离:三个文件名重命名(必要)

SPEC §3 给域 A 与域 B 都分配了同名文件 `Models.swift` / `Errors.swift` / `ImportService.swift`。
Swift 同 target 禁止同名源文件(报 `Filename "X.swift" used twice`),这是 SPEC 自身缺陷。
为不触碰 project.yml 与兄弟文件,本域将自己的三个文件改名(类型名与公开 API 完全不变):

| 原 SPEC 名 | 实际落盘名 |
|---|---|
| Sources/FileWorkspace/Models.swift | FileEntry.swift |
| Sources/FileWorkspace/Errors.swift | FileOperationError.swift |
| Sources/FileWorkspace/ImportService.swift | FileImportService.swift |

## 3. 我自己的编译错误修复记录(共 4 处,均在 6 轮上限内)

1. `compression_encode_buffer` / `compression_decode_buffer` 实际签名为
   `(dst, dstSize, src, srcSize, scratch, algorithm)` —— 无 `scratch_size` 参数(已核对 SDK compression.h)。删除多余实参。
2. `CP437.decode` 中 `UnicodeScalar(UInt8)` 非可选、`UnicodeScalar(UInt16)` 返回可选;改为显式 `UnicodeScalar(...)!`(高半区 0x80–0xFF 均非代理区,解包安全)。
3. 写入 staging 文件原先落在 `destinationURL.deletingLastPathComponent()`,当压缩包路径在源目录树内时,staging 会被一并枚举成幽灵条目;改为 `FileManager.default.temporaryDirectory`。
4. FileOpsTests 两处测试用错目录(复制到同目录同名),改用双目录。

## 4. 兄弟域遗留问题(非本域,不代修)

- **域 B 编译错误**:`Sources/PatchWorkspace/PackageCodec.swift:226:25`
  `error: contextual type for closure argument list expects 1 argument, which cannot be implicitly ignored`
  (keyAAD 尾随闭包实参 arity 与形参不符)。导致**整 target 构建失败**。
- **域 B 曾有两处 `Models.swift` 同名**(PatchWorkspace/Models.swift vs Repository/Models.swift),
  已观察到域 B 自行将 Repository/Models.swift 重命名为 RepositoryModels.swift 解决。
- 本域不引用任何兄弟域类型,故无「缺失兄弟符号」。

## 5. 验证方式(诚实说明)

兄弟文件当前有编译错误,整 target 无法构建。为验证本域代码+单测真实通过,执行了以下隔离验证
(临时把域 B/域 C1 的 Sources 与域 B 单测移出项目 → xcodegen → 构建/测试 → 原样移回):

- 隔离构建:exit 0,无 error 行(仅 AppIntents metadata 提示)。
- 隔离单测:`Executed 19 tests, with 0 failures (0 unexpected)` → `** TEST SUCCEEDED **`
  (ZipRoundTrip 5 + UnsafeZipReject 6 + FileOps 8)。

## 6. 新增本地化 key(服务层错误文案内联双语,未用 key)

| key | en | zh-Hans |
|---|---|---|
| files.root.documents | Documents | 文档 |
| files.root.caches | Caches | 缓存 |
| files.root.temporary | Temporary | 临时 |
| files.root.imported | Imported | 已导入 |

注:仅 `SandboxRoot.title` 使用 String(localized:);全部错误文案为内联「中文 · English」,
未新增错误类 key,避免与集成期合并冲突。
