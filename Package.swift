// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "metal_video_morpher2",
    platforms: [
        .macOS(.v13) // Set minimum macOS version to ensure Metal support
    ],
    dependencies: [
        // Add any external dependencies here
    ],
    targets: [
        // Main application target
        .executableTarget(
            name: "App",
            dependencies: ["Domain", "Data", "MetalRenderer"],
            path: "Sources/App"
        ),
        
        // Domain layer (business logic)
        .target(
            name: "Domain",
            dependencies: [],
            path: "Sources/Domain"
        ),
        
        // Data layer (data handling)
        .target(
            name: "Data",
            dependencies: ["Domain"],
            path: "Sources/Data"
        ),
        
        // Metal renderer layer
        .target(
            name: "MetalRenderer",
            dependencies: ["Domain"],
            path: "Sources/Metal",
            resources: [
                .process("Shaders") // Include shader files
            ]
        )
    ]
)
