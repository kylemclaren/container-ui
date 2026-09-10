import SwiftUI
import AppKit

struct ProjectsScreen: View {
    @Environment(AppModel.self) private var app
    @State private var pendingStart: ComposeProject?
    @State private var rebuild = false

    private var model: ComposeProjectsModel { app.projects }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text("Projects").font(Theme.Typography.largeTitle)
                        Text("Experimental")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.12), in: Capsule())
                            .help("Compose support is experimental. Review compatibility notes before starting a project.")
                    }
                    Text("Run applications from Compose files").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .disabled(model.isBusy)
                Button("Import Compose…", systemImage: "folder.badge.plus", action: importFile)
                    .disabled(model.isBusy)
            }.padding(20)
            Divider()
            HSplitView {
                List(selection: $model.selection) {
                    ForEach(model.projects) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(model.manifests[project.id]?.name ?? project.directory.lastPathComponent,
                                  systemImage: "folder.badge.gearshape")
                            Text(project.fileURL.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(project.id)
                    }
                }.frame(minWidth: 180, idealWidth: 210, maxWidth: 280)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = model.backendError {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(error, systemImage: "wrench.and.screwdriver").foregroundStyle(.orange)
                                Text("brew install container-compose").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                Link("Container-Compose setup and compatibility", destination: URL(string: "https://github.com/Mcrich23/Container-Compose/tree/1.1.0")!)
                            }.card()
                        }
                        if let project = model.selectedProject {
                            projectDetail(project)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your application, together").font(.title2)
                                Text("Import compose.yaml or docker-compose.yml to preview services, start the stack, and open each service’s logs or console. Files stay in their original directory.")
                                Button("Import Compose…", action: importFile).disabled(model.isBusy)
                            }.card()
                        }
                        if let title = model.operationTitle {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if model.isBusy { ProgressView().controlSize(.small) }
                                    Text("\(title) · \(model.operationProject ?? "Project")").font(.headline)
                                    Spacer()
                                    Button("Copy output") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(model.output.joined(separator: "\n"), forType: .string)
                                    }
                                }
                                Text("\(model.output.count) recent lines").font(.caption).foregroundStyle(.secondary)
                                ScrollView([.horizontal, .vertical]) {
                                    Text(model.output.joined(separator: "\n"))
                                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.frame(height: 220)
                            }.card()
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minWidth: 440)
            }
        }
        .task { await refresh() }
        .onChange(of: app.refreshTick) { Task { await refresh() } }
        .onChange(of: app.composeExecutablePath) { Task { await model.checkBackend(app.composeService) } }
        .alert("Couldn’t complete project action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Start \(pendingStart.flatMap { model.manifests[$0.id]?.name } ?? "project")?", isPresented: Binding(get: { pendingStart != nil }, set: { if !$0 { pendingStart = nil } }), titleVisibility: .visible) {
            if let project = pendingStart {
                Button(rebuild ? "Rebuild & start" : "Start project") { run(project, stop: false) }
            }
            Button("Cancel", role: .cancel) { pendingStart = nil }
        } message: {
            Text("Container-Compose recreates existing project containers. Their writable layers are replaced; named volumes and bind mounts are retained. Review the service preview and compatibility notes before continuing.")
        }
    }

    @ViewBuilder private func projectDetail(_ project: ComposeProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.manifests[project.id]?.name ?? project.directory.lastPathComponent).font(.title2.bold())
            Text(project.fileURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                Button("Reveal file") { NSWorkspace.shared.activateFileViewerSelecting([project.fileURL]) }
                Button("Forget project") {
                    do { try model.forget(project) } catch { model.errorMessage = error.localizedDescription }
                }.disabled(model.isBusy)
                Text("Forget only removes this list entry.").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let fileError = model.fileErrors[project.id] {
            Label(fileError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
        if let manifest = model.manifests[project.id] {
            let containers = manifest.containers(in: app.containers)
            HStack {
                Text("\(containers.filter(\.isRunning).count) running · \(manifest.services.count) services").foregroundStyle(.secondary)
                Spacer()
                Button("Stop project", systemImage: "stop.fill") { run(project, stop: true) }
                    .disabled(model.isBusy || !app.isBackendUp || containers.filter(\.isRunning).isEmpty)
                Menu {
                    Button("Start / recreate…") { rebuild = false; pendingStart = project }
                    Button("Rebuild & start…") { rebuild = true; pendingStart = project }
                } label: { Label("Start project", systemImage: "play.fill") }
                    .disabled(model.isBusy || model.backendVersion == nil || !app.isBackendUp || !manifest.canStart || model.fileErrors[project.id] != nil)
            }
            if !app.isBackendUp {
                Button("Start container service") { Task { await app.startService(); await refresh() } }
            }
            if !manifest.profiles.isEmpty {
                VStack(alignment: .leading) {
                    Text("Profiles").font(.headline)
                    ForEach(manifest.profiles, id: \.self) { profile in
                        Toggle(profile, isOn: Binding(get: { project.profiles.contains(profile) }, set: { enabled in
                            do { try model.setProfile(profile, enabled: enabled, project: project) }
                            catch { model.errorMessage = error.localizedDescription }
                        })).toggleStyle(.checkbox).disabled(model.isBusy)
                    }
                }.card()
            }
            let enabled = Set(manifest.enabledServices(profiles: project.profiles).map(\.name))
            ForEach(manifest.services) { service in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(service.name).font(.headline)
                        Spacer()
                        if !enabled.contains(service.name) { Text("Inactive profile").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(service.image ?? "Build: \(service.build ?? ".")").font(.system(.callout, design: .monospaced))
                    if !service.ports.isEmpty { Text("Ports: \(service.ports.joined(separator: ", "))").font(.caption) }
                    if !service.dependencies.isEmpty { Text("Depends on: \(service.dependencies.joined(separator: ", "))").font(.caption) }
                    ForEach(manifest.containers(in: app.containers, service: service.name)) { container in
                        HStack {
                            Text(container.name).font(.caption)
                            Text(container.isRunning ? "Running" : "Stopped").foregroundStyle(container.isRunning ? .green : .secondary)
                            Spacer()
                            Button("Inspect") { app.dispatch(.inspectContainer(id: container.id)) }
                            Button("Logs") { app.dispatch(.containerLogs(id: container.id)) }
                            Button("Console") { app.openConsole(container) }.disabled(!container.isRunning)
                        }
                    }
                }.card()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Compatibility").font(.headline)
                ForEach(manifest.diagnostics) { diagnostic in
                    Label(diagnostic.message, systemImage: diagnostic.blocking ? "xmark.octagon" : "info.circle")
                        .font(.callout).foregroundStyle(diagnostic.blocking ? Color.red : Color.secondary)
                }
            }.card()
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Compose YAML file. Relative paths and .env resolve from its directory."
        if panel.runModal() == .OK, let url = panel.url {
            do { try model.importFile(url) } catch { model.errorMessage = error.localizedDescription }
        }
    }

    private func refresh() async {
        model.refreshFiles()
        await model.checkBackend(app.composeService)
        await app.refreshContainers()
    }

    private func run(_ project: ComposeProject, stop: Bool) {
        guard let cli = app.cli else { model.errorMessage = "The container CLI is unavailable."; return }
        // Stopping uses ownership labels through the container CLI and remains available
        // even if the optional Compose executable has been removed.
        let service = app.composeService ?? ComposeService(executableURL: cli.executableURL, containerCLI: cli)
        pendingStart = nil
        Task {
            await model.run(project: project, service: service, stop: stop, rebuild: rebuild)
            await app.refreshContainers()
        }
    }
}
