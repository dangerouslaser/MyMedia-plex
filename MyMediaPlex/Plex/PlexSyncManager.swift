//
//  PlexSyncManager.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation
import SwiftData

/// Orchestrates library synchronization from Plex server
@Observable
@MainActor
class PlexSyncManager {
    static let shared = PlexSyncManager()

    // MARK: - State

    var syncState: PlexSyncState = .idle
    var currentProgress: SyncProgress?
    var lastError: Error?

    struct SyncProgress {
        var phase: String
        var current: Int
        var total: Int

        var percentage: Double {
            guard total > 0 else { return 0 }
            return Double(current) / Double(total)
        }
    }

    // MARK: - Private

    private var modelContext: ModelContext?

    private init() {}

    // MARK: - Configuration

    /// Sets the model context for database operations
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Sync Operations

    /// Performs a full library sync
    func performFullSync() async {
        guard syncState != .syncing else { return }
        guard let context = modelContext else {
            lastError = PlexSyncError.noModelContext
            return
        }

        syncState = .syncing
        lastError = nil
        currentProgress = SyncProgress(phase: "Starting...", current: 0, total: 0)

        do {
            // Get selected libraries
            let selectedLibraryIDs = getSelectedLibraryIDs()
            guard !selectedLibraryIDs.isEmpty else {
                throw PlexSyncError.noLibrariesSelected
            }

            // Fetch all library sections
            let sections = try await PlexAPIService.shared.fetchLibrarySections()
            let selectedSections = sections.filter { selectedLibraryIDs.contains($0.id) }

            let serverUUID = UserDefaults.standard.string(forKey: PreferenceKeys.plexServerUUID) ?? ""

            // Track synced rating keys for cleanup
            var syncedMovieKeys: Set<String> = []
            var syncedShowKeys: Set<String> = []

            // Sync each selected section
            for section in selectedSections {
                if section.isMovieLibrary {
                    let keys = try await syncMovieLibrary(
                        section: section,
                        serverUUID: serverUUID,
                        context: context
                    )
                    syncedMovieKeys.formUnion(keys)
                } else if section.isTVShowLibrary {
                    let keys = try await syncTVShowLibrary(
                        section: section,
                        serverUUID: serverUUID,
                        context: context
                    )
                    syncedShowKeys.formUnion(keys)
                }
            }

            // Remove items no longer in Plex
            currentProgress = SyncProgress(phase: "Cleaning up...", current: 0, total: 0)
            try await cleanupRemovedItems(
                syncedMovieKeys: syncedMovieKeys,
                syncedShowKeys: syncedShowKeys,
                serverUUID: serverUUID,
                context: context
            )

            // Save changes
            try context.save()

            // Update last sync date
            UserDefaults.standard.set(Date(), forKey: PreferenceKeys.lastPlexSyncDate)

            syncState = .completed
            currentProgress = nil

        } catch {
            lastError = error
            syncState = .error
            currentProgress = nil
        }
    }

    // MARK: - Movie Sync

    private func syncMovieLibrary(
        section: PlexLibrarySection,
        serverUUID: String,
        context: ModelContext
    ) async throws -> Set<String> {
        currentProgress = SyncProgress(phase: "Fetching movies...", current: 0, total: 0)

        let sectionID = Int(section.key) ?? 0
        let plexMovies = try await PlexAPIService.shared.fetchMovies(sectionID: sectionID)

        currentProgress = SyncProgress(phase: "Syncing movies...", current: 0, total: plexMovies.count)

        var syncedKeys: Set<String> = []

        for (index, plexMovie) in plexMovies.enumerated() {
            currentProgress = SyncProgress(
                phase: "Syncing: \(plexMovie.title)",
                current: index + 1,
                total: plexMovies.count
            )

            // Check if movie exists
            let existingMovie = try findExistingMovie(ratingKey: plexMovie.ratingKey, context: context)

            // Download artwork
            let artwork = await PlexImageLoader.shared.downloadArtwork(path: plexMovie.thumb)

            if let movie = existingMovie {
                // Update existing movie
                PlexMetadataMapper.updateMovie(movie, from: plexMovie, artwork: artwork)
            } else {
                // Create new movie
                let movie = PlexMetadataMapper.createMovie(
                    from: plexMovie,
                    serverUUID: serverUUID,
                    sectionID: sectionID,
                    artwork: artwork
                )
                context.insert(movie)
            }

            syncedKeys.insert(plexMovie.ratingKey)
        }

        return syncedKeys
    }

    // MARK: - TV Show Sync

