import SwiftUI
import Observation

@MainActor
@Observable
final class SystemViewModel {
    let service: SystemService

    var status: SystemStatus?
    var versions: [VersionInfo] = []
    var diskUsage: DiskUsageStats?

    var isLoading = false
    var errorMessage: String?

    var startLog: [String] = []
    var isStarting = false
    var isStopping = false

    init(service: SystemService) {
        self.service = service
    }

    var isRunning: Bool { status?.isRunning ?? false }
    var isBusy: Bool { isStarting || isStopping }

    var subtitle: String {
        guard let status else { return "Checking…" }
        if status.isRunning {
            return "apiserver \(status.apiServerVersion) · \(Formatting.shortDigest(status.apiServerCommit, length: 7))"
        }
        return status.state == .unregistered ? "Not registered" : "Stopped"
    }

    func load() async {
        isLoading = (status == nil)
        defer { isLoading = false }
        do {
            status = try await service.status()
            errorMessage = nil
        } catch let error as CLIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        versions = (try? await service.version()) ?? []
        if isRunning {
            diskUsage = try? await service.diskUsage()
        } else {
            diskUsage = nil
        }
    }

    func start(onFinish: @escaping () async -> Void) async {
        isStarting = true
        startLog = []
        errorMessage = nil
        defer { isStarting = false }
        do {
            for try await line in service.start() {
                let text = line.text
                if !text.isEmpty { startLog.append(text) }
            }
        } catch let error as CLIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
        await onFinish()
    }

    func stop(onFinish: @escaping () async -> Void) async {
        isStopping = true
        errorMessage = nil
        defer { isStopping = false }
        do {
            _ = try await service.stop()
        } catch let error as CLIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        await load()
        await onFinish()
    }
}
