# build-notes-patchui — 域 C2(补丁+仓库 UI 层)构建记录

## 1. 文件清单(绝对路径 + 行数)

| 文件 | 行数 |
|------|------|
| Sources/PatchWorkspace/ViewModels/PatchesViewModel.swift | 108 |
| Sources/PatchWorkspace/ViewModels/PatchEditorViewModel.swift | 182 |
| Sources/PatchWorkspace/ViewModels/RepositoryViewModel.swift | 117 |
| Sources/PatchWorkspace/Views/PatchesTabView.swift | 288 |
| Sources/PatchWorkspace/Views/PatchEditorView.swift | 364 |
| Sources/PatchWorkspace/Views/PatchRuleEditSheet.swift | 194 |
| Sources/PatchWorkspace/Views/PatchTargetPickerView.swift | 181 |
| Sources/PatchWorkspace/Views/RepositoryTabView.swift | 321 |
| **合计** | **1755** |

> 除任务指定的 6 个文件外,额外拆出两个视图文件(同属我的域目录,无跨域双写风险):
> `PatchRuleEditSheet.swift`(规则增删改 sheet)、`PatchTargetPickerView.swift`(自绘沙盒目录树选择器)。

## 2. 构建输出原文尾部

`xcodegen generate` → `Created project at .../DeviceToolbox.xcodeproj`(成功)

`xcodebuild ... build 2>&1 | tail -25`:

```
CreateBuildDescription

ClangStatCache /Applications/Xcode-beta.app/.../clang-stat-cache .../iphonesimulator27.0-....sdkstatcache

PruneExplicitPrecompiledModules .../SwiftExplicitPrecompiledModules

PruneExplicitPrecompiledModules .../SDKExplicitPrecompiledModules

PruneExplicitPrecompiledModules .../ExplicitPrecompiledModules

** BUILD SUCCEEDED **
```

- 编译错误:首轮 1 处(`store.delete(id:)` 缺 `try`),已修复;**0 warnings**。
- 修复轮数:1(≤6 上限内)。

## 3. 新增本地化 key 清单(key | en | zh-Hans)

> 未直接编辑 Localizable.strings(遵守双写禁令),以下清单由主会话合并。

### patch.*

| key | en | zh-Hans |
|-----|----|---------|
| patch.title | Patches | 补丁 |
| patch.section.projects | Projects | 项目库 |
| patch.count.rules | rules | 条规则 |
| patch.empty.title | No patches yet | 暂无补丁项目 |
| patch.empty.hint | Create a draft or import a .dtbp/.3105 package | 点击右上角 + 新建草稿,或导入 .dtbp/.3105 包 |
| patch.action.new | New Patch | 新建补丁 |
| patch.action.import | Import | 导入 |
| patch.action.create | Create | 创建 |
| patch.action.delete | Delete | 删除 |
| patch.action.save | Save | 保存 |
| patch.action.apply | Apply | 应用 |
| patch.action.restore | Roll Back | 回滚 |
| patch.action.add_rule | Add Rule | 添加规则 |
| patch.badge.applied | Applied | 已应用 |
| patch.badge.not_applied | Not applied | 未应用 |
| patch.draft.title | New Patch | 新建补丁 |
| patch.draft.name_prompt | Patch Name | 补丁名称 |
| patch.draft.message | Enter a name for the new patch project | 输入新补丁项目的名称 |
| patch.import.password_title | Import Package | 导入补丁包 |
| patch.import.password_prompt | Password (optional) | 密码(可选) |
| patch.import.password_message | Enter a password for private packages, otherwise leave empty | 私密补丁请输入密码,非私密请留空 |
| patch.confirm.delete | Delete this patch? This cannot be undone. | 确定删除该补丁吗?此操作不可撤销。 |
| patch.confirm.delete_rule | Delete this rule? | 确定删除该规则吗? |
| patch.busy.importing | Importing… | 正在导入… |
| patch.busy.saving | Saving… | 正在保存… |
| patch.busy.applying | Applying… | 正在应用… |
| patch.busy.restoring | Rolling back… | 正在回滚… |
| patch.error.title | Operation Failed | 操作失败 |
| patch.error.generic | The operation failed. Please try again. | 操作失败,请重试 |
| patch.error.empty_name | Name cannot be empty | 名称不能为空 |
| patch.error.no_rules | Add at least one rule before applying | 应用前请至少添加一条规则 |
| patch.error.not_applied | This patch has not been applied | 该补丁尚未应用 |
| patch.result.title | Done | 完成 |
| patch.result.saved | Saved | 已保存 |
| patch.result.applied | Patch applied | 补丁已应用 |
| patch.result.restored | Patch rolled back | 补丁已回滚 |
| patch.editor.title | Patch Editor | 补丁编辑器 |
| patch.editor.loading | Loading… | 正在加载… |
| patch.editor.section.info | Info | 信息 |
| patch.editor.section.rules | Rules | 规则 |
| patch.editor.name | Name | 名称 |
| patch.editor.name_prompt | Patch Name | 补丁名称 |
| patch.editor.name_message | Enter a new name for this patch | 输入该补丁的新名称 |
| patch.editor.author | Author | 作者 |
| patch.editor.updated | Updated | 更新时间 |
| patch.editor.status | Status | 状态 |
| patch.editor.rules_empty | No rules yet. Add a rule to get started. | 暂无规则,点击上方「添加规则」开始 |
| patch.editor.password_title | Password Required | 需要密码 |
| patch.editor.password_prompt | Password | 密码 |
| patch.editor.password_unlock | Unlock | 解锁 |
| patch.editor.load_failed | Failed to load this patch | 无法加载该补丁 |
| patch.editor.retry | Retry | 重试 |
| patch.rule.title.add | Add Rule | 添加规则 |
| patch.rule.title.edit | Edit Rule | 编辑规则 |
| patch.rule.save | Save | 保存 |
| patch.rule.action | Action | 动作 |
| patch.rule.action.replace | Replace File | 替换文件 |
| patch.rule.action.delete | Delete File | 删除文件 |
| patch.rule.action.add_folder | Add Folder | 新增文件夹 |
| patch.rule.path | Target Path | 目标路径 |
| patch.rule.path_prompt | Relative path | 相对路径 |
| patch.rule.browse | Browse | 浏览 |
| patch.rule.payload | Replacement Payload | 替换载荷 |
| patch.rule.payload_empty | Choose a file… | 选择文件… |
| patch.rule.payload_choose | Choose payload file | 选择载荷文件 |
| patch.rule.error.no_payload | Choose a payload file for replace action | 替换文件动作需选择载荷文件 |
| patch.picker.title | Choose Target | 选择目标路径 |
| patch.picker.loading | Loading… | 正在加载… |
| patch.picker.confirm | Choose | 选择 |
| patch.picker.hint | Tap a folder to enter, tap a file to select, then tap Choose. Tapping Choose directly selects the current folder. | 点击文件夹进入,点击文件选中,再点「选择」;直接点「选择」则选中当前文件夹 |
| patch.picker.empty | This folder is empty | 此文件夹为空 |
| patch.picker.empty_hint | Tap Choose to select this folder as the target | 可点击「选择」将当前文件夹作为目标 |

