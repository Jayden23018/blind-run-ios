//
//  EndpointRequest.swift
//  blindRun
//
//  领域 service 层与网络层之间的唯一数据结构。
//

import Foundation

/// 一条端点的三要素：方法、**完整字面量**路径、要不要带 JWT。
///
/// 存在的理由只有一个：把散在 27 个文件里的 `"/api/..."` 字面量收敛到各领域的
/// endpoint 枚举里。`scripts/validate-spec-coverage.mjs` 按字符串字面量扫路径，
/// 所以路径必须写成**一条完整的字面量**（可以带 `\(id)` 插值），
/// 不许 `base + "/orders/" + id` 那样拼 —— 拼出来的路径扫不到，等于绕过契约门禁。
struct EndpointRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let requiresAuth: Bool

    init(_ method: HTTPMethod, _ path: String, requiresAuth: Bool = true) {
        self.method = method
        self.path = path
        self.requiresAuth = requiresAuth
    }
}
