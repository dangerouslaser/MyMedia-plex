//
//  PlexImageLoader.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation
import AppKit

/// Handles downloading and processing artwork from Plex server
actor PlexImageLoader {
    static let shared = PlexImageLoader()

    private let apiService: PlexAPIService
    private var cache: [String: Data] = [:]

    private init() {
        self.apiService = PlexAPIService.shared
    }

    // MARK: - Public Methods

    /// Downloads artwork from Plex, optionally resizing it
    /// - Parameters:
    ///   - path: The Plex image path (e.g., "/library/metadata/123/thumb/456")
    ///   - resize: Whether to resize the image based on user preferences
    /// - Returns: Image data or nil if download fails
    func downloadArtwork(path: String?, resize: Bool = true) async -> Data? {
        guard let path = path, !path.isEmpty else {
            return nil
        }

        // Check cache first
        if let cached = cache[path] {
            return cached
        }

        do {
            var data = try await apiService.downloadImage(path: path)

            // Resize if enabled in preferences
            if resize && shouldDownsize {
                data = downsizeImage(data) ?? data
            }

            // Cache the result
            cache[path] = data

            return data
        } catch {
            return nil
        }
    }

    /// Clears the image cache
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private Methods

    private var shouldDownsize: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.downSizeArtwork)
    }

    private var maxWidth: Int {
        UserDefaults.standard.integer(forKey: PreferenceKeys.downSizeArtworkWidth)
    }

    private var maxHeight: Int {
        UserDefaults.standard.integer(forKey: PreferenceKeys.downSizeArtworkHeight)
    }

    /// Resizes image data to fit within max dimensions
    private func downsizeImage(_ data: Data) -> Data? {
        guard let image = NSImage(data: data) else {
            return nil
        }

        let maxW = maxWidth > 0 ? maxWidth : 1000
        let maxH = maxHeight > 0 ? maxHeight : 1000

        let originalSize = image.size

        // Calculate new size maintaining aspect ratio
        var newSize = originalSize

        if originalSize.width > CGFloat(maxW) || originalSize.height > CGFloat(maxH) {
            let widthRatio = CGFloat(maxW) / originalSize.width
            let heightRatio = CGFloat(maxH) / originalSize.height
            let ratio = min(widthRatio, heightRatio)

            newSize = CGSize(
                width: originalSize.width * ratio,
                height: originalSize.height * ratio
            )
        } else {
            // No need to resize
            return data
        }

        // Create resized image
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        // Convert to JPEG data with compression
        guard let tiffData = newImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.8]
              ) else {
            return data
        }

        return jpegData
    }
}
