import SwiftUI
import AppKit

/// Sheet for `container image pull`, streaming progress output.
struct PullImageView: View {
    let service: ImageService
    var onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reference = ""
    @State private var lines: [String] = []
    @State private var isPulling = false
    @State private var finished = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("docker.io/library/nginx:latest", text: $reference)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { if canPull { Task { await pull() } } }
                    PillButton(style: .accent) {
                        Task { await pull() }
                    } label: {
                        if isPulling {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Pull", systemImage: "arrow.down")
                        }
                    }
                    .disabled(!canPull)
                }

                console
            }
            .padding(16)
            Divider()
            footer
        }
        .frame(width: 600, height: 460)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            Text("Pull an image").font(Theme.Typography.title)
            Spacer()
            CircleIconButton(systemImage: "xmark", help: "Close", size: 26) { dismiss() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(Theme.Typography.monoCaption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                if lines.isEmpty {
                    Text("Pull progress appears here.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: lines.count) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if finished {
                Label("Pulled \(reference)", systemImage: "checkmark.circle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            Spacer()
            PillButton { dismiss() } label: { Text(finished ? "Done" : "Cancel") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canPull: Bool {
        !reference.trimmingCharacters(in: .whitespaces).isEmpty && !isPulling
    }

    private func pull() async {
        isPulling = true
        finished = false
        errorMessage = nil
        lines = []
        defer { isPulling = false }
        do {
            for try await line in service.pull(reference: reference.trimmingCharacters(in: .whitespaces)) {
                lines.append(line.text)
            }
            finished = true
            await onComplete()
        } catch let error as CLIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
