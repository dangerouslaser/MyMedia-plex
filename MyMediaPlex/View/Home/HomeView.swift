//
//  HomeView.swift
//  MyMedia
//
//  Created by Jonas Helmer on 31.03.25.
//

import SwiftUI
import SwiftData
import AwesomeSwiftyComponents



struct HomeView: View {
	@State private var isPlexConnected = false
	@State private var isCheckingAuth = true

	@Environment(CommandResource.self) private var commandResource
	@Environment(\.openURL) private var openURL

    var body: some View {
		Group {
			if isCheckingAuth {
				ProgressView("Loading...")
					.frame(maxWidth: .infinity, maxHeight: .infinity)
			} else if isPlexConnected {
				PlexHomeView()
			} else {
				PlexNotConnectedView()
			}
		}
		.alert(commandResource.errorTitle, isPresented: .constant(commandResource.errorMessage != nil)) {
			Button("OK"){ commandResource.clearError() }
			Button("Get Help") { openURL(URL(string: "https://github.com/photangralenphie/MyMedia/wiki/Help-%E2%80%90-Error-Codes")!) }
		} message: {
			commandResource.errorMessage ?? Text("Unknown Error")
		}
		.task {
			await checkPlexConnection()
		}
		.onReceive(NotificationCenter.default.publisher(for: .plexAuthStateChanged)) { _ in
			Task {
				await checkPlexConnection()
			}
		}
    }

	private func checkPlexConnection() async {
		isCheckingAuth = true
		isPlexConnected = await PlexAuthService.shared.isAuthenticated
		if isPlexConnected {
			await PlexAPIService.shared.loadServerURL()
		}
		isCheckingAuth = false
	}
}

// MARK: - Notification for auth state changes

extension Notification.Name {
	static let plexAuthStateChanged = Notification.Name("plexAuthStateChanged")
}
