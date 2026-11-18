import XCTest

final class TuiKhonUITests: XCTestCase {
    @MainActor
    func testAllFiveTabsCanBeSelectedWithoutCrashing() {
        let app = launchIsolatedApp()
        XCTAssertTrue(app.staticTexts["Tổng quan tài chính"].waitForExistence(timeout: 10))

        for tabName in ["Giao dịch", "Ngân sách", "Báo cáo", "Cài đặt", "Tổng quan"] {
            let tab = app.tabBars.buttons[tabName]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Không tìm thấy tab \(tabName)")
            tab.tap()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        }
    }

    @MainActor
    func testAddIncomeExpenseAndOpenFloatingAddSheet() {
        let app = launchIsolatedApp()
        XCTAssertTrue(app.buttons["dashboard.addIncome"].waitForExistence(timeout: 10))

        app.buttons["dashboard.addIncome"].tap()
        saveTransaction(in: app, amount: "1000000", category: "Lương")
        XCTAssertTrue(app.staticTexts["1.000.000 ₫"].waitForExistence(timeout: 5))

        app.buttons["dashboard.addExpense"].tap()
        saveTransaction(in: app, amount: "350000", category: "Ăn uống")
        XCTAssertTrue(app.staticTexts["650.000 ₫"].waitForExistence(timeout: 5))

        let addButton = app.buttons["app.addTransaction"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        XCTAssertTrue(app.textFields["transaction.amount"].waitForExistence(timeout: 5))
        app.buttons["transaction.cancel"].tap()
        XCTAssertTrue(app.buttons["dashboard.addIncome"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-com.apple.CoreData.ConcurrencyDebug",
            "1"
        ]
        app.launch()
        return app
    }

    @MainActor
    private func saveTransaction(in app: XCUIApplication, amount: String, category: String) {
        let amountField = app.textFields["transaction.amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 5))
        amountField.tap()
        amountField.typeText(amount)

        let categoryButton = app.buttons["transaction.category.\(category)"]
        XCTAssertTrue(categoryButton.waitForExistence(timeout: 5))
        categoryButton.tap()

        let saveButton = app.buttons["transaction.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
    }
}
