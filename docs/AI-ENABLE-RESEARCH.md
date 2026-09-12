# Spec Part 1 — Apple Intelligence 强开：MobileGestalt / eligibility 机制与模板（历史 → iOS 26 时代）

> 调研范围：PC 侧 / 历史路径。只读调研 4 个本地仓库 + 2 个关键 gist/issue（f1shy-dev gist、icedmoca gist、Nugget #1073、sumitduster-kiuzan discussion）。
> 所有结论均标注出处文件；拿不准的地方标注 **【需实测】**。禁止凭空编造。

---

## 0. 结论速览（给集成决策用）

1. **强开 Apple Intelligence = 改两个地方**：
   - **MobileGestalt 缓存文件**（`com.apple.MobileGestalt.plist` 的 `CacheExtra`）：加一个 `DeviceSupportsGenerativeModelSystems`（生成式模型能力），并在"硬件不支持机型强开"场景下伪造 `ProductType` / `HardwareModel` / `HardwarePlatform`。
   - **eligibility 回答文件**（`/var/db/eligibilityd/eligibility.plist`）：写入 `OS_ELIGIBILITY_DOMAIN_GREYMATTER` 域，把 `os_eligibility_answer_t` 置 4（eligible），各 `OS_ELIGIBILITY_INPUT_*` 置 3（强制放行）。

2. **两类目标本质不同**（务必区分）：
   - **(a) 硬件不支持机型强开（A16/A15 等 8GB 以下机型）**：需要伪造 ProductType 让 Apple 服务器允许下载模型。**这条在 iOS 18.1b5+ 已被服务端补丁封死**（模型下载接口校验真实硬件标识），历史上只在 18.1 beta 1–4 有效。
   - **(b) 国行/地区锁机型在受支持硬件上解锁**：主要是 **eligibility + 地区码**，纯文件写入即可，**不依赖服务端下载模型**，到 18.4+/26.x 仍可尝试（见 §C 版本矩阵）。

3. **许可证**：Nugget 是 **AGPL-3.0**，MisakaX 是 **MIT**，username3006 / sheevaahhh / f1shy-dev 均 **无 LICENSE（默认保留所有权利）**。gestalt key 名/plist 结构属功能性事实，可自写实现，但需注明来源（详见 §D）。

---

## A. 确切文件路径 + key 清单

### A.1 文件路径

| 用途 | 路径 | 出处 |
|---|---|---|
| MobileGestalt 缓存（改 `CacheExtra`） | `/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist`（等价 `/private/var/containers/...`） | `Nugget/src/tweaks/basic_plist_locations.py:6`（`FileLocation.mga`）；f1shy-dev gist Part1；icedmoca gist |
| AI eligibility（Apple Intelligence 回答） | `/var/db/eligibilityd/eligibility.plist` | `Nugget/src/tweaks/eligibility_tweak.py:123`（`AITweak.apply_tweak` 的 `restore_path`）；f1shy-dev gist Part2；username3006 README:79 |
| EU Enabler eligibility（DMA 功能，非 AI，但同机制） | `/var/db/os_eligibility/eligibility.plist` | `Nugget/src/tweaks/eligibility_tweak.py:59`（`EligibilityTweak`，lrdsnow EUEnabler） |
| EU Enabler 策略 Config（两个资产哈希，二选一） | `/var/MobileAsset/AssetsV2/com_apple_MobileAsset_OSEligibility/purpose_auto/c55a421c053e10233e5bfc15c42fa6230e5639a9.asset/AssetData/Config.plist` 或 `.../247556c634fc4cc4fd742f1b33af9abf194a986e.asset/AssetData/Config.plist` | `Nugget/src/tweaks/eligibility_tweak.py:70,77` |
| Feature Flags（AI 相关 flag） | `/var/preferences/FeatureFlags/Global.plist` | `Nugget/src/tweaks/basic_plist_locations.py:9`（`FileLocation.featureflags`） |

### A.2 MobileGestalt 关键 key（混淆名 → 真实名 → 值）

> 混淆名来自 Nugget `generate_mga.py`（设备信息字典）与 `tweak_loader.py`（AI 相关 tweak）。真实名由 f1shy-dev gist / Nugget 注释对照确认。

