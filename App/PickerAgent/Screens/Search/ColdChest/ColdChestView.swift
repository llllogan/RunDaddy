import SwiftUI

struct ColdChestView: View {
    let session: AuthSession

    @State private var skus: [SKU] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var isShowingAddSheet = false
    @State private var removingSkuIds: Set<String> = []

    private let skusService: SkusServicing = SkusService()

    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView("Loading SKUs…")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if skus.isEmpty {
                Section {
                    Text("No SKUs are in the cold chest.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Section {
                    ForEach(skus) { sku in
                        NavigationLink(destination: SkuDetailView(skuId: sku.id, session: session)) {
                            EntityResultRow(
                                result: SearchResult(
                                    id: sku.id,
                                    type: "sku",
                                    title: sku.code,
                                    subtitle: sku.name
                                )
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                Task { await removeFromColdChest(sku) }
                            } label: {
                                Label("Remove", systemImage: "minus.circle.fill")
                            }
                            .tint(.orange)
                            .disabled(removingSkuIds.contains(sku.id))
                        }
                    }
                } header: {
                    Text("\(skus.count) SKU\(skus.count == 1 ? "" : "s")")
                }
            }
        }
        .navigationTitle("Cold Chest")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            SkuBulkActionView(mode: .addToColdChest) {
                Task { await load(force: true) }
            }
        }
        .refreshable {
            await load(force: true)
        }
        .onAppear {
            loadTask?.cancel()
            loadTask = Task {
                await load(force: true)
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    @MainActor
    private func load(force: Bool) async {
        if !force, isLoading == false, skus.isEmpty == false {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let loadedSkus = try await skusService.getColdChestSkus()
            skus = loadedSkus
            isLoading = false
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Unable to load cold chest SKUs right now."
            skus = []
            isLoading = false
        }
    }

    @MainActor
    private func removeFromColdChest(_ sku: SKU) async {
        if removingSkuIds.contains(sku.id) {
            return
        }

        removingSkuIds.insert(sku.id)
        errorMessage = nil

        do {
            try await skusService.updateColdChestStatus(id: sku.id, isFreshOrFrozen: false)
            withAnimation(.easeInOut(duration: 0.2)) {
                skus.removeAll(where: { $0.id == sku.id })
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Unable to remove this SKU from the cold chest right now."
        }

        removingSkuIds.remove(sku.id)
    }
}