### repo.*

| key | en | zh-Hans |
|-----|----|---------|
| repo.title | Repository | 仓库 |
| repo.section.sources | Sources | 仓库源 |
| repo.section.packages | Packages | 补丁包 |
| repo.empty.sources | No repository sources yet | 暂无仓库源 |
| repo.empty.no_source | Select or add a repository source | 请选择或添加一个仓库源 |
| repo.empty.packages | No packages in this repository | 该仓库暂无补丁包 |
| repo.action.add_source | Add Source | 添加源 |
| repo.action.remove_source | Remove Source | 移除源 |
| repo.action.import | Import | 导入 |
| repo.busy.fetching | Fetching index… | 正在获取索引… |
| repo.add_source.title | Add Repository Source | 添加仓库源 |
| repo.add_source.name_prompt | Name | 名称 |
| repo.add_source.url_prompt | HTTPS URL | HTTPS 地址 |
| repo.add_source.message | Enter a name and an HTTPS URL of a repository index | 输入仓库源的名称与 HTTPS 索引地址 |
| repo.confirm.remove_source | Remove this source? | 确定移除该仓库源吗? |
| repo.import.password_title | Import Package | 导入补丁包 |
| repo.import.password_prompt | Password (optional) | 密码(可选) |
| repo.import.password_message | Enter a password for private packages, otherwise leave empty | 私密补丁请输入密码,非私密请留空 |
| repo.import.done | Package imported | 包已导入项目库 |
| repo.error.title | Operation Failed | 操作失败 |
| repo.error.generic | The operation failed. Please try again. | 操作失败,请重试 |
| repo.error.invalid_url | Invalid URL. A valid HTTPS URL is required. | 地址无效,请输入有效的 HTTPS 地址 |
| repo.result.title | Done | 完成 |

> 说明:域 B 已在 Localizable.strings 落盘的 `patch.error.*`(14 个)与 `repo.error.*`(8 个)直接复用,未重复列;`tab.patches` 也已有。本 UI 层复用了既有的 `common.ok` / `common.close` 与 `files.action.back`(目标树选择器返回键)。

## 4. 已知限制(诚实)

1. **新建草稿不自动跳转编辑器**:新建后项目出现在列表顶部,需手动点按进入编辑器(因 PatchesTabView 不持有自身 NavigationStack,遵循 FilesTabView 的 navigationDestination 模式,未做程序化 push)。
2. **导入/下载私密包统一走「可选密码」弹窗**:非私密包留空即可;服务层无法在不解码前区分「需密码」与「损坏」,故统一提示而非按错误类型二次询问。
3. **编辑已应用项目的规则**:允许改,但改后再次「应用」会触发域 B 的 `projectAlreadyApplied`(需先回滚);UI 不主动拦截,错误如实呈现。
4. **目标树选择器约束在应用根内**:`Documents/Patches/Applied/<name>/`,越出即按 lastPathComponent 兜底;相对路径最终以文本框内容为准并走 `PatchPathValidator` 校验。
5. **addFolder 主要靠手动输入相对路径**:目标树选择器对「新增文件夹」的辅助有限(可选中当前目录后再手改名称)。
6. 未新增 UI 测试(遵循规格 §6:C2 不加 UITest)。

## 5. 域 B API 与理解的差异

无。公开签名(ProjectStore / PatchPackageCodec / PatchTransaction / RepositoryStore / RepositoryImportService / 各模型)均以代码为准逐一对齐,未发现与规格不符处。
唯一注意点:`ProjectStore.delete(id:)` 被声明为 `throws`(实际删除缺索引时静默返回),故调用处需 `try`——已在实现中处理。
