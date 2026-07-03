import SwiftUI

struct ImagesScreen: View {
    @State private var model: ImagesViewModel
    @Environment(AppModel.self) private var app

    @State private var showPull = false
    @State private var showBuild = false
    @State private var tagTarget: ContainerImage?
    @State private var deleteTarget: ContainerImage?
    @State private var runTarget: ContainerImage?

    init(service: ImageService) {
        _model = State(initialValue: ImagesViewModel(service: service))
    }

    var body: some View {
        @Bindable var model = model
        ScreenScaffold(title: "Images", subtitle: model.subtitle) {
            SearchField(text: $model.searchText, prompt: "Search images")
            CircleIconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                Task { await model.load() }
            }
            PillButton { showBuild = true } label: {
                Label("Build", systemImage: "hammer.fill")
            }
            PillButton(style: .accent) { showPull = true } label: {
                Label("Pull", systemImage: "arrow.down.circle.fill")
            }
        } content: {
            content
        }
        .task {
            await model.load()
            // Re-check after load: an intent targeting a specific image can
            // arrive before the list exists (palette → fresh screen).
            consume(app.pendingIntent, listLoaded: true)
        }
        .onChange(of: app.refreshTick) { Task { await model.load() } }
        .onChange(of: app.pendingIntent, initial: true) { _, intent in
            consume(intent, listLoaded: !model.images.isEmpty)
        }
        .inspector(isPresented: inspectorPresented) {
            inspector.inspectorColumnWidth(min: 300, ideal: 360, max: 500)
        }
        .sheet(isPresented: $showPull) {
            PullImageView(service: model.service) { await model.load() }
        }
        .sheet(isPresented: $showBuild) {
            BuildImageView(service: model.service) { await model.load() }
        }
        .sheet(item: $tagTarget) { image in
            TagImageView(service: model.service, source: image.reference) { await model.load() }
        }
        .sheet(item: $runTarget) { image in
            if let containerService = app.containerService {
                RunContainerView(service: containerService, initialImage: image.reference) {
                    app.select(.containers)
                }
            }
        }
        .confirmationDialog(
            "Delete “\(deleteTarget?.reference ?? "")”?",
            isPresented: deleteDialogPresented,
            presenting: deleteTarget
        ) { image in
            Button("Delete", role: .destructive) {
                Task { await model.delete(image) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the image. Images used by a container can’t be deleted.")
        }
    }

    /// Consumes a palette intent addressed to this screen. Intents that name an
    /// image wait until the list has loaded so a fresh mount doesn't drop them;
    /// once loaded, unresolvable targets clear the intent.
    private func consume(_ intent: AppIntent?, listLoaded: Bool) {
        switch intent {
        case .pullImage:
            showPull = true
        case .buildImage:
            showBuild = true
        case .runImage(let reference):
            guard let image = model.images.first(where: { $0.reference == reference }) else {
                if listLoaded { app.clearIntent() }
                return
            }
            runTarget = image
        case .inspectImage(let id):
            guard model.images.contains(where: { $0.id == id }) else {
                if listLoaded { app.clearIntent() }  // target vanished; don't open an empty inspector
                return
            }
            model.selectedID = id
        default:
            return
        }
        app.clearIntent()
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            LoadingView(label: "Loading images…")
        } else if model.isDaemonDown {
            EmptyStateView(
                systemImage: "bolt.slash",
                title: "The container service isn’t running",
                message: "Start it to manage images.",
                actionTitle: "Open System",
                actionIcon: "gearshape.2.fill",
                action: { app.select(.system) }
            )
        } else if let message = model.errorMessage, model.images.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Couldn’t load images",
                message: message,
                actionTitle: "Retry",
                actionIcon: "arrow.clockwise",
                action: { Task { await model.load() } }
            )
        } else if model.filtered.isEmpty {
            EmptyStateView(
                systemImage: "square.stack.3d.up",
                title: model.searchText.isEmpty ? "No images yet" : "No matches",
                message: model.searchText.isEmpty ? "Pull an image from a registry to get started." : nil,
                actionTitle: model.searchText.isEmpty ? "Pull an image" : nil,
                actionIcon: "arrow.down.circle.fill",
                action: { showPull = true }
            )
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if let message = model.errorMessage, !model.images.isEmpty {
                InlineBanner(kind: .error, title: "Action failed", message: message)
                    .padding([.horizontal, .top], 16)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.filtered) { image in
                        ImageRow(
                            image: image,
                            isSelected: model.selectedID == image.id,
                            isBusy: model.busyIDs.contains(image.id),
                            onSelect: {
                                withAnimation(Theme.Motion.snappy) {
                                    model.selectedID = (model.selectedID == image.id) ? nil : image.id
                                }
                            },
                            onRun: app.containerService != nil ? { runTarget = image } : nil,
                            onTag: { tagTarget = image },
                            onDelete: { deleteTarget = image }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder private var inspector: some View {
        if let image = model.selected {
            ImageDetailView(image: image)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select an image").font(Theme.Typography.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspectorPresented: Binding<Bool> {
        Binding(get: { model.selectedID != nil }, set: { if !$0 { model.selectedID = nil } })
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }
}
