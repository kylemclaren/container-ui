import SwiftUI

/// Docker Hub search: type a term, browse repositories, inspect a repo's tags,
/// and pull straight into the local `container` store.
struct ExploreScreen: View {
    @State private var model: ExploreViewModel
    @Environment(AppModel.self) private var app

    @State private var pullTarget: PullTarget?

    init(service: DockerHubService) {
        _model = State(initialValue: ExploreViewModel(service: service))
    }

    /// Identifiable wrapper so `.sheet(item:)` can carry the reference to pull.
    private struct PullTarget: Identifiable {
        let id = UUID()
        let reference: String
    }

    var body: some View {
        @Bindable var model = model
        ScreenScaffold(title: "Explore", subtitle: model.subtitle) {
            SearchField(text: $model.query, prompt: "Search Docker Hub", width: 260)
        } content: {
            content
        }
        .onChange(of: model.query) { model.queryChanged() }
        .onDisappear { model.cancel() }
        .inspector(isPresented: inspectorPresented) {
            inspector.inspectorColumnWidth(min: 320, ideal: 380, max: 540)
        }
        .sheet(item: $pullTarget) { target in
            if let imageService = app.imageService {
                PullImageView(service: imageService, initialReference: target.reference) {}
            }
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading && model.results.isEmpty {
            LoadingView(label: "Searching Docker Hub…")
        } else if let error = model.errorState, model.results.isEmpty {
            errorState(error)
        } else if model.results.isEmpty {
            if model.hasSearched {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No results",
                    message: "Nothing on Docker Hub matched “\(model.query.trimmingCharacters(in: .whitespaces))”."
                )
            } else {
                EmptyStateView(
                    systemImage: "sparkle.magnifyingglass",
                    title: "Search Docker Hub",
                    message: "Find images to pull — try “nginx”, “postgres”, or “redis”."
                )
            }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if let error = model.errorState, !model.results.isEmpty {
                InlineBanner(kind: .warning, title: "Couldn’t refresh results", message: error.errorDescription)
                    .padding([.horizontal, .top], 16)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.results) { repo in
                        HubRepositoryRow(
                            repository: repo,
                            isSelected: model.selectedID == repo.id,
                            onSelect: {
                                withAnimation(Theme.Motion.snappy) {
                                    model.selectedID = (model.selectedID == repo.id) ? nil : repo.id
                                }
                            },
                            onPull: { pullTarget = PullTarget(reference: repo.pullReference()) }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder private func errorState(_ error: HubError) -> some View {
        EmptyStateView(
            systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
            title: error == .offline ? "You’re offline" : "Couldn’t reach Docker Hub",
            message: error.errorDescription,
            actionTitle: "Retry",
            actionIcon: "arrow.clockwise",
            action: { model.retry() }
        )
    }

    @ViewBuilder private var inspector: some View {
        if let repo = model.selected {
            HubRepositoryDetailView(repository: repo, service: model.service) { reference in
                pullTarget = PullTarget(reference: reference)
            }
            // Fresh instance per repo so @State (tags/isLoading) resets on switch.
            .id(repo.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select a repository")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(get: { model.selectedID != nil }, set: { if !$0 { model.selectedID = nil } })
    }
}
