import SwiftUI
import Observation

/// Drives the Explore screen: a debounced, cancellable Docker Hub search.
@MainActor
@Observable
final class ExploreViewModel {
    let service: DockerHubService

    var query = ""
    var results: [HubRepository] = []
    var isLoading = false
    var errorState: HubError?
    /// True once a real (≥ min length) search has completed, so the empty view
    /// can distinguish "type something" from "no matches".
    var hasSearched = false
    var selectedID: HubRepository.ID?

    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Minimum query length before a network search fires.
    private let minQueryLength = 2
    /// Debounce so typing doesn't hammer the API.
    private let debounce = Duration.milliseconds(300)

    init(service: DockerHubService) {
        self.service = service
    }

    var selected: HubRepository? { results.first { $0.id == selectedID } }

    var subtitle: String {
        if !results.isEmpty {
            return "\(results.count) result\(results.count == 1 ? "" : "s") on Docker Hub"
        }
        return "Search Docker Hub"
    }

    /// Called on every keystroke: cancels any pending search, clears results when
    /// the query is too short, otherwise debounces and searches.
    func queryChanged() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minQueryLength else {
            results = []
            errorState = nil
            isLoading = false
            hasSearched = false
            if selectedID != nil { selectedID = nil }
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            if Task.isCancelled { return }
            await self.performSearch(trimmed)
        }
    }

    /// Re-runs the current query immediately (used by the error-state Retry).
    func retry() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minQueryLength else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.performSearch(trimmed)
        }
    }

    /// Cancels any in-flight search (e.g. when the screen disappears).
    func cancel() {
        searchTask?.cancel()
    }

    private func performSearch(_ trimmed: String) async {
        isLoading = true
        do {
            let found = try await service.search(query: trimmed)
            try Task.checkCancellation()
            guard isCurrent(trimmed) else { return }   // superseded by a newer search
            withAnimation(Theme.Motion.smooth) { results = found }
            errorState = nil
            if let selectedID, !found.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch is CancellationError {
            return   // a newer search owns the state now — don't touch isLoading
        } catch {
            guard isCurrent(trimmed) else { return }
            errorState = (error as? HubError) ?? .offline
            // Keep any existing results on screen so a transient failure while
            // refining a query shows an inline "refresh failed" banner instead of
            // dumping the user to a full-screen error and closing the inspector.
            if results.isEmpty { selectedID = nil }
        }
        hasSearched = true
        isLoading = false
    }

    /// A response is current only if the query still matches and we weren't cancelled.
    private func isCurrent(_ trimmed: String) -> Bool {
        !Task.isCancelled && trimmed == query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
