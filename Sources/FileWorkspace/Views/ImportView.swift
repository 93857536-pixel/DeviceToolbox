import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// 文件导入:使用系统 .fileImporter 多选多种文档类型,回调选中文件 URL。
struct ImportView: View {
    @Environment(\.dismiss) private var dismiss

    let onPick: ([URL]) -> Void

    @State private var showImporter = false
    @State private var errorMessage: String?

    /// 允许导入的文档类型(覆盖常见文档 / 文本 / 图片 / 音视频 / 压缩包)。
    private static let allowedTypes: [UTType] = [
        .data, .text, .plainText, .pdf, .image, .audio, .video,
        .movie, .archive, .zip, .json, .xml, .html,
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.defaultSpacing) {
                Spacer()

                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.accent)

                Text(String(localized: "files.import.title"))
                    .font(.title2.bold())

                Text(String(localized: "files.import.hint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.cardPadding)

                Button {
                    showImporter = true
                } label: {
                    Label(String(localized: "files.import.choose"), systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.horizontal, Theme.cardPadding)

                Spacer()
            }
            .padding()
            .navigationTitle(String(localized: "files.import.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: Self.allowedTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    onPick(urls)
                    dismiss()
                case .failure(let error):
                    errorMessage = filesErrorMessage(for: error)
                }
            }
            .alert(String(localized: "files.error.title"), isPresented: errorBinding) {
                Button(String(localized: "common.ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
