//
//  ArtworkSelectorView.swift
//  MyMedia
//
//  Created by Jonas Helmer on 09.11.25.
//

import SwiftUI

struct ArtworkSelectorView: View {

	let tvShow: TvShow
	@State private var imageData: Data?
	@State private var alternativeArtworks: [Data] = []

	private let scale: Double
	private let pickerWidth: Double

	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var modelContext


	init(tvShow: TvShow) {
		self.tvShow = tvShow

		let scale = 0.65
		self.pickerWidth = LayoutConstants.artworkWidth * scale + 20
		self.scale = scale
	}

	var body: some View {
		NavigationStack {
			Form {
				HStack(alignment: .top) {
					// Current artwork
					if let currentArtwork = tvShow.artwork {
						VStack {
							Picker("Current:", selection: $imageData) {
								ArtworkView(imageData: currentArtwork, title: "", subtitle: "", scale: scale)
									.tag(currentArtwork)
							}
							.pickerStyle(.radioGroup)
							.frame(width: pickerWidth)
						}
					}

					// Episode artworks from sync
					if !alternativeArtworks.isEmpty {
						VStack {
							Picker("Episodes:", selection: $imageData) {
								ForEach(alternativeArtworks, id: \.self) { artwork in
									ArtworkView(imageData: artwork, title: "", subtitle: "", scale: scale)
										.tag(artwork)
								}
							}
							.pickerStyle(.radioGroup)
							.frame(width: pickerWidth)
						}
					}

					Divider()

					Picker("None:", selection: $imageData) {
						ArtworkView(imageData: nil, title: tvShow.title, subtitle: "(\(tvShow.year))", scale: scale)
							.tag(Data())
					}
					.pickerStyle(.radioGroup)
					.frame(width: pickerWidth)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: 600)
			.formStyle(.grouped)
			.onAppear { collectArtworks() }
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					if #available(macOS 26, *) {
						Button("Done", systemImage: "checkmark", role: .confirm, action: setArtwork)
					} else {
						Button("Done", systemImage: "checkmark", action: setArtwork)
					}
				}

				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", role: .cancel) { dismiss() }
				}
			}
		}
	}

	private func collectArtworks() {
		// Set initial selection to current artwork
		imageData = tvShow.artwork

		// Collect unique episode artworks
		var seen = Set<Data>()
		if let showArtwork = tvShow.artwork {
			seen.insert(showArtwork)
		}

		for episode in tvShow.episodes {
			if let artwork = episode.artwork, !seen.contains(artwork) {
				seen.insert(artwork)
				alternativeArtworks.append(artwork)
			}
		}
	}

	private func setArtwork() {
		tvShow.artwork = imageData
		dismiss()
	}
}
