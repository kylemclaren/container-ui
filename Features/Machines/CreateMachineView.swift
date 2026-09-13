import SwiftUI

/// Sheet for `container machine create`. Creating also boots the machine and
/// provisions the host user, so progress is streamed like a pull.
struct CreateMachineView: View {
    let service: MachineService
    var onDone: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    @State private var image = ""
    @State private var name = ""
    @State private var cpus = ""
    @State private var memory = ""
    @State private var homeMount: MachineHomeMount = .rw
    @State private var setDefault = false

    @State private var localImages: [String] = []
    @State private var lines: [String] = []
    @State private var isWorking = false
    @State private var finished = false
    @State private var errorMessage: String?
    @State private var showConsole = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                form
                progressCard
                consoleDisclosure
            }
            .padding(16)
            Divider()
            footer
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .animation(Theme.Motion.spring, value: showConsole)
        .task { await loadLocalImages() }
    }

    // MARK: Header / footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Create a machine").font(Theme.Typography.title)
                Text("A persistent Linux environment with your user and home directory mapped in.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
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
                Label("Created and booted \(createdName)", systemImage: "checkmark.circle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            } else if let warning = validationWarning {
                Label(warning, systemImage: "info.circle")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            PillButton { dismiss() } label: { Text(finished ? "Done" : "Cancel") }
            if !finished {
                PillButton(style: .accent) {
                    Task { await submit() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Create & boot", systemImage: "play.fill")
                    }
                }
                .disabled(!canCreate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(title: "Image")
                HStack(spacing: 8) {
                    TextField("e.g. ubuntu:24.04 or a local image", text: $image)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isWorking)
                    if !localImages.isEmpty {
                        Menu {
                            ForEach(localImages, id: \.self) { reference in
                                Button(reference) { image = reference }
                            }
                        } label: {
                            Label("Local", systemImage: "square.stack.3d.up")
                                .font(Theme.Typography.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(isWorking)
                    }
                }
                Text("Any Linux image with /sbin/init works. Images with systemd (e.g. Ubuntu) give you real services; minimal images still work for a shell.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "Name (optional)")
                    TextField("derived from the image", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isWorking)
                }
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "CPUs")
                    TextField("default", text: $cpus)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .disabled(isWorking)
                }
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "Memory")
                    TextField("half of host", text: $memory)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .disabled(isWorking)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(title: "Home directory")
                    Picker("", selection: $homeMount) {
                        ForEach(MachineHomeMount.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(isWorking)
                }
                Toggle("Make this the default machine", isOn: $setDefault)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(Theme.Typography.caption)
                    .padding(.top, 16)
                    .disabled(isWorking)
                Spacer()
            }
        }
    }

    // MARK: Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: finished ? "checkmark.circle.fill" : "desktopcomputer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(finished ? Color.green : Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stageTitle).font(Theme.Typography.headline)
                    Text(stageSubtitle)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            ProgressBar(fraction: finished ? 1 : 0, indeterminate: isWorking)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.cardFill, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Metrics.cardCorner, style: .continuous)
                .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
        }
        .opacity(isWorking || finished || errorMessage != nil ? 1 : 0.55)
    }

    private var stageTitle: String {
        if finished { return "Machine ready" }
        if errorMessage != nil { return "Create failed" }
        if isWorking { return lines.last(where: { $0.hasPrefix("[") }) ?? "Creating…" }
        return "Ready to create"
    }

    private var stageSubtitle: String {
        if finished { return "Open a shell to start using it." }
        if isWorking { return "Pulling the image if needed, then booting and setting up your user." }
        return "The machine boots right after it's created."
    }

    @ViewBuilder private var consoleDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Theme.Motion.spring) { showConsole.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(showConsole ? 90 : 0))
                    Text("CLI output").font(Theme.Typography.caption)
                    Spacer()
                    if !lines.isEmpty {
                        Text("\(lines.count) lines").font(Theme.Typography.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showConsole {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(Theme.Typography.monoCaption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 150)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    // MARK: Validation & actions

    private var trimmedImage: String { image.trimmingCharacters(in: .whitespaces) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var createdName: String { trimmedName.isEmpty ? "the machine" : trimmedName }

    private var validationWarning: String? {
        if !trimmedName.isEmpty, !MachineService.isValidName(trimmedName) {
            return "Names are 2–63 characters: letters, digits, dot, underscore, or hyphen, starting with a letter or digit."
        }
        let trimmedCPUs = cpus.trimmingCharacters(in: .whitespaces)
        if !trimmedCPUs.isEmpty, Int(trimmedCPUs).map({ $0 < 1 }) ?? true {
            return "CPUs must be a whole number."
        }
        return nil
    }

    private var canCreate: Bool {
        !trimmedImage.isEmpty && validationWarning == nil && !isWorking
    }

    private func loadLocalImages() async {
        guard let images = try? await app.imageService?.list() else { return }
        localImages = images.map(\.reference).sorted()
    }

    private func submit() async {
        guard canCreate else { return }
        isWorking = true
        errorMessage = nil
        lines = []
        defer { isWorking = false }
        let options = MachineCreateOptions(
            image: trimmedImage,
            name: trimmedName.isEmpty ? nil : trimmedName,
            cpus: Int(cpus.trimmingCharacters(in: .whitespaces)),
            memory: memory.trimmingCharacters(in: .whitespaces).isEmpty ? nil : memory.trimmingCharacters(in: .whitespaces),
            homeMount: homeMount == .rw ? nil : homeMount,
            setDefault: setDefault
        )
        do {
            for try await line in service.create(options) {
                lines.append(line.text)
            }
            finished = true
            await onDone()
        } catch let error as CLIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
