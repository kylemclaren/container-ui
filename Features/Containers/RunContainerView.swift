import SwiftUI

/// A form sheet for `container run`.
struct RunContainerView: View {
    let service: ContainerService
    var onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var image = ""
    @State private var name = ""
    @State private var ports = ""
    @State private var env = ""
    @State private var volumes = ""
    @State private var cpus = ""
    @State private var memory = ""
    @State private var commandText = ""
    @State private var detach = true
    @State private var remove = false

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Image", required: true) {
                        TextField("nginx:latest", text: $image)
                            .textFieldStyle(.roundedBorder)
                    }
                    field("Name") {
                        TextField("optional — defaults to a generated id", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 12) {
                        field("CPUs") {
                            TextField("auto", text: $cpus)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }
                        field("Memory") {
                            TextField("e.g. 1G", text: $memory)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                        }
                        Spacer()
                    }
                    field("Ports", hint: "one per line — host:container[/proto]") {
                        editor($ports, placeholder: "8080:80")
                    }
                    field("Environment", hint: "one KEY=VALUE per line") {
                        editor($env, placeholder: "NODE_ENV=production")
                    }
                    field("Volumes", hint: "one per line — source:target[,ro]") {
                        editor($volumes, placeholder: "/host/path:/container/path")
                    }
                    field("Command", hint: "overrides the image default") {
                        TextField("optional", text: $commandText)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack(spacing: 18) {
                        Toggle("Run detached", isOn: $detach)
                        Toggle("Remove on exit", isOn: $remove)
                    }
                    .toggleStyle(.checkbox)
                    .font(Theme.Typography.callout)
                }
                .padding(18)
            }
            .frame(height: 420)
            Divider()
            footer
        }
        .frame(width: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            Text("Run a container").font(Theme.Typography.title)
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
            }
            Spacer()
            PillButton { dismiss() } label: { Text("Cancel") }
            PillButton(style: .accent) {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Run", systemImage: "play.fill")
                }
            }
            .disabled(image.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Field helpers

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

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(Theme.Typography.mono)
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 64)
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
    }

    // MARK: Submit

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let options = RunOptions(
            image: image.trimmingCharacters(in: .whitespaces),
            name: name.trimmedNonEmpty,
            detach: detach,
            remove: remove,
            env: env.nonEmptyLines,
            publishPorts: ports.nonEmptyLines,
            volumes: volumes.nonEmptyLines,
            cpus: Int(cpus.trimmingCharacters(in: .whitespaces)),
            memory: memory.trimmedNonEmpty,
            command: commandText.split(separator: " ").map(String.init)
        )

        do {
            _ = try await service.run(options)
            await onComplete()
            dismiss()
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
