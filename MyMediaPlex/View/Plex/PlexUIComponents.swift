//
//  PlexUIComponents.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import SwiftUI

// MARK: - Plex Artwork View

/// Displays artwork loaded from Plex server using AsyncImage
struct PlexArtworkView: View {
    let imageURL: URL?
    let title: String
    let subtitle: String
    let cornerRadius: CGFloat
    let size: CGSize

    init(imageURL: URL?, title: String, subtitle: String = "", scale: CGFloat = 1.0) {
        self.imageURL = imageURL
        self.title = title
        self.subtitle = subtitle
        self.cornerRadius = LayoutConstants.cornerRadius * scale
        self.size = CGSize(width: LayoutConstants.artworkWidth * scale, height: LayoutConstants.artworkHeight * scale)
    }

    var body: some View {
        if let imageURL = imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    placeholderView
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                case .success(let image):
                    imageView(image)
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
        } else {
            placeholderView
        }
    }

    private func imageView(_ image: Image) -> some View {
        let mainImage = image
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)

        let backgroundImage = image
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)

        return ZStack {
            if #available(macOS 26.0, *) {
                backgroundImage
                mainImage
                    .glassEffect(in: .rect(cornerRadius: cornerRadius, style: .continuous))
            } else {
                backgroundImage
                    .overlay(.ultraThinMaterial)
                mainImage
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholderView: some View {
        Color.accentColor
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay(alignment: .center) {
                VStack {
                    Text(title)
                        .font(.headline)
                        .bold()
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                    }
                }
                .padding(8)
            }
    }
}

// MARK: - Plex Media Card

/// Card view for displaying Plex media in a grid
struct PlexMediaCard: View {
    let item: PlexMetadataItem
    let imageConfig: PlexImageURLConfig?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    PlexArtworkView(
                        imageURL: imageConfig?.url(for: item.thumb),
                        title: item.title,
                        subtitle: item.year.map { String($0) } ?? ""
                    )

                    // Watch status badge
                    if item.isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(6)
                    } else if let progress = item.viewOffset, let duration = item.duration, duration > 0 {
                        // Progress indicator
                        ProgressCircle(progress: Double(progress) / Double(duration))
                            .frame(width: 24, height: 24)
                            .padding(6)
                    }
                }

                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                if let year = item.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plex Media Row

/// Row view for displaying Plex media in a list
struct PlexMediaRow: View {
    let item: PlexMetadataItem
    let imageConfig: PlexImageURLConfig?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Thumbnail
                PlexArtworkView(
                    imageURL: imageConfig?.url(for: item.thumb),
                    title: item.title,
                    scale: 0.5
                )

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)

                    if item.isEpisode {
                        if let showTitle = item.grandparentTitle {
                            Text(showTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("S\(item.parentIndex ?? 0)E\(item.index ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if let year = item.year {
                            Text(String(year))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let genres = item.genre?.prefix(3) {
                        Text(genres.map(\.tag).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Watch status
                if item.isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let progress = item.viewOffset, let duration = item.duration, duration > 0 {
                    ProgressCircle(progress: Double(progress) / Double(duration))
                        .frame(width: 20, height: 20)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plex Episode Row

/// Specialized row for TV show episodes
struct PlexEpisodeRow: View {
    let episode: PlexMetadataItem
    let imageConfig: PlexImageURLConfig?
    let onPlay: () -> Void
    let onToggleWatched: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Episode number
            Text("\(episode.index ?? 0)")
                .font(.title2)
                .fontWeight(.medium)
                .frame(width: 32)
                .foregroundStyle(.secondary)

            // Thumbnail
            if let thumbURL = imageConfig?.url(for: episode.thumb) {
                AsyncImage(url: thumbURL) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.2)
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.headline)

                HStack {
                    if episode.durationMinutes > 0 {
                        Text("\(episode.durationMinutes) min")
                    }
                    if let date = episode.originallyAvailableAt {
                        Text(date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let summary = episode.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Actions
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.bordered)

            Button(action: onToggleWatched) {
                Image(systemName: episode.isWatched ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Progress Circle

/// Circular progress indicator
struct ProgressCircle: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 3)

            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Plex Genre Badge

/// Badge displaying a genre
struct PlexGenreBadge: View {
    let genre: String

    var body: some View {
        Text(genre)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.2))
            .clipShape(Capsule())
    }
}

// MARK: - Plex Genres Row

/// Horizontal scrolling row of genre badges
struct PlexGenresRow: View {
    let genres: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    PlexGenreBadge(genre: genre)
                }
            }
        }
    }
}

// MARK: - Plex Credits View

/// Displays cast and crew information
struct PlexCreditsView: View {
    let directors: [String]
    let writers: [String]
    let cast: [PlexRole]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !directors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Director")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(directors.joined(separator: ", "))
                        .font(.subheadline)
                }
            }

            if !writers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Writers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(writers.joined(separator: ", "))
                        .font(.subheadline)
                }
            }

            if !cast.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cast")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(cast.prefix(5).map(\.tag).joined(separator: ", "))
                        .font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Plex Loading View

/// Loading state placeholder
struct PlexLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plex Error View

/// Error state with retry option
struct PlexErrorView: View {
    let error: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.headline)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plex Empty View

/// Empty state for lists with no content
struct PlexEmptyView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Plex Media Actions Menu

/// Context menu actions for Plex media items
struct PlexMediaActionsMenu: View {
    let item: PlexMetadataItem
    let onToggleWatched: () async -> Void
    let onPlay: (() -> Void)?

    var body: some View {
        Group {
            if let onPlay = onPlay {
                Button("Play", systemImage: "play.fill", action: onPlay)
            }

            Button(item.isWatched ? "Mark Unwatched" : "Mark Watched",
                   systemImage: item.isWatched ? "eye.slash" : "eye") {
                Task {
                    await onToggleWatched()
                }
            }

            Divider()

            if let webURL = plexWebURL(for: item) {
                Link(destination: webURL) {
                    Label("View on Plex Web", systemImage: "globe")
                }
            }
        }
    }

    private func plexWebURL(for item: PlexMetadataItem) -> URL? {
        guard let serverUUID = UserDefaults.standard.string(forKey: PreferenceKeys.plexServerUUID) else {
            return nil
        }
        return URL(string: "https://app.plex.tv/desktop/#!/server/\(serverUUID)/details?key=/library/metadata/\(item.ratingKey)")
    }
}
