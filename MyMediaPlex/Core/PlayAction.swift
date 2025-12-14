//
//  PlayAction.swift
//  MyMedia
//
//  Created by Jonas Helmer on 28.09.25.
//

import SwiftUI
import SwiftData

enum PlayType: Codable {
	case play
	case resume
	case playAgain
	case playNextEpisode
	case resumeCurrentEpisode
	
	var text: LocalizedStringKey {
		switch self {
			case .play:
				return "Play"
			case .resume:
				return "Resume"
			case .playAgain:
				return "Play Again"
			case .playNextEpisode:
				return "Play next Episode"
			case .resumeCurrentEpisode:
				return "Resume Current Episode"
		}
	}
}

struct PlayAction: Hashable, Codable {
	// SwiftData identifiers (legacy)
	let identifiers: [PersistentIdentifier]
	let playType: PlayType

	// Plex streaming properties
	let plexRatingKey: String?
	let plexTitle: String?
	let plexStreamingURL: URL?
	let plexDurationMs: Int?
	let plexResumePositionMs: Int?

	// Legacy initializer for SwiftData
	init(identifiers: [PersistentIdentifier], playType: PlayType) {
		self.identifiers = identifiers
		self.playType = playType
		self.plexRatingKey = nil
		self.plexTitle = nil
		self.plexStreamingURL = nil
		self.plexDurationMs = nil
		self.plexResumePositionMs = nil
	}

	// Plex streaming initializer
	init(ratingKey: String, title: String, streamingURL: URL, durationMs: Int, resumePositionMs: Int) {
		self.identifiers = []
		self.playType = resumePositionMs > 0 ? .resume : .play
		self.plexRatingKey = ratingKey
		self.plexTitle = title
		self.plexStreamingURL = streamingURL
		self.plexDurationMs = durationMs
		self.plexResumePositionMs = resumePositionMs
	}

	/// Returns true if this is a Plex streaming action
	var isPlexStreaming: Bool {
		plexStreamingURL != nil
	}
}

