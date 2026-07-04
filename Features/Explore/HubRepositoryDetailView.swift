import SwiftUI
import AppKit

/// Inspector for a selected Docker Hub repository: a summary header plus the
/// repository's tags, each of which can be pulled.
struct HubRepositoryDetailView: View {
    let repository: HubRepository
    let service: DockerHubService
    /// Receives a fully-qualified pull reference (`docker.io/library/nginx:latest`).
    var onPull: (String) -> Void

    @State private var tags: [HubTag] = []
    // Starts true so the tags area shows a spinner on first appearance rather
    // than a one-frame "No tags found" flash before `.task` runs. Combined with
    // `.id(repo.id)` at the call site, switching repos gets a fresh instance, so
    // the previous repo's tags never flash under the new header.
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider().opacity(0.4)
                tagsSection
            }
            .padding(18)
        }
        .task(id: repository.id) { await loadTags() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(repository.repoName)
                    .font(Theme.Typography.title)
                    .textSelection(.enabled)
                    .lineLimit(2)
                if repository.isOfficial {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                        .help("Official image")
                }
            }
            if let description = repository.shortDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                StatChip(systemImage: "star.fill", text: "\(Formatting.compactCount(repository.starCount)) stars")
                StatChip(systemImage: "arrow.down.circle", text: "\(Formatting.compactCount(repository.pullCount)) pulls")
            }
            HStack(spacing: 8) {
                PillButton(style: .accent) { onPull(repository.pullReference()) } label: {
                    Label("Pull latest", systemImage: "arrow.down.circle.fill")
                }
                CopyButton(text: repository.pullReference())
                Spacer(minLength: 0)
                Link(destination: hubURL) {
                    Label("Docker Hub", systemImage: "arrow.up.forward.square")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var hubURL: URL {
        let path = repository.isOfficial ? "_/\(repository.repository)" : "r/\(repository.repoName)"
        return URL(string: "https://hub.docker.com/\(path)") ?? URL(string: "https://hub.docker.com")!
    }

    // MARK: Tags

    @ViewBuilder private var tagsSection: some View {
        HStack {
            SectionLabel(title: "Tags")
            Spacer()
            if !isLoading && !tags.isEmpty {
                Text("\(tags.count)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading tags…")
                    .font(Theme.Typography.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 14)
        } else if let errorMessage {
            Text(errorMessage)
                .font(Theme.Typography.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if tags.isEmpty {
            Text("No tags found for this repository.")
                .font(Theme.Typography.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                ForEach(orderedTags) { tag in
                    HubTagRow(tag: tag) { onPull(repository.pullReference(tag: tag.name)) }
                }
            }
        }
    }

    /// `latest` pinned first (stable), otherwise the API's last-updated order.
    private var orderedTags: [HubTag] {
        guard let index = tags.firstIndex(where: { $0.name == "latest" }), index != 0 else { return tags }
        var reordered = tags
        reordered.insert(reordered.remove(at: index), at: 0)
        return reordered
    }

    private func loadTags() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await service.tags(namespace: repository.namespace, repository: repository.repository)
            try Task.checkCancellation()
            tags = fetched
        } catch is CancellationError {
            return   // selection changed; the new .task owns state
        } catch let error as HubError {
            tags = []
            errorMessage = error.errorDescription
        } catch {
            tags = []
            errorMessage = "Couldn’t load tags."
        }
        isLoading = false
    }
}

/// One tag row in the repository inspector, with a hover-revealed Pull button.
private struct HubTagRow: View {
    let tag: HubTag
    var onPull: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(Theme.Typography.headline)
                    .lineLimit(1)
                    .textSelection(.enabled)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.monoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if hovering {
                CircleIconButton(systemImage: "arrow.down", help: "Pull \(tag.name)", size: 26, action: onPull)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Theme.Palette.controlBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Theme.Motion.snappy) { self.hovering = hovering }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let size = tag.displaySize { parts.append(Formatting.bytes(Int64(size))) }
        let platforms = tag.platformSummary
        if !platforms.isEmpty { parts.append(platforms) }
        if let updated = Formatting.relativeISO8601(tag.lastUpdated) { parts.append(updated) }
        return parts.joined(separator: "  ·  ")
    }
}
