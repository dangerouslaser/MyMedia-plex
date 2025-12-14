//
//  PlexModels.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation

// MARK: - Authentication Models

/// Response from PIN request
struct PlexPINResponse: Codable {
    let id: Int
    let code: String
    let expiresAt: String?
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case expiresAt
        case authToken
    }
}

/// User info response
struct PlexUser: Codable {
    let id: Int
    let uuid: String
    let email: String
    let username: String
    let title: String
    let thumb: String?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case email
        case username
        case title
        case thumb
    }
}

// MARK: - Resources (Servers)

/// Response wrapper for resources
struct PlexResourcesResponse: Codable {
    let resources: [PlexServer]

    init(from decoder: Decoder) throws {
        // The response is an array at the root level
        let container = try decoder.singleValueContainer()
        resources = try container.decode([PlexServer].self)
    }
}

/// A Plex server/resource
struct PlexServer: Codable, Identifiable {
    let name: String
    let product: String
    let productVersion: String
    let platform: String
    let clientIdentifier: String
    let owned: Bool
    let provides: String
    let connections: [PlexConnection]

    var id: String { clientIdentifier }

    /// Returns true if this is a Plex Media Server (not another client)
    var isMediaServer: Bool {
        provides.contains("server")
    }

    /// Best connection URL to use
    var bestConnectionURL: String? {
        // First, prefer local connections that are NOT Docker internal networks
        // Docker uses 172.17-31.x.x ranges which aren't reachable from host
        if let local = connections.first(where: { $0.local && !$0.relay && !$0.isDockerInternal }) {
            return local.uri
        }
        // Then try remote (non-relay) connections - these often work better
        if let remote = connections.first(where: { !$0.local && !$0.relay }) {
            return remote.uri
        }
        // Try any non-relay connection
        if let nonRelay = connections.first(where: { !$0.relay }) {
            return nonRelay.uri
        }
        // Fall back to relay as last resort
        return connections.first?.uri
    }

    /// Returns all connection URLs for testing
    var allConnectionURLs: [String] {
        connections.map { $0.uri }
    }
}

/// Connection info for a server
struct PlexConnection: Codable {
    let uri: String
    let local: Bool
    let relay: Bool
    let `protocol`: String?
    let address: String?
    let port: Int?

    enum CodingKeys: String, CodingKey {
        case uri
        case local
        case relay
        case `protocol`
        case address
        case port
    }

    /// Returns true if this is a Docker internal network address (172.17-31.x.x)
    /// These addresses are not reachable from the host machine
    var isDockerInternal: Bool {
        guard let address = address else { return false }
        // Docker typically uses 172.17.0.0/16 through 172.31.0.0/16
        if address.hasPrefix("172.") {
            let parts = address.split(separator: ".")
            if parts.count >= 2, let secondOctet = Int(parts[1]) {
                return secondOctet >= 17 && secondOctet <= 31
            }
        }
        return false
    }
}

// MARK: - Library Models

/// Wrapper for library sections response
struct PlexSectionsResponse: Codable {
    let mediaContainer: PlexMediaContainer<PlexLibrarySection>

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

/// Wrapper for library content response
struct PlexLibraryContentResponse: Codable {
    let mediaContainer: PlexLibraryMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

/// Generic media container wrapper
struct PlexMediaContainer<T: Codable>: Codable {
    let size: Int?
    let directory: [T]?

    enum CodingKeys: String, CodingKey {
        case size
        case directory = "Directory"
    }
}

/// Media container for library content (movies/shows)
struct PlexLibraryMediaContainer: Codable {
    let size: Int?
    let metadata: [PlexMetadataItem]?

    enum CodingKeys: String, CodingKey {
        case size
        case metadata = "Metadata"
    }
}

/// A library section (Movies, TV Shows, etc.)
struct PlexLibrarySection: Codable, Identifiable {
    let key: String
    let title: String
    let type: String
    let uuid: String
    let language: String?
    let agent: String?
    let scanner: String?

    var id: String { key }

    /// Returns true if this is a movie library
    var isMovieLibrary: Bool {
        type == "movie"
    }

    /// Returns true if this is a TV show library
    var isTVShowLibrary: Bool {
        type == "show"
    }
}

// MARK: - Media Item Models

/// A metadata item (can be movie, show, season, or episode)
struct PlexMetadataItem: Codable, Hashable, Identifiable {
    var id: String { ratingKey }
    let ratingKey: String
    let key: String
    let type: String
    let title: String
    let originalTitle: String?
    let summary: String?
    let year: Int?
    let duration: Int?  // milliseconds
    let originallyAvailableAt: String?  // "YYYY-MM-DD"
    let addedAt: Int?  // Unix timestamp
    let updatedAt: Int?  // Unix timestamp
    let studio: String?
    let contentRating: String?
    let rating: Double?
    let audienceRating: Double?

    // Images
    let thumb: String?
    let art: String?
    let banner: String?

    // Watch status
    let viewCount: Int?
    let viewOffset: Int?  // milliseconds - resume position
    let lastViewedAt: Int?  // Unix timestamp

    // TV-specific
    let index: Int?  // Episode/season number
    let parentIndex: Int?  // Season number (for episodes)
    let parentRatingKey: String?
    let parentTitle: String?
    let grandparentRatingKey: String?
    let grandparentTitle: String?
    let leafCount: Int?  // Total episodes
    let viewedLeafCount: Int?  // Watched episodes

