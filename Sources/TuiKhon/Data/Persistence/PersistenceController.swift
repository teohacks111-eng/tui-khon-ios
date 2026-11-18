#if canImport(CoreData)
import Combine
import CoreData
import Foundation

@MainActor
final class PersistenceController: ObservableObject {
    private(set) var container: NSPersistentContainer
    @Published private(set) var isReady = false
    @Published private(set) var loadError: String?

    init() {
        let inMemory = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let storeContainer = Self.makeContainer(inMemory: inMemory)
        container = storeContainer
        Self.configureViewContext(storeContainer.viewContext)
        loadPersistentStores(on: storeContainer, allowRecovery: !inMemory)
    }

    private static func makeContainer(
        storeURL: URL? = nil,
        inMemory: Bool = false
    ) -> NSPersistentContainer {
        let storeContainer = NSPersistentContainer(
            name: "TuiKhon",
            managedObjectModel: makeManagedObjectModel()
        )

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            description.url = nil
            storeContainer.persistentStoreDescriptions = [description]
        } else if let storeURL {
            storeContainer.persistentStoreDescriptions = [
                NSPersistentStoreDescription(url: storeURL)
            ]
        }

        for description in storeContainer.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.setOption(
                NSNumber(value: true),
                forKey: NSMigratePersistentStoresAutomaticallyOption
            )
            description.setOption(
                NSNumber(value: true),
                forKey: NSInferMappingModelAutomaticallyOption
            )
        }
        configureViewContext(storeContainer.viewContext)
        return storeContainer
    }

    private static func configureViewContext(_ context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        context.undoManager = nil
        context.name = "TuiKhon.viewContext"
    }

    private func loadPersistentStores(
        on storeContainer: NSPersistentContainer,
        allowRecovery: Bool
    ) {
        storeContainer.loadPersistentStores { [weak self] description, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    let message = error.localizedDescription
                    CrashLogger.record("Core Data load failed: \(message)")

                    guard allowRecovery, let storeURL = description.url else {
                        self.loadError = message
                        NSLog("Túi Khôn persistent store failed to load: %@", message)
                        return
                    }

                    do {
                        let backupURL = try Self.backupExistingStore(at: storeURL)
                        let recoveredContainer = Self.makeContainer(storeURL: storeURL)
                        self.container = recoveredContainer
                        Self.configureViewContext(recoveredContainer.viewContext)
                        NSLog(
                            "Túi Khôn moved an unreadable store to recovery backup: %@",
                            backupURL.path
                        )
                        self.loadPersistentStores(on: recoveredContainer, allowRecovery: false)
                    } catch {
                        self.loadError = "Không thể mở dữ liệu cũ và cũng không sao lưu được store. Dữ liệu gốc được giữ nguyên. Chi tiết: \(error.localizedDescription)"
                        NSLog("Túi Khôn store recovery failed: %@", error.localizedDescription)
                    }
                    return
                }

                do {
                    let repository = FinanceRepository(context: storeContainer.viewContext)
                    _ = try repository.ensureDefaultWallet()
                    try repository.repairLegacyTransactions()
                    self.isReady = true
                    self.loadError = nil
                } catch {
                    self.loadError = error.localizedDescription
                    CrashLogger.record("Core Data initial repair failed: \(error.localizedDescription)")
                    NSLog("Túi Khôn could not prepare default wallet: %@", error.localizedDescription)
                }
            }
        }
    }

    /// Preserve the previous SQLite database and its WAL/SHM files before
    /// retrying with a clean store. The backup remains in Documents/StoreRecovery.
    private static func backupExistingStore(at storeURL: URL) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: storeURL.path])
        }
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "Documents"])
        }

        let recoveryDirectory = documents.appendingPathComponent("StoreRecovery", isDirectory: true)
        try fileManager.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = recoveryDirectory.appendingPathComponent(
            "\(storeURL.lastPathComponent).\(timestamp).backup",
            isDirectory: false
        )

        // Move the database file first, then its SQLite sidecars with matching names.
        try fileManager.moveItem(at: storeURL, to: backupURL)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: sidecar.path) else { continue }
            let backupSidecar = URL(fileURLWithPath: backupURL.path + suffix)
            try fileManager.moveItem(at: sidecar, to: backupSidecar)
        }
        return backupURL
    }

    /// Nine-entity Core Data model built entirely in Swift; no momc or .xcdatamodeld.
    static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let transaction = entity(FinancialRecordEntityName.transaction, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("amount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("currencyCode", .stringAttributeType, defaultValue: "VND"),
            attribute("type", .stringAttributeType, defaultValue: "expense"),
            attribute("date", .dateAttributeType, optional: true),
            attribute("note", .stringAttributeType, defaultValue: ""),
            attribute("merchant", .stringAttributeType, optional: true),
            attribute("tagsJSON", .binaryDataAttributeType, defaultValue: Data()),
            attribute("receiptImageData", .binaryDataAttributeType, optional: true),
            attribute("excludeFromReports", .booleanAttributeType, defaultValue: false),
            attribute("source", .stringAttributeType, defaultValue: "manual"),
            attribute("status", .stringAttributeType, defaultValue: "confirmed"),
            attribute("createdAt", .dateAttributeType, optional: true),
            attribute("updatedAt", .dateAttributeType, optional: true),
            attribute("deletedAt", .dateAttributeType, optional: true),
        ])
        let category = entity(FinancialRecordEntityName.category, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("name", .stringAttributeType, defaultValue: ""),
            attribute("icon", .stringAttributeType, defaultValue: "tag"),
            attribute("colorHex", .stringAttributeType, defaultValue: "#808080"),
            attribute("type", .stringAttributeType, defaultValue: "expense"),
            attribute("sortOrder", .integer32AttributeType, defaultValue: Int32(0)),
            attribute("isArchived", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType, optional: true),
        ])
        let wallet = entity(FinancialRecordEntityName.wallet, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("name", .stringAttributeType, defaultValue: "Tiền mặt"),
            attribute("type", .stringAttributeType, defaultValue: "cash"),
            attribute("currencyCode", .stringAttributeType, defaultValue: "VND"),
            attribute("initialBalance", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("isArchived", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType, optional: true),
        ])
        let budget = entity(FinancialRecordEntityName.budget, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("period", .stringAttributeType, defaultValue: "monthly"),
            attribute("amount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("rolloverEnabled", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType, optional: true),
            attribute("updatedAt", .dateAttributeType, optional: true),
        ])
        let recurringRule = entity(FinancialRecordEntityName.recurringRule, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("title", .stringAttributeType, defaultValue: ""),
            attribute("amount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("currencyCode", .stringAttributeType, defaultValue: "VND"),
            attribute("type", .stringAttributeType, defaultValue: "expense"),
            attribute("frequency", .stringAttributeType, defaultValue: "monthly"),
            attribute("nextOccurrence", .dateAttributeType, optional: true),
            attribute("reminderDaysBefore", .integer32AttributeType, defaultValue: Int32(0)),
            attribute("isEnabled", .booleanAttributeType, defaultValue: true),
            attribute("createdAt", .dateAttributeType, optional: true),
        ])
        let goal = entity(FinancialRecordEntityName.goal, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("title", .stringAttributeType, defaultValue: ""),
            attribute("targetAmount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("savedAmount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("currencyCode", .stringAttributeType, defaultValue: "VND"),
            attribute("targetDate", .dateAttributeType, optional: true),
            attribute("isArchived", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType, optional: true),
        ])
        let debt = entity(FinancialRecordEntityName.debt, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("personName", .stringAttributeType, defaultValue: ""),
            attribute("direction", .stringAttributeType, defaultValue: "lent"),
            attribute("principalAmount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("paidAmount", .integer64AttributeType, defaultValue: Int64(0)),
            attribute("currencyCode", .stringAttributeType, defaultValue: "VND"),
            attribute("dueDate", .dateAttributeType, optional: true),
            attribute("note", .stringAttributeType, defaultValue: ""),
            attribute("createdAt", .dateAttributeType, optional: true),
        ])
        let merchantRule = entity(FinancialRecordEntityName.merchantRule, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("keyword", .stringAttributeType, defaultValue: ""),
            attribute("matchCount", .integer32AttributeType, defaultValue: Int32(0)),
            attribute("updatedAt", .dateAttributeType, optional: true),
        ])
        let appSettings = entity(FinancialRecordEntityName.appSettings, attributes: [
            attribute("id", .UUIDAttributeType, optional: true),
            attribute("financialMonthStartDay", .integer32AttributeType, defaultValue: Int32(1)),
            attribute("baseCurrencyCode", .stringAttributeType, defaultValue: "VND"),
            attribute("faceIDEnabled", .booleanAttributeType, defaultValue: false),
            attribute("balancesHidden", .booleanAttributeType, defaultValue: false),
            attribute("createdAt", .dateAttributeType, optional: true),
            attribute("updatedAt", .dateAttributeType, optional: true),
        ])

        model.entities = [
            transaction, category, wallet, budget, recurringRule,
            goal, debt, merchantRule, appSettings,
        ]

        let transactionCategory = relationship("category", destination: category, toMany: false)
        let categoryTransactions = relationship("transactions", destination: transaction, toMany: true)
        connect(transactionCategory, to: categoryTransactions)

        let transactionWallet = relationship("wallet", destination: wallet, toMany: false)
        let walletTransactions = relationship("transactions", destination: transaction, toMany: true)
        connect(transactionWallet, to: walletTransactions)

        let transactionDestinationWallet = relationship("destinationWallet", destination: wallet, toMany: false)
        let walletIncomingTransfers = relationship("incomingTransfers", destination: transaction, toMany: true)
        connect(transactionDestinationWallet, to: walletIncomingTransfers)

        let categoryParent = relationship("parent", destination: category, toMany: false)
        let categoryChildren = relationship("children", destination: category, toMany: true)
        connect(categoryParent, to: categoryChildren)

        let budgetCategory = relationship("category", destination: category, toMany: false)
        let categoryBudgets = relationship("budgets", destination: budget, toMany: true)
        connect(budgetCategory, to: categoryBudgets)

        let merchantRuleCategory = relationship("category", destination: category, toMany: false)
        let categoryMerchantRules = relationship("merchantRules", destination: merchantRule, toMany: true)
        connect(merchantRuleCategory, to: categoryMerchantRules)

        let settingsDefaultWallet = relationship("defaultWallet", destination: wallet, toMany: false)
        let walletSettings = relationship("settings", destination: appSettings, toMany: true)
        connect(settingsDefaultWallet, to: walletSettings)

        transaction.properties += [
            transactionCategory, transactionWallet, transactionDestinationWallet,
        ]
        category.properties += [
            categoryTransactions, categoryParent, categoryChildren,
            categoryBudgets, categoryMerchantRules,
        ]
        wallet.properties += [walletTransactions, walletIncomingTransfers, walletSettings]
        budget.properties += [budgetCategory]
        merchantRule.properties += [merchantRuleCategory]
        appSettings.properties += [settingsDefaultWallet]

        return model
    }

    private static func entity(
        _ name: String,
        attributes: [NSAttributeDescription]
    ) -> NSEntityDescription {
        let result = NSEntityDescription()
        result.name = name
        result.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        result.properties = attributes
        return result
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let result = NSAttributeDescription()
        result.name = name
        result.attributeType = type
        result.isOptional = optional
        result.defaultValue = defaultValue
        return result
    }

    private static func relationship(
        _ name: String,
        destination: NSEntityDescription,
        toMany: Bool
    ) -> NSRelationshipDescription {
        let result = NSRelationshipDescription()
        result.name = name
        result.destinationEntity = destination
        result.minCount = 0
        result.maxCount = toMany ? 0 : 1
        result.isOptional = true
        result.deleteRule = .nullifyDeleteRule
        return result
    }

    private static func connect(
        _ relationship: NSRelationshipDescription,
        to inverse: NSRelationshipDescription
    ) {
        relationship.inverseRelationship = inverse
        inverse.inverseRelationship = relationship
    }
}
#endif
