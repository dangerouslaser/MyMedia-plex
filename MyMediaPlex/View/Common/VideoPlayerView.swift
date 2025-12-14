//
//  VideoPlayerView.swift
//  MyMedia
//
//  Created by Jonas Helmer on 01.04.25.
//

import SwiftUI
import AVKit
import SwiftData
import AwesomeSwiftyComponents
import MediaPlayer
import SwiftUIIntrospect

struct VideoPlayerView: View {

	@State private var errorText: String = ""
	@State private var showErrorSheet: Bool = false
	private var playType: PlayType

	// Legacy SwiftData support
	@State private var queue: [any IsWatchable]
	@State private var currentWatchable: (any IsWatchable)?

	// Plex streaming support
	private var plexPlayAction: PlayAction?
	@State private var plexRatingKey: String?
	@State private var plexTitle: String?
	@State private var plexDurationMs: Int?

	@State private var player = AVQueuePlayer()

	@State private var currentNowPlayingWatchableId = UUID()
	let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()

	@Environment(\.dismiss) private var dismiss

	@AppStorage(PreferenceKeys.autoPlay) private var autoPlay: Bool = true
	@AppStorage(PreferenceKeys.playerStyle) private var playerStyle: AVPlayerViewControlsStyle = .floating

	// Plex streaming initializer
	init(playAction: PlayAction, context: ModelContext) {
		if playAction.isPlexStreaming {
			// Plex streaming mode
			self.plexPlayAction = playAction
			self.queue = []
			self.playType = playAction.playType
		} else {
			// Legacy SwiftData mode
			var initQueue: [any IsWatchable] = []
			for id in playAction.identifiers {
				let object = context.model(for: id)
				if(object is (any IsWatchable)) {
					initQueue.append(object as! (any IsWatchable))
				}
			}

			if initQueue.isEmpty {
				self.currentWatchable = nil
				self.queue = []
				self.playType = .play
				return
			}

			self.queue = initQueue
			self.playType = playAction.playType
			self.plexPlayAction = nil
		}
	}
	
