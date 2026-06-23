import SwiftUI

struct ImageDetailView: View {
    let image: ContainerImage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                overview

                if !image.platforms.isEmpty {
                    section("Platforms") {
                        ForEach(image.platforms, id: \.display) { platform in
                            Text(platform.display)
                                .font(Theme.Typography.mono)
                                .textSelection(.enabled)
                        }
                    }
                }

                if let config = image.primaryVariant?.config.config {
                    section("Config") {
                        if let entrypoint = config.entrypoint, !entrypoint.isEmpty {
                            KeyValueRow("Entrypoint", entrypoint.joined(separator: " "), mono: true)
                        }
                        if let cmd = config.cmd, !cmd.isEmpty {
                            KeyValueRow("Cmd", cmd.joined(separator: " "), mono: true)
                        }
                        if let workingDir = config.workingDir, !workingDir.isEmpty {
                            KeyValueRow("Workdir", workingDir, mono: true)
                        }
                        if let user = config.user, !user.isEmpty {
                            KeyValueRow("User", user)
                        }
                        if let stopSignal = config.stopSignal {
                            KeyValueRow("Stop signal", stopSignal)
                        }
                    }

                    if let env = config.env, !env.isEmpty {
                        section("Environment") {
                            ForEach(Array(env.enumerated()), id: \.offset) { _, entry in
                                Text(entry)
                                    .font(Theme.Typography.monoCaption)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if let labels = config.labels, !labels.isEmpty {
                        section("Labels") {
                            ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                KeyValueRow(key, value, mono: true)
                            }
                        }
                    }
                }

                if let variant = image.primaryVariant {
                    section("Layers") {
                        KeyValueRow("Count", "\(variant.config.rootfs.diffIDs.count)")
                        KeyValueRow("Type", variant.config.rootfs.type)
                    }
                }
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(image.parsedReference.displayName)
                    .font(Theme.Typography.title)
                    .lineLimit(1)
                Text(image.shortID)
                    .font(Theme.Typography.monoCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            CopyButton(text: image.reference)
        }
    }

    private var overview: some View {
        section("Overview") {
            KeyValueRow("Reference", image.reference, mono: true)
            KeyValueRow("ID", image.shortID, mono: true)
            KeyValueRow("Size", Formatting.bytes(image.displaySize))
            KeyValueRow("Created", image.createdAt.formatted(date: .abbreviated, time: .shortened))
            KeyValueRow("Media type", image.configuration.descriptor.mediaType, mono: true)
            KeyValueRow("Digest", Formatting.shortDigest(image.configuration.descriptor.digest, length: 19), mono: true)
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title: title)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
    }
}
