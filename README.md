# Túi Khôn

Ứng dụng quản lý chi tiêu cá nhân native cho iPhone, xây dựng bằng Swift 6, SwiftUI, Core Data và xtool.

## Phase 0

- SwiftPM project, iOS 18.0 trở lên.
- Core Data model gồm 9 entity được khai báo trực tiếp bằng Swift: NSManagedObjectModel, NSEntityDescription, NSAttributeDescription và NSRelationshipDescription. Không cần .xcdatamodeld hoặc momc.
- Local-first persistent store; chưa bật CloudKit hoặc App Group.
- Các thuộc tính có giá trị mặc định hoặc optional; mọi relationship đều optional.
- Không dùng uniqueness constraints.
- Swift Testing cho logic tiền tệ và kiểm tra schema Core Data trên nền tảng có Core Data.

## Build từ Windows PowerShell

    .\build-ipa.ps1

Script chạy unit tests trong Ubuntu WSL, sau đó gọi xtool dev build --ipa không có --sign. IPA được sao chép vào artifacts\TuiKhon-debug.ipa.

Build Release:

    .\build-ipa.ps1 -Configuration release

## Cấu trúc

- Sources/TuiKhon/App: SwiftUI app và root view.
- Sources/TuiKhon/Domain: logic thuần Swift, độc lập framework.
- Sources/TuiKhon/Data/Models: tên entity và schema records.
- Sources/TuiKhon/Data/Persistence: Core Data model builder và persistent container.
- Sources/TuiKhon/Features: UI theo tính năng.
- Resources/PrivacyInfo.xcprivacy: privacy manifest.
- Tests/TuiKhonTests: unit tests.

## Quyền riêng tư và lưu trữ

Dữ liệu được lưu cục bộ trên iPhone. Phase 0 không gửi dữ liệu tới máy chủ, không bật CloudKit/iCloud, không dùng App Group, analytics hay package bên thứ ba. Core Data schema được thiết kế để có thể xem xét nâng cấp sang NSPersistentCloudKitContainer ở phase sau; điều đó chưa được bật.

## Phân phối

IPA unsigned là gói ứng dụng iOS chưa ký. Có thể sao chép/chia sẻ file, nhưng iPhone không thể cài trực tiếp cho đến khi IPA được ký bằng phương thức phân phối hợp lệ.