    // Nested objects
    let genre: [PlexTag]?
    let director: [PlexTag]?
    let writer: [PlexTag]?
    let role: [PlexRole]?
    let producer: [PlexTag]?
    let country: [PlexTag]?
    let media: [PlexMedia]?

    enum CodingKeys: String, CodingKey {
        case ratingKey
        case key
        case type
        case title
        case originalTitle
        case summary
        case year
        case duration
        case originallyAvailableAt
        case addedAt
        case updatedAt
        case studio
        case contentRating
        case rating
        case audienceRating
        case thumb
        case art
        case banner
        case viewCount
        case viewOffset
        case lastViewedAt
        case index
        case parentIndex
        case parentRatingKey
        case parentTitle
        case grandparentRatingKey
        case grandparentTitle
        case leafCount
        case viewedLeafCount
        case genre = "Genre"
        case director = "Director"
        case writer = "Writer"
        case role = "Role"
        case producer = "Producer"
        case country = "Country"
        case media = "Media"
    }

    // MARK: - Computed Properties

    var isMovie: Bool { type == "movie" }
    var isTVShow: Bool { type == "show" }
    var isSeason: Bool { type == "season" }
    var isEpisode: Bool { type == "episode" }

    var isWatched: Bool {
        if isEpisode || isMovie {
            return (viewCount ?? 0) > 0
        }
        if isTVShow {
            return (viewedLeafCount ?? 0) == (leafCount ?? 0) && (leafCount ?? 0) > 0
        }
        return false
    }

    /// Duration in minutes
    var durationMinutes: Int {
        guard let duration = duration else { return 0 }
        return duration / 60000
    }

    /// Progress in minutes
    var progressMinutes: Int {
        guard let viewOffset = viewOffset else { return 0 }
        return viewOffset / 60000
    }

    /// Release date as Date object
    var releaseDate: Date? {
        guard let dateString = originallyAvailableAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    /// Date added as Date object
    var dateAdded: Date? {
        guard let addedAt = addedAt else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(addedAt))
    }

    /// Genre names as array
    var genreNames: [String] {
        genre?.map(\.tag) ?? []
    }

    /// Director names as array
    var directorNames: [String] {
        director?.map(\.tag) ?? []
    }

    /// Writer names as array
    var writerNames: [String] {
        writer?.map(\.tag) ?? []
    }

    /// Producer names as array
    var producerNames: [String] {
        producer?.map(\.tag) ?? []
    }

    /// Cast member names as array
    var castNames: [String] {
        role?.map(\.tag) ?? []
    }

    /// Best streaming URL part key
    var streamingPartKey: String? {
        media?.first?.part?.first?.key
    }
}

// MARK: - Supporting Types

/// Generic tag (genre, director, writer, etc.)
struct PlexTag: Codable, Hashable {
    let tag: String
}

/// Role/cast member with character name
struct PlexRole: Codable, Hashable {
    let tag: String
    let role: String?
    let thumb: String?
}

/// Media version info
struct PlexMedia: Codable, Hashable {
    let id: Int?
    let duration: Int?
    let videoResolution: String?
    let aspectRatio: Double?
    let audioChannels: Int?
    let audioCodec: String?
    let videoCodec: String?
    let container: String?
    let videoFrameRate: String?
    let part: [PlexPart]?

    enum CodingKeys: String, CodingKey {
        case id
        case duration
        case videoResolution
        case aspectRatio
        case audioChannels
        case audioCodec
        case videoCodec
        case container
        case videoFrameRate
        case part = "Part"
    }

    /// Video quality as app enum
    var hdVideoQuality: HDVideoQuality {
        guard let resolution = videoResolution else { return .sd }
        switch resolution.lowercased() {
        case "4k", "2160":
            return .uhd4k
        case "1080":
            return .hd1080p
        case "720":
            return .hd720p
        default:
            return .sd
        }
    }
}

/// Media file part
struct PlexPart: Codable, Hashable {
    let id: Int?
    let key: String
    let duration: Int?
    let file: String?
    let size: Int?
    let container: String?
    let stream: [PlexStream]?

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case duration
        case file
        case size
        case container
        case stream = "Stream"
    }
}

/// Stream info (video, audio, subtitle tracks)
struct PlexStream: Codable, Hashable {
    let id: Int?
    let streamType: Int  // 1=video, 2=audio, 3=subtitle
    let codec: String?
    let language: String?
    let languageCode: String?
    let displayTitle: String?
    let selected: Bool?

    var isVideo: Bool { streamType == 1 }
    var isAudio: Bool { streamType == 2 }
    var isSubtitle: Bool { streamType == 3 }
}

// MARK: - Children Response (seasons/episodes)

struct PlexChildrenResponse: Codable {
    let mediaContainer: PlexLibraryMediaContainer

    enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

// MARK: - Image URL Helper

/// Configuration for constructing authenticated image and streaming URLs
struct PlexImageURLConfig: Sendable {
    let baseURL: String
    let token: String

    /// Constructs an authenticated image URL for use with AsyncImage
    func url(for path: String?) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }
        return PlexEndpoints.imageURL(baseURL: baseURL, imagePath: path, token: token)
    }

    /// Constructs an authenticated streaming URL for video playback
    func streamingURL(partKey: String?) -> URL? {
        guard let partKey = partKey, !partKey.isEmpty else { return nil }
        return PlexEndpoints.streamingURL(baseURL: baseURL, partKey: partKey, token: token)
    }
}
