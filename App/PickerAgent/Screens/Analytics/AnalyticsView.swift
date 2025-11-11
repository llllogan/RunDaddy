//
//  AnalyticsView.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/11/2025.
//

import SwiftUI

struct AnalyticsView: View {
    let session: AuthSession
    
    var body: some View {
        List {
            Section("Analytics") {
                DailyInsightsChartView(session: session)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
    }
}