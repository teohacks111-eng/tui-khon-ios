import Foundation
import Testing
@testable import TuiKhon

struct MoneyAmountTests {
    @Test
    func formatsVietnameseDongWithGrouping() {
        #expect(MoneyAmount(minorUnits: 1_250_000).formatted == "1.250.000 ₫")
    }

    @Test
    func formatsZero() {
        #expect(MoneyAmount(minorUnits: 0).formatted == "0 ₫")
    }

    @Test
    func formatsNegativeAmountWithoutFloatingPoint() {
        #expect(MoneyAmount(minorUnits: -35_000).formatted == "−35.000 ₫")
    }

    @Test
    func preservesForeignCurrencyCode() {
        #expect(MoneyAmount(minorUnits: 123_456, currencyCode: "usd").formatted == "123.456 USD")
    }
}

struct LedgerMathTests {
    @Test
    func incomeExpenseAndTransferProduceCorrectTotalsAndWalletBalances() {
        let cash = "cash"
        let bank = "bank"
        let result = LedgerCalculator.calculate([
            LedgerEntry(amount: 1_000_000, type: .income, sourceWalletID: cash),
            LedgerEntry(amount: 350_000, type: .expense, sourceWalletID: cash),
            LedgerEntry(amount: 200_000, type: .transfer, sourceWalletID: cash, destinationWalletID: bank)
        ])
        #expect(result.income == 1_000_000)
        #expect(result.expense == 350_000)
        #expect(result.netBalance == 650_000)
        #expect(result.walletBalances.first(where: { $0.walletID == cash })?.balance == 450_000)
        #expect(result.walletBalances.first(where: { $0.walletID == bank })?.balance == 200_000)
    }

    @Test
    func transferDoesNotChangeIncomeOrExpenseAndPreservesNetBalance() {
        let cash = "cash"
        let bank = "bank"
        let result = LedgerCalculator.calculate(
            [LedgerEntry(amount: 500_000, type: .transfer, sourceWalletID: cash, destinationWalletID: bank)],
            openingBalances: [cash: 700_000]
        )
        #expect(result.income == 0)
        #expect(result.expense == 0)
        #expect(result.netBalance == 700_000)
        #expect(result.walletBalances.first(where: { $0.walletID == cash })?.balance == 200_000)
        #expect(result.walletBalances.first(where: { $0.walletID == bank })?.balance == 500_000)
    }

    @Test
    func incomeAndExpenseHaveOppositeEffectsOnSameWallet() {
        let wallet = "cash"
        let result = LedgerCalculator.calculate([
            LedgerEntry(amount: 1_000_000, type: .income, sourceWalletID: wallet),
            LedgerEntry(amount: 350_000, type: .expense, sourceWalletID: wallet)
        ])
        #expect(result.income == 1_000_000)
        #expect(result.expense == 350_000)
        #expect(result.netBalance == 650_000)
        #expect(result.walletBalances.first?.balance == 650_000)
    }
}

#if canImport(CoreData)
import CoreData

