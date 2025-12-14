//
//  PlexTokenManager.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation
import Security

/// Manages secure storage of Plex authentication tokens using Keychain
final class PlexTokenManager {
    static let shared = PlexTokenManager()

    private let service = "com.mymediaplex.plex"
    private let authTokenKey = "authToken"
    private let clientIdentifierKey = "clientIdentifier"

    private init() {}

    // MARK: - Auth Token

    /// Stores the Plex auth token securely in Keychain
    func storeAuthToken(_ token: String) throws {
        try store(key: authTokenKey, value: token)
    }

    /// Retrieves the Plex auth token from Keychain
    func retrieveAuthToken() -> String? {
        return retrieve(key: authTokenKey)
    }

    /// Deletes the Plex auth token from Keychain
    func deleteAuthToken() throws {
        try delete(key: authTokenKey)
    }

    /// Checks if user is authenticated
    var isAuthenticated: Bool {
        return retrieveAuthToken() != nil
    }

    // MARK: - Client Identifier

    /// Gets or creates a unique client identifier for this app installation
    func getOrCreateClientIdentifier() -> String {
        if let existing = retrieve(key: clientIdentifierKey) {
            return existing
        }

        let newIdentifier = UUID().uuidString
        try? store(key: clientIdentifierKey, value: newIdentifier)
        return newIdentifier
    }

    /// Retrieves the client identifier
    func retrieveClientIdentifier() -> String? {
        return retrieve(key: clientIdentifierKey)
    }

    // MARK: - Clear All

    /// Clears all Plex-related data from Keychain (for sign out)
    func clearAll() throws {
        try? delete(key: authTokenKey)
        // Keep client identifier - it should persist across sign in/out
    }

    // MARK: - Private Keychain Operations

    private func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw PlexTokenError.encodingFailed
        }

        // Delete existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw PlexTokenError.keychainError(status: status)
        }
    }

    private func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlexTokenError.keychainError(status: status)
        }
    }
}

// MARK: - Errors

enum PlexTokenError: LocalizedError {
    case encodingFailed
    case keychainError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode token data"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}
