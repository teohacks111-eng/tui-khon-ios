import Foundation

/// Stable Core Data entity names used by the local persistence model.
/// Relationships are UUID references in Phase 0 so the schema stays explicit
/// and can be migrated without SwiftData macros.
enum FinancialRecordEntityName {
    static let transaction = "TransactionRecord"
    static let category = "CategoryRecord"
    static let wallet = "WalletRecord"
    static let budget = "BudgetRecord"
    static let recurringRule = "RecurringRuleRecord"
    static let goal = "GoalRecord"
    static let debt = "DebtRecord"
    static let merchantRule = "MerchantRuleRecord"
    static let appSettings = "AppSettingsRecord"
}
