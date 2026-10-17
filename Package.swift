// swift-tools-version: 6.2
import PackageDescription
import Foundation

let package = Package(
    name: "Jotway",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        // 本地修补版：移除 #Preview（该宏依赖 Xcode 私有插件 PreviewsMacros，CLT 环境无法编译）
        .package(path: "Vendor/KeyboardShortcuts"),
    ],
    targets: [
        .executableTarget(name: "JotwayClipboardOCR", path: "Helpers/ClipboardOCR",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist", "-Xlinker",
                URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .appendingPathComponent("Resources/ClipboardOCR-Info.plist").path])]),
        .target(name: "CSQLiteVec", path: "Vendor/sqlite-vec", exclude: ["LICENSE-MIT"],
                publicHeadersPath: "include", cSettings: [.define("SQLITE_CORE")],
                linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(
            name: "Jotway",
            dependencies: [
                "CSQLiteVec",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources",
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "JotwayTests",
            dependencies: ["Jotway"],
            path: "Tests/JotwayTests"
        )
    ]
)
