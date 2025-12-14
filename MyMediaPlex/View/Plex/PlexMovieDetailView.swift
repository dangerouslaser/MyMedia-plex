//
//  PlexMovieDetailView.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import SwiftUI

/// Detail view for a Plex movie
struct PlexMovieDetailView: View {
    let ratingKey: String
    @State private var viewModel = PlexMovieDetailViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.movie == nil {
                PlexLoadingView()
            } else if let error = viewModel.error, viewModel.movie == nil {
                PlexErrorView(error: error) {
                    Task { await viewModel.load(ratingKey: ratingKey) }
                }
            } else if let movie = viewModel.movie {
                ScrollView {
                    movieContent(movie)
                }
            }
        }
        .navigationTitle(viewModel.movie?.title ?? "Movie")
        .toolbar {
            if let movie = viewModel.movie {
                ToolbarItem {
                    Button(movie.isWatched ? "Mark Unwatched" : "Mark Watched",
                           systemImage: movie.isWatched ? "eye.slash" : "eye") {
                        Task { await viewModel.toggleWatched() }
                    }
                }

                ToolbarItem {
                    Button("Play", systemImage: "play.fill") {
                        playMovie(movie)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .task {
            await viewModel.load(ratingKey: ratingKey)
        }
    }

    @ViewBuilder
    private func movieContent(_ movie: PlexMetadataItem) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with artwork and basic info
            HStack(alignment: .top, spacing: 24) {
                // Poster
                PlexArtworkView(
                    imageURL: viewModel.imageConfig?.url(for: movie.thumb),
                    title: movie.title,
                    scale: 1.5
                )

                // Details
                VStack(alignment: .leading, spacing: 12) {
                    Text(movie.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    HStack(spacing: 16) {
                        if let year = movie.year {
                            Text(String(year))
                        }
                        if movie.durationMinutes > 0 {
                            Text("\(movie.durationMinutes) min")
                        }
                        if let rating = movie.contentRating {
                            Text(rating)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .foregroundStyle(.secondary)

                    // Ratings
                    HStack(spacing: 16) {
                        if let rating = movie.rating {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                            }
                        }
                        if let audienceRating = movie.audienceRating {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                Text(String(format: "%.1f", audienceRating))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    // Watch status
                    HStack(spacing: 8) {
                        if movie.isWatched {
                            Label("Watched", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if let progress = movie.progressMinutes, progress > 0 {
                            Label("\(progress) min watched", systemImage: "clock")
                                .foregroundStyle(.orange)
                        } else {
                            Label("Unwatched", systemImage: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Genres
                    if !movie.genreNames.isEmpty {
                        PlexGenresRow(genres: movie.genreNames)
                    }

                    Spacer()

                    // Play button
                    Button {
                        playMovie(movie)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()

            // Summary
            if let summary = movie.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text(summary)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }

            // Credits
            if !movie.directorNames.isEmpty || !movie.writerNames.isEmpty || movie.role != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Credits")
                        .font(.headline)
                    PlexCreditsView(
                        directors: movie.directorNames,
                        writers: movie.writerNames,
                        cast: movie.role ?? []
                    )
                }
                .padding(.horizontal)
            }

            // Technical info
            if let media = movie.media?.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Media Info")
                        .font(.headline)

                    HStack(spacing: 16) {
                        if let resolution = media.videoResolution {
                            Label(resolution, systemImage: "tv")
                        }
                        if let videoCodec = media.videoCodec {
                            Label(videoCodec.uppercased(), systemImage: "film")
                        }
                        if let audioCodec = media.audioCodec {
                            Label(audioCodec.uppercased(), systemImage: "speaker.wave.2")
                        }
                        if let channels = media.audioChannels {
                            Label("\(channels).1", systemImage: "speaker.3")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom)
    }

    private func playMovie(_ movie: PlexMetadataItem) {
        guard let partKey = movie.streamingPartKey else { return }

        Task {
            guard let url = await PlexAPIService.shared.streamingURL(partKey: partKey) else { return }

            let playAction = PlayAction(
                ratingKey: movie.ratingKey,
                title: movie.title,
                streamingURL: url,
                durationMs: movie.duration ?? 0,
                resumePositionMs: movie.viewOffset ?? 0
            )
            openWindow(value: playAction)
        }
    }
}

// MARK: - Preview

#Preview {
    PlexMovieDetailView(ratingKey: "12345")
}
