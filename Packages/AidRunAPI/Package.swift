// swift-tools-version: 6.1
//
// 后端契约生成的 API 客户端，独立成包。
//
// 为什么不放在 App target 里：
// 主工程设了 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，而生成代码假设的是
// Swift 默认的 nonisolated。两者相撞时，自动合成的一致性（Hashable / Decodable）
// 会带上 MainActor 隔离，满足不了 Sendable 约束 —— 2026-08-06 就是被
// `submitVerification` 的 multipart body 卡住的。APIClient.swift 的注释里
// 记着同一类冲突的另一次发作。
//
// 修那一个报错只能撑到后端下次加个 multipart 端点。独立成包是把这一类冲突
// 整个消掉：包里用 SPM 的默认隔离（nonisolated），主工程的设置管不到这里。
// 附带好处是 16k 行生成代码不再进 App target 的编译单元。
//
// 这个包里只放「面向 OpenAPI 运行时」的代码：生成产物 + 鉴权中间件 + 传输层装配。
// App 侧不直接 import OpenAPIRuntime，避免把同一场隔离冲突再打一遍。
import PackageDescription

let package = Package(
    name: "AidRunAPI",
    // 加 macOS 不是为了出 Mac 版：这个包不依赖高德，所以它是本仓库唯一
    // 能在 Mac 上直接 `swift test` 的地方。别的测试都得插真机
    // （模拟器因高德无 arm64-sim slice 永久不可用，见 AGENTS.md 第 9 节）。
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "AidRunAPI", targets: ["AidRunAPI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-runtime", exact: "1.12.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", exact: "1.3.1"),
    ],
    targets: [
        .target(
            name: "AidRunAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ]
        ),
        .testTarget(name: "AidRunAPITests", dependencies: ["AidRunAPI"]),
    ]
)
