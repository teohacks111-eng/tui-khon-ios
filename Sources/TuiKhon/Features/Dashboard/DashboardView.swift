#if canImport(SwiftUI) && canImport(CoreData)
import SwiftUI
import CoreData

@MainActor
struct DashboardView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(
        fetchRequest: FinanceRepository.transactionFetchRequest(),
        animation: .default
    ) private var transactions: FetchedResults<NSManagedObject>

    @State private var entryKind: TransactionKind?

    private var monthTransactions: [NSManagedObject] {
        let calendar = Calendar.current
        return transactions.filter { record in
            guard let date = record.value(forKey: "date") as? Date else { return false }
            return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
                && calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        }
    }

    private var income: Int64 {
        monthTransactions.filter { ($0.value(forKey: "type") as? String) == "income" }
            .reduce(Int64(0)) { $0 + $1.amountValue }
    }

    private var expense: Int64 {
        monthTransactions.filter { ($0.value(forKey: "type") as? String) == "expense" }
            .reduce(Int64(0)) { $0 + $1.amountValue }
    }

    private var balance: Int64 {
        transactions.reduce(Int64(0)) { total, record in
            let amount = record.amountValue
            switch record.value(forKey: "type") as? String {
            case "income": return total + amount
            case "expense": return total - amount
            default: return total
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tổng quan tài chính")
                    .font(.title2.weight(.bold))
                    .tracking(-0.4)

                summaryCards
                quickActions
                recentTransactions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
        .sheet(item: $entryKind) { selectedKind in
            TransactionEntryView(kind: selectedKind)
                .environment(\.managedObjectContext, context)
                .onAppear {
                    CrashLogger.record("Add transaction sheet appeared: \(selectedKind.rawValue)")
                }
        }
    }

    @ViewBuilder
    private var summaryCards: some View {
        let content = VStack(spacing: 12) {
            LiquidGlassPanel(cornerRadius: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("SỐ DƯ HIỆN TẠI", systemImage: "wallet.pass")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Text(money(balance))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(transactions.isEmpty ? "Hãy thêm khoản thu hoặc chi đầu tiên" : "Tổng thu trừ tổng chi")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                amountCard(title: "Thu nhập", amount: income, symbol: "arrow.down.left", tint: .green)
                amountCard(title: "Chi tiêu", amount: expense, symbol: "arrow.up.right", tint: .orange)
            }
        }

        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) { content }
        } else {
            content
        }
    }

    private func amountCard(title: String, amount: Int64, symbol: String, tint: Color) -> some View {
        LiquidGlassPanel(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                Text(money(amount))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Trong tháng này")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thao tác nhanh")
                .font(.headline)
            HStack(spacing: 12) {
                actionButton(title: "Thêm thu", symbol: "plus.circle.fill", tint: .green, kind: .income)
                actionButton(title: "Thêm chi", symbol: "minus.circle.fill", tint: .orange, kind: .expense)
            }
        }
    }

    private func actionButton(title: String, symbol: String, tint: Color, kind: TransactionKind) -> some View {
        Button {
            CrashLogger.record("Tap dashboard quick action: \(kind.rawValue)")
            entryKind = kind
        } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(kind == .income ? "dashboard.addIncome" : "dashboard.addExpense")
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Giao dịch gần đây")
                    .font(.headline)
                Spacer()
                Text("\(transactions.count) giao dịch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if transactions.isEmpty {
                LiquidGlassPanel(cornerRadius: 20) {
                    ContentUnavailableView(
                        "Chưa có giao dịch",
                        systemImage: "tray",
                        description: Text("Nhấn Thêm thu hoặc Thêm chi để bắt đầu ghi chép.")
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transactions.prefix(12).enumerated()), id: \.element.objectID) { index, record in
                        transactionRow(record)
                        if index < min(transactions.count, 12) - 1 {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func transactionRow(_ record: NSManagedObject) -> some View {
        let isIncome = (record.value(forKey: "type") as? String) == "income"
        let title = (record.value(forKey: "note") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (isIncome ? "Khoản thu" : "Khoản chi")
        let date = record.value(forKey: "date") as? Date ?? Date()
        return HStack(spacing: 12) {
            Image(systemName: isIncome ? "arrow.down.left" : "arrow.up.right")
                .font(.headline)
                .foregroundStyle(isIncome ? .green : .orange)
                .frame(width: 36, height: 36)
                .background((isIncome ? Color.green : Color.orange).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(isIncome ? "+" : "−")\(money(record.amountValue))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isIncome ? .green : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 12)
    }

    private func money(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: NSNumber(value: value)) ?? "0") + " ₫"
    }
}

private extension NSManagedObject {
    var amountValue: Int64 { (value(forKey: "amount") as? NSNumber)?.int64Value ?? 0 }
}

@MainActor
struct TransactionEntryView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: TransactionKind
    @FetchRequest(fetchRequest: FinanceRepository.walletFetchRequest(), animation: .default)
    private var wallets: FetchedResults<NSManagedObject>
    @State private var amount = ""
    @FocusState private var amountFieldFocused: Bool
    @State private var category = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var sourceWalletID: UUID?
    @State private var destinationWalletID: UUID?
    @State private var errorMessage: String?

    init(kind: TransactionKind) {
        _kind = State(initialValue: kind)
    }

    private var isIncome: Bool { kind == .income }
    private var categories: [String] {
        kind == .income
            ? ["Lương", "Thưởng", "Freelance", "Lãi tiết kiệm", "Hoa hồng"]
            : ["Ăn uống", "Di chuyển", "Mua sắm", "Nhà cửa", "Hóa đơn", "Sức khỏe", "Giáo dục", "Giải trí", "Làm đẹp", "Du lịch", "Gia đình", "Thú cưng", "Quà tặng", "Từ thiện", "Khác"]
    }
    private var parsedAmount: Int64? {
        let digits = amount.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int64(digits)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Loại giao dịch") {
                    Picker("Loại", selection: $kind) {
                        Text("Chi tiêu").tag(TransactionKind.expense)
                        Text("Thu nhập").tag(TransactionKind.income)
                        Text("Chuyển ví").tag(TransactionKind.transfer)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("transaction.kind")
                }

                Section("Số tiền") {
                    TextField("Ví dụ: 150000", text: $amount)
                        .keyboardType(.numberPad)
                        .focused($amountFieldFocused)
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("transaction.amount")
                    Text("Nhập số tiền bằng VND.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(kind == .transfer ? "Hai ví chuyển tiền" : "Danh mục và ví") {
                    if !wallets.isEmpty {
                        Picker("Ví nguồn", selection: $sourceWalletID) {
                            Text("Ví mặc định").tag(Optional<UUID>.none)
                            ForEach(wallets, id: \.objectID) { wallet in
                                let id = wallet.value(forKey: "id") as? UUID
                                Text(wallet.value(forKey: "name") as? String ?? "Ví").tag(id)
                            }
                        }
                        if kind == .transfer {
                            Picker("Ví nhận", selection: $destinationWalletID) {
                                Text("Chọn ví nhận").tag(Optional<UUID>.none)
                                ForEach(wallets, id: \.objectID) { wallet in
                                    let id = wallet.value(forKey: "id") as? UUID
                                    Text(wallet.value(forKey: "name") as? String ?? "Ví").tag(id)
                                }
                            }
                        }
                    }
                    if kind != .transfer {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
                            ForEach(categories, id: \.self) { item in
                                Button {
                                    category = item
                                } label: {
                                    Text(item)
                                        .font(.caption.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(category == item ? Color.green.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("transaction.category.\(item)")
                            }
                        }
                        TextField("Danh mục khác", text: $category)
                    }
                    TextField("Ghi chú (không bắt buộc)", text: $note)
                    DatePicker("Ngày giao dịch", selection: $date, displayedComponents: .date)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isIncome ? "Thêm khoản thu" : "Thêm khoản chi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Xong") { amountFieldFocused = false }
                        .accessibilityIdentifier("transaction.keyboardDone")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") { dismiss() }
                        .accessibilityIdentifier("transaction.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("transaction.save")
                }
            }
            .tint(isIncome ? .green : .orange)
        }
    }

    private func save() {
        CrashLogger.record("Transaction save tapped: type=\(kind.rawValue), amount=\(amount), category=\(category)")
        guard let value = parsedAmount, value > 0 else {
            errorMessage = "Vui lòng nhập số tiền lớn hơn 0."
            return
        }

        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try FinanceRepository(context: context).addTransaction(
                amount: value,
                kind: kind,
                date: date,
                note: cleanNote.isEmpty ? cleanCategory : cleanNote,
                merchant: cleanCategory,
                sourceWalletID: sourceWalletID,
                destinationWalletID: destinationWalletID,
                categoryName: cleanCategory.isEmpty ? nil : cleanCategory
            )
            CrashLogger.record("Transaction save succeeded: type=\(kind.rawValue), amount=\(value)")
            dismiss()
        } catch {
            CrashLogger.record("Transaction save failed: \(error.localizedDescription)")
            errorMessage = "Không thể lưu giao dịch: \(error.localizedDescription)"
        }
    }
}
#endif
