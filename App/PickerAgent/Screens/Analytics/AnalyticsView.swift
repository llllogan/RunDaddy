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
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var showingSearchResults = false
    @StateObject private var chartsViewModel: ChartsViewModel
    private let searchService = SearchService()

    init(session: AuthSession) {
        self.session = session
        _chartsViewModel = StateObject(wrappedValue: ChartsViewModel(session: session))
    }
    
    var body: some View {
        NavigationStack {
            List {
                if showingSearchResults && !searchResults.isEmpty {
                    Section("Search Results") {
                        ForEach(searchResults) { result in
                            NavigationLink(destination: destinationView(for: result)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.headline)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                
                Section("Total Items vs Packed") {
                    DailyInsightsChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                Section("Packing Pace") {
                    PeriodComparisonChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
                Section("Top Locations") {
                    TopLocationsChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                }
                Section("Top SKUs") {
                    TopSkusChartView(viewModel: chartsViewModel, refreshTrigger: chartRefreshTrigger)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search locations, machines, SKUs...")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    showingSearchResults = false
                    searchResults = []
                }
            }
            .refreshable {
                chartRefreshTrigger.toggle()
            }
            .onChange(of: session, initial: false) { _, newSession in
                chartsViewModel.updateSession(newSession)
            }
            .overlay {
                if isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                }
            }
        }
    }
    
    @ViewBuilder
    private func destinationView(for result: SearchResult) -> some View {
        switch result.type {
        case "machine":
            MachineDetailView(machineId: result.id, session: session)
        case "location":
            SearchLocationDetailView(locationId: result.id, session: session)
        case "sku":
            SkuDetailView(skuId: result.id, session: session)
        default:
            Text("Unknown result type")
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showingSearchResults = false
            searchResults = []
            return
        }
        
        isSearching = true
        Task {
            do {
                let response = try await searchService.search(query: searchText)
                await MainActor.run {
                    searchResults = response.results
                    showingSearchResults = true
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    isSearching = false
                    // Could show error message here
                }
            }
        }
    }
}