	var body: some View {
		VideoPlayer(player: player)
			.sheet(isPresented: $showErrorSheet){
				Text("error: \(errorText)")
			}
			.onAppear(perform: createPlaybackQueue)
			.onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem)) { _ in
				videoDidFinish()
			}
			.onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemTimeJumped, object: player.currentItem)) { _ in
				updateNowPlayingInfo()
			}
			.onDisappear(perform: onDisappear)
			.introspect(.videoPlayer, on: .macOS(.v15, .v26)) { AVPlayerView in
				AVPlayerView.allowsPictureInPicturePlayback = true
				AVPlayerView.controlsStyle = playerStyle
				AVPlayerView.showsSharingServiceButton = true
				AVPlayerView.showsTimecodes = true
			}
	}
	
	func createPlaybackQueue() {
		// Plex streaming mode
		if let plexAction = plexPlayAction, let streamingURL = plexAction.plexStreamingURL {
			plexRatingKey = plexAction.plexRatingKey
			plexTitle = plexAction.plexTitle
			plexDurationMs = plexAction.plexDurationMs

			let avItem = AVPlayerItem(url: streamingURL)
			player.insert(avItem, after: nil)
			player.preventsDisplaySleepDuringVideoPlayback = true
			player.play()

			// Seek to resume position if needed
			if playType == .resume, let resumeMs = plexAction.plexResumePositionMs, resumeMs > 0 {
				let resumeSeconds = Double(resumeMs) / 1000.0
				player.seek(to: CMTime(seconds: resumeSeconds, preferredTimescale: 1))
			}

			// Report playback started to Plex
			updatePlexProgress(state: .playing)
			updateNowPlayingInfoForPlex()
			return
		}

		// Legacy SwiftData mode
		if queue.isEmpty {
			return
		}

		let avItems = queue.compactMap { watchable -> AVPlayerItem? in
			guard let url = watchable.url else {
				return nil
			}
			return AVPlayerItem(url: url)
		}

		guard !avItems.isEmpty else {
			errorText = "Unable to load media. Please check your Plex connection."
			showErrorSheet = true
			return
		}

		for item in avItems {
			player.insert(item, after: nil)
		}

		if autoPlay {
			player.actionAtItemEnd = .advance
		}

		currentWatchable = queue.removeFirst()
		player.preventsDisplaySleepDuringVideoPlayback = true
		player.play()

		if playType == .resume || playType == .resumeCurrentEpisode {
			let progressSeconds = Double((currentWatchable?.progressMinutes ?? 0) * 60)
			self.player.seek(to: CMTime(seconds: progressSeconds, preferredTimescale: 1))
		}

		// Report playback started to Plex
		updatePlexProgress(state: .playing)
	}
	
	func videoDidFinish() {
		// Plex streaming mode
		if let ratingKey = plexRatingKey {
			Task {
				try? await PlexAPIService.shared.markWatched(ratingKey: ratingKey)
			}
			dismiss()
			return
		}

		// Legacy SwiftData mode
		currentWatchable?.progressMinutes = currentWatchable?.durationMinutes ?? 0
		currentWatchable?.isWatched = true

		// Mark as watched on Plex (scrobble) for legacy items with Plex rating key
		if let ratingKey = currentWatchable?.plexRatingKey {
			Task {
				try? await PlexAPIService.shared.markWatched(ratingKey: ratingKey)
			}
		}

		if queue.isEmpty {
			dismiss()
			return
		}

		currentWatchable = queue.removeFirst()
		updatePlexProgress(state: .playing)
	}
	
	func onDisappear() {
		// Report progress to Plex when stopping playback
		updatePlexProgress(state: .stopped)

		// Legacy SwiftData mode - save progress
		if currentWatchable != nil {
			let currentSeconds = player.currentItem?.currentTime().seconds ?? 0
			currentWatchable?.progressMinutes = Int(currentSeconds) / 60
		}

		nowPlayingInfoCenter.nowPlayingInfo = nil
	}

	/// Updates Plex timeline with current playback progress
	private func updatePlexProgress(state: PlaybackState) {
		let currentTimeMs = Int((player.currentItem?.currentTime().seconds ?? 0) * 1000)

		// Plex streaming mode
		if let ratingKey = plexRatingKey, let durationMs = plexDurationMs {
			Task {
				try? await PlexAPIService.shared.updateProgress(
					ratingKey: ratingKey,
					timeMs: currentTimeMs,
					durationMs: durationMs,
					state: state
				)
			}
			return
		}

		// Legacy SwiftData mode with Plex rating key
		guard let watchable = currentWatchable,
			  let ratingKey = watchable.plexRatingKey else {
			return
		}

		let durationMs = watchable.durationMinutes * 60 * 1000

		Task {
			try? await PlexAPIService.shared.updateProgress(
				ratingKey: ratingKey,
				timeMs: currentTimeMs,
				durationMs: durationMs,
				state: state
			)
		}
	}

	/// Updates Now Playing info for Plex streaming mode
	private func updateNowPlayingInfoForPlex() {
		guard let title = plexTitle else { return }

		var nowPlayingInfo: [String: Any] = [:]
		nowPlayingInfo[MPMediaItemPropertyTitle] = title

		if let durationMs = plexDurationMs {
			nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
		}

		nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
	}

	private func updateNowPlayingInfo() {
		guard let currentWatchable else { return }
		if player.timeControlStatus != .playing { return }
		if currentWatchable.id == currentNowPlayingWatchableId { return }

		currentNowPlayingWatchableId = currentWatchable.id
		var nowPlayingInfo: [String: Any] = [:]
		nowPlayingInfo[MPMediaItemPropertyTitle] = currentWatchable.title

		if let imageData = currentWatchable.artwork, let image = NSImage(data: imageData) {
			// @Sendable: https://developer.apple.com/forums/thread/764874?answerId=810243022#810243022
			nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
		}
		if let episode = currentWatchable as? Episode {
			nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Season \(episode.season) Episode \(episode.episode)"
		}
		nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
	}
}
