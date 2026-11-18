#if canImport(SwiftUI) && canImport(CoreData)
import SwiftUI
import CoreData

@main
@MainActor
struct TuiKhonApp: App {
    @StateObject private var persistenceController = PersistenceController()

    init() {
        CrashLogger.install()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let loadError = persistenceController.loadError {
                    ContentUnavailableView(
                        "Không thể mở dữ liệu",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(loadError)
                    )
                } else if persistenceController.isReady {
                    AppRootView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                } else {
                    ProgressView("Đang khởi tạo dữ liệu...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
#endif
