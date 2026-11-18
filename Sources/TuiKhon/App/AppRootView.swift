#if canImport(SwiftUI) && canImport(CoreData)
import SwiftUI
import CoreData
import Charts
import UIKit

@MainActor
struct AppRootView: View {
    @Environment(\.managedObjectContext) private var context
    @State private var selectedTab = 0
    @State private var newTransactionKind: TransactionKind?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem { Label("Tổng quan", systemImage: "square.grid.2x2") }
                    .tag(0)
                TransactionsTabView()
                    .tabItem { Label("Giao dịch", systemImage: "list.bullet.rectangle") }
                    .tag(1)
                BudgetsTabView()
                    .tabItem { Label("Ngân sách", systemImage: "chart.pie") }
                    .tag(2)
                ReportsTabView()
                    .tabItem { Label("Báo cáo", systemImage: "chart.bar") }
                    .tag(3)
                SettingsTabView()
                    .tabItem { Label("Cài đặt", systemImage: "gearshape") }
                    .tag(4)
            }
            .tint(.green)

            Button {
                CrashLogger.record("Tap FAB: mở form thêm giao dịch; tab=\(selectedTab)")
                newTransactionKind = .expense
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.green, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            }
            .accessibilityLabel("Thêm giao dịch")
            .accessibilityIdentifier("app.addTransaction")
            .padding(.trailing, 22)
            .padding(.bottom, 82)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            CrashLogger.record("Tab changed: \(oldValue) -> \(newValue)")
        }
        .sheet(item: $newTransactionKind) { selectedKind in
            TransactionEntryView(kind: selectedKind)
                .environment(\.managedObjectContext, context)
        }
    }
}

@MainActor
private struct TransactionsTabView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: FinanceRepository.transactionFetchRequest(), animation: .default)
    private var transactions: FetchedResults<NSManagedObject>
    @State private var query = ""

    private var filtered: [NSManagedObject] {
        guard !query.isEmpty else { return Array(transactions) }
        return transactions.filter {
            (($0.value(forKey: "note") as? String) ?? "").localizedCaseInsensitiveContains(query)
                || (($0.value(forKey: "merchant") as? String) ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView("Chưa có giao dịch", systemImage: "tray")
                } else {
                    ForEach(filtered, id: \.objectID) { record in
                        TransactionListRow(record: record)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    guard let id = record.value(forKey: "id") as? UUID else { return }
                                    do { try FinanceRepository(context: context).deleteTransaction(id: id) }
                                    catch { NSLog("Delete transaction failed: %@", error.localizedDescription) }
                                } label: { Label("Xóa", systemImage: "trash") }
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.bottom, 88, for: .scrollContent)
            .navigationTitle("Giao dịch")
            .searchable(text: $query, prompt: "Tìm ghi chú hoặc danh mục")
        }
    }
}

private struct TransactionListRow: View {
    let record: NSManagedObject
    var body: some View {
        let type = TransactionKind(rawValue: record.value(forKey: "type") as? String ?? "expense") ?? .expense
        let amount = (record.value(forKey: "amount") as? NSNumber)?.int64Value ?? 0
        let title = (record.value(forKey: "note") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Giao dịch"
        let date = record.value(forKey: "date") as? Date ?? Date()
        HStack {
            Image(systemName: type == .income ? "arrow.down.left" : (type == .transfer ? "arrow.left.arrow.right" : "arrow.up.right"))
                .foregroundStyle(type == .income ? .green : (type == .transfer ? .blue : .orange))
                .frame(width: 34, height: 34)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(date, format: .dateTime.locale(Locale(identifier: "vi_VN")).day().month().year())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(type == .income ? "+" : (type == .transfer ? "↔" : "−"))\(MoneyAmount(minorUnits: amount).formatted)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(type == .income ? .green : (type == .transfer ? .blue : .primary))
        }
    }
}

@MainActor
private struct BudgetsTabView: View {
    @FetchRequest(fetchRequest: FinanceRepository.budgetFetchRequest(), animation: .default)
    private var budgets: FetchedResults<NSManagedObject>

