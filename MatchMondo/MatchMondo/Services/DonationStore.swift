import StoreKit

@MainActor
final class DonationStore: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var purchaseSucceeded = false
    @Published var purchaseError: String?

    private let productIDs = [
        "com.matchmondo.app.donation.1",
        "com.matchmondo.app.donation.5",
        "com.matchmondo.app.donation.10"
    ]

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = Task {
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                }
            }
        }
        Task { await load() }
    }

    deinit {
        transactionListener?.cancel()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: productIDs)
            print("[DonationStore] Fetched \(fetched.count) products: \(fetched.map { $0.id })")
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            print("[DonationStore] Error loading products: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    purchaseSucceeded = true
                }
            case .userCancelled:
                break
            default:
                purchaseError = "Purchase could not be completed."
            }
        } catch {
            purchaseError = "Purchase failed. Please try again."
        }
    }
}
