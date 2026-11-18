#if canImport(ObjectiveC)
import Foundation

/// Records Objective-C uncaught exceptions to Documents/last_crash.txt.
/// Swift runtime traps (for example SIGTRAP from a queue assertion) are
/// recorded by iOS as .ips crash reports and are not catchable by this handler.
enum CrashLogger {
    private static let fileName = "last_crash.txt"

    static func install() {
        NSSetUncaughtExceptionHandler(tuiKhonUncaughtExceptionHandler)
    }

    static func recordException(_ exception: NSException) {
        let details = [
            "Túi Khôn uncaught Objective-C exception",
            "Time: \(ISO8601DateFormatter().string(from: Date()))",
            "Name: \(exception.name.rawValue)",
            "Reason: \(exception.reason ?? "(không có)")",
            "",
            "Stack trace:",
            exception.callStackSymbols.joined(separator: "\n")
        ].joined(separator: "\n")
        write(details)
    }

    static func readLastCrashLog() -> String {
        guard let url = logURL(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Chưa có log NSException được ghi nhận.\n\nLưu ý: SIGTRAP/dispatch_assert_queue và một số lỗi Swift runtime được iOS ghi vào báo cáo .ips, không được NSSetUncaughtExceptionHandler bắt."
        }
        return text
    }

    static func record(_ message: String) {
        let text = [
            "Túi Khôn diagnostic event",
            "Time: \(ISO8601DateFormatter().string(from: Date()))",
            message
        ].joined(separator: "\n")
        write(text)
    }

    private static func write(_ text: String) {
        guard let url = logURL() else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("Túi Khôn could not write crash log: %@", error.localizedDescription)
        }
    }

    private static func logURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

private func tuiKhonUncaughtExceptionHandler(_ exception: NSException) {
    CrashLogger.recordException(exception)
}
#else
import Foundation

enum CrashLogger {
    static func install() {}
    static func readLastCrashLog() -> String { "Crash log chỉ được hỗ trợ trên iOS." }
    static func record(_ message: String) {}
}
#endif