struct CoreDataModelTests {
    @Test @MainActor
    func declaresExactEntityAttributeAndRelationshipContracts() {
        let model = PersistenceController.makeManagedObjectModel()

        let expectedAttributes: [String: Set<String>] = [
            FinancialRecordEntityName.transaction: [
                "id", "amount", "currencyCode", "type", "date", "note", "merchant",
                "tagsJSON", "receiptImageData", "excludeFromReports", "source", "status",
                "createdAt", "updatedAt", "deletedAt"
            ],
            FinancialRecordEntityName.category: [
                "id", "name", "icon", "colorHex", "type", "sortOrder", "isArchived", "createdAt"
            ],
            FinancialRecordEntityName.wallet: [
                "id", "name", "type", "currencyCode", "initialBalance", "isArchived", "createdAt"
            ],
            FinancialRecordEntityName.budget: [
                "id", "period", "amount", "rolloverEnabled", "createdAt", "updatedAt"
            ],
            FinancialRecordEntityName.recurringRule: [
                "id", "title", "amount", "currencyCode", "type", "frequency",
                "nextOccurrence", "reminderDaysBefore", "isEnabled", "createdAt"
            ],
            FinancialRecordEntityName.goal: [
                "id", "title", "targetAmount", "savedAmount", "currencyCode",
                "targetDate", "isArchived", "createdAt"
            ],
            FinancialRecordEntityName.debt: [
                "id", "personName", "direction", "principalAmount", "paidAmount",
                "currencyCode", "dueDate", "note", "createdAt"
            ],
            FinancialRecordEntityName.merchantRule: [
                "id", "keyword", "matchCount", "updatedAt"
            ],
            FinancialRecordEntityName.appSettings: [
                "id", "financialMonthStartDay", "baseCurrencyCode", "faceIDEnabled",
                "balancesHidden", "createdAt", "updatedAt"
            ]
        ]

        let expectedRelationships: [String: Set<String>] = [
            FinancialRecordEntityName.transaction: ["category", "wallet", "destinationWallet"],
            FinancialRecordEntityName.category: ["transactions", "parent", "children", "budgets", "merchantRules"],
            FinancialRecordEntityName.wallet: ["transactions", "incomingTransfers", "settings"],
            FinancialRecordEntityName.budget: ["category"],
            FinancialRecordEntityName.recurringRule: [],
            FinancialRecordEntityName.goal: [],
            FinancialRecordEntityName.debt: [],
            FinancialRecordEntityName.merchantRule: ["category"],
            FinancialRecordEntityName.appSettings: ["defaultWallet"]
        ]

        #expect(Set(model.entities.compactMap(\.name)) == Set(expectedAttributes.keys))

        for (name, attributes) in expectedAttributes {
            guard let entity = model.entitiesByName[name] else {
                #expect(Bool(false), "Thiếu entity \(name)")
                continue
            }
            #expect(Set(entity.attributesByName.keys) == attributes)
            #expect(Set(entity.relationshipsByName.keys) == (expectedRelationships[name] ?? []))
        }

        #expect(model.entities.allSatisfy { $0.uniquenessConstraints.isEmpty })
        #expect(model.entities.flatMap(\.properties).allSatisfy { property in
            if let attribute = property as? NSAttributeDescription {
                return attribute.isOptional || attribute.defaultValue != nil
            }
            if let relationship = property as? NSRelationshipDescription {
                return relationship.isOptional && relationship.inverseRelationship != nil
            }
            return false
        })
    }

    @Test @MainActor
    func allSwiftUIFetchRequestsNameTheirCoreDataEntitiesExplicitly() {
        let transactions = FinanceRepository.transactionFetchRequest()
        let wallets = FinanceRepository.walletFetchRequest()
        let budgets = FinanceRepository.budgetFetchRequest()

        #expect(transactions.entityName == FinancialRecordEntityName.transaction)
        #expect(transactions.predicate?.predicateFormat == "deletedAt == nil")
        #expect(transactions.sortDescriptors?.first?.key == "date")

        #expect(wallets.entityName == FinancialRecordEntityName.wallet)
        #expect(wallets.predicate?.predicateFormat == "isArchived == NO")
        #expect(wallets.sortDescriptors?.first?.key == "createdAt")

        #expect(budgets.entityName == FinancialRecordEntityName.budget)
        #expect(budgets.predicate?.predicateFormat == "period == \"monthly\"")
        #expect(budgets.sortDescriptors?.first?.key == "createdAt")
    }

    @Test @MainActor
    func walletAndTransactionCRUDUpdatesOverviewWithoutCrashing() throws {
        let context = try makeInMemoryContext()
        let repository = FinanceRepository(context: context)
        let date = Date()

        let firstWallet = try repository.ensureDefaultWallet()
        let secondWallet = try repository.ensureDefaultWallet()
        #expect(firstWallet.objectID == secondWallet.objectID)
        #expect(firstWallet.value(forKey: "name") as? String == "Tiền mặt")
        #expect(firstWallet.value(forKey: "currencyCode") as? String == "VND")

        let income = try repository.addTransaction(
            amount: 100_000,
            kind: .income,
            date: date,
            note: "Lương",
            merchant: "Công việc"
        )
        let expense = try repository.addTransaction(
            amount: 25_000,
            kind: .expense,
            date: date,
            note: "Ăn sáng",
            merchant: "Ăn uống"
        )

        guard
            let incomeID = income.value(forKey: "id") as? UUID,
            let expenseID = expense.value(forKey: "id") as? UUID
        else {
            throw FinanceRepositoryError.transactionNotFound
        }

        let initial = try repository.overview(referenceDate: date)
        #expect(initial.balance == 75_000)
        #expect(initial.incomeThisMonth == 100_000)
        #expect(initial.expenseThisMonth == 25_000)
        #expect(initial.transactionCount == 2)

        try repository.updateTransaction(
            id: expenseID,
            amount: 30_000,
            kind: .expense,
            date: date,
            note: "Ăn trưa",
            merchant: "Ăn uống"
        )
        let updated = try repository.overview(referenceDate: date)
        #expect(updated.balance == 70_000)
        #expect(updated.expenseThisMonth == 30_000)

        try repository.deleteTransaction(id: expenseID)
        let afterDelete = try repository.overview(referenceDate: date)
        #expect(afterDelete.balance == 100_000)
        #expect(afterDelete.incomeThisMonth == 100_000)
        #expect(afterDelete.expenseThisMonth == 0)
        #expect(afterDelete.transactionCount == 1)

        try repository.deleteTransaction(id: incomeID)
        let empty = try repository.overview(referenceDate: date)
        #expect(empty.balance == 0)
        #expect(empty.transactionCount == 0)
    }

    @MainActor
    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: PersistenceController.makeManagedObjectModel()
        )
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil,
            options: nil
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        return context
    }
}

