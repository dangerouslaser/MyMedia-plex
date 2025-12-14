//
//  PlexAPIService.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation

/// Core Plex API client for making authenticated requests
actor PlexAPIService {
    static let shared = PlexAPIService()

    private let session: URLSession
    private let tokenManager: PlexTokenManager
    private let decoder: JSONDecoder

    /// The currently selected server base URL
    private(set) var serverURL: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        self.tokenManager = PlexTokenManager.shared
        self.decoder = JSONDecoder()
    }

    // MARK: - Configuration

    /// Sets the current server URL
    func setServerURL(_ url: String) {
        serverURL = url
        UserDefaults.standard.set(url, forKey: PreferenceKeys.plexServerURL)
    }

    /// Loads the server URL from UserDefaults
    func loadServerURL() {
        serverURL = UserDefaults.standard.string(forKey: PreferenceKeys.plexServerURL)
    }

    /// Client identifier for this app instance
    var clientIdentifier: String {
        tokenManager.getOrCreateClientIdentifier()
    }

    /// Current auth token (if authenticated)
    var authToken: String? {
        tokenManager.retrieveAuthToken()
    }

    // MARK: - Generic Request Methods

    /// Makes an authenticated GET request and decodes the response
    func get<T: Decodable>(_ url: String, requiresAuth: Bool = true) async throws -> T {
        guard let requestURL = URL(string: url) else {
            throw PlexAPIError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        let token = requiresAuth ? authToken : nil
        if requiresAuth && token == nil {
            throw PlexAPIError.notAuthenticated
        }

        let headers = PlexHeaders.standard(token: token, clientIdentifier: clientIdentifier)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw PlexAPIError.unauthorized
            }
            throw PlexAPIError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PlexAPIError.decodingError(underlying: error)
        }
    }

    /// Makes an authenticated GET request without expecting a response body
    func getVoid(_ url: String) async throws {
        guard let requestURL = URL(string: url) else {
            throw PlexAPIError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"

        guard let token = authToken else {
            throw PlexAPIError.notAuthenticated
        }

        let headers = PlexHeaders.standard(token: token, clientIdentifier: clientIdentifier)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw PlexAPIError.unauthorized
            }
            throw PlexAPIError.serverError(statusCode: httpResponse.statusCode)
        }
    }

    /// Makes a POST request with form data
    func post<T: Decodable>(_ url: String, body: [String: String]? = nil, requiresAuth: Bool = false) async throws -> T {
        guard let requestURL = URL(string: url) else {
            throw PlexAPIError.invalidURL(url)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"

        let token = requiresAuth ? authToken : nil
        let headers = PlexHeaders.forPinRequest(clientIdentifier: clientIdentifier)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if let token = token {
            request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        }

        if let body = body {
            let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = bodyString.data(using: .utf8)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw PlexAPIError.serverError(statusCode: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PlexAPIError.decodingError(underlying: error)
        }
    }

    // MARK: - Library Operations

    /// Fetches all library sections from the current server
    func fetchLibrarySections() async throws -> [PlexLibrarySection] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.sections(baseURL: baseURL)
        let response: PlexSectionsResponse = try await get(url)
        return response.mediaContainer.directory ?? []
    }

    /// Fetches all movies from a library section
    func fetchMovies(sectionID: Int) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.sectionContent(baseURL: baseURL, sectionID: sectionID)
        let response: PlexLibraryContentResponse = try await get(url)
        return response.mediaContainer.metadata ?? []
    }

    /// Fetches all TV shows from a library section
    func fetchTVShows(sectionID: Int) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.sectionContent(baseURL: baseURL, sectionID: sectionID)
        let response: PlexLibraryContentResponse = try await get(url)
        return response.mediaContainer.metadata ?? []
    }

    /// Fetches detailed metadata for an item
    func fetchMetadata(ratingKey: String) async throws -> PlexMetadataItem {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.metadata(baseURL: baseURL, ratingKey: ratingKey)
        let response: PlexLibraryContentResponse = try await get(url)

        guard let item = response.mediaContainer.metadata?.first else {
            throw PlexAPIError.itemNotFound(ratingKey: ratingKey)
        }

        return item
    }

    /// Fetches seasons for a TV show
    func fetchSeasons(showRatingKey: String) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.children(baseURL: baseURL, ratingKey: showRatingKey)
        let response: PlexChildrenResponse = try await get(url)
        return response.mediaContainer.metadata?.filter { $0.isSeason } ?? []
    }

    /// Fetches episodes for a season
    func fetchEpisodes(seasonRatingKey: String) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.children(baseURL: baseURL, ratingKey: seasonRatingKey)
        let response: PlexChildrenResponse = try await get(url)
        return response.mediaContainer.metadata?.filter { $0.isEpisode } ?? []
    }

    /// Fetches all episodes for a TV show (flattened across all seasons)
    func fetchAllEpisodes(showRatingKey: String) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.allLeaves(baseURL: baseURL, ratingKey: showRatingKey)
        let response: PlexChildrenResponse = try await get(url)
        return response.mediaContainer.metadata ?? []
    }

    /// Fetches recently added items from a library section
    func fetchRecentlyAdded(sectionID: Int, limit: Int = 50) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.recentlyAdded(baseURL: baseURL, sectionID: sectionID, limit: limit)
        let response: PlexLibraryContentResponse = try await get(url)
        return response.mediaContainer.metadata ?? []
    }

    /// Fetches on deck items (continue watching)
    func fetchOnDeck(limit: Int = 50) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.onDeck(baseURL: baseURL, limit: limit)
        let response: PlexLibraryContentResponse = try await get(url)
        return response.mediaContainer.metadata ?? []
    }

    /// Fetches unwatched items from a library section
    func fetchUnwatched(sectionID: Int, limit: Int = 100) async throws -> [PlexMetadataItem] {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.unwatched(baseURL: baseURL, sectionID: sectionID, limit: limit)
        let response: PlexLibraryContentResponse = try await get(url)
        return response.mediaContainer.metadata ?? []
    }

    // MARK: - Watch Status

    /// Marks an item as watched
    func markWatched(ratingKey: String) async throws {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.scrobble(baseURL: baseURL, ratingKey: ratingKey)
        try await getVoid(url)
    }

    /// Marks an item as unwatched
    func markUnwatched(ratingKey: String) async throws {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.unscrobble(baseURL: baseURL, ratingKey: ratingKey)
        try await getVoid(url)
    }

    /// Updates playback progress
    func updateProgress(ratingKey: String, timeMs: Int, durationMs: Int, state: PlaybackState = .playing) async throws {
        guard let baseURL = serverURL else {
            throw PlexAPIError.noServerConfigured
        }

        let url = PlexEndpoints.timeline(baseURL: baseURL, ratingKey: ratingKey, state: state, timeMs: timeMs, durationMs: durationMs)
        try await getVoid(url)
    }

    // MARK: - Images

    /// Downloads image data from Plex
    func downloadImage(path: String) async throws -> Data {
        guard let baseURL = serverURL, let token = authToken else {
            throw PlexAPIError.notAuthenticated
        }

        guard let url = PlexEndpoints.imageURL(baseURL: baseURL, imagePath: path, token: token) else {
            throw PlexAPIError.invalidURL(path)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexAPIError.imageDownloadFailed
        }

        return data
    }

    /// Constructs a streaming URL for a media part
    func streamingURL(partKey: String) -> URL? {
        guard let baseURL = serverURL, let token = authToken else {
            return nil
        }
        return PlexEndpoints.streamingURL(baseURL: baseURL, partKey: partKey, token: token)
    }

    /// Constructs an authenticated image URL for use with AsyncImage
    func imageURL(path: String?) -> URL? {
        guard let path = path, !path.isEmpty,
              let baseURL = serverURL,
              let token = authToken else {
            return nil
        }
        return PlexEndpoints.imageURL(baseURL: baseURL, imagePath: path, token: token)
    }

    /// Returns configuration needed to construct image URLs (for use in views)
    var imageURLConfig: PlexImageURLConfig? {
        guard let baseURL = serverURL, let token = authToken else {
            return nil
        }
        return PlexImageURLConfig(baseURL: baseURL, token: token)
    }

    // MARK: - Server Connection Testing

    /// Tests connection to a server
    func testConnection(serverURL: String) async throws -> Bool {
        let url = PlexEndpoints.sections(baseURL: serverURL)
        let _: PlexSectionsResponse = try await get(url)
        return true
    }
}

// MARK: - Errors

enum PlexAPIError: LocalizedError {
    case invalidURL(String)
    case notAuthenticated
    case unauthorized
    case noServerConfigured
    case invalidResponse
    case serverError(statusCode: Int)
    case decodingError(underlying: Error)
    case itemNotFound(ratingKey: String)
    case imageDownloadFailed
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .notAuthenticated:
            return "Not authenticated. Please sign in to Plex."
        case .unauthorized:
            return "Authentication expired. Please sign in again."
        case .noServerConfigured:
            return "No Plex server configured."
        case .invalidResponse:
            return "Invalid response from server."
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .itemNotFound(let ratingKey):
            return "Item not found: \(ratingKey)"
        case .imageDownloadFailed:
            return "Failed to download image."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
