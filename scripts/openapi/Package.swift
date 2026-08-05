// swift-tools-version: 6.1
//
// 只用来把 swift-openapi-generator 的 CLI 钉在一个确定版本上，本包不参与 App 构建。
// 生成流程见 scripts/generate-api-client.sh。
//
// 版本用 exact 而不是 from：生成器小版本变化会改动产物格式，
// 而产物是 check-in 进仓库的，浮动版本会让 CI 的「重新生成 + git diff --exit-code」
// 在没人改 spec 的情况下平白变红。
import PackageDescription

let package = Package(
    name: "aidrun-openapi-tools",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.13.0")
    ]
)