| 混淆 key（写在 plist 里） | 真实名 | 类型/值 | 用途 | 出处 |
|---|---|---|---|---|
| `A62OafQ85EJAiiqKn4agtg` | `DeviceSupportsGenerativeModelSystems` | `integer = 1` | **核心**：声明设备支持生成式模型系统（AI 能力开关） | `tweak_loader.py:56`（`TweakID.AIGestalt`）；f1shy gist Part1（"Generative Model capability"）；username3006 README:64-66,106 |
| `h9jDsbgj7xIVeIQ8S3/X3Q` | `ProductType` | `string`，伪装为 AI 机型（见下） | 型号伪装，让服务器允许下载模型 | `generate_mga.py:62`；`tweak_loader.py:59`（`SpoofModel`）；f1shy gist |
| `oYicEKzVTz4/CxxE05pEgQ` | `HardwareModel` / `TargetSubType` | `string`，伪装为 `D83AP` 等板卡名 | 硬件板卡伪装（与型号配套） | `generate_mga.py:82`；`tweak_loader.py:100`（`SpoofHardware`） |
| `5pYKlGnYYBzGvAlIU8RjEQ` | `HardwarePlatform` | `string`，伪装为 `t8130` 等 SoC 代号 | CPU/SoC 伪装（与型号配套） | `generate_mga.py:28`；`tweak_loader.py:141`（`SpoofCPU`） |
| `0+nc/Udy4WNG8S+Q7a/s1A` | `ProductType`（第二个 cache-extra 键） | `string` | `generate_mga.py` 里 `prod` 的另一个键（注：同值） | `generate_mga.py:24` |

> **重要**：Nugget 的 GUI 逻辑（`eligibility.py:66-73`）在用户选一个伪装型号时，会**同时**写 `SpoofModel` + `SpoofHardware` + `SpoofCPU` 三个键（勾选 hardware/cpu 时）。即"型号伪装"实际是三键联动。

**ProductType 伪装值（Nugget 实际内置列表，`tweak_loader.py:59-99`）**：

| 值 | 对应机型 | 值 | 对应机型 |
|---|---|---|---|
| `iPhone16,1` | iPhone 15 Pro | `iPad16,1`/`16,2` | iPad mini (A17 Pro) |
| `iPhone16,2` | iPhone 15 Pro Max | `iPad16,3`/`16,4` | iPad Pro 11" (M4) |
| `iPhone17,1` | iPhone 16 Pro | `iPad16,5`/`16,6` | iPad Pro 13" (M4) |
| `iPhone17,2` | iPhone 16 Pro Max | `iPad14,3`–`14,11` | iPad Pro/Air (M2) |
| `iPhone17,3` | iPhone 16 | `iPad13,4`–`13,17` | iPad Pro/Air (M1) |
| `iPhone17,4` | iPhone 16 Plus | | |
| `iPhone18,3` | iPhone 17 | | |

对应 `SpoofHardware`：`D83AP`(15Pro)、`D84AP`(15ProMax)、`D47AP/D48AP`(16/16Plus)、`D93AP/D94AP`(16Pro/Max)、`V57AP`(17)、`J410AP/J411AP`(iPad mini A17Pro)、`J717AP/J718AP`(iPad Pro 11" M4)、`J720AP/J721AP`(iPad Pro 13" M4) 等。
对应 `SpoofCPU`：`t8130`(A17 Pro)、`t8140`(A18)、`t8150`(A19)、`t8182`(M4)、`t8112`(M2)、`t8103`(M1)。

> **更正**：任务描述里的"iPhone15,4–iPhone17,4"不准确。`iPhone15,4` 是 iPhone 15（A16，**不**支持 AI）。AI 机型从 `iPhone16,1`（15 Pro）起步。icedmoca gist 曾写"iPhone15,2 through iPhone17,4"，同样是错的/泛写。**以 Nugget 源码列表为准**。

### A.3 国行/地区解锁相关 key（RegionCode / RegionInfo）

