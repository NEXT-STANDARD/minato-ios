//
// NotificationService.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

protocol NotificationAuthorizing {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    )
}

protocol NotificationRequestDelivering {
    func add(_ request: UNNotificationRequest)
}

private final class NotificationCenterAuthorizerAdapter: NotificationAuthorizing {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        center.requestAuthorization(options: options, completionHandler: completionHandler)
    }
}

private final class NotificationCenterRequestDelivererAdapter: NotificationRequestDelivering {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func add(_ request: UNNotificationRequest) {
        Task {
            try? await center.add(request)
        }
    }
}

private struct NoopNotificationAuthorizer: NotificationAuthorizing {
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        completionHandler(false, nil)
    }
}

private struct NoopNotificationRequestDeliverer: NotificationRequestDelivering {
    func add(_ request: UNNotificationRequest) {}
}

final class NotificationService {
    static let shared = NotificationService()

    private let isRunningTestsProvider: () -> Bool
    private let authorizer: NotificationAuthorizing
    private let requestDeliverer: NotificationRequestDelivering

    /// Returns true if running in test environment (XCTest, Swift Testing, or CI)
    private var isRunningTests: Bool {
        isRunningTestsProvider()
    }

    private init() {
        self.isRunningTestsProvider = {
            let env = ProcessInfo.processInfo.environment
            return NSClassFromString("XCTestCase") != nil ||
                   env["XCTestConfigurationFilePath"] != nil ||
                   env["XCTestBundlePath"] != nil ||
                   env["GITHUB_ACTIONS"] != nil ||
                   env["CI"] != nil
        }
        if isRunningTestsProvider() {
            self.authorizer = NoopNotificationAuthorizer()
            self.requestDeliverer = NoopNotificationRequestDeliverer()
        } else {
            let center = UNUserNotificationCenter.current()
            self.authorizer = NotificationCenterAuthorizerAdapter(center: center)
            self.requestDeliverer = NotificationCenterRequestDelivererAdapter(center: center)
        }
    }

    internal init(
        isRunningTestsProvider: @escaping () -> Bool,
        authorizer: NotificationAuthorizing,
        requestDeliverer: NotificationRequestDelivering
    ) {
        self.isRunningTestsProvider = isRunningTestsProvider
        self.authorizer = authorizer
        self.requestDeliverer = requestDeliverer
    }

    func requestAuthorization() {
        guard !isRunningTests else { return }
        authorizer.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                // Register MINATO action categories for quick approval from notifications
                Self.registerMINATOActionCategories()
            } else {
                // Permission denied
            }
        }
    }
    
    func sendLocalNotification(
        title: String,
        body: String,
        identifier: String,
        userInfo: [String: Any]? = nil,
        interruptionLevel: UNNotificationInterruptionLevel = .active,
        categoryIdentifier: String? = nil
    ) {
        guard !isRunningTests else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = interruptionLevel
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        if let userInfo = userInfo {
            content.userInfo = userInfo
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        requestDeliverer.add(request)
    }
    
    func sendMentionNotification(from sender: String, message: String) {
        let title = "🫵 you were mentioned by \(sender)"
        let body = message
        let identifier = "mention-\(UUID().uuidString)"
        
        sendLocalNotification(title: title, body: body, identifier: identifier)
    }
    
    func sendPrivateMessageNotification(from sender: String, message: String, peerID: PeerID) {
        let title = "🔒 DM from \(sender)"
        let body = message
        let identifier = "private-\(UUID().uuidString)"
        let userInfo = ["peerID": peerID.id, "senderName": sender]
        
        sendLocalNotification(title: title, body: body, identifier: identifier, userInfo: userInfo)
    }
    
    // MINATO: Register action categories for quick approval from notifications
    static let minatoReplyCategoryId = "MINATO_REPLY_APPROVAL"
    static let minatoScheduleCategoryId = "MINATO_SCHEDULE_APPROVAL"
    static let approveActionId = "MINATO_APPROVE"
    static let declineActionId = "MINATO_DECLINE"

    static func registerMINATOActionCategories() {
        let approveReply = UNNotificationAction(
            identifier: approveActionId, title: "承認して送信", options: [.foreground]
        )
        let dismissReply = UNNotificationAction(
            identifier: declineActionId, title: "却下", options: [.destructive]
        )
        let replyCategory = UNNotificationCategory(
            identifier: minatoReplyCategoryId,
            actions: [approveReply, dismissReply],
            intentIdentifiers: [], options: []
        )

        let approveSchedule = UNNotificationAction(
            identifier: approveActionId, title: "承認", options: [.foreground]
        )
        let declineSchedule = UNNotificationAction(
            identifier: declineActionId, title: "辞退", options: [.destructive]
        )
        let scheduleCategory = UNNotificationCategory(
            identifier: minatoScheduleCategoryId,
            actions: [approveSchedule, declineSchedule],
            intentIdentifiers: [], options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([replyCategory, scheduleCategory])
    }

    // MINATO: Agent needs owner confirmation
    func sendAgentConfirmationNotification(from peerName: String, message: String, peerID: PeerID, requestId: String? = nil) {
        let title = "⚡ \(peerName) からのメッセージ"
        let body = "「\(message.prefix(50))」— 返信してください"
        let identifier = "agent-confirm-\(UUID().uuidString)"
        var userInfo: [String: Any] = ["peerID": peerID.id, "actionType": "agent_confirmation"]
        if let requestId {
            userInfo["requestId"] = requestId
            userInfo["categoryIdentifier"] = Self.minatoScheduleCategoryId
        } else {
            userInfo["categoryIdentifier"] = Self.minatoReplyCategoryId
        }

        sendLocalNotification(title: title, body: body, identifier: identifier,
                              userInfo: userInfo, interruptionLevel: .timeSensitive,
                              categoryIdentifier: userInfo["categoryIdentifier"] as? String)
    }

    // Geohash public chat notification with deep link to a specific geohash
    func sendGeohashActivityNotification(geohash: String, titlePrefix: String = "#", bodyPreview: String) {
        let title = "\(titlePrefix)\(geohash)"
        let identifier = "geo-activity-\(geohash)-\(Date().timeIntervalSince1970)"
        let deeplink = "bitchat://geohash/\(geohash)"
        let userInfo: [String: Any] = ["deeplink": deeplink]
        sendLocalNotification(title: title, body: bodyPreview, identifier: identifier, userInfo: userInfo)
    }

    func sendNetworkAvailableNotification(peerCount: Int) {
        let title = "👥 bitchatters nearby!"
        let body = peerCount == 1 ? "1 person around" : "\(peerCount) people around"
        // Fixed identifier so iOS updates the existing notification instead of creating new ones
        let identifier = "network-available"

        sendLocalNotification(
            title: title,
            body: body,
            identifier: identifier,
            interruptionLevel: .timeSensitive
        )
    }
}
