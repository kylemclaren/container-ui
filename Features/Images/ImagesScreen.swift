import SwiftUI

struct ImagesScreen: View {
    @State private var model: ImagesViewModel
    @Environment(AppModel.self) private var app

    @State private var showPull = false
    @State private var tagTarget: ContainerImage?
    @State private var deleteTarget: ContainerImage?

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
            PillButton(style: .accent) { showPull = true } label: {
                Label("Pull", systemImage: "arrow.down.circle.fill")
            }
        } content: {
            content
        }
        .task { await model.load() }
        .inspector(isPresented: inspectorPresented) {
            inspector.inspectorColumnWidth(min: 300, ideal: 360, max: 500)
        }
        .sheet(isPresented: $showPull) {
            PullImageView(service: model.service) { await model.load() }
        }
        .sheet(item: $tagTarget) { image in
            TagImageView(service: model.service, source: image.reference) { await model.load() }
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
