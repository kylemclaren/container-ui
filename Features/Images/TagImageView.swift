import SwiftUI

/// Sheet for `container image tag`.
struct TagImageView: View {
    let service: ImageService
    let source: String
    var onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var target = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                Text("Tag image").font(Theme.Typography.title)
                Spacer()
                CircleIconButton(systemImage: "xmark", help: "Close", size: 26) { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(title: "Source")
                    Text(source).font(Theme.Typography.mono).textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "New tag")
                    TextField("docker.io/library/app:1.0", text: $target)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if canTag { Task { await submit() } } }
                }
            }
            .padding(16)

            Divider()
            HStack(spacing: 10) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                PillButton { dismiss() } label: { Text("Cancel") }
                PillButton(style: .accent) {
                    Task { await submit() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Tag", systemImage: "tag")
                    }
                }
                .disabled(!canTag)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 480)
    }

    private var canTag: Bool {
        !target.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await service.tag(source: source, target: target.trimmingCharacters(in: .whitespaces))
            await onComplete()
            dismiss()
        } catch let error as CLIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
