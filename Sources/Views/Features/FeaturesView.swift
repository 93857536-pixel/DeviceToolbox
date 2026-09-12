import SwiftUI

/// 功能中心:功能列表 + 状态筛选。
struct FeaturesView: View {
    @StateObject private var viewModel = FeatureViewModel()

    var body: some View {
        List {
            Section {
                Picker(String(localized: "features.filter"), selection: $viewModel.filterStatus) {
                    Text(String(localized: "features.filter.all")).tag(CapabilityStatus?.none)
                    Text(String(localized: "features.filter.supported")).tag(CapabilityStatus?.some(.supported))
                    Text(String(localized: "features.filter.partial")).tag(CapabilityStatus?.some(.partial))
                    Text(String(localized: "features.filter.unsupported")).tag(CapabilityStatus?.some(.unsupported))
                    Text(String(localized: "features.filter.unknown")).tag(CapabilityStatus?.some(.unknown))
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)
            }

            if viewModel.filteredItems.isEmpty {
                Section {
                    Text(String(localized: "features.empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            } else {
                Section {
                    ForEach(viewModel.filteredItems) { item in
                        NavigationLink {
                            FeatureDetailView(item: item)
                        } label: {
                            FeatureRowView(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "features.title"))
        .task {
            if viewModel.items.isEmpty {
                await viewModel.load()
            }
        }
        .refreshable { await viewModel.load() }
    }
}
