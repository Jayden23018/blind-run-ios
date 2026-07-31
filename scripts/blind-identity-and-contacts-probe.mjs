#!/usr/bin/env node

// 盲人实名认证 + 紧急联系人变更的云端契约探针。
//
// 隐私红线：
// - 身份证号只用内置的合成值，脚本不接受任何外部传入的身份证号，输出里也只有 '***REDACTED***'。
// - 手机号、联系人姓名一律脱敏后再进报告，任何原文都不落日志。
//
// 副作用与回滚：探针只新增自己创建的联系人，结束时删除它们并把主联系人恢复原状。
// 账号原有的联系人绝不删除；因此「删除最后一位」这一项只有在账号原本没有联系人时才会真正验证。

const baseURL = 'http://47.114.113.171';
const phone = process.env.AIDRUN_BLIND_PROBE_PHONE;
const contactPhonePrefix = process.env.AIDRUN_BLIND_PROBE_CONTACT_PHONE;
const fallbackCode = process.env.AIDRUN_BLIND_PROBE_CODE ?? '000000';
const shouldSendCode = process.env.AIDRUN_BLIND_PROBE_SKIP_SEND_CODE !== '1';
const shouldSubmitIdentity = process.env.AIDRUN_BLIND_PROBE_SKIP_IDENTITY !== '1';
const timeoutMs = Number(process.env.AIDRUN_BLIND_PROBE_TIMEOUT_MS ?? '20000');

// 合成身份证号：行政区划 110101 + 生日 19900307 + 顺序码 781 + 校验位 X。
// 真实实名接口必然会拒绝它，探针要验证的是「拒绝方式是否符合契约」，不是通过实名。
const SYNTHETIC_ID_CARD_NUMBER = '11010119900307781X';
const SYNTHETIC_ID_CARD_NAME = '探针测试';
const MAX_CONTACTS = 5;
const VALID_VERIFY_STATUSES = ['NOT_VERIFIED', 'VERIFIED', 'FAILED'];

if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
  throw new Error('Set AIDRUN_BLIND_PROBE_PHONE to a blind-role test phone number.');
}
if (!contactPhonePrefix || !/^1[3-9]\d{9}$/.test(contactPhonePrefix)) {
  throw new Error(
    'Set AIDRUN_BLIND_PROBE_CONTACT_PHONE to a phone number you control. '
    + 'The backend sends a notification SMS to every contact this probe creates.'
  );
}
if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  throw new Error('AIDRUN_BLIND_PROBE_TIMEOUT_MS must be a positive number.');
}

const maskedPhone = maskPhone(phone);

function maskPhone(value) {
  const text = String(value ?? '');
  if (text.length < 7) return text.length > 0 ? '***' : null;
  return `${text.slice(0, 3)}****${text.slice(-4)}`;
}

/// 联系人姓名是 PII，报告里只保留「有没有填」和字数。
function nameShape(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  return { present: text.length > 0, length: text.length };
}

/// 探针自己创建的联系人手机号：末两位换成序号，避免和账号原有联系人撞号。
function probeContactPhone(index) {
  return `${contactPhonePrefix.slice(0, 9)}${String(index % 100).padStart(2, '0')}`;
}

class BackendUnreachableError extends Error {}

function unwrap(value) {
  if (value && typeof value === 'object' && value.data && typeof value.data === 'object') {
    return value.data;
  }
  return value;
}

async function http(method, path, { token, body, allowFailure = false } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let response;
  try {
    response = await fetch(new URL(path, baseURL), {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {})
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: controller.signal
    });
  } catch (error) {
    // fetch 只在网络层失败时抛异常：连不上、DNS 失败、超时中断。
    throw new BackendUnreachableError(`${method} ${path}: ${error?.name ?? 'NetworkError'}`);
  } finally {
    clearTimeout(timer);
  }

  const text = await response.text();
  let parsed = {};
  if (text.trim()) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { raw: text };
    }
  }
  const reply = { ok: response.ok, status: response.status, body: unwrap(parsed) };
  if (!reply.ok && !allowFailure) {
    throw new Error(`${method} ${path} failed with ${reply.status}: ${errorCodeOf(reply) ?? 'no code'}`);
  }
  return reply;
}

