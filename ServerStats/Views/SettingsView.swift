import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 30
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var notificationsEnabled = true
    @State private var servers: [ServerConfig] = ServerConfigStore.load()
    @State private var editingServer: ServerConfig?
    @State private var showingAddSheet = false

    // Get monitor from environment to apply changes
    @EnvironmentObject var monitor: ServerMonitor

    var body: some View {
        TabView {
            serversTab
                .tabItem { Label("Server", systemImage: "server.rack") }
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            servers = ServerConfigStore.load()
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    notificationsEnabled = settings.authorizationStatus == .authorized
                }
            }
        }
    }

    // MARK: - Servers Tab

    private var serversTab: some View {
        VStack(spacing: 0) {
            List {
                ForEach(servers) { server in
                    ServerRow(server: server, onEdit: {
                        editingServer = server
                    }, onDelete: {
                        servers.removeAll { $0.id == server.id }
                        saveAndApply()
                    })
                }
                .onMove { from, to in
                    servers.move(fromOffsets: from, toOffset: to)
                    saveAndApply()
                }
                .onDelete { offsets in
                    servers.remove(atOffsets: offsets)
                    saveAndApply()
                }
            }

            Divider()

            HStack {
                Button(action: { showingAddSheet = true }) {
                    Label("Add Server", systemImage: "plus")
                }
                Spacer()
                Text("\(servers.count) Server")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .sheet(item: $editingServer) { server in
            ServerEditSheet(server: server) { updated in
                if let idx = servers.firstIndex(where: { $0.id == updated.id }) {
                    servers[idx] = updated
                    saveAndApply()
                }
                editingServer = nil
            } onCancel: {
                editingServer = nil
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ServerEditSheet(server: nil) { newServer in
                servers.append(newServer)
                saveAndApply()
                showingAddSheet = false
            } onCancel: {
                showingAddSheet = false
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Refresh") {
                LabeledContent("Interval") {
                    Stepper(
                        "\(Int(refreshInterval)) seconds",
                        value: $refreshInterval,
                        in: 5...120,
                        step: 5
                    )
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }

            if !notificationsEnabled {
                Section("Notifications") {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Notifications are disabled.")
                            .font(.system(size: 12))
                    }
                    Button("Open System Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func saveAndApply() {
        ServerConfigStore.save(servers)
        monitor.updateServers(servers)
    }
}

// MARK: - Server Row

struct ServerRow: View {
    let server: ServerConfig
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(size: 13, weight: .medium))
                Text(server.baseURL)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("RAM \(Int(server.ramThreshold))%")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Load \(Int(server.loadThreshold))%")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Server Edit Sheet

struct ServerEditSheet: View {
    let isNew: Bool
    @State private var name: String
    @State private var shortName: String
    @State private var baseURL: String
    @State private var cpuThreshold: Double
    @State private var ramThreshold: Double
    @State private var loadThreshold: Double
    private let serverId: UUID
    let onSave: (ServerConfig) -> Void
    let onCancel: () -> Void

    init(server: ServerConfig?, onSave: @escaping (ServerConfig) -> Void, onCancel: @escaping () -> Void) {
        self.isNew = server == nil
        self.serverId = server?.id ?? UUID()
        _name = State(initialValue: server?.name ?? "")
        _shortName = State(initialValue: server?.shortName ?? "")
        _baseURL = State(initialValue: server?.baseURL ?? "https://")
        _cpuThreshold = State(initialValue: server?.cpuThreshold ?? 80)
        _ramThreshold = State(initialValue: server?.ramThreshold ?? 80)
        _loadThreshold = State(initialValue: server?.loadThreshold ?? 80)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(isNew ? "Add Server" : "Edit Server")
                .font(.headline)

            Form {
                Section("Server") {
                    LabeledContent("Name") {
                        TextField("", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Short Name") {
                        TextField("", text: $shortName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    LabeledContent("Glances URL") {
                        TextField("https://...", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Section("Thresholds") {
                    LabeledContent("CPU") {
                        Stepper("\(Int(cpuThreshold))%", value: $cpuThreshold, in: 50...100, step: 5)
                    }
                    LabeledContent("RAM") {
                        Stepper("\(Int(ramThreshold))%", value: $ramThreshold, in: 50...100, step: 5)
                    }
                    LabeledContent("Load") {
                        Stepper("\(Int(loadThreshold))%", value: $loadThreshold, in: 50...100, step: 5)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isNew ? "Add" : "Save") {
                    let config = ServerConfig(
                        id: serverId,
                        name: name,
                        shortName: shortName,
                        baseURL: baseURL,
                        cpuThreshold: cpuThreshold,
                        ramThreshold: ramThreshold,
                        loadThreshold: loadThreshold
                    )
                    onSave(config)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || shortName.isEmpty || !baseURL.hasPrefix("https://") || baseURL.count < 10)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
