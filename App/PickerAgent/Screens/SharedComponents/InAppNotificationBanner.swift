//
//  InAppNotificationBanner.swift
//  PickAgent
//
//  Created by ChatGPT on 6/6/2025.
//

import SwiftUI

struct InAppNotification: Identifiable, Equatable {
    enum Style {
        case info
        case success
        case warning
        case error
    }

    let id: UUID
    let message: String
    let style: Style
    let isDismissable: Bool
    let autoDismissAfter: TimeInterval?

    init(
        id: UUID = UUID(),
        message: String,
        style: Style,
        isDismissable: Bool = true,
        autoDismissAfter: TimeInterval? = nil
    ) {
        self.id = id
        self.message = message
        self.style = style
        self.isDismissable = isDismissable
        self.autoDismissAfter = autoDismissAfter ?? (isDismissable ? 4 : nil)
    }
}

private extension InAppNotification.Style {
    var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var background: Color {
        switch self {
        case .info:
            return Color(red: 0.90, green: 0.95, blue: 1.0)
        case .success:
            return Color(red: 0.90, green: 0.98, blue: 0.92)
        case .warning:
            return Color(red: 1.0, green: 0.95, blue: 0.90)
        case .error:
            return Color(red: 1.0, green: 0.93, blue: 0.93)
        }
    }

    var foreground: Color {
        switch self {
        case .info:
            return Color.blue
        case .success:
            return Color.green
        case .warning:
            return Color.orange
        case .error:
            return Color.red
        }
    }
}

struct InAppNotificationBanner: View {
    let notification: InAppNotification
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.style.iconName)
                .font(.headline)
                .foregroundStyle(notification.style.foreground)
                .padding(.top, 2)

            Text(notification.message)
                .font(.subheadline)
                .foregroundStyle(notification.style.foreground.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .leading)

            if notification.isDismissable, let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(notification.style.foreground.opacity(0.8))
                        .padding(6)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(notification.style.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

private struct InAppNotificationStack: View {
    let notifications: [InAppNotification]
    var onDismiss: ((InAppNotification) -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(notifications) { notification in
                InAppNotificationBanner(notification: notification) {
                    onDismiss?(notification)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    guard let delay = notification.autoDismissAfter else { return }
                    guard let onDismiss else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        onDismiss(notification)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

extension View {
    func inAppNotifications(
        _ notifications: [InAppNotification],
        topPadding: CGFloat = 64,
        onDismiss: ((InAppNotification) -> Void)? = nil
    ) -> some View {
        overlay(alignment: .topLeading) {
            if !notifications.isEmpty {
                InAppNotificationStack(
                    notifications: notifications,
                    onDismiss: onDismiss
                )
                .padding(.horizontal, 16)
                .padding(.top, topPadding)
                .ignoresSafeArea(edges: .top)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: notifications)
    }
}