function errorCodeOf(reply) {
  return reply?.body?.errorCode ?? reply?.body?.code ?? null;
}

function sixDigitCode(response, fallback) {
  const candidates = [
    response?.body?.verificationCode,
    response?.body?.smsCode,
    response?.body?.code,
    fallback
  ];
  return candidates.find(value => /^\d{6}$/.test(String(value)))?.toString();
}

function contactSnapshot(contact = {}) {
  return {
    id: contact.id ?? null,
    name: nameShape(contact.name),
    phone: maskPhone(contact.phone),
    // 后端 v1.5.0 起返回明文手机号；脱敏是探针的责任，不是后端的。
    phoneIsPlainText: typeof contact.phone === 'string' && /^\d{11}$/.test(contact.phone),
    relationshipPresent: typeof contact.relationship === 'string' && contact.relationship.trim().length > 0,
    isPrimary: contact.isPrimary ?? null
  };
}

async function listContacts(token, userId) {
  const reply = await http('GET', `/api/users/${userId}/emergency-contacts`, { token });
  const list = Array.isArray(reply.body) ? reply.body : (reply.body?.items ?? []);
  return list.map(contactSnapshot);
}

function primaryIds(contacts) {
  return contacts.filter(contact => contact.isPrimary === true).map(contact => contact.id);
}

