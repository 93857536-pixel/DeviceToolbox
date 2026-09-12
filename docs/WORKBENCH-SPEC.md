# DeviceToolbox Workbench — 文件工作台移植规格 (WORKBENCH-SPEC)

版本: 1.0 | 2026-09-05 | 目标: 把 3105 (GPLv3, /tmp/3105) 的"可用设计"干净移植进 DeviceToolbox

## 0. 铁律(所有子代理必读)

1. 全公开 API、零第三方依赖、零 exploit、零私有框架、零反检测、零伪装 bundle ID
2. 文件读写只允许在自己 app 沙盒内(FileManager 可达范围);禁止任何绝对路径越权尝试
3. **禁止逐行复制 3105 代码**(GPLv3)。可以阅读 /tmp/3105 源码理解格式与设计,实现必须自写;
   格式事实(magic/字段布局/加密流程)按互操作需要还原,但代码表达要原创
4. Swift 6 严格并发(strict concurrency);struct Codable+Sendable;enum 错误带中文+英文文案
5. 全部 UI 用 Theme(橙色 #FF9500 主色,白/浅灰卡片圆角,深色模式自适应),中文为主 + 英文双语文案
6. 新增文件后必须 `xcodegen generate` 再构建;修错轮数上限 6,剩余错误原文写入自己的 build-notes-<域>.md
7. 诚实条款:汇报必须给真实构建/测试输出原文,禁止"假装成功"

## 1. 工程现状事实(只读锚点)

- 工程: <PROJECT_ROOT>
- Xcode: 27.0 beta (/Applications/Xcode-beta.app), xcode-select 已指向;iOS deployment 17.0;Swift 6.0
- project.yml: sources 为目录 glob(`Sources` 与 `Tests/DeviceToolboxTests`)→ 新增子目录/文件自动进入 target,**不用改 project.yml**,但每次新文件后必须 `xcodegen generate`
- 构建命令(模拟器): `cd ~/Programming/Projects/DeviceToolbox && xcodegen generate && xcodebuild -project DeviceToolbox.xcodeproj -scheme DeviceToolbox -destination 'platform=iOS Simulator,id=4164588D-870F-46D8-9C18-3F97C0C9415B' -derivedDataPath build/wb-dd build 2>&1 | tail -30`
- 单测命令: 同上但加 `-only-testing:DeviceToolboxTests test`
- 现有文件结构(已存在,禁止修改,除非本规格授权):
  - Sources/Core/{Theme.swift, Logger.swift, AppStorageKeys.swift, DeviceCapability.swift}
  - Sources/Models/, Sources/Services/(设备检测服务, 与本次无关), Sources/ViewModels/, Sources/Views/
  - 主入口 DeviceToolboxApp.swift;免责声明 DisclaimerView → MainTabView
  - MainTabView.swift 内 `enum MainTab: Hashable { home, device, features, tools, settings }` 5 Tab
  - 本地化: String(localized:) 用法 + en.lproj/Localizable.strings 与 zh-Hans.lproj/Localizable.strings(手工维护 key-value,key 形如 "tab.home")
  - 主题: Theme.accent;视图风格 SectionCard/StatCard 等 Components 可用
- 现有测试: Tests/DeviceToolboxTests(12 个服务层单测,勿破坏);Tests/DeviceToolboxUITests(免责声明流程)
- 参考源码(只读,理解用): /tmp/3105/ThreeOneOSFive/{helpers/PatchProjectModels.swift, helpers/PatchPackageCodec.swift, helpers/PatchTransaction.swift, helpers/PatchProjectStore.swift, helpers/PackageRepositoryModels.swift, helpers/PackageRepositoryStore.swift, views/PatchProjectsView.swift, views/FileBrowserView.swift, views/RepositoryMarketplaceView.swift, helpers/FileManagerService.swift, helpers/ZIPArchiveWriter.swift, helpers/ZIPArchiveExtractor.swift}

## 2. 产品布局决策(已定,勿改)

MainTab 调整为 5 Tab: home(首页) | device(设备) | files(文件,新) | patches(补丁,新) | settings(设置)。
原 features/tools 两个 tab 移除,FeaturesView/ToolsView 文件保留,由 HomeView 增加入口卡 push 访问。
(该改造由主会话在集成期执行,任何子代理不要碰 MainTabView.swift / HomeView.swift)

## 3. 新增目录与文件归属表(谁写谁,防双写)

禁止两个代理写同一文件。目录 mkdir 无害。

### 域 A: Sources/FileWorkspace/ (文件工作台服务层+ZIP) — 代理 A
```
Sources/FileWorkspace/Models.swift            — FileEntry{name,path,isDirectory,size,modifiedAt,childCount} Hashable
Sources/FileWorkspace/Errors.swift            — FileOperationError(中文+英文文案,枚举见 3105 FileManagerService 错误集为灵感,自写)
Sources/FileWorkspace/SandboxRoots.swift      — 沙盒根: Documents, Caches, tmp(可含"已导入"子目录 Documents/Imported)
Sources/FileWorkspace/WorkspaceService.swift  — list/stat/mkdir/rename/delete/copy/move(冲突策略 fail|replace|keepBoth)/批量
Sources/FileWorkspace/ImportService.swift     — 接收 [URL](UIDocumentPicker 安全作用域副本)拷入 Imported/
Sources/FileWorkspace/ZIP/Writer.swift        — 自实现 zip 写入(stored + deflate via Compression framework COMPRESSION_ZLIB)
Sources/FileWorkspace/ZIP/Reader.swift        — 自实现 zip 读取: local/central header 解析、CRC32 校验、防 zip-slip(拒绝 ../ 与绝对路径)、
                                              单条膨胀大小上限 256MB、总量上限 1GB、条目数上限 5000, 违规抛 .unsafeArchive
Sources/FileWorkspace/ZIP/ZipArchiveService.swift — write(files:[URL], to:URL) throws; extract(archive:URL,to:URL,progress?) throws -> ZipResult{fileCount,byteCount}
```

### 域 B: Sources/PatchWorkspace/ (补丁+仓库服务层) — 代理 B
```
Sources/PatchWorkspace/Models.swift           — PatchProject{id,name,author,isPrivate,createdAt,updatedAt,targetRootName(沙盒内基目录名,默认"Patches"),origin?},
                                               PatchRule{id,relativePath,replacementFilename?,replacementData?,action:replaceFile|deleteFile|addFolder},
                                               PatchDirectory 由 rules 推导不需要独立类型(设计自定但字段语义如上)
Sources/PatchWorkspace/Errors.swift
Sources/PatchWorkspace/PackageCodec.swift     — 自家格式 "DTBP" magic Data("DTBP1PACK\0") schema1 AES-GCM envelope(结构设计参照 3105 的 envelope 思路但自写),
                                               公开 API: encodePackage(project,password?)->Data; decodePackage(Data,password?)->DecodedPackage
                                               兼容导入: import3105Package(Data, password?) throws -> PatchProject  ← 必须支持 3105 v3 真实包解码
                                               (先精读 /tmp/3105 PatchPackageCodec.swift 全文, 还原其 v3 格式: magic "3105PATCH\0",
                                               envelope 字段 schemaVersion/keyAADVersion/packageID/isPasswordProtected/kdfSalt/kdfIterations/
                                               wrappedContentKey/publicContentKey/keyFingerprint/encryptedPayload, payload JSON{project,replacementDigests},
                                               AES-GCM 细节与 KDF(PBKDF2 参数)照源码事实实现; bundleID 语义映射: rule.bundleID+relativePath
                                               → 我们的 relativePath = "<bundleID>/<relativePath>", origin 记 repositoryName/URL/packageIdentifier)
Sources/PatchWorkspace/ProjectStore.swift      — 项目持久化 Documents/Patches/Projects/*.dtbp 文件 + 索引 JSON; CRUD; 包体含 replacementData(文件内容)
Sources/PatchWorkspace/Transaction.swift       — 应用/回滚事务: 目标根 Documents/Patches/Applied/<projectName>/; apply 前把将覆盖/删除的原文
                                               journal 到 Documents/Patches/.Journal/<UUID>/; restore 按 journal 恢复原状并删新增;
                                               validateTargetPath 防穿越; 错误含 projectAlreadyApplied/restoreTargetsChanged 等
Sources/PatchWorkspace/Repository/Models.swift — RepositorySource{id,name,baseURL}, RepositoryIndexEntry{id,title,summary?,downloadURL,sha256?,bundleIDs[]?}
Sources/PatchWorkspace/Repository/RepositoryStore.swift — 源 CRUD(UserDefaults suite "patch.repositories")+ fetchIndex(URLSession,缓存+ETag)+ download(校验大小上限 200MB)
Sources/PatchWorkspace/Repository/ImportService.swift — download→codec→project 导入项目库
```

### 域 C1: Sources/FileWorkspace/ViewModels + Views — 代理 C1(可与 A/B 并行,按上方磁盘契约写,类型签名以本规格为准)
```
Sources/FileWorkspace/ViewModels/WorkspaceViewModel.swift — 当前目录路径栈, entries 状态, 多选集合, 操作执行+错误呈现(走服务层)
Sources/FileWorkspace/Views/FilesTabView.swift          — 根: 三区列表(Documents/Caches/tmp 卡片)+ 已导入入口 + 新建/导入工具按钮
Sources/FileWorkspace/Views/FileBrowserView.swift       — 目录浏览(面包屑/返回)、文件行(图标/名称/大小/日期)、长按或多选模式:
                                                           复制/移动(目标文件夹选择器自绘树)/压缩为zip/删除(确认弹窗)/重命名/新建文件夹
                                                           文件点按 QuickLook 预览(QLPreviewController 包装 UIViewRepresentable, 公开 API)
Sources/FileWorkspace/Views/FolderPickerView.swift      — 自绘沙盒目录树选择器(供移动/压缩目标)
Sources/FileWorkspace/Views/ImportView.swift            — .fileImporter 允许多种文档类型, 多选
```

### 域 C2: Sources/PatchWorkspace/ViewModels + Views — 代理 C2(轮 2 派, 契约同域 B)
```
Sources/PatchWorkspace/ViewModels/PatchesViewModel.swift
Sources/PatchWorkspace/Views/PatchesTabView.swift       — 项目库列表(名称/作者/私密锁/更新时间/应用状态徽标) + 工具栏(新建/导入 .dtbp/.3105/从仓库)
Sources/PatchWorkspace/Views/PatchEditorView.swift      — 项目详情: 规则列表(路径行+动作), 编辑: 选目标沙盒文件/文件夹(自绘选择器) + 选替换载荷(文件选择器/系统 fileImporter)
Sources/PatchWorkspace/Views/PatchApplyView.swift       — 应用/回滚按钮与结果、事务历史(简易)
Sources/PatchWorkspace/Views/RepositoryTabView.swift    — 仓库源列表 + 包索引浏览 + 下载导入进度 + 错误呈现
```

## 4. 共享契约(签名以本规格为唯一真源;子代理实现须与此一致)

Swift 6 注意: 服务层 struct/enum 全部 Sendable;需要隔离的状态放 @MainActor 的 ObservableObject(用 @Observable 或 ObservableObject 均可,
工程现有 ViewModel 风格是 ObservableObject → 沿用 ObservableObject + @Published, import Combine)

ZIP 写入 deflate 实现提示: import Compression;compression_encode_buffer(..., COMPRESSION_ZLIB) 逐块;CRC32 自实现查表;不要依赖任何第三方库。
ZIP 读取: 自己解析 EOCD/central directory/local headers(签名 0x04034b50/0x02014b50/0x06054b50), inflate 用 compression_decode_buffer;文件名解码 UTF-8 与 CP437 回退。

UI 风格: 背景系统分组灰;卡片用 Theme 圆角;空态与错误态都要有文案;全部交互文案走 String(localized:)(key 前缀: files. / patch. / repo.);
中英 key 加入 en.lproj 与 zh-Hans.lproj 的 Localizable.strings —— 注意这两个文件是【共享资源】:由主会话在集成期统一合并,任何代理在自己汇报里列明新增 key 清单(key=中文值/英文值),不要直接改这两个文件,避免双写冲突。

## 5. 本地化 key 命名

- tab.files / tab.patches(主会话加)
- files.* (域 A/C1) / patch.* (域 B/C2) / repo.* (域 B/C2)
汇报必须附"新增本地化 key 清单"表格:key | en | zh-Hans

## 6. 测试(代理 A/B 各自把单测加入 Tests/DeviceToolboxTests/, 新文件自动进 target; C1/C2 不需要单测但 UI 测试文件不得新增, 避免与现有 UITests 冲突)

- 代理 A: ZipRoundTripTests(小文件/空目录/中文文件名/嵌套), UnsafeZipRejectTests(路径穿越/超大声明/CRC 损坏), FileOpsTests(复制冲突 keepBoth 命名规则/删除)
- 代理 B: CodecRoundTripTests(无密码/带密码往返、错误密码报错、截断数据报错), 3105ImportTests(用一个真实 3105 v3 样例包 hex 内联 fixture 解码成功 —— 没有真实 fixture 时用自产 v3 结构构造), TransactionTests(apply 后文件变化、restore 后字节级还原、模拟 targetChanged 冲突)

## 7. 汇报格式(每代理必须)

1. 文件清单(绝对路径+行数)
2. 构建/测试输出原文尾部(BUILD SUCCEEDED / Executed N tests, 0 failures; 失败则完整错误)
3. 新增本地化 key 清单
4. 已知限制与未完成项(诚实)
5. 若兄弟文件缺失导致编译失败: 列出缺失符号清单, 不许删功能绕过, 不许补写兄弟域文件

## 8. 双写禁令与只读区

- 各代理只写自己的目录(见 §3);Sources/Workspace 之外禁止写任何文件
- en.lproj / zh-Hans.lproj Localizable.strings 禁止直接编辑(见 §4)
- MainTabView.swift / HomeView.swift / DeviceToolboxApp.swift / DisclaimerView.swift 禁止编辑(主会话负责)
- 即使编译报"找不到 X"(X 属兄弟域),也禁止自己补写,记入 build-notes
