import SwiftUI
import AppKit

/// Sheet for `container build`: pick a context directory and (optionally) a
/// Dockerfile, tag, build args, and target stage, then stream the build output.
struct BuildImageView: View {
    let service: ImageService
    var onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var contextDir = ""
    @State private var dockerfile = ""
    @State private var tag = ""
    @State private var buildArgs = ""
    @State private var labels = ""
    @State private var target = ""
    @State private var noCache = false

    @State private var lines: [String] = []
    @State private var isBuilding = false
    @State private var finished = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pathField(
                        "Context directory", required: true,
                        hint: "the build context sent to the builder",
                        text: $contextDir, placeholder: "/path/to/project",
                        choose: chooseContext, chooseDirectories: true
                    )
                    pathField(
                        "Dockerfile", hint: "defaults to Dockerfile in the context",
                        text: $dockerfile, placeholder: "optional — path to a Dockerfile",
                        choose: chooseDockerfile, chooseDirectories: false
                    )
                    field("Tag", hint: "name for the built image") {
                        TextField("optional — e.g. myapp:latest", text: $tag)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isBuilding)
                    }
                    field("Build args", hint: "one KEY=VALUE per line") {
                        editor($buildArgs, placeholder: "VERSION=1.2.3")
                    }
                    field("Labels", hint: "one KEY=VALUE per line") {
                        editor($labels, placeholder: "team=infra")
                    }
                    field("Target stage", hint: "for multi-stage builds") {
                        TextField("optional — e.g. builder", text: $target)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isBuilding)
                    }
                    Toggle("Build without cache", isOn: $noCache)
                        .toggleStyle(.checkbox)
                        .font(Theme.Typography.callout)
                        .disabled(isBuilding)

                    if showConsole { consoleSection }
                }
                .padding(18)
            }
            .frame(height: 460)
            Divider()
            footer
        }
        .frame(width: 620)
        .animation(Theme.Motion.spring, value: showConsole)
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 17))
                .foregroundStyle(Color.accentColor)
            Text("Build an image").font(Theme.Typography.title)
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
                Label(tag.trimmedNonEmpty.map { "Built \($0)" } ?? "Build complete",
                      systemImage: "checkmark.circle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            }
            Spacer()
            PillButton { dismiss() } label: { Text(finished ? "Done" : "Cancel") }
            PillButton(style: .accent) {
                Task { await build() }
            } label: {
                if isBuilding {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Build", systemImage: "hammer.fill")
                }
            }
            .disabled(!canBuild)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Console

    private var showConsole: Bool {
        isBuilding || finished || errorMessage != nil || !lines.isEmpty
    }

    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel(title: "Build output")
                Spacer()
                if !lines.isEmpty {
                    Text("\(lines.count) lines")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            console.frame(height: 180)
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
                    Text(isBuilding ? "Starting build…" : "Build output appears here.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: lines.count) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Field helpers

    @ViewBuilder private func field<Content: View>(
        _ label: String,
        required: Bool = false,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(label).font(Theme.Typography.caption)
                if required { Text("*").foregroundStyle(.red).font(Theme.Typography.caption) }
                if let hint {
                    Text(hint).font(Theme.Typography.monoCaption).foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }

    private func pathField(
        _ label: String,
        required: Bool = false,
        hint: String? = nil,
        text: Binding<String>,
        placeholder: String,
        choose: @escaping () -> Void,
        chooseDirectories: Bool
    ) -> some View {
        field(label, required: required, hint: hint) {
            HStack(spacing: 8) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBuilding)
                PillButton(action: choose) {
                    Label("Browse…", systemImage: chooseDirectories ? "folder" : "doc")
                }
                .disabled(isBuilding)
            }
        }
    }

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(Theme.Typography.mono)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 56)
            .background(Theme.Palette.controlBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(Theme.Typography.mono)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .disabled(isBuilding)
    }

    // MARK: - Panels

    private func chooseContext() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let dir = contextDir.trimmedNonEmpty { panel.directoryURL = URL(fileURLWithPath: dir) }
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { contextDir = url.path }
    }

    private func chooseDockerfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let dir = contextDir.trimmedNonEmpty { panel.directoryURL = URL(fileURLWithPath: dir) }
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url { dockerfile = url.path }
    }

    // MARK: - Build

    private var canBuild: Bool {
        contextDir.trimmedNonEmpty != nil && !isBuilding
    }

    private func build() async {
        isBuilding = true
        finished = false
        errorMessage = nil
        lines = []
        defer { isBuilding = false }

        let options = BuildOptions(
            contextDirectory: contextDir.trimmingCharacters(in: .whitespaces),
            tag: tag.trimmedNonEmpty,
            dockerfilePath: dockerfile.trimmedNonEmpty,
            buildArgs: buildArgs.nonEmptyLines,
            labels: labels.nonEmptyLines,
            noCache: noCache,
            target: target.trimmedNonEmpty
        )

        do {
            for try await line in service.build(options) {
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

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nonEmptyLines: [String] {
        split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
