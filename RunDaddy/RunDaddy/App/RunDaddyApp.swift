//
//  RunDaddyApp.swift
//  RunDaddy
//
//  Created by Logan Janssen on 12/10/2025.
//

import SwiftUI
import SwiftData

@main
struct RunDaddyApp: App {
    @StateObject private var sessionController = PackingSessionController()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Run.self,
            RunCoil.self,
            Coil.self,
            Machine.self,
            Location.self,
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(sessionController)
                .environment(\.haptics, HapticFeedbackService.live)
        }
        .modelContainer(sharedModelContainer)
    }
}