    private func syncTVShowLibrary(
        section: PlexLibrarySection,
        serverUUID: String,
        context: ModelContext
    ) async throws -> Set<String> {
        currentProgress = SyncProgress(phase: "Fetching TV shows...", current: 0, total: 0)

        let sectionID = Int(section.key) ?? 0
        let plexShows = try await PlexAPIService.shared.fetchTVShows(sectionID: sectionID)

        currentProgress = SyncProgress(phase: "Syncing TV shows...", current: 0, total: plexShows.count)

        var syncedKeys: Set<String> = []

        for (index, plexShow) in plexShows.enumerated() {
            currentProgress = SyncProgress(
                phase: "Syncing: \(plexShow.title)",
                current: index + 1,
                total: plexShows.count
            )

            // Check if show exists
            let existingShow = try findExistingTvShow(ratingKey: plexShow.ratingKey, context: context)

            // Download artwork
            let artwork = await PlexImageLoader.shared.downloadArtwork(path: plexShow.thumb)

            let show: TvShow
            if let existing = existingShow {
                // Update existing show
                PlexMetadataMapper.updateTvShow(existing, from: plexShow, artwork: artwork)
                show = existing
            } else {
                // Create new show
                show = PlexMetadataMapper.createTvShow(
                    from: plexShow,
                    serverUUID: serverUUID,
                    sectionID: sectionID,
                    artwork: artwork
                )
                context.insert(show)
            }

            // Sync episodes for this show
            try await syncEpisodesForShow(
                show: show,
                plexShowRatingKey: plexShow.ratingKey,
                serverUUID: serverUUID,
                context: context
            )

            syncedKeys.insert(plexShow.ratingKey)
        }

        return syncedKeys
    }

    private func syncEpisodesForShow(
        show: TvShow,
        plexShowRatingKey: String,
        serverUUID: String,
        context: ModelContext
    ) async throws {
        // Fetch all episodes for the show
        let plexEpisodes = try await PlexAPIService.shared.fetchAllEpisodes(showRatingKey: plexShowRatingKey)

        // Track synced episode keys
        var syncedEpisodeKeys: Set<String> = []

        for plexEpisode in plexEpisodes {
            // Check if episode exists
            let existingEpisode = show.episodes.first { $0.plexRatingKey == plexEpisode.ratingKey }

            // Download artwork (episode still)
            let artwork = await PlexImageLoader.shared.downloadArtwork(path: plexEpisode.thumb)

            if let episode = existingEpisode {
                // Update existing episode
                PlexMetadataMapper.updateEpisode(episode, from: plexEpisode, artwork: artwork)
            } else {
                // Create new episode
                let episode = PlexMetadataMapper.createEpisode(
                    from: plexEpisode,
                    serverUUID: serverUUID,
                    artwork: artwork
                )
                show.episodes.append(episode)
            }

            syncedEpisodeKeys.insert(plexEpisode.ratingKey)
        }

        // Remove episodes no longer in Plex
        show.episodes.removeAll { episode in
            guard let key = episode.plexRatingKey else { return false }
            return !syncedEpisodeKeys.contains(key)
        }
    }

    // MARK: - Cleanup

    private func cleanupRemovedItems(
        syncedMovieKeys: Set<String>,
        syncedShowKeys: Set<String>,
        serverUUID: String,
        context: ModelContext
    ) async throws {
        // Remove movies that are no longer in Plex
        let movieDescriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.plexServerUUID == serverUUID }
        )
        let movies = try context.fetch(movieDescriptor)

        for movie in movies {
            if let key = movie.plexRatingKey, !syncedMovieKeys.contains(key) {
                context.delete(movie)
            }
        }

        // Remove TV shows that are no longer in Plex
        let showDescriptor = FetchDescriptor<TvShow>(
            predicate: #Predicate { $0.plexServerUUID == serverUUID }
        )
        let shows = try context.fetch(showDescriptor)

        for show in shows {
            if let key = show.plexRatingKey, !syncedShowKeys.contains(key) {
                context.delete(show)
            }
        }
    }

    // MARK: - Helpers

    private func getSelectedLibraryIDs() -> Set<String> {
        guard let array = UserDefaults.standard.array(forKey: PreferenceKeys.plexSelectedLibraries) as? [String] else {
            return []
        }
        return Set(array)
    }

    private func findExistingMovie(ratingKey: String, context: ModelContext) throws -> Movie? {
        let descriptor = FetchDescriptor<Movie>(
            predicate: #Predicate { $0.plexRatingKey == ratingKey }
        )
        return try context.fetch(descriptor).first
    }

    private func findExistingTvShow(ratingKey: String, context: ModelContext) throws -> TvShow? {
        let descriptor = FetchDescriptor<TvShow>(
            predicate: #Predicate { $0.plexRatingKey == ratingKey }
        )
        return try context.fetch(descriptor).first
    }
}

// MARK: - Sync State

enum PlexSyncState: Equatable {
    case idle
    case syncing
    case completed
    case error
}

// MARK: - Sync Errors

enum PlexSyncError: LocalizedError {
    case noModelContext
    case noLibrariesSelected
    case syncFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noModelContext:
            return "Database not initialized"
        case .noLibrariesSelected:
            return "No libraries selected for sync"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        }
    }
}
