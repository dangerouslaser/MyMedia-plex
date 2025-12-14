//
//  PlexHomeView.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import SwiftUI

/// Main home view for Plex content
struct PlexHomeView: View {
    @State private var viewModel = PlexHomeViewModel()
    @State private var libraryViewModel = PlexLibraryViewModel()
    @State private var selectedLibrary: PlexLibrarySection?

    var body: some View {
        NavigationSplitView {
            // Sidebar with libraries
            List(selection: $selectedLibrary) {
                Section("Libraries") {
                    ForEach(libraryViewModel.movieLibraries) { library in
                        NavigationLink(value: library) {
                            Label(library.title, systemImage: "film")
                        }
                    }

                    ForEach(libraryViewModel.tvShowLibraries) { library in
                        NavigationLink(value: library) {
                            Label(library.title, systemImage: "tv")
                        }
                    }
                }

                Section("Quick Access") {
                    NavigationLink {
                        PlexOnDeckView()
                    } label: {
                        Label("Continue Watching", systemImage: "play.circle")
                    }

                    NavigationLink {
                        PlexRecentlyAddedView()
                    } label: {
                        Label("Recently Added", systemImage: "clock")
                    }
                }
            }
            .navigationTitle("Plex")
            .listStyle(.sidebar)
            .task {
                await libraryViewModel.loadLibraries()
            }
        } detail: {
            // Detail view
            if let library = selectedLibrary {
                PlexLibraryView(library: library)
            } else {
                // Default home view
                PlexDashboardView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Dashboard View

/// Default dashboard showing on deck and recently added
struct PlexDashboardView: View {
    @Bindable var viewModel: PlexHomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isLoading && viewModel.onDeck.isEmpty {
                    PlexLoadingView()
                } else if let error = viewModel.error {
                    PlexErrorView(error: error) {
                        Task { await viewModel.refresh() }
                    }
                } else {
                    // On Deck
                    if !viewModel.onDeck.isEmpty {
                        sectionView(title: "Continue Watching", items: viewModel.onDeck)
                    }

                    // Recently Added Movies
                    if !viewModel.recentlyAddedMovies.isEmpty {
                        sectionView(title: "Recently Added Movies", items: viewModel.recentlyAddedMovies)
                    }

                    // Recently Added Shows
                    if !viewModel.recentlyAddedShows.isEmpty {
                        sectionView(title: "Recently Added TV Shows", items: viewModel.recentlyAddedShows)
                    }

                    if viewModel.onDeck.isEmpty && viewModel.recentlyAddedMovies.isEmpty && viewModel.recentlyAddedShows.isEmpty {
                        PlexEmptyView(
                            title: "No Content",
                            message: "Select a library from the sidebar to browse your media",
                            systemImage: "rectangle.on.rectangle"
                        )
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func sectionView(title: String, items: [PlexMetadataItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(items, id: \.ratingKey) { item in
                        NavigationLink(value: item) {
                            PlexMediaCard(
                                item: item,
                                imageConfig: viewModel.imageConfig,
                                onTap: {}
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: PlexMetadataItem.self) { item in
            if item.isMovie {
                PlexMovieDetailView(ratingKey: item.ratingKey)
            } else if item.isTVShow {
                PlexShowDetailView(ratingKey: item.ratingKey)
            } else if item.isEpisode {
                // For episodes, navigate to the show
                if let showKey = item.grandparentRatingKey {
                    PlexShowDetailView(ratingKey: showKey)
                }
            }
        }
    }
}

// MARK: - On Deck View

/// View showing all on deck items
struct PlexOnDeckView: View {
    @State private var viewModel = PlexLibraryViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                PlexLoadingView()
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                PlexErrorView(error: error) {
                    Task { await viewModel.loadOnDeck() }
                }
            } else if viewModel.items.isEmpty {
                PlexEmptyView(
                    title: "Nothing to Continue",
                    message: "Start watching something to see it here",
                    systemImage: "play.circle"
                )
            } else {
                ScrollView {
                    PlexGridView(
                        items: viewModel.items,
                        imageConfig: viewModel.imageConfig
                    )
                }
            }
        }
        .navigationTitle("Continue Watching")
        .task {
            await viewModel.loadOnDeck()
        }
        .refreshable {
            await viewModel.loadOnDeck()
        }
    }
}

// MARK: - Recently Added View

/// View showing all recently added items
struct PlexRecentlyAddedView: View {
    @State private var viewModel = PlexLibraryViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                PlexLoadingView()
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                PlexErrorView(error: error) {
                    Task { await loadRecentlyAdded() }
                }
            } else if viewModel.items.isEmpty {
                PlexEmptyView(
                    title: "No Recent Additions",
                    message: "New content will appear here when added to your libraries",
                    systemImage: "clock"
                )
            } else {
                ScrollView {
                    PlexGridView(
                        items: viewModel.items,
                        imageConfig: viewModel.imageConfig
                    )
                }
            }
        }
        .navigationTitle("Recently Added")
        .task {
            await loadRecentlyAdded()
        }
        .refreshable {
            await loadRecentlyAdded()
        }
    }

    private func loadRecentlyAdded() async {
        // Load from first available library
        await viewModel.loadLibraries()
        if let firstLibrary = viewModel.libraries.first {
            await viewModel.loadRecentlyAdded(for: firstLibrary, limit: 50)
        }
    }
}

// MARK: - Not Connected View

/// View shown when Plex is not connected
struct PlexNotConnectedView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Connect to Plex")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in to your Plex account to browse and stream your media library.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            Button {
                openSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    PlexHomeView()
}