async function main() {
  const issues = [];
  const checks = {};

  let selectedCode = fallbackCode;
  if (shouldSendCode) {
    const sent = await http('POST', '/api/auth/send-code', { body: { phone } });
    selectedCode = sixDigitCode(sent, fallbackCode);
  }
  if (!selectedCode) {
    throw new Error('No six-digit verification code is available. Set AIDRUN_BLIND_PROBE_CODE.');
  }

  const login = await http('POST', '/api/auth/verify-code', {
    body: { phone, code: selectedCode },
    allowFailure: true
  });
  if (!login.ok) {
    report({
      authenticated: false,
      errorCode: errorCodeOf(login),
      issues: ['AUTH_FIXED_CODE_REJECTED'],
      nextAction: 'Set AIDRUN_BLIND_PROBE_CODE to the current SMS code and rerun the probe.'
    });
    process.exitCode = 2;
    return;
  }

  const token = login.body?.token;
  const userId = login.body?.userId;
  if (!token || !userId) {
    throw new Error('verify-code returned no token or userId.');
  }
  if (login.body.role !== 'BLIND') {
    throw new Error(`Probe refuses to switch roles; current role is ${login.body.role ?? 'unset'}.`);
  }

  // --- 实名认证 ---------------------------------------------------------

  const profileBefore = await http('GET', '/api/blind/profile', { token });
  checks.identity = {
    statusBefore: profileBefore.body?.verifyStatus ?? null,
    submitted: false,
    submitStatus: null,
    submitErrorCode: null,
    statusAfter: null,
    idCardNumber: '***REDACTED***',
    idCardSource: 'synthetic'
  };
  if (!VALID_VERIFY_STATUSES.includes(checks.identity.statusBefore ?? 'NOT_VERIFIED')) {
    issues.push('IDENTITY_STATUS_OUT_OF_CONTRACT');
  }

  if (shouldSubmitIdentity && checks.identity.statusBefore !== 'VERIFIED') {
    const submit = await http('POST', '/api/blind/verify-identity', {
      token,
      body: { idCardName: SYNTHETIC_ID_CARD_NAME, idCardNumber: SYNTHETIC_ID_CARD_NUMBER },
      allowFailure: true
    });
    checks.identity.submitted = true;
    checks.identity.submitStatus = submit.status;
    checks.identity.submitErrorCode = errorCodeOf(submit);
    if (!submit.ok && submit.status >= 500) {
      issues.push('IDENTITY_SUBMIT_SERVER_ERROR');
    }
    if (!submit.ok && submit.status < 500 && !checks.identity.submitErrorCode) {
      // 客户端要靠稳定的 code 做文案映射，只有中文 message 是不够的。
      issues.push('IDENTITY_REJECTION_WITHOUT_ERROR_CODE');
    }

    const profileAfter = await http('GET', '/api/blind/profile', { token });
    checks.identity.statusAfter = profileAfter.body?.verifyStatus ?? null;
    if (!VALID_VERIFY_STATUSES.includes(checks.identity.statusAfter ?? 'NOT_VERIFIED')) {
      issues.push('IDENTITY_STATUS_OUT_OF_CONTRACT');
    }
    if (checks.identity.statusAfter === 'VERIFIED') {
      // 合成号码通过实名意味着后端没有真正校验。
      issues.push('IDENTITY_ACCEPTED_SYNTHETIC_NUMBER');
    }
  }

  // --- 紧急联系人 -------------------------------------------------------

  const original = await listContacts(token, userId);
  const originalPrimaryId = primaryIds(original)[0] ?? null;
  checks.contacts = {
    originalCount: original.length,
    originalPrimaryCount: primaryIds(original).length,
    plainTextPhone: original.some(contact => contact.phoneIsPlainText)
  };
  if (original.length > 0 && checks.contacts.originalPrimaryCount !== 1) {
    issues.push('PRIMARY_INVARIANT_BROKEN_BEFORE_PROBE');
  }

  if (original.length >= MAX_CONTACTS) {
    // 已经占满 5 位，再新增就会被后端拒绝；探针不删用户自己的联系人，所以只能跳过。
    checks.contacts.skipped = 'ACCOUNT_ALREADY_AT_CONTACT_LIMIT';
    report({ authenticated: true, userId, checks, issues });
    process.exitCode = issues.length > 0 ? 2 : 0;
    return;
  }

  const createdIds = [];
  try {
    // 新增
    const createReply = await http('POST', `/api/users/${userId}/emergency-contacts`, {
      token,
      body: {
        name: '探针联系人一',
        phone: probeContactPhone(91),
        relationship: '朋友',
        isPrimary: false
      }
    });
    const createdId = createReply.body?.id ?? null;
    if (!createdId) throw new Error('Create emergency contact returned no id.');
    createdIds.push(createdId);

    let afterCreate = await listContacts(token, userId);
    checks.contacts.create = {
      ok: afterCreate.some(contact => contact.id === createdId),
      countDelta: afterCreate.length - original.length
    };
    if (!checks.contacts.create.ok) issues.push('CREATE_NOT_REFLECTED_IN_LIST');

    // 修改：PUT 对 isPrimary 是无条件赋值，必须原样回传当前值，否则会把主联系人清空。
    const createdSnapshot = afterCreate.find(contact => contact.id === createdId) ?? {};
    await http('PUT', `/api/users/${userId}/emergency-contacts/${createdId}`, {
      token,
      body: {
        name: '探针联系人一',
        phone: probeContactPhone(92),
        relationship: '同事',
        isPrimary: createdSnapshot.isPrimary === true
      }
    });
    afterCreate = await listContacts(token, userId);
    const updated = afterCreate.find(contact => contact.id === createdId) ?? {};
    checks.contacts.update = {
      relationshipApplied: updated.relationshipPresent === true,
      phoneApplied: updated.phone === maskPhone(probeContactPhone(92)),
      primaryPreserved: (updated.isPrimary === true) === (createdSnapshot.isPrimary === true)
    };
    if (!checks.contacts.update.phoneApplied) issues.push('UPDATE_DID_NOT_APPLY_PHONE');
    if (!checks.contacts.update.primaryPreserved) issues.push('UPDATE_CLOBBERED_PRIMARY_FLAG');
    if (primaryIds(afterCreate).length !== 1) issues.push('PRIMARY_INVARIANT_BROKEN_AFTER_UPDATE');

    // 设为主联系人：返回空对象，必须重新 GET 才能拿到列表。
    const setPrimary = await http(
      'PUT',
      `/api/users/${userId}/emergency-contacts/${createdId}/set-primary`,
      { token, allowFailure: true }
    );
    const afterSetPrimary = await listContacts(token, userId);
    checks.contacts.setPrimary = {
      status: setPrimary.status,
      returnsList: Array.isArray(setPrimary.body),
      newPrimaryId: primaryIds(afterSetPrimary)[0] ?? null,
      primaryCount: primaryIds(afterSetPrimary).length
    };
    if (checks.contacts.setPrimary.newPrimaryId !== createdId) issues.push('SET_PRIMARY_NOT_APPLIED');
    if (checks.contacts.setPrimary.primaryCount !== 1) issues.push('SET_PRIMARY_NOT_ATOMIC');

    // 数量上限：补到 5 位再试第 6 位。
    let currentCount = afterSetPrimary.length;
    for (let index = currentCount; index < MAX_CONTACTS; index += 1) {
      const filler = await http('POST', `/api/users/${userId}/emergency-contacts`, {
        token,
        body: {
          name: `探针联系人${index}`,
          phone: probeContactPhone(index),
          relationship: '朋友',
          isPrimary: false
        }
      });
      if (filler.body?.id) createdIds.push(filler.body.id);
      currentCount += 1;
    }
    const overLimit = await http('POST', `/api/users/${userId}/emergency-contacts`, {
      token,
      body: {
        name: '探针超限联系人',
        phone: probeContactPhone(99),
        relationship: '朋友',
        isPrimary: false
      },
      allowFailure: true
    });
    if (overLimit.ok && overLimit.body?.id) createdIds.push(overLimit.body.id);
    checks.contacts.overLimit = {
      countBefore: currentCount,
      rejected: !overLimit.ok,
      status: overLimit.status,
      errorCode: errorCodeOf(overLimit)
    };
    if (overLimit.ok) issues.push('OVER_LIMIT_CONTACT_ACCEPTED');

    // 删除最后一位：只有账号原本没有联系人时才可能在不破坏用户数据的前提下验证。
    if (original.length === 0) {
      for (const id of createdIds.slice(1)) {
        await http('DELETE', `/api/users/${userId}/emergency-contacts/${id}`, { token, allowFailure: true });
      }
      createdIds.length = 1;
      const deleteLast = await http(
        'DELETE',
        `/api/users/${userId}/emergency-contacts/${createdIds[0]}`,
        { token, allowFailure: true }
      );
      const afterDeleteLast = await listContacts(token, userId);
      checks.contacts.deleteLast = {
        rejected: !deleteLast.ok,
        status: deleteLast.status,
        errorCode: errorCodeOf(deleteLast),
        remainingCount: afterDeleteLast.length
      };
      if (deleteLast.ok) {
        issues.push('LAST_CONTACT_DELETION_ACCEPTED');
        createdIds.length = 0;
      }
    } else {
      checks.contacts.deleteLast = {
        skipped: 'ACCOUNT_HAS_PRE_EXISTING_CONTACTS',
        reason: 'Probe never deletes contacts it did not create.'
      };
    }
  } finally {
    // --- 回滚 -----------------------------------------------------------
    for (const id of createdIds) {
      await http('DELETE', `/api/users/${userId}/emergency-contacts/${id}`, { token, allowFailure: true });
    }
    if (originalPrimaryId !== null) {
      await http(
        'PUT',
        `/api/users/${userId}/emergency-contacts/${originalPrimaryId}/set-primary`,
        { token, allowFailure: true }
      );
    }
    const restored = await listContacts(token, userId);
    checks.cleanup = {
      restoredCount: restored.length,
      restoredPrimaryId: primaryIds(restored)[0] ?? null,
      matchesOriginal: restored.length === original.length && (primaryIds(restored)[0] ?? null) === originalPrimaryId
    };
    if (!checks.cleanup.matchesOriginal) issues.push('CLEANUP_DID_NOT_RESTORE_ORIGINAL_STATE');
  }

  report({ authenticated: true, userId, checks, issues });
  if (issues.length > 0) {
    process.exitCode = 2;
  }
}

function report(payload) {
  console.log(JSON.stringify({ baseURL, phone: maskedPhone, ...payload }, null, 2));
}

try {
  await main();
} catch (error) {
  if (error instanceof BackendUnreachableError) {
    report({
      reachable: false,
      authenticated: false,
      issues: ['BACKEND_UNREACHABLE'],
      detail: error.message,
      nextAction: `Confirm ${baseURL} is up and reachable from this network, then rerun the probe.`
    });
    process.exitCode = 2;
  } else {
    throw error;
  }
}