    var body: some View {
        NavigationStack {
            List {
                if budgets.isEmpty {
                    ContentUnavailableView(
                        "Chưa có ngân sách",
                        systemImage: "chart.pie",
                        description: Text("Ngân sách theo danh mục sẽ xuất hiện tại đây.")
                    )
                } else {
                    ForEach(budgets, id: \.objectID) { budget in
                        VStack(alignment: .leading) {
                            Text((budget.value(forKey: "category") as? NSManagedObject)?.value(forKey: "name") as? String ?? "Ngân sách")
                            Text(MoneyAmount(minorUnits: (budget.value(forKey: "amount") as? NSNumber)?.int64Value ?? 0).formatted)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentMargins(.bottom, 88, for: .scrollContent)
            .navigationTitle("Ngân sách")
        }
    }
}

@MainActor
private struct ReportsTabView: View {
    @FetchRequest(fetchRequest: FinanceRepository.transactionFetchRequest(), animation: .default)
    private var transactions: FetchedResults<NSManagedObject>

    private var totals: [(String, Int64)] {
        let calendar = Calendar.current
        let now = Date()
        let month = transactions.filter {
            guard let date = $0.value(forKey: "date") as? Date else { return false }
            return calendar.isDate(date, equalTo: now, toGranularity: .month)
        }
        let income = month.filter { $0.value(forKey: "type") as? String == "income" }
            .reduce(Int64(0)) { $0 + (($1.value(forKey: "amount") as? NSNumber)?.int64Value ?? 0) }
        let expense = month.filter { $0.value(forKey: "type") as? String == "expense" }
            .reduce(Int64(0)) { $0 + (($1.value(forKey: "amount") as? NSNumber)?.int64Value ?? 0) }
        return [("Thu nhập", income), ("Chi tiêu", expense)]
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tổng hợp tháng này").font(.headline)
                Chart(totals, id: \.0) { item in
                    BarMark(x: .value("Loại", item.0), y: .value("Số tiền", item.1))
                        .foregroundStyle(by: .value("Loại", item.0))
                }
                .frame(height: 240)
                ForEach(totals, id: \.0) { item in
                    HStack {
                        Text(item.0)
                        Spacer()
                        Text(MoneyAmount(minorUnits: item.1).formatted).bold()
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Báo cáo")
        }
    }
}

@MainActor
private struct SettingsTabView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: FinanceRepository.walletFetchRequest(), animation: .default)
    private var wallets: FetchedResults<NSManagedObject>
    @State private var showingCrashLog = false
    @State private var showingCopyConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Ví của tôi") {
                    ForEach(wallets, id: \.objectID) { wallet in
                        HStack {
                            Label(wallet.value(forKey: "name") as? String ?? "Ví", systemImage: "wallet.bifold")
                            Spacer()
                            Text(MoneyAmount(minorUnits: (wallet.value(forKey: "initialBalance") as? NSNumber)?.int64Value ?? 0).formatted)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        do { _ = try FinanceRepository(context: context).ensureDefaultWallet() }
                        catch { NSLog("Default wallet error: %@", error.localizedDescription) }
                    } label: {
                        Label("Kiểm tra ví mặc định", systemImage: "arrow.clockwise")
                    }
                }
                Section("Ứng dụng") {
                    Label("Dữ liệu được lưu trên iPhone", systemImage: "lock.shield")
                    Label("Khóa Face ID", systemImage: "faceid")
                        .foregroundStyle(.secondary)
                    Text("Thiết lập khóa sinh trắc học sẽ được bật sau khi hoàn thiện kiểm tra xác thực trên thiết bị.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Chẩn đoán") {
                    Button {
                        showingCrashLog = true
                    } label: {
                        Label("Xem log lỗi gần nhất", systemImage: "doc.text.magnifyingglass")
                    }
                    .accessibilityIdentifier("settings.viewCrashLog")
                }
            }
            .contentMargins(.bottom, 88, for: .scrollContent)
            .navigationTitle("Cài đặt")
            .sheet(isPresented: $showingCrashLog) {
                NavigationStack {
                    ScrollView {
                        Text(CrashLogger.readLastCrashLog())
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle("Log lỗi gần nhất")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Đóng") { showingCrashLog = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Sao chép") {
                                UIPasteboard.general.string = CrashLogger.readLastCrashLog()
                                showingCopyConfirmation = true
                            }
                        }
                    }
                    .alert("Đã sao chép log", isPresented: $showingCopyConfirmation) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Log đã được sao chép vào clipboard.")
                    }
                }
            }
        }
    }
}
#endif