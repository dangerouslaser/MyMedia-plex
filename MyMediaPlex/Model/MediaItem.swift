//
//  Item.swift
//  MyMedia
//
//  Created by Jonas Helmer on 27.03.25.
//

import Foundation
import SwiftUI
import SwiftData

protocol IsPinnable {
	var id: UUID { get }
	var title: String { get }
	var isPinned: Bool { get set }
}

extension IsPinnable {
	var systemImageName: String {
		switch self {
			case is TvShow:
				return Tabs.tvShows.systemImage
			case is Movie:
				return Tabs.movies.systemImage
			case is MediaCollection:
				return Tabs.collections.systemImage
			default:
				return "questionmark"
		}
	}
}

protocol MediaItem: Identifiable, IsPinnable {
	var id: UUID { get }
	var title: String { get }
	var dateAdded: Date { get }
	var artwork: Data? { get }
	
	var year: Int { get }
	
	var isWatched: Bool { get set }
	var isFavorite: Bool { get set }
}

protocol HasGenre: MediaItem {
	var genre: [String] { get }
}

protocol HasCredits: MediaItem {
	var cast: [String] { get }
	var directors: [String] { get }
	var coDirectors: [String] { get }
	var screenwriters: [String] { get }
	var producers: [String] { get }
	var executiveProducers: [String] { get }
	var composer: String? { get }
}

protocol IsWatchable: MediaItem {
	var progressMinutes: Int { get set }
	var durationMinutes: Int { get }
}

extension MediaItem {
	var dateAddedSection: String {
		let calendar = Calendar.current
		let now = Date()

		if calendar.isDateInToday(dateAdded) {
			return "Today"
		} else if let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now),
				  dateAdded >= oneWeekAgo {
			return "Last Week"
		} else if let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now),
				  dateAdded >= oneMonthAgo {
			return "Last Month"
		} else if let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now),
				  dateAdded >= threeMonthsAgo {
			return "Last 3 Months"
		} else if let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now),
				  dateAdded >= oneYearAgo {
			return "Last Year"
		} else {
			return "Older"
		}
	}
	
	mutating func toggleWatched() {
		withAnimation {
			self.isWatched.toggle()
		}

		// Sync watch status with Plex
		if let watchable = self as? any IsWatchable,
		   let ratingKey = watchable.plexRatingKey {
			let isWatched = self.isWatched
			Task {
				do {
					if isWatched {
						try await PlexAPIService.shared.markWatched(ratingKey: ratingKey)
					} else {
						try await PlexAPIService.shared.markUnwatched(ratingKey: ratingKey)
					}
				} catch {
					// Silently fail - local state is still updated
				}
			}
		}
	}
	
	mutating func toggleFavorite() {
		withAnimation {
			self.isFavorite.toggle()
		}
	}
	
	mutating func togglePinned() {
		withAnimation {
			self.isPinned.toggle()
		}
	}
	
	@MainActor
	func play(playType: PlayType, openWindow: OpenWindowAction) {
		let ids: [PersistentIdentifier] = switch self {
			case let tvShow as TvShow :
				tvShow.findEpisodesToPlay().map(\.persistentModelID)
			case let movie as Movie:
				[movie.persistentModelID]
			case let episode as Episode:
				[episode.persistentModelID]
			default: []
		}
		
		let playAction = PlayAction(identifiers: ids, playType: playType)
		openWindow(value: playAction)
	}
	
	func playWithDefaultPlayer() {
		switch self {
			case let tvShow as TvShow :
				if let url = tvShow.findEpisodesToPlay().first?.url {
					NSWorkspace.shared.open(url)
				}
			case let isWatchable as any IsWatchable:
				if let url = isWatchable.url {
					NSWorkspace.shared.open(url)
				}
			default: break
		}
	}
}

extension IsWatchable {
	/// Returns the streaming URL for Plex content
	var url: URL? {
		// Get the streaming path from the concrete type
		let streamPath: String? = switch self {
		case let movie as Movie:
			movie.streamingURL
		case let episode as Episode:
			episode.streamingURL
		default:
			nil
		}

		guard let path = streamPath,
			  let token = PlexTokenManager.shared.retrieveAuthToken(),
			  let serverURLString = UserDefaults.standard.string(forKey: PreferenceKeys.plexServerURL) else {
			return nil
		}

		return PlexEndpoints.streamingURL(baseURL: serverURLString, partKey: path, token: token)
	}

	/// Returns the Plex rating key for this item, if available
	var plexRatingKey: String? {
		switch self {
		case let movie as Movie:
			return movie.plexRatingKey
		case let episode as Episode:
			return episode.plexRatingKey
		default:
			return nil
		}
	}

	/// Opens this item in Plex Web
	@MainActor
	func openInPlexWeb() {
		guard let ratingKey = self.plexRatingKey,
			  let serverUUID = (self as? Movie)?.plexServerUUID ?? (self as? Episode)?.plexServerUUID else {
			return
		}

		// Construct Plex Web URL
		let plexWebURL = "https://app.plex.tv/desktop/#!/server/\(serverUUID)/details?key=%2Flibrary%2Fmetadata%2F\(ratingKey)"
		if let url = URL(string: plexWebURL) {
			NSWorkspace.shared.open(url)
		}
	}
}

