//
//  HapticFeedbackService.swift
//  RunDaddy
//
//  Created by ChatGPT on 07/03/2026.
//

import Foundation
import SwiftUI
import UIKit
#if canImport(CoreHaptics)
import CoreHaptics
#endif

@MainActor
final class HapticFeedbackService {
    static let live = HapticFeedbackService(mode: .live)
    static let preview = HapticFeedbackService(mode: .preview)

    enum Feedback {
        case impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat?)
        case notification(UINotificationFeedbackGenerator.FeedbackType)
        case selection
    }

    private enum Mode {
        case live
        case preview
    }

    private let mode: Mode
    private let supportsHaptics: Bool
    private let softImpactGenerator = UIImpactFeedbackGenerator(style: .soft)
    private let lightImpactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let rigidImpactGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyImpactGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init(mode: Mode) {
        self.mode = mode
#if canImport(CoreHaptics)
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
#else
        supportsHaptics = true
#endif
        prepareGeneratorsIfNeeded()
    }

    func primaryButtonTap() {
        play(.impact(style: .medium, intensity: 0.9))
    }

    func secondaryButtonTap() {
        play(.impact(style: .light, intensity: 0.6))
    }

    func prominentActionTap() {
        play(.impact(style: .heavy, intensity: 1.0))
    }

    func destructiveActionTap() {
        play(.impact(style: .rigid, intensity: 1.0))
    }

    func selectionChanged() {
        play(.selection)
    }

    func success() {
        play(.notification(.success))
    }

    func warning() {
        play(.notification(.warning))
    }

    func error() {
        play(.notification(.error))
    }

    func play(_ feedback: Feedback) {
        guard canPlayHaptics else { return }
        prepareGeneratorsIfNeeded()

        switch feedback {
        case let .impact(style, intensity):
            let generator = impactGenerator(for: style)
            if let intensity {
                generator.impactOccurred(intensity: intensity)
            } else {
                generator.impactOccurred()
            }
        case let .notification(type):
            notificationGenerator.prepare()
            notificationGenerator.notificationOccurred(type)
        case .selection:
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        }
    }

    private var canPlayHaptics: Bool {
        mode == .live && supportsHaptics
    }

    private var hasPreparedGenerators = false

    private func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light:
            lightImpactGenerator.prepare()
            return lightImpactGenerator
        case .medium:
            mediumImpactGenerator.prepare()
            return mediumImpactGenerator
        case .heavy:
            heavyImpactGenerator.prepare()
            return heavyImpactGenerator
        case .soft:
            softImpactGenerator.prepare()
            return softImpactGenerator
        case .rigid:
            rigidImpactGenerator.prepare()
            return rigidImpactGenerator
        @unknown default:
            mediumImpactGenerator.prepare()
            return mediumImpactGenerator
        }
    }

    private func prepareGeneratorsIfNeeded() {
        guard mode == .live, supportsHaptics, !hasPreparedGenerators else { return }
        softImpactGenerator.prepare()
        lightImpactGenerator.prepare()
        mediumImpactGenerator.prepare()
        rigidImpactGenerator.prepare()
        heavyImpactGenerator.prepare()
        selectionGenerator.prepare()
        notificationGenerator.prepare()
        hasPreparedGenerators = true
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
