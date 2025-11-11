//
//  AnalyticsView.swift
//  PickAgent
//
//  Created by Logan Janssen on 11/11/2025.
//

import SwiftUI

struct AnalyticsView: View {
    let session: AuthSession
    
    @State private var chartRefreshTrigger = false
    @StateObject private var chartsViewModel: ChartsViewModel

    init(session: AuthSession) {
        self.session = session
        _chartsViewModel = StateObject(wrappedValue: ChartsViewModel(session: session))
    }
    
    var body: some View {
        List {
            Section("Total Items vs Packed") {
                DailyInsightsChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section("Top Locations") {
                TopLocationsChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            chartRefreshTrigger.toggle()
        }
    }
}
