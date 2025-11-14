//
//  HapticsService.swift
//  PickAgent
//
//  Created by Logan Janssen on 14/11/2025.
//

import Foundation
import UIKit
import Combine

final class HapticsService: ObservableObject {
    @MainActor
    static let shared = HapticsService()
    
    @Published private var isPrepared = false
    
    private var impactFeedbackGenerator: UIImpactFeedbackGenerator?
    private var selectionFeedbackGenerator: UISelectionFeedbackGenerator?
    private var notificationFeedbackGenerator: UINotificationFeedbackGenerator?
    
    @MainActor
    private init() {
        setupGenerators()
    }
    
    @MainActor
    private func setupGenerators() {
        impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        notificationFeedbackGenerator = UINotificationFeedbackGenerator()
        
        // Prepare generators for immediate response
        impactFeedbackGenerator?.prepare()
        selectionFeedbackGenerator?.prepare()
        notificationFeedbackGenerator?.prepare()
        
        isPrepared = true
    }
    
    // MARK: - Impact Feedback
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        impactFeedbackGenerator = UIImpactFeedbackGenerator(style: style)
        impactFeedbackGenerator?.impactOccurred()
    }
    
    func lightImpact() {
        impact(.light)
    }
    
    func mediumImpact() {
        impact(.medium)
    }
    
    func heavyImpact() {
        impact(.heavy)
    }
    
    // MARK: - Selection Feedback
    func selection() {
        selectionFeedbackGenerator?.selectionChanged()
    }
    
    // MARK: - Notification Feedback
    func success() {
        notificationFeedbackGenerator?.notificationOccurred(.success)
    }
    
    func warning() {
        notificationFeedbackGenerator?.notificationOccurred(.warning)
    }
    
    func error() {
        notificationFeedbackGenerator?.notificationOccurred(.error)
    }
    
    // MARK: - Context-Specific Methods
    func statusChanged() {
        // Medium impact for status changes
        mediumImpact()
    }
    
    func userAssigned() {
        // Success feedback for user assignments
        success()
    }
    
    func userUnassigned() {
        // Light impact for unassignments
        lightImpact()
    }
    
    func actionCompleted() {
        // Selection feedback for general actions
        selection()
    }
    
    func resetCompleted() {
        // Warning feedback for reset operations
        warning()
    }
}
