/// Transaction amounts are stored as positive values; the ledger applies direction.
public enum TransactionKind: String, CaseIterable, Equatable, Identifiable, Sendable {
    case expense
    case income
    case transfer
    public var id: String { rawValue }
}

public struct LedgerEntry: Equatable, Sendable {
    public let amount: Int64
    public let type: TransactionKind
    public let sourceWalletID: String
    public let destinationWalletID: String?

    public init(amount: Int64, type: TransactionKind, sourceWalletID: String, destinationWalletID: String? = nil) {
        self.amount = amount
        self.type = type
        self.sourceWalletID = sourceWalletID
        self.destinationWalletID = destinationWalletID
    }
}

public struct WalletLedgerBalance: Equatable, Sendable {
    public let walletID: String
    public let balance: Int64
}

public struct LedgerSummary: Equatable, Sendable {
    public let income: Int64
    public let expense: Int64
    public let netBalance: Int64
    public let walletBalances: [WalletLedgerBalance]
}

/// Pure accounting engine used by the repository and deterministic unit tests.
public enum LedgerCalculator {
    public static func calculate(_ entries: [LedgerEntry], openingBalances: [String: Int64] = [:]) -> LedgerSummary {
        var balances = openingBalances
        var income: Int64 = 0
        var expense: Int64 = 0

        for entry in entries where entry.amount > 0 {
            switch entry.type {
            case .income:
                income += entry.amount
                balances[entry.sourceWalletID, default: 0] += entry.amount
            case .expense:
                expense += entry.amount
                balances[entry.sourceWalletID, default: 0] -= entry.amount
            case .transfer:
                guard let destination = entry.destinationWalletID,
                      destination != entry.sourceWalletID else { continue }
                balances[entry.sourceWalletID, default: 0] -= entry.amount
                balances[destination, default: 0] += entry.amount
            }
        }

        let walletBalances = balances.map {
            WalletLedgerBalance(walletID: $0.key, balance: $0.value)
        }.sorted { $0.walletID < $1.walletID }

        return LedgerSummary(
            income: income,
            expense: expense,
            netBalance: walletBalances.reduce(Int64(0)) { $0 + $1.balance },
            walletBalances: walletBalances
        )
    }
}