| 混淆 key | 真实名 | 值 | 用途 | 出处 |
|---|---|---|---|---|
| `h63QSdBCiT/z0WU6rdQv6Q` | `RegionCode` | `"US"`（改地区码） | 地区码，国行解锁关键 | `tweak_loader.py:23`（`Shutter`）；`generate_mga.py:61` |
| `zHeENZu+wbg7PUprwNwBWg` | `RegionInfo` | `"LL/A"`（改 SKU 地区） | 区域 SKU | `tweak_loader.py:23`；`generate_mga.py:96` |

> f1shy gist "Extra: Regional Requirements"：国行先做 MisakaX 的 "Disable Shutter Sound"（把设备从 Asia 改成 Europe/USA），再配合 eligibility。Nugget 的 `Shutter` tweak 正是改这两个键为 `US` / `LL/A`。

### A.4 AI 相关 Feature Flags（`/var/preferences/FeatureFlags/Global.plist`）

| Category | flag 名 | 值 | 出处 |
|---|---|---|---|
| `Siri` | `sae_override` | `{"Enabled": true}` | `tweak_loader.py:57`（`AIFeatureFlags`） |
| `Siri` | `assistant_engine_override` | `{"Enabled": true}` | 同上 |
| `SiriUI` | `sae` | `{"Enabled": true}` | `tweak_loader.py:58`（`AIFeatureFlagsUI`） |

f1shy gist "Extra: Other Information" 另提到可折腾 `PrivateCloudCompute`、`TextComposer`、`Siri`、`SiriNL` 等 flag（未给出具体值，**【需实测】**）。

---

## B. eligibility.plist 完整模板（Apple Intelligence 用）

> 来源：f1shy-dev gist `eligibility.plist` 文件（原版），与 Nugget `AITweak`（`eligibility_tweak.py:92-123`）逐字段一致。写入 `/var/db/eligibilityd/eligibility.plist`。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>OS_ELIGIBILITY_DOMAIN_CALCIUM</key>
	<dict>
		<key>os_eligibility_answer_source_t</key>
		<integer>1</integer>
		<key>os_eligibility_answer_t</key>
		<integer>2</integer>
		<key>status</key>
		<dict>
			<key>OS_ELIGIBILITY_INPUT_CHINA_CELLULAR</key>
			<integer>2</integer>
		</dict>
	</dict>
	<key>OS_ELIGIBILITY_DOMAIN_GREYMATTER</key>
	<dict>
		<key>context</key>
		<dict>
			<key>OS_ELIGIBILITY_CONTEXT_ELIGIBLE_DEVICE_LANGUAGES</key>
			<array>
				<string>en</string>
			</array>
		</dict>
		<key>os_eligibility_answer_source_t</key>
		<integer>1</integer>
		<key>os_eligibility_answer_t</key>
		<integer>4</integer>
		<key>status</key>
		<dict>
			<key>OS_ELIGIBILITY_INPUT_DEVICE_LANGUAGE</key>
			<integer>3</integer>
			<key>OS_ELIGIBILITY_INPUT_DEVICE_REGION_CODE</key>
			<integer>3</integer>
			<key>OS_ELIGIBILITY_INPUT_EXTERNAL_BOOT_DRIVE</key>
			<integer>3</integer>
			<key>OS_ELIGIBILITY_INPUT_GENERATIVE_MODEL_SYSTEM</key>
			<integer>3</integer>
			<key>OS_ELIGIBILITY_INPUT_SHARED_IPAD</key>
			<integer>3</integer>
			<key>OS_ELIGIBILITY_INPUT_SIRI_LANGUAGE</key>
			<integer>3</integer>
		</dict>
	</dict>
