import SwiftUI
import AppKit

/// Sheet for `container image pull`, rendering a parsed progress bar with the
/// raw CLI output tucked behind a collapsible disclosure.
struct PullImageView: View {
    let service: ImageService
    var onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reference: String
    @State private var lines: [String] = []
    @State private var progress: PullProgress?
    @State private var displayedFraction: Double = 0
    @State private var isPulling = false
    @State private var finished = false
    @State private var errorMessage: String?
    @State private var showConsole = false

    init(service: ImageService, initialReference: String = "", onComplete: @escaping () async -> Void) {
        self.service = service
        self.onComplete = onComplete
        _reference = State(initialValue: initialReference)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                inputRow
                progressCard
                consoleDisclosure
            }
            .padding(16)
            Divider()
            footer
        }
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)  // hug content; no dead space
        .animation(Theme.Motion.spring, value: showConsole)
    }

    // MARK: - Header / footer

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

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("docker.io/library/nginx:latest", text: $reference)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if canPull { Task { await pull() } } }
                .disabled(isPulling)
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
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: stageIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(finished ? Color.green : Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stageTitle)
                        .font(Theme.Typography.headline)
                    if let subtitle = stageSubtitle {
                        Text(subtitle)
                            .font(Theme.Typography.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int((displayedFraction * 100).rounded()))%")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let trailing = stageTrailing {
                        Text(trailing)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressBar(fraction: displayedFraction, indeterminate: isIndeterminate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardCorner, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        }
        .opacity(hasActivity ? 1 : 0.55)
    }

    /// True once a pull has started; before that the card shows a neutral hint.
    private var hasActivity: Bool { isPulling || finished || errorMessage != nil }

    private var isIndeterminate: Bool { isPulling && progress == nil }

    private var stageIcon: String {
        if finished { return "checkmark.circle.fill" }
        return progress?.systemImage ?? "shippingbox"
    }

    private var stageTitle: String {
        if finished { return "Pull complete" }
        if errorMessage != nil { return "Pull failed" }
        if let progress { return progress.title }
        return isPulling ? "Starting…" : "Ready to pull"
    }

    private var stageSubtitle: String? {
        if finished { return reference }
        if errorMessage != nil { return nil }
        if let progress { return progress.subtitle }
        return isPulling ? nil : "Enter an image reference and press Pull."
    }

    /// Right-aligned secondary text: "Step 1 of 2 · 12s".
    private var stageTrailing: String? {
        guard let progress, !finished else { return nil }
        var parts = ["Step \(progress.stepIndex) of \(progress.stepCount)"]
        if let elapsed = progress.elapsedSeconds { parts.append("\(elapsed)s") }
        return parts.joined(separator: " · ")
    }

    // MARK: - CLI output

    @ViewBuilder
    private var consoleDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Theme.Motion.spring) { showConsole.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showConsole ? 90 : 0))
                    Text("CLI output")
                        .font(Theme.Typography.caption)
                    Spacer()
                    if !lines.isEmpty {
                        Text("\(lines.count) lines")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showConsole { console.frame(height: 180) }
        }
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
                    Text("CLI output appears here once a pull starts.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: lines.count) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Actions

    private var canPull: Bool {
        !reference.trimmingCharacters(in: .whitespaces).isEmpty && !isPulling
    }

    private func pull() async {
        isPulling = true
        finished = false
        errorMessage = nil
        lines = []
        progress = nil
        displayedFraction = 0
        defer { isPulling = false }
        do {
            for try await line in service.pull(reference: reference.trimmingCharacters(in: .whitespaces)) {
                lines.append(line.text)
                if let parsed = PullProgress.parse(line: line.text) {
                    progress = parsed
                    // Clamp upward so the bar never jumps backwards between phases.
                    withAnimation(Theme.Motion.smooth) {
                        displayedFraction = max(displayedFraction, parsed.overallFraction)
                    }
                }
            }
            withAnimation(Theme.Motion.smooth) { displayedFraction = 1 }
            finished = true
            await onComplete()
        } catch let error as CLIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
