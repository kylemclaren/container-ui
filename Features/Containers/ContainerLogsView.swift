import SwiftUI
import AppKit

/// A streaming log viewer presented as a sheet. Reads from a `Source` so the
/// same viewer serves containers (`container logs`) and machines
/// (`container machine logs`).
struct ContainerLogsView: View {
    /// Where the lines come from: a display name plus one-shot and followed readers.
    struct Source {
        let name: String
        let fetch: @Sendable (_ tail: Int) async throws -> String
        let stream: @Sendable (_ tail: Int) -> AsyncThrowingStream<StreamLine, Error>

        static func container(_ container: Container, service: ContainerService) -> Source {
            Source(
                name: container.name,
                fetch: { tail in try await service.logs(id: container.id, tail: tail) },
                stream: { tail in service.streamLogs(id: container.id, tail: tail) }
            )
        }

        static func machine(_ machine: ContainerMachine, service: MachineService) -> Source {
            Source(
                name: machine.name,
                fetch: { tail in try await service.logs(id: machine.id, tail: tail) },
                stream: { tail in service.streamLogs(id: machine.id, tail: tail) }
            )
        }
    }

    let source: Source

    init(service: ContainerService, container: Container) {
        source = .container(container, service: service)
    }

    init(source: Source) {
        self.source = source
    }

    @Environment(\.dismiss) private var dismiss

    @State private var lines: [LogLine] = []
    @State private var follow = true
    @State private var autoscroll = true
    @State private var errorMessage: String?

    private struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logBody
            Divider()
            footer
        }
        .frame(width: 760, height: 500)
        .task(id: follow) { await stream() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Logs").font(Theme.Typography.headline)
                Text(source.name).font(Theme.Typography.monoCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Follow", isOn: $follow)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(Theme.Typography.caption)
            Toggle("Auto-scroll", isOn: $autoscroll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(Theme.Typography.caption)
            CircleIconButton(systemImage: "xmark", help: "Close", size: 26) { dismiss() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var logBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(Theme.Typography.mono)
                            .foregroundStyle(line.isError ? Color.red : Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: lines.count) {
                guard autoscroll else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .overlay {
                if lines.isEmpty && errorMessage == nil {
                    Text(follow ? "Waiting for output…" : "No logs.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Text("\(lines.count) lines")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PillButton {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            PillButton { lines = [] } label: { Label("Clear", systemImage: "trash") }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func stream() async {
        lines = []
        errorMessage = nil
        do {
            if follow {
                for try await line in source.stream(500) {
                    append(line)
                }
            } else {
                let text = try await source.fetch(1000)
                lines = text
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { LogLine(text: String($0), isError: false) }
            }
        } catch is CancellationError {
            // expected when toggling follow / closing
        } catch let error as CLIError {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    private func append(_ line: StreamLine) {
        let entry: LogLine
        switch line {
        case .standardOutput(let text): entry = LogLine(text: text, isError: false)
        case .standardError(let text): entry = LogLine(text: text, isError: true)
        }
        lines.append(entry)
        if lines.count > 5000 {
            lines.removeFirst(lines.count - 5000)
        }
    }
}
