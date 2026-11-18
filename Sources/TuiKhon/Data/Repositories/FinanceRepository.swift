#if canImport(CoreData)
import CoreData
import Foundation

enum FinanceRepositoryError: LocalizedError {
    case invalidAmount
    case entityUnavailable(String)
    case transactionNotFound
    case walletNotFound
    case invalidTransfer

    var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Số tiền phải lớn hơn 0."
        case .entityUnavailable(let name): return "Không tìm thấy cấu trúc dữ liệu: \(name)."
        case .transactionNotFound: return "Giao dịch không còn tồn tại hoặc đã bị xóa."
        case .walletNotFound: return "Không tìm thấy ví đã chọn."
        case .invalidTransfer: return "Chuyển ví cần chọn hai ví khác nhau."
        }
    }
}

struct FinanceOverview: Equatable {
    let balance: Int64
    let incomeThisMonth: Int64
    let expenseThisMonth: Int64
    let transactionCount: Int
}

@MainActor
final class FinanceRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func ensureDefaultWallet() throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.wallet)
        request.predicate = NSPredicate(format: "name == %@ AND isArchived == NO", "Tiền mặt")
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first { return existing }

        let wallet = try makeObject(entityName: FinancialRecordEntityName.wallet)
        wallet.setValue(UUID(), forKey: "id")
        wallet.setValue("Tiền mặt", forKey: "name")
        wallet.setValue("cash", forKey: "type")
        wallet.setValue("VND", forKey: "currencyCode")
        wallet.setValue(Int64(0), forKey: "initialBalance")
        wallet.setValue(false, forKey: "isArchived")
        wallet.setValue(Date(), forKey: "createdAt")
        try save()
        return wallet
    }

    func wallets() throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.wallet)
        request.predicate = NSPredicate(format: "isArchived == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    @discardableResult
    func addWallet(name: String, openingBalance: Int64 = 0, type: String = "bank") throws -> NSManagedObject {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw FinanceRepositoryError.walletNotFound }
        let wallet = try makeObject(entityName: FinancialRecordEntityName.wallet)
        wallet.setValue(UUID(), forKey: "id")
        wallet.setValue(cleanName, forKey: "name")
        wallet.setValue(type, forKey: "type")
        wallet.setValue("VND", forKey: "currencyCode")
        wallet.setValue(openingBalance, forKey: "initialBalance")
        wallet.setValue(false, forKey: "isArchived")
        wallet.setValue(Date(), forKey: "createdAt")
        try save()
        return wallet
    }

    @discardableResult
    func addTransaction(
        amount: Int64,
        kind: TransactionKind,
        date: Date = Date(),
        note: String = "",
        merchant: String = "",
        sourceWalletID: UUID? = nil,
        destinationWalletID: UUID? = nil,
        categoryName: String? = nil
    ) throws -> NSManagedObject {
        guard amount > 0 else { throw FinanceRepositoryError.invalidAmount }
        let defaultWallet = try ensureDefaultWallet()
        let sourceWallet = try sourceWalletID.map(fetchWallet(id:)) ?? defaultWallet
        let destinationWallet: NSManagedObject?
        if kind == .transfer {
            guard let destinationWalletID, destinationWalletID != sourceWalletID,
                  destinationWalletID != (sourceWallet.value(forKey: "id") as? UUID) else {
                throw FinanceRepositoryError.invalidTransfer
            }
            destinationWallet = try fetchWallet(id: destinationWalletID)
        } else {
            destinationWallet = nil
        }

        let record = try makeObject(entityName: FinancialRecordEntityName.transaction)
        record.setValue(UUID(), forKey: "id")
        record.setValue(amount, forKey: "amount")
        record.setValue("VND", forKey: "currencyCode")
        record.setValue(kind.rawValue, forKey: "type")
        record.setValue(date, forKey: "date")
        record.setValue(note.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "note")
        record.setValue(merchant.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "merchant")
        record.setValue("manual", forKey: "source")
        record.setValue("confirmed", forKey: "status")
        record.setValue(Date(), forKey: "createdAt")
        record.setValue(Date(), forKey: "updatedAt")
        record.setValue(sourceWallet, forKey: "wallet")
        record.setValue(destinationWallet, forKey: "destinationWallet")

        if let categoryName, kind != .transfer {
            record.setValue(try ensureCategory(named: categoryName, kind: kind), forKey: "category")
        }
        try save()
        return record
    }

    func updateTransaction(
        id: UUID,
        amount: Int64,
        kind: TransactionKind,
        date: Date,
        note: String,
        merchant: String,
        sourceWalletID: UUID? = nil,
        destinationWalletID: UUID? = nil,
        categoryName: String? = nil
    ) throws {
        guard amount > 0 else { throw FinanceRepositoryError.invalidAmount }
        let record = try fetchTransaction(id: id)
        let sourceWallet = try sourceWalletID.map(fetchWallet(id:))
            ?? (record.value(forKey: "wallet") as? NSManagedObject)
            ?? ensureDefaultWallet()
        let destinationWallet: NSManagedObject?
        if kind == .transfer {
            guard let destinationWalletID,
                  destinationWalletID != (sourceWallet.value(forKey: "id") as? UUID) else {
                throw FinanceRepositoryError.invalidTransfer
            }
            destinationWallet = try fetchWallet(id: destinationWalletID)
        } else {
            destinationWallet = nil
        }
        record.setValue(amount, forKey: "amount")
        record.setValue(kind.rawValue, forKey: "type")
        record.setValue(date, forKey: "date")
        record.setValue(note.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "note")
        record.setValue(merchant.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "merchant")
        record.setValue(sourceWallet, forKey: "wallet")
        record.setValue(destinationWallet, forKey: "destinationWallet")
        record.setValue(categoryName.flatMap { try? ensureCategory(named: $0, kind: kind) }, forKey: "category")
        record.setValue(Date(), forKey: "updatedAt")
        try save()
    }

    func deleteTransaction(id: UUID) throws {
        let record = try fetchTransaction(id: id)
        record.setValue(Date(), forKey: "deletedAt")
        record.setValue(Date(), forKey: "updatedAt")
        try save()
    }

    func restoreTransaction(id: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.transaction)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        guard let record = try context.fetch(request).first else {
            throw FinanceRepositoryError.transactionNotFound
        }
        record.setValue(nil, forKey: "deletedAt")
        record.setValue(Date(), forKey: "updatedAt")
        try save()
    }

    /// Backfills pre-Phase-1 records to the default wallet and repairs income
    /// records whose category or Vietnamese title clearly identifies them as income.
    func repairLegacyTransactions() throws {
        let defaultWallet = try ensureDefaultWallet()
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.transaction)
        let records = try context.fetch(request)
        let incomeTerms = ["lương", "thưởng", "freelance", "tiền lãi", "lãi tiết kiệm", "hoa hồng"]
        var changed = false

        for record in records {
            if record.value(forKey: "wallet") == nil {
                record.setValue(defaultWallet, forKey: "wallet")
                changed = true
            }

            guard record.value(forKey: "type") as? String == TransactionKind.expense.rawValue else {
                continue
            }
            let category = record.value(forKey: "category") as? NSManagedObject
            let categoryType = category?.value(forKey: "type") as? String
            let categoryName = category?.value(forKey: "name") as? String ?? ""
            let note = record.value(forKey: "note") as? String ?? ""
            let merchant = record.value(forKey: "merchant") as? String ?? ""
            let descriptor = "\(categoryName) \(note) \(merchant)".folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "vi_VN")
            )
            let isKnownIncomeCategory = categoryType == TransactionKind.income.rawValue
                || incomeTerms.contains { term in
                    descriptor.contains(term.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN")))
                }
            if isKnownIncomeCategory {
                record.setValue(TransactionKind.income.rawValue, forKey: "type")
                record.setValue(Date(), forKey: "updatedAt")
                changed = true
            }
        }
        if changed { try save() }
    }

    func overview(referenceDate: Date = Date()) throws -> FinanceOverview {
        let records = try context.fetch(Self.transactionFetchRequest())
        let calendar = Calendar.current
        let monthRecords = records.filter { record in
            guard let date = record.value(forKey: "date") as? Date else { return false }
            return calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
                && calendar.isDate(date, equalTo: referenceDate, toGranularity: .year)
        }
        let income = monthRecords.filter { $0.value(forKey: "type") as? String == TransactionKind.income.rawValue }
            .reduce(Int64(0)) { $0 + amount(of: $1) }
        let expense = monthRecords.filter { $0.value(forKey: "type") as? String == TransactionKind.expense.rawValue }
            .reduce(Int64(0)) { $0 + amount(of: $1) }
        let balances = try walletBalances()
        return FinanceOverview(
            balance: balances.reduce(Int64(0)) { $0 + $1.value },
            incomeThisMonth: income,
            expenseThisMonth: expense,
            transactionCount: records.count
        )
    }

    func walletBalances() throws -> [(id: UUID, name: String, value: Int64)] {
        let wallets = try self.wallets()
        let records = try context.fetch(Self.transactionFetchRequest())
        return wallets.compactMap { wallet in
            guard let id = wallet.value(forKey: "id") as? UUID else { return nil }
            var balance = (wallet.value(forKey: "initialBalance") as? NSNumber)?.int64Value ?? 0
            for record in records {
                let sourceID = (record.value(forKey: "wallet") as? NSManagedObject)?.value(forKey: "id") as? UUID
                let destinationID = (record.value(forKey: "destinationWallet") as? NSManagedObject)?.value(forKey: "id") as? UUID
                let amount = amount(of: record)
                switch record.value(forKey: "type") as? String {
                case TransactionKind.income.rawValue where sourceID == id: balance += amount
                case TransactionKind.expense.rawValue where sourceID == id: balance -= amount
                case TransactionKind.transfer.rawValue:
                    if sourceID == id { balance -= amount }
                    if destinationID == id { balance += amount }
                default: break
                }
            }
            return (id, wallet.value(forKey: "name") as? String ?? "Ví", balance)
        }
    }

    static func transactionFetchRequest() -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.transaction)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.predicate = NSPredicate(format: "deletedAt == nil")
        return request
    }

    static func walletFetchRequest() -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.wallet)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.predicate = NSPredicate(format: "isArchived == NO")
        return request
    }

    static func budgetFetchRequest() -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.budget)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.predicate = NSPredicate(format: "period == %@", "monthly")
        return request
    }

    private func ensureCategory(named name: String, kind: TransactionKind) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.category)
        request.predicate = NSPredicate(format: "name ==[c] %@ AND type == %@ AND isArchived == NO", name, kind.rawValue)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first { return existing }
        let category = try makeObject(entityName: FinancialRecordEntityName.category)
        category.setValue(UUID(), forKey: "id")
        category.setValue(name, forKey: "name")
        category.setValue(kind.rawValue, forKey: "type")
        category.setValue("tag", forKey: "icon")
        category.setValue("#64748B", forKey: "colorHex")
        category.setValue(Int32(0), forKey: "sortOrder")
        category.setValue(false, forKey: "isArchived")
        category.setValue(Date(), forKey: "createdAt")
        return category
    }

    private func fetchWallet(id: UUID) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: FinancialRecordEntityName.wallet)
        request.predicate = NSPredicate(format: "id == %@ AND isArchived == NO", id as NSUUID)
        request.fetchLimit = 1
        guard let wallet = try context.fetch(request).first else { throw FinanceRepositoryError.walletNotFound }
        return wallet
    }

    private func fetchTransaction(id: UUID) throws -> NSManagedObject {
        let request = Self.transactionFetchRequest()
        request.predicate = NSPredicate(format: "id == %@ AND deletedAt == nil", id as NSUUID)
        request.fetchLimit = 1
        guard let record = try context.fetch(request).first else { throw FinanceRepositoryError.transactionNotFound }
        return record
    }

    private func amount(of record: NSManagedObject) -> Int64 {
        (record.value(forKey: "amount") as? NSNumber)?.int64Value ?? 0
    }

    private func makeObject(entityName: String) throws -> NSManagedObject {
        guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: context) else {
            throw FinanceRepositoryError.entityUnavailable(entityName)
        }
        return NSManagedObject(entity: entity, insertInto: context)
    }

    private func save() throws {
        do {
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
    }
}
#endif
