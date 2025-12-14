//
//  PlexSyncStatusView.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import SwiftUI

/// Shows Plex sync status in the sidebar bottom bar
struct PlexSyncStatusView: View {

    @State private var syncManager = PlexSyncManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sync progress (when syncing)
            if syncManager.syncState == .syncing, let progress = syncManager.currentProgress {
                HStack {
                    ProgressView(value: progress.percentage)
                        .progressViewStyle(.circular)
                        .frame(height: 40)

                    VStack(alignment: .leading) {
                        Text("Syncing")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(progress.phase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Divider()
            }

            // Sync complete indicator (briefly shown)
            if syncManager.syncState == .completed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    Text("Sync Complete")
                        .font(.subheadline)
                }

                Divider()
            }

            // Error indicator
            if syncManager.syncState == .error, let error = syncManager.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading) {
                        Text("Sync Failed")
                            .font(.subheadline)

                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Divider()
            }

            // Main sync button and status
            HStack {
                Button {
                    Task {
                        await syncManager.performFullSync()
                    }
                } label: {
                    Label("Sync with Plex", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .disabled(syncManager.syncState == .syncing)

                Spacer()

                if let lastSync = lastSyncDate {
                    Text(lastSync, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 3)
        }
    }

    private var lastSyncDate: Date? {
        UserDefaults.standard.object(forKey: PreferenceKeys.lastPlexSyncDate) as? Date
    }
}

#Preview {
    PlexSyncStatusView()
        .frame(width: 250)
}
