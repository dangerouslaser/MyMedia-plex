//
//  PlexShowDetailView.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import SwiftUI

/// Detail view for a Plex TV show
struct PlexShowDetailView: View {
    let ratingKey: String
    @State private var viewModel = PlexShowDetailViewModel()
    @State private var selectedSeason: PlexMetadataItem?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.show == nil {
                PlexLoadingView()
            } else if let error = viewModel.error, viewModel.show == nil {
                PlexErrorView(error: error) {
                    Task { await viewModel.load(ratingKey: ratingKey) }
                }
            } else if let show = viewModel.show {
                ScrollView {
                    showContent(show)
                }
            }
        }
        .navigationTitle(viewModel.show?.title ?? "TV Show")
        .toolbar {
            if let nextEpisode = viewModel.nextUnwatchedEpisode {
                ToolbarItem {
                    Button("Continue", systemImage: "play.fill") {
                        playEpisode(nextEpisode)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task {
            await viewModel.load(ratingKey: ratingKey)
            await viewModel.loadAllEpisodes()
            if let firstSeason = viewModel.seasons.first {
                selectedSeason = firstSeason
            }
        }
    }

    @ViewBuilder
    private func showContent(_ show: PlexMetadataItem) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with artwork and basic info
            HStack(alignment: .top, spacing: 24) {
                // Poster
                PlexArtworkView(
                    imageURL: viewModel.imageConfig?.url(for: show.thumb),
                    title: show.title,
                    scale: 1.5
                )

                // Details
                VStack(alignment: .leading, spacing: 12) {
                    Text(show.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    HStack(spacing: 16) {
                        if let year = show.year {
                            Text(String(year))
                        }
                        if let studio = show.studio {
                            Text(studio)
                        }
                        if let rating = show.contentRating {
                            Text(rating)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .foregroundStyle(.secondary)

                    // Progress
                    if let leafCount = show.leafCount, let viewedLeafCount = show.viewedLeafCount {
                        HStack(spacing: 8) {
                            Text("\(viewedLeafCount) of \(leafCount) episodes watched")
                            ProgressView(value: Double(viewedLeafCount), total: Double(leafCount))
                                .frame(width: 100)
                        }
                        .foregroundStyle(.secondary)
                    }

                    // Ratings
                    HStack(spacing: 16) {
                        if let rating = show.rating {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                            }
                        }
                        if let audienceRating = show.audienceRating {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                Text(String(format: "%.1f", audienceRating))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Genres
                    if !show.genreNames.isEmpty {
                        PlexGenresRow(genres: show.genreNames)
                    }

                    Spacer()

                    // Continue watching button
                    if let nextEpisode = viewModel.nextUnwatchedEpisode {
                        Button {
                            playEpisode(nextEpisode)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Continue Watching", systemImage: "play.fill")
                                Text("S\(nextEpisode.parentIndex ?? 0)E\(nextEpisode.index ?? 0) - \(nextEpisode.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .padding()

            // Summary
            if let summary = show.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text(summary)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            // Seasons
            if !viewModel.seasons.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Seasons")
                        .font(.headline)
                        .padding(.horizontal)

                    // Season picker
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.seasons, id: \.ratingKey) { season in
                                Button {
                                    selectedSeason = season
                                    Task {
                                        await viewModel.loadEpisodes(for: season)
                                    }
                                } label: {
                                    Text(season.title)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedSeason?.ratingKey == season.ratingKey ?
                                                    Color.accentColor : Color.secondary.opacity(0.2))
                                        .foregroundStyle(selectedSeason?.ratingKey == season.ratingKey ?
                                                         .white : .primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Episodes for selected season
                    if let season = selectedSeason,
                       let episodes = viewModel.episodes[season.ratingKey] {
                        episodesList(episodes)
                    } else if selectedSeason != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
        }
        .padding(.bottom)
    }

    @ViewBuilder
    private func episodesList(_ episodes: [PlexMetadataItem]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(episodes, id: \.ratingKey) { episode in
                PlexEpisodeRow(
                    episode: episode,
                    imageConfig: viewModel.imageConfig,
                    onPlay: { playEpisode(episode) },
                    onToggleWatched: {
                        Task {
                            do {
                                if episode.isWatched {
                                    try await PlexAPIService.shared.markUnwatched(ratingKey: episode.ratingKey)
                                } else {
                                    try await PlexAPIService.shared.markWatched(ratingKey: episode.ratingKey)
                                }
                                // Refresh episodes
                                if let season = selectedSeason {
                                    await viewModel.loadEpisodes(for: season)
                                }
                            } catch {
                                viewModel.error = error.localizedDescription
                            }
                        }
                    }
                )
                .padding(.horizontal)
                Divider()
            }
        }
    }

    private func playEpisode(_ episode: PlexMetadataItem) {
        guard let partKey = episode.streamingPartKey else { return }

        Task {
            guard let url = await PlexAPIService.shared.streamingURL(partKey: partKey) else { return }

            let playAction = PlayAction(
                ratingKey: episode.ratingKey,
                title: "\(episode.grandparentTitle ?? "") - \(episode.title)",
                streamingURL: url,
                durationMs: episode.duration ?? 0,
                resumePositionMs: episode.viewOffset ?? 0
            )
            openWindow(value: playAction)
        }
    }
}

// MARK: - Preview

#Preview {
    PlexShowDetailView(ratingKey: "12345")
}