</dict>
</plist>
```

**字段语义（推断，**需实测**核对 Apple Wiki "Eligibility" 页）**：
- `OS_ELIGIBILITY_DOMAIN_GREYMATTER` = Apple Intelligence（生成式模型系统）域。
- `OS_ELIGIBILITY_DOMAIN_CALCIUM` = China Cellular（国行蜂窝锁）域，`CHINA_CELLULAR=2` 表示"非国行蜂窝限制"。
- `os_eligibility_answer_source_t`：`1` = 设备侧回答（`4` = 资产/策略侧回答，见 EU Enabler 模板）。
- `os_eligibility_answer_t`：`4` = eligible（放行），`2` = not eligible（拦截）。
- `status` 里各 `OS_ELIGIBILITY_INPUT_*` 值 `3` = 该输入项被"覆盖/无关"，不构成拦截。

> sumitduster-kiuzan 讨论里把 GREYMATTER 记作 "1,4,3,3,3,3" = `answer_source_t=1, answer_t=4, 输入项全 3`（macOS 侧只有 4 个输入项，iOS 侧 Nugget 用 6 个输入项）。**iOS/macOS 输入项集合不同，需实测确认目标系统实际输入项数。**

### B.2 文件属主/权限（关键未决点）

- **Nugget（iOS）**：`AITweak.apply_tweak` 返回的 `FileToRestore` **未显式指定 owner/group**，走类默认 `owner=501, group=501`（= mobile:mobile），mode 默认 `0755`（`restore.py:13`、`tweak_classes.py:13`、`backup.py:14` `DEFAULT`）。即 Nugget 以 **mobile:mobile / 0755** 写 `/var/db/eligibilityd/eligibility.plist`。
- **sumitduster（macOS 手动法）**：原话 "do command+i on the file, click lock"（`/var/db/eligibilityd/eligibility.plist`），即设成 **root 属主 + 只读**。
- **结论**：iOS 真机该文件原本 root 属主；但 eligibilityd 以 root 运行，0755 世界可读，root 仍可读，故 mobile 属主**可能**也能用。**属主/权限要求（mobile:mobile vs root）标注【需实测】。**

---

## C. 历史版本适用矩阵

| iOS 版本 | 可用注入通道 | gestalt 改写 | eligibility | 说明 / 出处 |
|---|---|---|---|---|
| **17.0 – 18.1.1** | **sparserestore**（恢复符号链接穿越） | ✅ 可写 MGA | ✅ | `Nugget/README.md`（"Sparserestore works 17.0-18.1.1"）；`restore.py:128` `has_sparserestore_capability` |
| **18.1 beta 1 – 4** | sparserestore | ✅ **硬件强开有效**（ProductType 伪装 + `DeviceSupportsGenerativeModelSystems`，可真正下载模型） | ✅ | f1shy-dev gist / username3006 / sheevaahhh（三者一致） |
| **18.1 beta 5 / 18.1 正式** | — | ❌ **硬件强开被服务端补丁**（"patched as of 18.1 DevBeta 5"） | 仅 UI 层面残留 | f1shy gist 顶部 WARNING；username3006/sheevaahhh README 顶部 |
| **18.2 – 18.7.x** | **BookRestore**（iBooks 下载 DB + 域恢复） | ✅（AI Enabler + 设备伪装，但 18.1b5+ 后**不支持机型**无法再下模型） | ✅ | `Nugget/README.md`（"BookRestore works 18.2-26.1"）；`tweak_loader.py:465-470`（`<=18.2` 才加载 eligibility/mga tweak） |
| **18.4+** | BookRestore | 官方已支持 15Pro+；国行官方渠道解锁 | ✅（国行可用此路径） | `Nugget/README.md` Features |
| **26.0 – 26.1** | BookRestore | ✅ AI Enabler + 设备伪装（**需"设备专属 MGA 文件"**） | ✅ | `Nugget/README.md` "Getting the File"（26.1 及以下需设备专属 MGA）；`constants.py:39` `has_bookrestore()`（`<=26.1` 为 True） |
| **26.2+** | ❌ 全补丁 | ❌ **MGA/AI Enabler 不再支持**（`is_exploit_fully_patched`） | — | `Nugget/README.md`（"Mobilegestalt and AI Enabler tweaks are not supported on iOS 26.2+"）；`constants.py:27-29` |
| **26.5+** | ❌ | — | ❌ **eligibility 改写失效**（Apple 改了 eligibility 系统，疑似加签名/完整性校验或移走验证） | Nugget issue #1073（title: "Apple Intelligence Eligibility Tweak No Longer Works on iOS/macOS 26.5+"） |
| **27.0** | ❌ | ❌ | ❌ | `Nugget/README.md` 顶部 WARNING（"DO NOT USE THIS ON iOS 27! ... partial restore method patched"） |

**关于 `constants.py` 的版本窗口细节（与 README 略有出入，需实测）**：
- `has_partial_sparserestore()`：`< 18.2`（或 build `22C5109p`/`22C5125e`）为 True（`constants.py:39-44`）。
- `has_bookrestore()`：`18.7.5 ≤ v < 26.0` 返回 **False**；`<= 26.1`（或 build `23C5027f`）返回 True（`constants.py:31-37`）。即 18.7.5–25.x 有一段 BookRestore 不可用的窗口，与 README 的"18.2–26.1 全覆盖"表述**不一致**，以源码为准并**标注【需实测】**。
- `is_exploit_fully_patched()`：当 `!(has_bookrestore || has_partial_sparserestore)` 时为 True，即 **26.2+ 全补丁**（`constants.py:27-29`）。

**关于 `18.4+ 服务端校验 intelligence.apple.com/v1/models`**：仅见于 icedmoca gist（SEO 风格、可信度较低），描述模型下载端点的服务端设备证明校验（`MISValidateSignatureAndCopyInfo` 返回伪装硬件标识，同时保留 BoardId/UniqueDeviceID）。**该说法与"18.1b5 补丁"同源但细节未见于主仓库源码，标注【需实测】。**

---

## D. 许可审计表

| 仓库/来源 | License | 结论与可借鉴范围 |
|---|---|---|
| **leminlimez/Nugget** | **AGPL-3.0**（`LICENSE` 头 = GNU AFFERO GPL v3） | 可借鉴 key 名/值/列表与逻辑；但你的项目是 GPLv3，混入 AGPL 代码后**该部分需遵守 AGPL（网络 copyleft）**，须保留版权声明。gestalt 混淆 key 名、plist 结构属功能性事实，自写实现 + 注明来源最稳妥。 |
| **straight-tamago/misakaX** | **MIT**（Copyright 2024 little_34306） | 可自由借鉴（保留版权+许可声明即可）。**注意：仓库只有 README/CHANGELOG/LICENSE，无源码**——AI 实现在闭源二进制里，只能从 README 功能清单推断（"Apple Intelligence (iOS 18.1 Beta, ALL DEVICES ON 18.1)"）。 |
| **username3006/apple-intelligence** | **无 LICENSE** | 默认保留所有权利。内容 = f1shy-dev gist 的转载。**只作只读参考**，勿直接复制整段文字；key 名/plist 逻辑可自写重述。 |
| **sheevaahhh/apple-intelligence** | **无 LICENSE** | 同上（与 username3006 内容逐字相同）。 |
| **f1shy-dev gist**（真正源头，`23b4a78dc283edd30ae2b2e6429129b5`） | **无 LICENSE** | 源头教程。gestalt key / eligibility.plist 模板出自此处。功能事实可借鉴，表述需自写。 |
| **lrdsnow/EUEnabler**（Nugget 引用，未克隆） | 未在本地核验 | EU Enabler 机制（`os_eligibility/eligibility.plist` + Config.plist）来源；需单独核验其许可。 |

**给自写实现的建议**：key 名（混淆字符串）与 `eligibility.plist` 字段结构是**功能性/事实性数据**，独立重新实现不构成侵权；但要 (1) 在代码注释/README 中注明数据来源（Nugget/f1shy-dev/MisakaX），(2) 避免复制大段教程散文，(3) 若直接搬 Nugget 的 Python 逻辑代码，需遵守 AGPL-3.0。

---

## E. 「已有内核读写 + root」前提下，本路径哪些步骤可改为在机执行

### 前提回顾
PC 工具（Nugget/MisakaX）之所以"必须 PC"，是因为它们**没有设备侧 root**，只能靠：
1. 从设备导出 MGA 文件（捷径）→ PC 上改 → 写回；
2. 用 **sparserestore（17.0-18.1.1）** 或 **BookRestore（18.2-26.1）** 两个"非 root 文件写入漏洞"来绕过系统写保护、把文件写进受保护区。

你的 App 已具备 **内核读写 + 沙盒逃逸 + root 写任意文件**，比 PC 工具的权限**更强**，理论上可绕过整个"导出→改→漏洞写回"流程。但结论要分步骤看：

### E.1 可直接改为在机执行（纯文件写入）✅
| 步骤 | 结论 | 说明 |
|---|---|---|
| 写 `eligibility.plist`（GREYMATTER） | ✅ 可纯在机 | 就是往 `/var/db/eligibilityd/eligibility.plist` 写一个 plist。root 写任意文件即可。写后 kill/重启 `eligibilityd`（或重启）触发重读。属主建议 root:wheel（与真机一致）。 |
| 写 Feature Flags（`/var/preferences/FeatureFlags/Global.plist`） | ✅ 可纯在机 | 普通文件，root 可写。 |
| 国行/地区解锁（`RegionCode`/`RegionInfo` + GREYMATTER eligibility） | ✅ 基本可纯在机 | 这类解锁**不依赖下载模型**，本质是"地区码 + eligibility 回答"两个文件写入。设备本身硬件已支持 AI（8GB+A17Pro/M 系）时，写文件 + 重启即可尝试。 |

### E.2 可改但需额外注意（文件可写，但缓存有完整性约束）⚠️
| 步骤 | 结论 | 说明 |
|---|---|---|
| 写 MobileGestalt 缓存（`com.apple.MobileGestalt.plist`） | ⚠️ 文件可写，但**不能整体替换** | MobileGestalt 是**带完整性的缓存**：有 `CacheUUID`、`CacheVersion`（=build）、以及 `CacheData`（二进制、含**设备专属**内容）。iOS 26.1 及以下，Nugget 明确要求"设备专属 MGA 文件"（README "Getting the File"），不能套通用模板。**正确做法：读本机现有 MGA → 只改 `CacheExtra` 里的目标 key → 保留 CacheData/CacheUUID/CacheVersion → 写回**。用 root 直接读本机文件，反而比 PC 的"捷径导出"更方便。 |
| 修改 `CacheExtra` 的 `DeviceSupportsGenerativeModelSystems` | ⚠️ 可写，但**需重启 + 可能触发缓存重建校验** | 见上。且仅加这一个 key 不涉及硬件伪装，风险低于 ProductType 伪装。 |
| 伪装 `ProductType`/`HardwareModel`/`HardwarePlatform` | ⚠️ 可写文件，**但 18.1b5+ 服务器不认** | 见 E.3。 |

### E.3 单靠"写文件"解决不了的部分（需内核级 hook，非纯文件）❌
| 目标 | 结论 | 说明 |
|---|---|---|
| **(a) 硬件不支持机型强开（18.1b5+ / 18.4+ / 26.x）** | ❌ 文件写入**不够** | 18.1b5 起 Apple 在**模型下载端点**做服务端校验：伪装 ProductType 写在 gestalt 缓存里，但 `MISValidateSignatureAndCopyInfo` 会返回**真实**硬件标识（来自 AP ticket/真实硬件，而非 gestalt 缓存）。要骗过服务端，需**在内核/进程层 hook 该函数返回伪装值**（同时保留 BoardId/UniqueDeviceID）——这是**内核级 hook 工程**，远超"写文件"。这也是为何历史上硬件强开只在 18.1b1-4 有效。 |
| **(b) 国行解锁（受支持硬件）** | ✅ 见 E.1，基本纯文件 | 不涉及硬件伪装，不碰服务端模型下载校验，可纯在机。 |

### E.4 与 PC 工具相比，你在机方案的优势与风险
- **优势**：无需 USB/PC、无需 sparserestore/BookRestore 漏洞、无需开发者模式、可直接读本机真实 MGA（拿到设备专属 CacheData 更可靠）。
- **风险/未知（【需实测】）**：
  1. MobileGestalt 缓存**写后是否会被系统重建/校验覆盖**——需要保证写回时机（如关机前）与完整性字段正确；PC 工具走的是"漏洞写入 + 崩溃恢复强制重载"的特殊路径（`restore.py:180-182` `crash_on_purpose`），直接 root 写文件是否等价**未验证**。
  2. eligibilityd 是否校验 `eligibility.plist` 的属主/权限/签名（26.5+ 已确认失效，疑似加了签名/完整性校验，见 issue #1073）。
  3. `os_eligibility_answer_t` 各值与各 `OS_ELIGIBILITY_INPUT_*` 语义，iOS vs macOS 输入项数量差异，**需实测确认**。
  4. 26.2+ MGA 通道全补丁、26.5+ eligibility 失效、27.0 恢复法全补丁——**在机方案在这些版本同样受制于这些补丁**（补丁是在系统侧，不是"PC vs 在机"的问题）。

---

## F. 关键出处文件索引

| 仓库 | 文件 | 关键内容 |
|---|---|---|
| Nugget | `src/tweaks/tweak_loader.py` | AI 全部 tweak：`AIGestalt`(key)、`SpoofModel/Hardware/CPU`(值列表)、`AIFeatureFlags(UI)` |
| Nugget | `src/tweaks/eligibility_tweak.py` | `AITweak`（GREYMATTER/CALCIUM plist 生成 + 路径 `/var/db/eligibilityd/eligibility.plist`）、`EligibilityTweak`（EU Enabler） |
| Nugget | `src/devicemanagement/generate_mga.py` | 混淆 key ↔ 真实名映射表（完整） |
| Nugget | `src/tweaks/basic_plist_locations.py` | 所有 plist 路径 |
| Nugget | `src/tweaks/tweak_classes.py` | `MobileGestaltTweak` 写 `CacheExtra` 逻辑、默认 owner=501/group=501 |
| Nugget | `src/devicemanagement/constants.py` | 版本窗口（sparserestore/BookRestore/全补丁判定） |
| Nugget | `src/devicemanagement/device_manager.py` | `get_domain_for_path`（路径→备份域映射）、`apply_changes`（各 tweak 落盘流程） |
| Nugget | `src/restore/restore.py`、`bookrestore.py`、`backup.py` | sparserestore / BookRestore 写入机制、owner/group/mode 默认值 |
| Nugget | `files/eligibility/eligibility.plist`、`Config.plist` | EU Enabler 模板（含全部 OS_ELIGIBILITY_DOMAIN_* 列表） |
| Nugget | `README.md` | 版本支持矩阵、iOS 27 警告、26.2+ 不支持声明 |
| MisakaX | `README.md` | 功能清单（含 "Apple Intelligence iOS 18.1 Beta, ALL DEVICES ON 18.1"）、支持 16.0-18.2b2、TrollRestore 漏洞 |
| username3006 / sheevaahhh | `README.md` | f1shy 教程转载（Part1 gestalt、Part2 eligibility、Part4 恢复 FaceID、地区要求） |
| f1shy-dev gist | `best_SAE_trick.md`、`eligibility.plist` | 源头教程 + 完整 eligibility 模板 |
| Nugget issue #1073 | — | 26.5+ eligibility 失效（Apple 改系统/加校验） |
| icedmoca gist | `enableappleintelligenceonunsupportediphones.md` | 18.1b5+ 服务端校验说法（低可信，需实测） |

---

## G. 待实测清单（汇总）

1. `eligibility.plist` 属主/权限：`mobile:mobile 0755`（Nugget）vs `root + 只读`（sumitduster）哪个正确/都可用。
2. GREYMATTER `status` 输入项：iOS 6 项 vs macOS 4 项，目标 iOS 版本实际需要哪几项。
3. `os_eligibility_answer_t` / `os_eligibility_input` 各数值的精确语义（4=eligible、3=覆盖、2=拦截 为推断，需对照 Apple Wiki "Eligibility" 页）。
4. 在机 root 直写 MGA 缓存后是否被系统重建/校验覆盖（vs PC 的 crash_on_purpose 强制重载路径）。
5. 18.7.5–25.x 的 BookRestore 可用性窗口（`constants.py` 与 README 表述不一致）。
6. 18.4+/26.x 服务端 `intelligence.apple.com/v1/models` 校验的具体实现与绕过可行性（icedmoca 说法待证）。
7. 26.5+ eligibility 失效的具体补丁机制（issue #1073 仅推测）。