struct LedgerCalculatorTests {
    @Test
    func incomeExpenseAndTransferProduceCorrectTotalsAndWalletBalances() {
        let cash = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let bank = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let entries = [
            LedgerEntry(amount: 1_000_000, type: .income, sourceWalletID: cash),
            LedgerEntry(amount: 350_000, type: .expense, sourceWalletID: cash),
            LedgerEntry(amount: 200_000, type: .transfer, sourceWalletID: cash, destinationWalletID: bank)
        ]

        let result = LedgerCalculator.calculate(entries)

        #expect(result.income == 1_000_000)
        #expect(result.expense == 350_000)
        #expect(result.netBalance == 650_000)
        #expect(result.walletBalances.first(where: { $0.walletID == cash })?.balance == 450_000)
        #expect(result.walletBalances.first(where: { $0.walletID == bank })?.balance == 200_000)
    }

    @Test
    func transferDoesNotInflateIncomeOrExpenseAndPreservesTotalBalance() {
        let cash = "cash"
        let bank = "bank"
        let result = LedgerCalculator.calculate(
            [LedgerEntry(amount: 500_000, type: .transfer, sourceWalletID: cash, destinationWalletID: bank)],
            openingBalances: [cash: 700_000]
        )

        #expect(result.income == 0)
        #expect(result.expense == 0)
        #expect(result.netBalance == 700_000)
        #expect(result.walletBalances.first(where: { $0.walletID == cash })?.balance == 200_000)
        #expect(result.walletBalances.first(where: { $0.walletID == bank })?.balance == 500_000)
    }

    @Test
    func incomeAndExpenseHaveOppositeEffectsOnSameWallet() {
        let wallet = "cash"
        let result = LedgerCalculator.calculate([
            LedgerEntry(amount: 1_000_000, type: .income, sourceWalletID: wallet),
            LedgerEntry(amount: 350_000, type: .expense, sourceWalletID: wallet)
        ])
        #expect(result.income == 1_000_000)
        #expect(result.expense == 350_000)
        #expect(result.netBalance == 650_000)
        #expect(result.walletBalances.first?.balance == 650_000)
    }
}
#endif
