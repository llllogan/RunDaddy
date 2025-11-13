import SwiftUI

struct SkuDetailView: View {
    let skuId: String
    let session: AuthSession
    
    @State private var sku: SKU?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading SKU details...")
            } else if let errorMessage = errorMessage {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let sku = sku {
                List {
                    Section("SKU Information") {
                        HStack {
                            Text("Code")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(sku.code)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("Name")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(sku.name)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("Type")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(sku.type)
                                .foregroundColor(.primary)
                        }
                        if let category = sku.category {
                            HStack {
                                Text("Category")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(category)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .navigationTitle(sku.code)
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .task {
            await loadSkuDetails()
        }
    }
    
    private func loadSkuDetails() async {
        do {
            sku = try await SkusService().getSku(id: skuId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}