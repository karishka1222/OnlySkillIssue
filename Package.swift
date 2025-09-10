// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OnlySkillIssue",
    products: [
            .library(
                name: "FInterpreter",
                targets: ["FInterpreter"]
            ),
            .executable(
                name: "FInterpreterCLI",
                targets: ["FInterpreterCLI"]
            )
    ],
    targets: [
            .target(
                name: "FInterpreter",
                path: "Sources/FInterpreter"
            ),
            .executableTarget(
                name: "FInterpreterCLI",
                dependencies: ["FInterpreter"],
                path: "Sources/FInterpreterCLI",
                resources: [
                    .process("Resources")
                ]
            ),
            .testTarget(
                name: "FInterpreterTests",
                dependencies: ["FInterpreter"],
                path: "Tests/"
            )
    ]
)
