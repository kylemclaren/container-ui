import SwiftUI
import Observation

@MainActor
@Observable
final class ImagesViewModel {
    let service: ImageService

    var images: [ContainerImage] = []
    var isLoading = false
    var errorMessage: String?
    var isDaemonDown = false

    var searchText = ""
    var selectedID: ContainerImage.ID?
    var busyIDs: Set<String> = []

    init(service: ImageService) {
        self.service = service
    }

    var filtered: [ContainerImage] {
        guard !searchText.isEmpty else { return images }
        let query = searchText.lowercased()
        return images.filter { $0.reference.lowercased().contains(query) }
    }

    var selected: ContainerImage? { images.first { $0.id == selectedID } }

    var subtitle: String {
        if images.isEmpty { return "No images" }
        let total = images.map(\.displaySize).reduce(0, +)
        return "\(images.count) images · \(Formatting.bytes(total))"
    }

    func load() async {
        isLoading = images.isEmpty
        defer { isLoading = false }
        do {
            let list = try await service.list()
            withAnimation(Theme.Motion.smooth) {
                images = list.sorted { $0.reference.localizedStandardCompare($1.reference) == .orderedAscending }
            }
            errorMessage = nil
            isDaemonDown = false
        } catch let error as CLIError {
            handle(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ image: ContainerImage) async {
        await perform(image.id) { _ = try await self.service.delete(references: [image.reference]) }
        if selectedID == image.id { selectedID = nil }
    }

    func tag(source: String, target: String) async {
        await perform(source) { _ = try await self.service.tag(source: source, target: target) }
    }

    private func perform(_ id: String, _ action: @escaping () async throws -> Void) async {
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await action()
            await load()
        } catch let error as CLIError {
            handle(error)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ error: CLIError) {
        errorMessage = error.localizedDescription
        if error.isBackendUnavailable { isDaemonDown = true }
    }
}
