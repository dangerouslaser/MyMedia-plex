//
//  PlexViewModels.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation
import SwiftUI

// MARK: - Library View Model

/// Observable view model for browsing Plex libraries
@Observable
@MainActor
class PlexLibraryViewModel {
    // State
    var libraries: [PlexLibrarySection] = []
    var selectedLibraryID: String?
    var items: [PlexMetadataItem] = []
    var isLoading = false
    var error: String?
    var imageConfig: PlexImageURLConfig?

    // Filters
    var showUnwatchedOnly = false
    var selectedGenre: String?

    // Computed
    var filteredItems: [PlexMetadataItem] {
        var result = items
        if showUnwatchedOnly {
            result = result.filter { !$0.isWatched }
        }
        if let genre = selectedGenre {
            result = result.filter { $0.genreNames.contains(genre) }
        }
        return result
    }

    var allGenres: [String] {
        let genres = items.flatMap { $0.genreNames }
        return Array(Set(genres)).sorted()
    }

    var movieLibraries: [PlexLibrarySection] {
        libraries.filter { $0.isMovieLibrary }
    }

    var tvShowLibraries: [PlexLibrarySection] {
        libraries.filter { $0.isTVShowLibrary }
    }

    // MARK: - Loading

    func loadLibraries() async {
        isLoading = true
        error = nil

        do {
            libraries = try await PlexAPIService.shared.fetchLibrarySections()
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadItems(for library: PlexLibrarySection) async {
        guard let sectionID = Int(library.key) else { return }

        isLoading = true
        error = nil
        selectedLibraryID = library.id

        do {
            if library.isMovieLibrary {
                items = try await PlexAPIService.shared.fetchMovies(sectionID: sectionID)
            } else if library.isTVShowLibrary {
                items = try await PlexAPIService.shared.fetchTVShows(sectionID: sectionID)
            }
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
            items = []
        }

        isLoading = false
    }

    func loadRecentlyAdded(for library: PlexLibrarySection, limit: Int = 20) async {
        guard let sectionID = Int(library.key) else { return }

        isLoading = true
        error = nil

        do {
            items = try await PlexAPIService.shared.fetchRecentlyAdded(sectionID: sectionID, limit: limit)
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
            items = []
        }

        isLoading = false
    }

    func loadOnDeck(limit: Int = 20) async {
        isLoading = true
        error = nil

        do {
            items = try await PlexAPIService.shared.fetchOnDeck(limit: limit)
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
            items = []
        }

        isLoading = false
    }

    func loadUnwatched(for library: PlexLibrarySection, limit: Int = 100) async {
        guard let sectionID = Int(library.key) else { return }

        isLoading = true
        error = nil

        do {
            items = try await PlexAPIService.shared.fetchUnwatched(sectionID: sectionID, limit: limit)
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
            items = []
        }

        isLoading = false
    }

    // MARK: - Actions

    func toggleWatched(_ item: PlexMetadataItem) async {
        do {
            if item.isWatched {
                try await PlexAPIService.shared.markUnwatched(ratingKey: item.ratingKey)
            } else {
                try await PlexAPIService.shared.markWatched(ratingKey: item.ratingKey)
            }
            // Refresh the item in the list
            if let index = items.firstIndex(where: { $0.ratingKey == item.ratingKey }) {
                items[index] = try await PlexAPIService.shared.fetchMetadata(ratingKey: item.ratingKey)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        if let libraryID = selectedLibraryID,
           let library = libraries.first(where: { $0.id == libraryID }) {
            await loadItems(for: library)
        }
    }
}

// MARK: - Movie Detail View Model

/// Observable view model for movie details
@Observable
@MainActor
class PlexMovieDetailViewModel {
    var movie: PlexMetadataItem?
    var isLoading = false
    var error: String?
    var imageConfig: PlexImageURLConfig?

    func load(ratingKey: String) async {
        isLoading = true
        error = nil

        do {
            movie = try await PlexAPIService.shared.fetchMetadata(ratingKey: ratingKey)
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func toggleWatched() async {
        guard let movie = movie else { return }

        do {
            if movie.isWatched {
                try await PlexAPIService.shared.markUnwatched(ratingKey: movie.ratingKey)
            } else {
                try await PlexAPIService.shared.markWatched(ratingKey: movie.ratingKey)
            }
            // Refresh
            self.movie = try await PlexAPIService.shared.fetchMetadata(ratingKey: movie.ratingKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    var streamingURL: URL? {
        imageConfig?.streamingURL(partKey: movie?.streamingPartKey)
    }
}

// MARK: - Show Detail View Model

/// Observable view model for TV show details
@Observable
@MainActor
class PlexShowDetailViewModel {
    var show: PlexMetadataItem?
    var seasons: [PlexMetadataItem] = []
    var episodes: [String: [PlexMetadataItem]] = [:] // seasonRatingKey -> episodes
    var isLoading = false
    var error: String?
    var imageConfig: PlexImageURLConfig?

    func load(ratingKey: String) async {
        isLoading = true
        error = nil

        do {
            show = try await PlexAPIService.shared.fetchMetadata(ratingKey: ratingKey)
            seasons = try await PlexAPIService.shared.fetchSeasons(showRatingKey: ratingKey)
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadEpisodes(for season: PlexMetadataItem) async {
        guard episodes[season.ratingKey] == nil else { return } // Already loaded

        do {
            let seasonEpisodes = try await PlexAPIService.shared.fetchEpisodes(seasonRatingKey: season.ratingKey)
            episodes[season.ratingKey] = seasonEpisodes
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadAllEpisodes() async {
        guard let showKey = show?.ratingKey else { return }

        do {
            let allEpisodes = try await PlexAPIService.shared.fetchAllEpisodes(showRatingKey: showKey)
            // Group by season
            for episode in allEpisodes {
                if let seasonKey = episode.parentRatingKey {
                    if episodes[seasonKey] == nil {
                        episodes[seasonKey] = []
                    }
                    if !episodes[seasonKey]!.contains(where: { $0.ratingKey == episode.ratingKey }) {
                        episodes[seasonKey]!.append(episode)
                    }
                }
            }
            // Sort episodes by index
            for key in episodes.keys {
                episodes[key]?.sort { ($0.index ?? 0) < ($1.index ?? 0) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    var nextUnwatchedEpisode: PlexMetadataItem? {
        for season in seasons.sorted(by: { ($0.index ?? 0) < ($1.index ?? 0) }) {
            if let seasonEpisodes = episodes[season.ratingKey] {
                if let unwatched = seasonEpisodes.first(where: { !$0.isWatched }) {
                    return unwatched
                }
            }
        }
        return nil
    }

    func toggleSeasonWatched(_ season: PlexMetadataItem) async {
        guard let seasonEpisodes = episodes[season.ratingKey] else { return }

        let allWatched = seasonEpisodes.allSatisfy { $0.isWatched }

        do {
            for episode in seasonEpisodes {
                if allWatched {
                    try await PlexAPIService.shared.markUnwatched(ratingKey: episode.ratingKey)
                } else {
                    try await PlexAPIService.shared.markWatched(ratingKey: episode.ratingKey)
                }
            }
            // Refresh episodes for this season
            await loadEpisodes(for: season)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Episode Detail View Model

/// Observable view model for episode details
@Observable
@MainActor
class PlexEpisodeDetailViewModel {
    var episode: PlexMetadataItem?
    var isLoading = false
    var error: String?
    var imageConfig: PlexImageURLConfig?

    func load(ratingKey: String) async {
        isLoading = true
        error = nil

        do {
            episode = try await PlexAPIService.shared.fetchMetadata(ratingKey: ratingKey)
            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func toggleWatched() async {
        guard let episode = episode else { return }

        do {
            if episode.isWatched {
                try await PlexAPIService.shared.markUnwatched(ratingKey: episode.ratingKey)
            } else {
                try await PlexAPIService.shared.markWatched(ratingKey: episode.ratingKey)
            }
            // Refresh
            self.episode = try await PlexAPIService.shared.fetchMetadata(ratingKey: episode.ratingKey)
        } catch {
            self.error = error.localizedDescription
        }
    }

    var streamingURL: URL? {
        imageConfig?.streamingURL(partKey: episode?.streamingPartKey)
    }
}

// MARK: - Home View Model

/// Observable view model for the home/dashboard view
@Observable
@MainActor
class PlexHomeViewModel {
    var onDeck: [PlexMetadataItem] = []
    var recentlyAddedMovies: [PlexMetadataItem] = []
    var recentlyAddedShows: [PlexMetadataItem] = []
    var isLoading = false
    var error: String?
    var imageConfig: PlexImageURLConfig?

    private var movieLibraryIDs: [Int] = []
    private var showLibraryIDs: [Int] = []

    func load() async {
        isLoading = true
        error = nil

        do {
            // Get libraries first
            let libraries = try await PlexAPIService.shared.fetchLibrarySections()
            movieLibraryIDs = libraries.filter { $0.isMovieLibrary }.compactMap { Int($0.key) }
            showLibraryIDs = libraries.filter { $0.isTVShowLibrary }.compactMap { Int($0.key) }

            // Load on deck
            onDeck = try await PlexAPIService.shared.fetchOnDeck(limit: 10)

            // Load recently added from each library type
            for libraryID in movieLibraryIDs {
                let recent = try await PlexAPIService.shared.fetchRecentlyAdded(sectionID: libraryID, limit: 10)
                recentlyAddedMovies.append(contentsOf: recent)
            }

            for libraryID in showLibraryIDs {
                let recent = try await PlexAPIService.shared.fetchRecentlyAdded(sectionID: libraryID, limit: 10)
                recentlyAddedShows.append(contentsOf: recent)
            }

            imageConfig = await PlexAPIService.shared.imageURLConfig
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        recentlyAddedMovies = []
        recentlyAddedShows = []
        onDeck = []
        await load()
    }
}
