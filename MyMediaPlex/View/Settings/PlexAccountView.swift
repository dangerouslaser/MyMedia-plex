//
//  PlexAccountView.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import SwiftUI

/// Settings view for Plex account connection and configuration
struct PlexAccountView: View {
    @State private var viewModel = PlexAccountViewModel()

    var body: some View {
        Form {
            // Connection Status Section
            Section("Account") {
                switch viewModel.connectionState {
                case .disconnected:
                    disconnectedView

                case .connecting:
                    connectingView

                case .waitingForAuth(let pin):
                    waitingForAuthView(pin: pin)

                case .connected:
                    connectedView
                }
            }

            // Server Selection (when connected but no server selected)
            if viewModel.connectionState == .connected && viewModel.selectedServer == nil && !viewModel.servers.isEmpty {
                Section("Select Server") {
                    serverSelectionView
                }
            }

            // Library Selection (when server is selected)
            if viewModel.selectedServer != nil && !viewModel.libraries.isEmpty {
                Section("Libraries") {
                    librarySelectionView
                }
            }

            // Sync Settings (when fully configured)
            if viewModel.isFullyConfigured {
                Section("Sync") {
                    syncSettingsView
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.loadInitialState()
        }
    }

    // MARK: - Subviews

    private var disconnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Not connected", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)

            Button("Sign in with Plex") {
                Task {
                    await viewModel.startSignIn()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var connectingView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Connecting...")
                .foregroundStyle(.secondary)
        }
    }

    private func waitingForAuthView(pin: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter this code at plex.tv/link:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(pin)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Link(destination: URL(string: "https://plex.tv/link")!) {
                    Label("Open plex.tv/link", systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.bordered)

                Button("Cancel") {
                    viewModel.cancelSignIn()
                }
                .buttonStyle(.bordered)
            }

            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Waiting for authorization...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let username = viewModel.username {
                Label(username, systemImage: "person.circle.fill")
                    .font(.headline)
            }

            if let serverName = viewModel.selectedServerName {
                Label(serverName, systemImage: "server.rack")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button("Sign Out", role: .destructive) {
                Task {
                    await viewModel.signOut()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var serverSelectionView: some View {
        Group {
            ForEach(viewModel.servers) { server in
                Button {
                    Task {
                        await viewModel.selectServer(server)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(server.name)
                                .font(.headline)
                            Text(server.owned ? "Owned" : "Shared")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.isSelectingServer {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSelectingServer)
            }

            if let error = viewModel.serverError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var librarySelectionView: some View {
        Group {
            ForEach(viewModel.libraries) { library in
                Toggle(isOn: viewModel.bindingForLibrary(library)) {
                    HStack {
                        Image(systemName: library.isMovieLibrary ? "film" : "tv")
                            .foregroundStyle(.secondary)
                        Text(library.title)
                    }
                }
            }

            if viewModel.selectedLibraryIDs.isEmpty {
                Text("Select at least one library to sync")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var syncSettingsView: some View {
        Group {
            Toggle("Auto-sync on launch", isOn: $viewModel.autoSync)

            if let lastSync = viewModel.lastSyncDate {
                LabeledContent("Last synced") {
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Sync Now") {
                Task {
                    await viewModel.syncNow()
                }
            }
            .disabled(viewModel.isSyncing)
        }
    }
}

// MARK: - View Model

@Observable
@MainActor
class PlexAccountViewModel {
    // State
    var connectionState: PlexConnectionState = .disconnected
    var servers: [PlexServer] = []
    var selectedServer: PlexServer?
    var libraries: [PlexLibrarySection] = []
    var selectedLibraryIDs: Set<String> = []
    var username: String?
    var isSelectingServer = false
    var isSyncing = false
    var serverError: String?

    // Settings
    var autoSync: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKeys.plexAutoSync) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKeys.plexAutoSync) }
    }

    var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: PreferenceKeys.lastPlexSyncDate) as? Date
    }

    var selectedServerName: String? {
        UserDefaults.standard.string(forKey: PreferenceKeys.plexServerName)
    }

    var isFullyConfigured: Bool {
        connectionState == .connected && selectedServerName != nil && !selectedLibraryIDs.isEmpty
    }

    // Private
    private var pollingTask: Task<Void, Never>?

    // MARK: - Initialization

    func loadInitialState() async {
        // Load selected libraries from UserDefaults
        if let savedLibraries = UserDefaults.standard.array(forKey: PreferenceKeys.plexSelectedLibraries) as? [String] {
            selectedLibraryIDs = Set(savedLibraries)
        }

        // Check if already authenticated
        let isAuthenticated = await PlexAuthService.shared.isAuthenticated

        if isAuthenticated {
            connectionState = .connected

            // Load user info
            do {
                let user = try await PlexAuthService.shared.fetchUser()
                username = user.username
            } catch {
                // User info fetch failed, but still connected
            }

            // Load server URL
            await PlexAPIService.shared.loadServerURL()

            // If server is configured, load libraries
            if selectedServerName != nil {
                await loadLibraries()
            } else {
                // Need to select server - fetch servers
                await fetchServers()
            }
        }
    }

    // MARK: - Sign In Flow

    func startSignIn() async {
        connectionState = .connecting

        do {
            // Request PIN
            let pinResponse = try await PlexAuthService.shared.requestPIN()
            connectionState = .waitingForAuth(pin: pinResponse.code)

            // Start polling in background
            pollingTask = Task {
                do {
                    _ = try await PlexAuthService.shared.pollForAuthorization(pinID: pinResponse.id)

                    // Authorization successful
                    await MainActor.run {
                        connectionState = .connected
                    }

                    // Fetch user and servers
                    await fetchUserAndServers()
                } catch {
                    await MainActor.run {
                        connectionState = .disconnected
                    }
                }
            }
        } catch {
            connectionState = .disconnected
        }
    }

    func cancelSignIn() {
        pollingTask?.cancel()
        pollingTask = nil
        connectionState = .disconnected
    }

    // MARK: - Server Selection

    func fetchServers() async {
        do {
            servers = try await PlexAuthService.shared.fetchServers()
        } catch {
            servers = []
        }
    }

    func selectServer(_ server: PlexServer) async {
        isSelectingServer = true
        serverError = nil

        do {
            try await PlexAuthService.shared.selectServer(server)
            selectedServer = server

            // Load libraries for selected server
            await loadLibraries()
        } catch {
            serverError = error.localizedDescription
            print("Server selection error: \(error)")
        }

        isSelectingServer = false
    }

    // MARK: - Library Selection

    func loadLibraries() async {
        do {
            libraries = try await PlexAPIService.shared.fetchLibrarySections()
        } catch {
            libraries = []
        }
    }

    func bindingForLibrary(_ library: PlexLibrarySection) -> Binding<Bool> {
        Binding(
            get: { self.selectedLibraryIDs.contains(library.id) },
            set: { isSelected in
                if isSelected {
                    self.selectedLibraryIDs.insert(library.id)
                } else {
                    self.selectedLibraryIDs.remove(library.id)
                }
                self.saveSelectedLibraries()
            }
        )
    }

    private func saveSelectedLibraries() {
        UserDefaults.standard.set(Array(selectedLibraryIDs), forKey: PreferenceKeys.plexSelectedLibraries)
    }

    // MARK: - Sync

    func syncNow() async {
        isSyncing = true
        await PlexSyncManager.shared.performFullSync()
        isSyncing = false
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await PlexAuthService.shared.signOut()
        } catch {
            // Continue with local cleanup even if remote sign out fails
        }

        connectionState = .disconnected
        servers = []
        selectedServer = nil
        libraries = []
        selectedLibraryIDs = []
        username = nil
    }

    // MARK: - Private Helpers

    private func fetchUserAndServers() async {
        do {
            let user = try await PlexAuthService.shared.fetchUser()
            await MainActor.run {
                username = user.username
            }
        } catch {
            // User fetch failed
        }

        await fetchServers()
    }
}

// MARK: - Connection State

enum PlexConnectionState: Equatable {
    case disconnected
    case connecting
    case waitingForAuth(pin: String)
    case connected
}

#Preview {
    PlexAccountView()
        .frame(width: 350, height: 400)
}
