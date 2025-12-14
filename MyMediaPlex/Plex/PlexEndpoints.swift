//
//  PlexEndpoints.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation

/// Defines all Plex API endpoints and URL construction helpers
enum PlexEndpoints {

    // MARK: - plex.tv Authentication Endpoints

    /// Base URL for plex.tv API
    static let plexTVBase = "https://plex.tv"

    /// Request a new PIN for user authorization
    /// POST https://plex.tv/api/v2/pins
    static let pins = "\(plexTVBase)/api/v2/pins"

    /// Poll for PIN authorization status
    /// GET https://plex.tv/api/v2/pins/{id}
    static func pinStatus(id: Int) -> String {
        return "\(plexTVBase)/api/v2/pins/\(id)"
    }

    /// Get user's available resources (servers)
    /// GET https://plex.tv/api/v2/resources
    static let resources = "\(plexTVBase)/api/v2/resources"

    /// Get authenticated user info
    /// GET https://plex.tv/api/v2/user
    static let user = "\(plexTVBase)/api/v2/user"

    /// URL where users enter their PIN code
    static let linkURL = "https://plex.tv/link"

    // MARK: - Server Library Endpoints

    /// Get all library sections
    /// GET {baseURL}/library/sections
    static func sections(baseURL: String) -> String {
        return "\(baseURL)/library/sections"
    }

    /// Get contents of a library section (movies or shows)
    /// GET {baseURL}/library/sections/{sectionID}/all
    static func sectionContent(baseURL: String, sectionID: Int) -> String {
        return "\(baseURL)/library/sections/\(sectionID)/all"
    }

    /// Get detailed metadata for an item
    /// GET {baseURL}/library/metadata/{ratingKey}
    static func metadata(baseURL: String, ratingKey: String) -> String {
        return "\(baseURL)/library/metadata/\(ratingKey)"
    }

    /// Get children of an item (seasons for show, episodes for season)
    /// GET {baseURL}/library/metadata/{ratingKey}/children
    static func children(baseURL: String, ratingKey: String) -> String {
        return "\(baseURL)/library/metadata/\(ratingKey)/children"
    }

    /// Get all episodes for a TV show (flattened)
    /// GET {baseURL}/library/metadata/{ratingKey}/allLeaves
    static func allLeaves(baseURL: String, ratingKey: String) -> String {
        return "\(baseURL)/library/metadata/\(ratingKey)/allLeaves"
    }

    // MARK: - Watch Status Endpoints

    /// Mark item as watched (scrobble)
    /// GET {baseURL}/:/scrobble?key={ratingKey}&identifier=com.plexapp.plugins.library
    static func scrobble(baseURL: String, ratingKey: String) -> String {
        return "\(baseURL)/:/scrobble?key=\(ratingKey)&identifier=com.plexapp.plugins.library"
    }

    /// Mark item as unwatched (unscrobble)
    /// GET {baseURL}/:/unscrobble?key={ratingKey}&identifier=com.plexapp.plugins.library
    static func unscrobble(baseURL: String, ratingKey: String) -> String {
        return "\(baseURL)/:/unscrobble?key=\(ratingKey)&identifier=com.plexapp.plugins.library"
    }

    /// Update playback timeline/progress
    /// GET {baseURL}/:/timeline?ratingKey={ratingKey}&key=/library/metadata/{ratingKey}&state={state}&time={timeMs}&duration={durationMs}
    static func timeline(baseURL: String, ratingKey: String, state: PlaybackState, timeMs: Int, durationMs: Int) -> String {
        let stateString = state.rawValue
        return "\(baseURL)/:/timeline?ratingKey=\(ratingKey)&key=/library/metadata/\(ratingKey)&state=\(stateString)&time=\(timeMs)&duration=\(durationMs)"
    }

    // MARK: - Streaming/Transcode Endpoints

    /// Get the streaming URL for a media part
    /// {baseURL}{partKey}?X-Plex-Token={token}
    static func streamingURL(baseURL: String, partKey: String, token: String) -> URL? {
        var components = URLComponents(string: baseURL)
        components?.path = partKey
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        return components?.url
    }

    // MARK: - Image Endpoints

    /// Get image URL (thumb, art, etc.)
    /// {baseURL}{imagePath}?X-Plex-Token={token}
    static func imageURL(baseURL: String, imagePath: String, token: String) -> URL? {
        guard !imagePath.isEmpty else { return nil }
        var components = URLComponents(string: baseURL)
        components?.path = imagePath
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        return components?.url
    }
}

// MARK: - Supporting Types

enum PlaybackState: String {
    case playing = "playing"
    case paused = "paused"
    case stopped = "stopped"
    case buffering = "buffering"
}

// MARK: - Standard Plex Headers

struct PlexHeaders {
    /// Standard headers required for all Plex API requests
    static func standard(token: String?, clientIdentifier: String) -> [String: String] {
        var headers: [String: String] = [
            "Accept": "application/json",
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": "MyMediaPlex",
            "X-Plex-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "X-Plex-Platform": "macOS",
            "X-Plex-Platform-Version": ProcessInfo.processInfo.operatingSystemVersionString,
            "X-Plex-Device": "Mac",
            "X-Plex-Device-Name": Host.current().localizedName ?? "Mac"
        ]

        if let token = token {
            headers["X-Plex-Token"] = token
        }

        return headers
    }

    /// Headers specifically for PIN requests (no token needed)
    static func forPinRequest(clientIdentifier: String) -> [String: String] {
        var headers = standard(token: nil, clientIdentifier: clientIdentifier)
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        return headers
    }
}
