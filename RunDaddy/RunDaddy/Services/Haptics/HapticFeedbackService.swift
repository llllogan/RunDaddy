//
//  HapticFeedbackService.swift
//  RunDaddy
//
//  Created by ChatGPT on 07/03/2026.
//

import Foundation
import SwiftUI
import UIKit

@MainActor
final class HapticFeedbackService {
    static let live = HapticFeedbackService(mode: .live)
    static let preview = HapticFeedbackService(mode: .preview)

    private enum Mode {
        case live
        case preview
    }

    private let mode: Mode
    private let softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init(mode: Mode) {
        self.mode = mode
        if mode == .live {
            prepareGenerators()
        }
    }

    func primaryButtonTap() {
        guard isLive else { return }
        mediumImpactGenerator.prepare()
        mediumImpactGenerator.impactOccurred(intensity: 0.9)
    }

    func secondaryButtonTap() {
        guard isLive else { return }
        softImpactGenerator.prepare()
        softImpactGenerator.impactOccurred(intensity: 0.6)
    }

    func prominentActionTap() {
        guard isLive else { return }
        heavyImpactGenerator.prepare()
        heavyImpactGenerator.impactOccurred(intensity: 1.0)
    }

    func destructiveActionTap() {
        guard isLive else { return }
        rigidImpactGenerator.prepare()
        rigidImpactGenerator.impactOccurred(intensity: 1.0)
    }

    func selectionChanged() {
        guard isLive else { return }
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    func success() {
        guard isLive else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }

    func warning() {
        guard isLive else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.warning)
    }

    func error() {
        guard isLive else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.error)
    }

    private var isLive: Bool {
        mode == .live
    }

    private func prepareGenerators() {
        softImpactGenerator.prepare()
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        rigidImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
    }
}

private struct HapticFeedbackServiceKey: EnvironmentKey {
    @MainActor
    static let defaultValue = HapticFeedbackService.preview
}

extension EnvironmentValues {
    var haptics: HapticFeedbackService {
        get { self[HapticFeedbackServiceKey.self] }
        set { self[HapticFeedbackServiceKey.self] = newValue }
    }
}
