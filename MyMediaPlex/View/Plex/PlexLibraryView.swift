//
//  PlexLibraryView.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import SwiftUI

/// Main view for browsing a Plex library (movies or TV shows)
struct PlexLibraryView: View {
    let library: PlexLibrarySection
    @State private var viewModel = PlexLibraryViewModel()

    @AppStorage("plexViewPreference") private var viewPreference: ViewOption = .grid
    @AppStorage("plexSortOrder") private var sortOrder: SortOption = .title

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    PlexLoadingView()
                } else if let error = viewModel.error, viewModel.items.isEmpty {
                    PlexErrorView(error: error) {
                        Task { await viewModel.loadItems(for: library) }
                    }
                } else if viewModel.items.isEmpty {
                    PlexEmptyView(
                        title: "No Items",
                        message: "This library is empty",
                        systemImage: library.isMovieLibrary ? "film" : "tv"
                    )
                } else {
                    contentView
                }
            }
            .navigationTitle(library.title)
            .toolbar {
                ToolbarItem {
                    Picker("Sort by", systemImage: "arrow.up.arrow.down", selection: $sortOrder.animation()) {
                        ForEach(SortOption.allCases) { option in
                            Label(option.title, systemImage: option.systemImageName)
                        }
                    }
                }

                ToolbarItem {
                    Picker("View", selection: $viewPreference.animation()) {
                        ForEach([ViewOption.grid, ViewOption.list], id: \.self) { option in
                            Label(option.title, systemImage: option.symbolName)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                ToolbarItem {
                    Toggle(isOn: $viewModel.showUnwatchedOnly.animation()) {
                        Label("Unwatched Only", systemImage: "eye.slash")
                    }
                }
            }
            .refreshable {
                await viewModel.loadItems(for: library)
            }
        }
        .task {
            await viewModel.loadItems(for: library)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let items = sortedItems(viewModel.filteredItems)

        switch viewPreference {
        case .grid:
            ScrollView {
                PlexGridView(
                    items: items,
                    imageConfig: viewModel.imageConfig
                )
            }
        case .list, .detailList:
            ScrollView {
                PlexListView(
                    items: items,
                    imageConfig: viewModel.imageConfig
                )
            }
        }
    }

    private func sortedItems(_ items: [PlexMetadataItem]) -> [PlexMetadataItem] {
        switch sortOrder {
        case .title:
            return items.sorted { $0.title < $1.title }
        case .releaseDate:
            return items.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .dateAdded:
            return items.sorted { ($0.addedAt ?? 0) > ($1.addedAt ?? 0) }
        }
    }
}

// MARK: - Plex Grid View

/// Grid view for displaying Plex media items
struct PlexGridView: View {
    let items: [PlexMetadataItem]
    let imageConfig: PlexImageURLConfig?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items, id: \.ratingKey) { item in
                NavigationLink(value: item) {
                    PlexMediaCard(
                        item: item,
                        imageConfig: imageConfig,
                        onTap: {}
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    PlexItemContextMenu(item: item)
                }
            }
        }
        .padding()
        .navigationDestination(for: PlexMetadataItem.self) { item in
            if item.isMovie {
                PlexMovieDetailView(ratingKey: item.ratingKey)
            } else if item.isTVShow {
                PlexShowDetailView(ratingKey: item.ratingKey)
            }
        }
    }
}

// MARK: - Plex List View

/// List view for displaying Plex media items
struct PlexListView: View {
    let items: [PlexMetadataItem]
    let imageConfig: PlexImageURLConfig?

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(items, id: \.ratingKey) { item in
                NavigationLink(value: item) {
                    PlexMediaRow(
                        item: item,
                        imageConfig: imageConfig,
                        onTap: {}
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    PlexItemContextMenu(item: item)
                }
                Divider()
            }
        }
        .padding()
        .navigationDestination(for: PlexMetadataItem.self) { item in
            if item.isMovie {
                PlexMovieDetailView(ratingKey: item.ratingKey)
            } else if item.isTVShow {
                PlexShowDetailView(ratingKey: item.ratingKey)
            }
        }
    }
}

// MARK: - Context Menu

struct PlexItemContextMenu: View {
    let item: PlexMetadataItem

    var body: some View {
        Button(item.isWatched ? "Mark Unwatched" : "Mark Watched",
               systemImage: item.isWatched ? "eye.slash" : "eye") {
            Task {
                do {
                    if item.isWatched {
                        try await PlexAPIService.shared.markUnwatched(ratingKey: item.ratingKey)
                    } else {
                        try await PlexAPIService.shared.markWatched(ratingKey: item.ratingKey)
                    }
                } catch {
                    print("Error toggling watch status: \(error)")
                }
            }
        }

        Divider()

        if let webURL = plexWebURL(for: item) {
            Link(destination: webURL) {
                Label("View on Plex Web", systemImage: "globe")
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

// MARK: - Preview

#Preview {
    PlexLibraryView(library: PlexLibrarySection(
        key: "1",
        title: "Movies",
        type: "movie",
        uuid: "test",
        language: "en",
        agent: nil,
        scanner: nil
    ))
}
