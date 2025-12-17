import SwiftUI

struct ColdChestView: View {
    let session: AuthSession

    @State private var skus: [SKU] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadTask: Task<Void, Never>?

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
                    }
                } header: {
                    Text("\(skus.count) SKU\(skus.count == 1 ? "" : "s")")
                }
            }
        }
        .navigationTitle("Cold Chest")
        .navigationBarTitleDisplayMode(.inline)
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
}
