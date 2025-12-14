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
	
	@State private var queue: [any IsWatchable]
	@State private var currentWatchable: (any IsWatchable)?
	@State private var player = AVQueuePlayer()

	@State private var currentNowPlayingWatchableId = UUID()
	let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
	
	@Environment(\.dismiss) private var dismiss
	
	@AppStorage(PreferenceKeys.autoPlay) private var autoPlay: Bool = true
	@AppStorage(PreferenceKeys.playerStyle) private var playerStyle: AVPlayerViewControlsStyle = .floating
	
	init(playAction: PlayAction, context: ModelContext) {
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
		currentWatchable?.progressMinutes = currentWatchable?.durationMinutes ?? 0
		currentWatchable?.isWatched = true

		// Mark as watched on Plex (scrobble)
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
		let currentSeconds = player.currentItem?.currentTime().seconds ?? 0
		currentWatchable?.progressMinutes = Int(currentSeconds) / 60

		// Report progress to Plex when stopping playback
		updatePlexProgress(state: .stopped)

		nowPlayingInfoCenter.nowPlayingInfo = nil
	}

	/// Updates Plex timeline with current playback progress
	private func updatePlexProgress(state: PlaybackState) {
		guard let watchable = currentWatchable,
			  let ratingKey = watchable.plexRatingKey else {
			return
		}

		let currentTimeMs = Int((player.currentItem?.currentTime().seconds ?? 0) * 1000)
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
