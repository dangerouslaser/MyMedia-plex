//
//  PlexMetadataMapper.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation

/// Maps Plex API metadata to SwiftData models
struct PlexMetadataMapper {

    // MARK: - Movie Mapping

    /// Creates a new Movie from Plex metadata
    static func createMovie(
        from plex: PlexMetadataItem,
        serverUUID: String,
        sectionID: Int,
        artwork: Data?
    ) -> Movie {
        let movie = Movie(
            artwork: artwork,
            title: plex.title,
            genre: plex.genreNames,
            durationMinutes: plex.durationMinutes,
            releaseDate: plex.releaseDate ?? Date(),
            shortDescription: plex.summary,
            longDescription: plex.summary,
            cast: plex.castNames,
            producers: plex.producerNames,
            executiveProducers: [],
            directors: plex.directorNames,
            coDirectors: [],
            screenwriters: plex.writerNames,
            composer: nil,
            studio: plex.studio,
            hdVideoQuality: plex.media?.first?.hdVideoQuality,
            rating: plex.contentRating,
            languages: extractLanguages(from: plex)
        )

        // Set Plex properties
        movie.plexRatingKey = plex.ratingKey
        movie.plexServerUUID = serverUUID
        movie.plexLibrarySectionID = sectionID
        movie.streamingURL = plex.streamingPartKey
        movie.plexLastSyncedAt = Date()

        // Set watch status from Plex
        movie.isWatched = plex.isWatched
        movie.progressMinutes = plex.progressMinutes

        return movie
    }

    /// Updates an existing Movie with Plex metadata
    static func updateMovie(
        _ movie: Movie,
        from plex: PlexMetadataItem,
        artwork: Data?
    ) {
        movie.title = plex.title
        movie.genre = plex.genreNames
        movie.durationMinutes = plex.durationMinutes
        movie.releaseDate = plex.releaseDate ?? movie.releaseDate
        movie.shortDescription = plex.summary
        movie.longDescription = plex.summary
        movie.cast = plex.castNames
        movie.producers = plex.producerNames
        movie.directors = plex.directorNames
        movie.screenwriters = plex.writerNames
        movie.studio = plex.studio
        movie.hdVideoQuality = plex.media?.first?.hdVideoQuality
        movie.rating = plex.contentRating
        movie.languages = extractLanguages(from: plex)

        if let artwork = artwork {
            movie.artwork = artwork
        }

        movie.streamingURL = plex.streamingPartKey
        movie.plexLastSyncedAt = Date()

        // Only update watch status if Plex shows watched and local doesn't
        // This prevents overwriting local "mark as watched" before sync
        if plex.isWatched && !movie.isWatched {
            movie.isWatched = true
        }
        if plex.progressMinutes > movie.progressMinutes {
            movie.progressMinutes = plex.progressMinutes
        }
    }

    // MARK: - TV Show Mapping

    /// Creates a new TvShow from Plex metadata
    static func createTvShow(
        from plex: PlexMetadataItem,
        serverUUID: String,
        sectionID: Int,
        artwork: Data?
    ) -> TvShow {
        let show = TvShow(
            title: plex.title,
            year: plex.year ?? Calendar.current.component(.year, from: Date()),
            genre: plex.genreNames,
            showDescription: plex.summary,
            episodes: [],
            artwork: artwork
        )

        // Set Plex properties
        show.plexRatingKey = plex.ratingKey
        show.plexServerUUID = serverUUID
        show.plexLibrarySectionID = sectionID
        show.plexLastSyncedAt = Date()

        return show
    }

    /// Updates an existing TvShow with Plex metadata
    static func updateTvShow(
        _ show: TvShow,
        from plex: PlexMetadataItem,
        artwork: Data?
    ) {
        show.title = plex.title
        show.year = plex.year ?? show.year
        show.genre = plex.genreNames
        show.showDescription = plex.summary

        if let artwork = artwork {
            show.artwork = artwork
        }

        show.plexLastSyncedAt = Date()
    }

    // MARK: - Episode Mapping

    /// Creates a new Episode from Plex metadata
    static func createEpisode(
        from plex: PlexMetadataItem,
        serverUUID: String,
        artwork: Data?
    ) -> Episode {
        let episode = Episode(
            artwork: artwork,
            season: plex.parentIndex ?? 1,
            episode: plex.index ?? 1,
            title: plex.title,
            durationMinutes: plex.durationMinutes,
            releaseDate: plex.releaseDate ?? Date(),
            episodeShortDescription: plex.summary,
            episodeLongDescription: plex.summary,
            cast: plex.castNames,
            producers: plex.producerNames,
            executiveProducers: [],
            directors: plex.directorNames,
            coDirectors: [],
            screenwriters: plex.writerNames,
            composer: nil,
            studio: plex.studio,
            network: nil,
            rating: plex.contentRating,
            languages: extractLanguages(from: plex)
        )

        // Set Plex properties
        episode.plexRatingKey = plex.ratingKey
        episode.plexServerUUID = serverUUID
        episode.streamingURL = plex.streamingPartKey
        episode.plexLastSyncedAt = Date()

        // Set watch status from Plex
        episode.isWatched = plex.isWatched
        episode.progressMinutes = plex.progressMinutes

        return episode
    }

    /// Updates an existing Episode with Plex metadata
    static func updateEpisode(
        _ episode: Episode,
        from plex: PlexMetadataItem,
        artwork: Data?
    ) {
        episode.season = plex.parentIndex ?? episode.season
        episode.episode = plex.index ?? episode.episode
        episode.title = plex.title
        episode.durationMinutes = plex.durationMinutes
        episode.releaseDate = plex.releaseDate ?? episode.releaseDate
        episode.episodeShortDescription = plex.summary
        episode.episodeLongDescription = plex.summary
        episode.cast = plex.castNames
        episode.producers = plex.producerNames
        episode.directors = plex.directorNames
        episode.screenwriters = plex.writerNames
        episode.studio = plex.studio
        episode.rating = plex.contentRating
        episode.languages = extractLanguages(from: plex)

        if let artwork = artwork {
            episode.artwork = artwork
        }

        episode.streamingURL = plex.streamingPartKey
        episode.plexLastSyncedAt = Date()

        // Only update watch status if Plex shows watched and local doesn't
        if plex.isWatched && !episode.isWatched {
            episode.isWatched = true
        }
        if plex.progressMinutes > episode.progressMinutes {
            episode.progressMinutes = plex.progressMinutes
        }
    }

    // MARK: - Helpers

    /// Extracts language codes from Plex media streams
    private static func extractLanguages(from plex: PlexMetadataItem) -> [String] {
        guard let media = plex.media?.first,
              let part = media.part?.first,
              let streams = part.stream else {
            return []
        }

        return streams
            .filter { $0.isAudio }
            .compactMap { $0.languageCode }
    }
}
