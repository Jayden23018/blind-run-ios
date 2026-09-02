//
//  MockAPIClient+EmergencyContact.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 紧急联系人 分段。行为零改动，只改文件位置。
//

import Foundation

extension MockAPIClient {

    // MARK: - Emergency Contact Handlers

    func handleAddEmergencyContact(body: (any Encodable & Sendable)?) throws -> EmergencyContactResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyContactRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "请求格式错误"))
        }
        // 后端 EmergencyContactService.addContact：count >= 5 时抛 CONTACT_LIMIT_EXCEEDED（400）。
        guard emergencyContacts.count < EmergencyContactRules.maxCount else {
            throw APIError.serverError(ErrorResponse(
                code: "CONTACT_LIMIT_EXCEEDED",
                message: "最多添加 \(EmergencyContactRules.maxCount) 个紧急联系人"
            ))
        }
        try validateContactFields(request, requireAllFields: true)

        // 第一个联系人必定是主联系人；显式要求主联系人时旧的自动取消。
        let shouldBePrimary = (request.isPrimary ?? false) || emergencyContacts.isEmpty
        let contact = EmergencyContactResponse(
            id: nextContactId,
            name: request.name?.trimmed,
            phone: request.phone?.trimmed,
            relationship: request.relationship?.trimmed.nilIfBlank,
            isPrimary: shouldBePrimary
        )
        nextContactId += 1
        emergencyContacts.append(contact)
        if shouldBePrimary {
            applyPrimaryContact(id: contact.id)
        }
        return try storedEmergencyContact(id: contact.id)
    }

    func handleUpdateEmergencyContact(
        contactId: Int64,
        body: (any Encodable & Sendable)?
    ) throws -> EmergencyContactResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(EmergencyContactRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "BAD_REQUEST", message: "请求格式错误"))
        }
        guard let index = emergencyContacts.firstIndex(where: { $0.id == contactId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        try validateContactFields(request, requireAllFields: false)

        // PATCH 语义：请求里为 nil 的字段保留旧值（后端 EmergencyContactService.updateContact 逐字段判空）。
        let existingContact = emergencyContacts[index]
        emergencyContacts[index] = EmergencyContactResponse(
            id: existingContact.id,
            name: request.name?.trimmed ?? existingContact.name,
            phone: request.phone?.trimmed ?? existingContact.phone,
            relationship: request.relationship?.trimmed.nilIfBlank ?? existingContact.relationship,
            isPrimary: request.isPrimary ?? existingContact.isPrimary
        )

        // 设成主联系人时旧的自动取消。
        // 唯一的主联系人被显式置 false 时，后端**不报错**，而是把列表里的下一个补成主联系人
        // （EmergencyContactService.updateContact 末尾的补偿分支，与 deleteContact 一致）。
        // Mock 不得在这里造一个后端从不返回的 400，否则客户端会为不存在的失败分支写死逻辑。
        if request.isPrimary == true {
            applyPrimaryContact(id: contactId)
        } else if request.isPrimary == false, existingContact.isPrimary == true {
            promoteFirstContact(excluding: contactId)
        }

        return try storedEmergencyContact(id: contactId)
    }

    /// `PUT .../{contactId}/set-primary`：后端返回 `{"success": true}`，不返回列表，客户端必须重新 GET。
    func handleSetPrimaryEmergencyContact(contactId: Int64) throws -> EmptyResponse {
        guard emergencyContacts.contains(where: { $0.id == contactId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        applyPrimaryContact(id: contactId)
        return EmptyResponse()
    }

    func handleDeleteEmergencyContact(contactId: Int64) throws -> EmptyResponse {
        guard let index = emergencyContacts.firstIndex(where: { $0.id == contactId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        // 后端 EmergencyContactService.deleteContact：count <= 1 时抛 CONTACT_MINIMUM_REQUIRED（400）。
        guard emergencyContacts.count > EmergencyContactRules.minCount else {
            throw APIError.serverError(ErrorResponse(
                code: "CONTACT_MINIMUM_REQUIRED",
                message: "至少保留 \(EmergencyContactRules.minCount) 个紧急联系人"
            ))
        }
        let removed = emergencyContacts.remove(at: index)
        // 删掉的是主联系人时顺延给列表第一个，保证"恰好一个主联系人"不变量不被 Mock 自己破坏。
        if removed.isPrimary == true {
            promoteFirstContact(excluding: removed.id)
        }
        return EmptyResponse()
    }

    /// 原子设置主联系人：目标置 true，其余一律置 false。
    private func applyPrimaryContact(id: Int64) {
        emergencyContacts = emergencyContacts.map { contact in
            EmergencyContactResponse(
                id: contact.id,
                name: contact.name,
                phone: contact.phone,
                relationship: contact.relationship,
                isPrimary: contact.id == id
            )
        }
    }

    /// 后端在"主联系人被删除/被取消"后把列表里的下一个补成主联系人；没有其他联系人时保持 0 个主联系人。
    private func promoteFirstContact(excluding contactId: Int64) {
        guard let next = emergencyContacts.first(where: { $0.id != contactId }) else { return }
        applyPrimaryContact(id: next.id)
    }

    private func storedEmergencyContact(id: Int64) throws -> EmergencyContactResponse {
        guard let contact = emergencyContacts.first(where: { $0.id == id }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "紧急联系人不存在"))
        }
        return contact
    }

    /// 校验顺序与后端 `EmergencyContactRequest` 严格一致：Bean Validation（`@Size` + `@Pattern`，
    /// 统一 400 `VALIDATION_ERROR`）先跑，`EmergencyContactService.addContact` 里手写的
    /// `CONTACT_FIELD_REQUIRED` 后跑。顺序反了会让 Mock 在「phone 传空串」时报错码与线上不一致。
    private func validateContactFields(_ request: EmergencyContactRequest, requireAllFields: Bool) throws {
        let name = request.name?.trimmed
        let phone = request.phone?.trimmed

        // —— Bean Validation 层 ——
        if let name, name.count > EmergencyContactRules.maxNameLength {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人姓名过长"))
        }
        if let phone {
            if phone.count > EmergencyContactRules.maxPhoneLength {
                throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人手机号过长"))
            }
            // 后端 2026-07-31 给 phone 加了 `@Pattern(^1[3-9]\d{9}$)`（与登录链路同款），
            // Mock 不能再比线上松 —— 松了就把「乱填的号码能存进去」这个安全缺口在开发期遮住。
            // `@Pattern` 对 null 放行、对空串不放行，所以这里只在 phone 非 nil 时判。
            if !AppState.isValidMainlandPhone(phone) {
                throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "手机号格式不正确"))
            }
        }
        if let relationship = request.relationship?.trimmed,
           relationship.count > EmergencyContactRules.maxRelationshipLength {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "联系人关系过长"))
        }

        // —— 服务端手写校验层：后端对空姓名/缺手机号分别抛 CONTACT_FIELD_REQUIRED（400），姓名先判 ——
        guard requireAllFields else { return }
        if name?.isEmpty != false {
            throw APIError.serverError(
                ErrorResponse(code: "CONTACT_FIELD_REQUIRED", message: "联系人姓名不能为空"))
        }
        if phone?.isEmpty != false {
            throw APIError.serverError(
                ErrorResponse(code: "CONTACT_FIELD_REQUIRED", message: "联系人电话不能为空"))
        }
    }
}
