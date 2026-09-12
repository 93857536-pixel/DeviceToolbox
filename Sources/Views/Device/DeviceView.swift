import SwiftUI

/// 设备详情:硬件/软件/存储/电池/屏幕/网络/系统 分组列表。
struct DeviceView: View {
    @StateObject private var viewModel = DeviceViewModel()

    var body: some View {
        ScrollView {
            content
        }
        .background(Theme.pageBackdrop)
        .navigationTitle(String(localized: "device.title"))
        .task { await viewModel.load() }
        .refreshable { await viewModel.reload() }
    }

    // MARK: - 内容分发

    @ViewBuilder
    private var content: some View {
        if let info = viewModel.deviceInfo {
            VStack(spacing: Theme.defaultSpacing) {
                hardwareSection(info.hardware)
                softwareSection(info.software)
                storageSection(info.storage)
                batterySection(info.battery)
                screenSection(info.screen)
                networkSection(info.network)
                systemSection(info.system)
            }
            .padding(Theme.defaultSpacing)
        } else if viewModel.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(String(localized: "device.loading"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.unsupported)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "device.retry")) {
                    Task { await viewModel.reload() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding()
        }
    }

    // MARK: - 各分组

    private func hardwareSection(_ h: HardwareInfo) -> some View {
        SectionCard(title: String(localized: "device.hardware"), systemImage: "cpu") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatCard(title: String(localized: "device.marketing.name"), value: h.marketingName, systemImage: "tag")
                StatCard(title: String(localized: "device.machine.id"), value: h.machineIdentifier, systemImage: "number")
                StatCard(title: String(localized: "device.device.type"), value: h.deviceType, systemImage: "apps.iphone")
                StatCard(title: String(localized: "device.ram"), value: Self.bytes(h.totalRAMBytes), systemImage: "memorychip")
                StatCard(title: String(localized: "device.cpu.cores"), value: "\(h.activeProcessorCount) / \(h.processorCount)", systemImage: "cpu")
            }
        }
    }

    private func softwareSection(_ s: SoftwareInfo) -> some View {
        SectionCard(title: String(localized: "device.software"), systemImage: "gearshape.2") {
            infoRow(String(localized: "device.system.name"), s.systemName)
            infoRow(String(localized: "device.system.version"), s.systemVersion)
            infoRow(String(localized: "device.version.string"), s.versionString)
            infoRow(String(localized: "device.build.number"), s.buildNumber ?? String(localized: "device.apple.not.open"))
            infoRow(String(localized: "device.uptime"), Self.uptime(s.systemUptime))
            infoRow(String(localized: "device.locale"), s.localeIdentifier)
            infoRow(String(localized: "device.languages"), s.preferredLanguages.joined(separator: ", "))
        }
    }

    private func storageSection(_ st: StorageInfo) -> some View {
        SectionCard(title: String(localized: "device.storage"), systemImage: "internaldrive") {
            infoRow(String(localized: "device.storage.total"), Self.bytes(st.totalBytes))
            infoRow(String(localized: "device.storage.free"), Self.bytes(st.freeBytes))
            infoRow(String(localized: "device.storage.used"), Self.bytes(st.usedBytes))
        }
    }

    private func batterySection(_ b: BatteryInfo) -> some View {
        SectionCard(title: String(localized: "device.battery"), systemImage: "battery.75") {
            infoRow(String(localized: "device.battery.level"), b.level.map { "\(Int($0 * 100))%" } ?? String(localized: "device.not.available"))
            infoRow(String(localized: "device.battery.state"), batteryStateTitle(b.state))
            infoRow(String(localized: "device.battery.lowpower"), b.isLowPowerModeEnabled ? String(localized: "common.yes") : String(localized: "common.no"))
        }
    }

    private func screenSection(_ sc: ScreenInfo) -> some View {
        SectionCard(title: String(localized: "device.screen"), systemImage: "display") {
            infoRow(String(localized: "device.screen.size"), "\(Int(sc.widthPoints)) × \(Int(sc.heightPoints)) pt")
            infoRow(String(localized: "device.screen.scale"), String(format: "%.0f%%", sc.scale * 100))
            infoRow(String(localized: "device.screen.native"), "\(Int(sc.nativeWidth)) × \(Int(sc.nativeHeight)) px")
            infoRow(String(localized: "device.screen.brightness"), "\(Int(sc.brightness * 100))%")
            infoRow(String(localized: "device.screen.refresh"), refreshText(sc))
        }
    }

    private func networkSection(_ n: NetworkInfo) -> some View {
        SectionCard(title: String(localized: "device.network"), systemImage: "wifi") {
            infoRow(String(localized: "device.network.status"), networkStatusTitle(n.status))
            infoRow(String(localized: "device.network.type"), networkTypeTitle(n.interfaceType))
            infoRow(String(localized: "device.network.interfaces"), n.interfaceNames.isEmpty ? "—" : n.interfaceNames.joined(separator: ", "))
            infoRow(String(localized: "device.network.ipv4"), n.supportsIPv4 ? String(localized: "common.yes") : String(localized: "common.no"))
            infoRow(String(localized: "device.network.ipv6"), n.supportsIPv6 ? String(localized: "common.yes") : String(localized: "common.no"))
        }
    }

    private func systemSection(_ s: SystemInfo) -> some View {
        SectionCard(title: String(localized: "device.system"), systemImage: "cpu") {
            infoRow(String(localized: "device.system.arch"), s.cpuArchitecture)
            infoRow(String(localized: "device.system.simulator"), s.isSimulator ? String(localized: "common.yes") : String(localized: "common.no"))
            infoRow(String(localized: "device.system.kernel"), s.kernelVersion ?? "—")
            infoRow(String(localized: "device.system.hostname"), s.hostname)
        }
    }

    // MARK: - 行

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }

    // MARK: - 文案映射

    private func batteryStateTitle(_ state: BatteryState) -> String {
        switch state {
        case .unknown: return String(localized: "device.battery.state.unknown")
        case .unplugged: return String(localized: "device.battery.state.unplugged")
        case .charging: return String(localized: "device.battery.state.charging")
        case .full: return String(localized: "device.battery.state.full")
        }
    }

    private func networkStatusTitle(_ status: NetworkStatus) -> String {
        switch status {
        case .requiresConnection: return String(localized: "device.network.status.requiresConnection")
        case .satisfied: return String(localized: "device.network.status.satisfied")
        case .unsatisfied: return String(localized: "device.network.status.unsatisfied")
        case .unknown: return String(localized: "device.network.status.unknown")
        }
    }

    private func networkTypeTitle(_ type: NetworkInterfaceType) -> String {
        switch type {
        case .wifi: return String(localized: "device.network.type.wifi")
        case .cellular: return String(localized: "device.network.type.cellular")
        case .wiredEthernet: return String(localized: "device.network.type.wired")
        case .loopback: return String(localized: "device.network.type.loopback")
        case .other: return String(localized: "device.network.type.other")
        case .none: return String(localized: "device.network.type.none")
        }
    }

    private func refreshText(_ sc: ScreenInfo) -> String {
        if let fps = sc.maximumFramesPerSecond {
            return "\(String(localized: "device.screen.refresh.about")) \(fps) Hz"
        }
        return String(localized: "device.screen.refresh.undetectable")
    }

    // MARK: - 格式化

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    private static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    private static func uptime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "—"
    }
}
