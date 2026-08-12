#!/usr/bin/env node

const baseURL = 'http://47.114.113.171';
const phone = process.env.AIDRUN_AUTH_LIFECYCLE_PHONE;
const fallbackCode = process.env.AIDRUN_AUTH_LIFECYCLE_CODE ?? '000000';
const timeoutMs = Number(process.env.AIDRUN_AUTH_LIFECYCLE_TIMEOUT_MS ?? 25000);

if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
  throw new Error('Set AIDRUN_AUTH_LIFECYCLE_PHONE to an approved disposable phone number.');
}

const result = {
  baseURL,
  phone: `${phone.slice(0, 3)}****${phone.slice(-4)}`,
  userId: null,
  recreatedUserId: null,
  logoutBlacklistRejected: false,
  deleteOwnershipRejected: false,
  activeOrderDeletionBlocked: false,
  softDeletionConfirmed: false,
  allTokensInvalidated: false,
  phoneReregistered: false,
  finalCleanupDeleted: false
};

let cleanupToken = null;
let cleanupUserId = null;
let activeOrderId = null;

function log(step, detail = '') {
  console.log(`[auth-lifecycle-probe] ${step}${detail ? ` ${detail}` : ''}`);
}

function unwrap(value) {
  if (value && typeof value === 'object' && value.data && typeof value.data === 'object') {
    return value.data;
  }
  return value;
}

function errorCode(body) {
  return body?.errorCode ?? body?.error?.errorCode ?? body?.data?.errorCode
    ?? body?.code ?? body?.error?.code ?? body?.data?.code;
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

  const reply = { ok: response.ok, status: response.status, body: unwrap(parsed), rawBody: parsed };
  if (!reply.ok && !allowFailure) {
    const error = new Error(`${method} ${path} failed with ${reply.status}: ${text}`);
    error.reply = reply;
    throw error;
  }
  return reply;
}

function verificationCode(response, fallback) {
  const candidates = [response.body.verificationCode, response.body.smsCode, response.body.code];
  return candidates.find(value => /^\d{6}$/.test(String(value))) ?? fallback;
}

async function readCode(label, configured) {
  if (configured) return configured;
  if (!process.stdin.isTTY) throw new Error(`Set ${label} to the newly sent SMS code.`);
  return new Promise(resolve => {
    process.stdout.write(`[auth-lifecycle-probe] ${label}: `);
    process.stdin.setEncoding('utf8');
    process.stdin.once('data', value => resolve(value.trim()));
  });
}

async function authenticate({ sendCode = false, code } = {}) {
  let selectedCode = code ?? fallbackCode;
  if (sendCode) {
    const sent = await http('POST', '/api/auth/send-code', { body: { phone } });
    selectedCode = verificationCode(sent, undefined)
      ?? await readCode('enter-initial-code', process.env.AIDRUN_AUTH_LIFECYCLE_CODE);
  }
  const verified = await http('POST', '/api/auth/verify-code', {
    body: { phone, code: selectedCode }
  });
  if (!verified.body.token || !verified.body.userId) {
    throw new Error(`Unexpected verify-code response: ${JSON.stringify(verified.body)}`);
  }
  return verified.body;
}

async function requestReregistrationCode() {
  await http('POST', '/api/auth/send-code', { body: { phone } });
  return readCode(
    'enter-reregistration-code',
    process.env.AIDRUN_AUTH_LIFECYCLE_REREGISTRATION_CODE
  );
}

async function requestSecondarySessionCode() {
  await http('POST', '/api/auth/send-code', { body: { phone } });
  return readCode(
    'enter-secondary-session-code',
    process.env.AIDRUN_AUTH_LIFECYCLE_SECONDARY_CODE
  );
}

async function ensureBlindRole(session) {
  if (session.role === 'BLIND') return session;
  const selected = await http('POST', '/api/user/role', {
    token: session.token,
    body: { role: 'BLIND' },
    allowFailure: true
  });
  if (!selected.ok) {
    throw new Error(`Unable to select BLIND role (${selected.status}): ${JSON.stringify(selected.rawBody)}`);
  }
  return { ...session, ...selected.body, token: selected.body.token ?? session.token };
}

async function prepareBlindProfile(session) {
  await http('PUT', '/api/blind/profile', {
    token: session.token,
    body: {
      name: `生命周期探针${phone.slice(-4)}`,
      runningPace: 'MODERATE',
      visionLevel: 'LOW_VISION',
      hasGuideDog: false,
      tetherPreference: 'TETHER_ROPE',
      chatPreference: 'NO_PREFERENCE',
      defaultPace: 'MODERATE'
    }
  });

  const path = `/api/users/${session.userId}/emergency-contacts`;
  const existing = await http('GET', path, { token: session.token, allowFailure: true });
  if (existing.ok && Array.isArray(existing.body) && existing.body.length > 0) return;
  await http('POST', path, {
    token: session.token,
    body: {
      name: '生命周期探针联系人',
      phone: '13800001111',
      relationship: '家人',
      isPrimary: true
    }
  });
}

function backendDateTime(date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}:${values.second}`;
}

async function createBlockingOrder(session) {
  const created = await http('POST', '/api/orders', {
    token: session.token,
    body: {
      startLatitude: 39.9042,
      startLongitude: 116.4074,
      startAddress: '账户生命周期云端探针起点',
      plannedStartTime: backendDateTime(new Date(Date.now() + 60 * 60 * 1000)),
      plannedEndTime: backendDateTime(new Date(Date.now() + 2 * 60 * 60 * 1000)),
      expectedDurationMinutes: 60,
      pacePreference: 'MODERATE',
      routePreference: 'PARK_TRAIL',
      routeNotes: '账户生命周期云端契约探针',
      hasGuideDogThisRun: false,
      specialNotes: '测试完成后自动取消'
    }
  });
  const id = created.body.id ?? created.body.orderId;
  if (!id) throw new Error(`Unexpected create-order response: ${JSON.stringify(created.body)}`);
  return id;
}

async function expectUnauthorized(token, label) {
  const response = await http('GET', '/api/auth/me', { token, allowFailure: true });
  if (response.status !== 401) {
    throw new Error(`${label} expected 401, got ${response.status}: ${JSON.stringify(response.rawBody)}`);
  }
}

async function deleteSelf(token, userId) {
  return http('DELETE', `/api/users/${userId}`, { token });
}

async function main() {
  log('authenticate', result.phone);
  const skipInitialSend = process.env.AIDRUN_AUTH_LIFECYCLE_SKIP_INITIAL_SEND === '1';
  const first = await authenticate({
    sendCode: !skipInitialSend,
    code: skipInitialSend ? process.env.AIDRUN_AUTH_LIFECYCLE_CODE : undefined
  });
  result.userId = first.userId;
  cleanupToken = first.token;
  cleanupUserId = first.userId;
  await http('GET', '/api/auth/me', { token: first.token });

  log('probe-logout-blacklist');
  const parallelSession = await ensureBlindRole(first);
  await http('POST', '/api/auth/logout', { token: first.token });
  await expectUnauthorized(first.token, 'Logged-out token');
  await http('GET', '/api/auth/me', { token: parallelSession.token });
  result.logoutBlacklistRejected = true;
  cleanupToken = parallelSession.token;

  log('probe-delete-ownership');
  const foreignId = Number(parallelSession.userId) + 900000000;
  const ownership = await http('DELETE', `/api/users/${foreignId}`, {
    token: parallelSession.token,
    allowFailure: true
  });
  if (ownership.status !== 403) {
    throw new Error(`Foreign delete expected 403, got ${ownership.status}: ${JSON.stringify(ownership.rawBody)}`);
  }
  await http('GET', '/api/auth/me', { token: parallelSession.token });
  result.deleteOwnershipRejected = true;

  log('probe-active-order-deletion');
  const blind = await ensureBlindRole(parallelSession);
  cleanupToken = blind.token;
  await prepareBlindProfile(blind);
  activeOrderId = await createBlockingOrder(blind);
  const blocked = await http('DELETE', `/api/users/${blind.userId}`, {
    token: blind.token,
    allowFailure: true
  });
  if (blocked.status !== 409 || errorCode(blocked.rawBody) !== 'ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED') {
    throw new Error(`Active-order delete expected 409/ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED, got ${blocked.status}/${errorCode(blocked.rawBody) ?? 'no-code'}: ${JSON.stringify(blocked.rawBody)}`);
  }
  await http('GET', '/api/auth/me', { token: blind.token });
  result.activeOrderDeletionBlocked = true;
  await http('POST', `/api/orders/${activeOrderId}/cancel`, { token: blind.token });
  activeOrderId = null;

  log('probe-soft-delete-and-all-token-invalidation');
  log('send-secondary-session-code');
  const secondaryCode = await requestSecondarySessionCode();
  const secondToken = (await authenticate({ code: secondaryCode })).token;
  const deletion = await deleteSelf(blind.token, blind.userId);
  if (deletion.body.success !== true
      || deletion.body.phoneReusable !== true
      || deletion.body.allTokensInvalidated !== true) {
    throw new Error(`Unexpected delete response: ${JSON.stringify(deletion.body)}`);
  }
  result.softDeletionConfirmed = true;
  cleanupToken = null;
  cleanupUserId = null;
  await expectUnauthorized(blind.token, 'Deleting token');
  await expectUnauthorized(secondToken, 'Second account token');
  result.allTokensInvalidated = true;

  log('probe-phone-reregistration');
  const reregistrationCode = await requestReregistrationCode();
  const recreated = await authenticate({ code: reregistrationCode });
  result.recreatedUserId = recreated.userId;
  cleanupToken = recreated.token;
  cleanupUserId = recreated.userId;
  await http('GET', '/api/auth/me', { token: recreated.token });
  result.phoneReregistered = true;

  log('final-cleanup-delete');
  const finalDeletion = await deleteSelf(recreated.token, recreated.userId);
  if (finalDeletion.body.success !== true) {
    throw new Error(`Final cleanup delete returned an unexpected response: ${JSON.stringify(finalDeletion.body)}`);
  }
  result.finalCleanupDeleted = true;
  cleanupToken = null;
  cleanupUserId = null;

  console.log('\n[auth-lifecycle-probe] summary');
  console.log(JSON.stringify(result, null, 2));
}

async function cleanup() {
  if (activeOrderId && cleanupToken) {
    const cancelled = await http('POST', `/api/orders/${activeOrderId}/cancel`, {
      token: cleanupToken,
      allowFailure: true
    });
    log('cleanup-order', `id=${activeOrderId} status=${cancelled.status}`);
    if (cancelled.ok) activeOrderId = null;
  }
  if (!activeOrderId && cleanupToken && cleanupUserId) {
    const deleted = await http('DELETE', `/api/users/${cleanupUserId}`, {
      token: cleanupToken,
      allowFailure: true
    });
    log('cleanup-account', `id=${cleanupUserId} status=${deleted.status}`);
  }
}

main().catch(async error => {
  console.error('\n[auth-lifecycle-probe] failed');
  console.error(error.stack ?? error.message);
  try {
    await cleanup();
  } catch (cleanupError) {
    console.error(`[auth-lifecycle-probe] cleanup failed: ${cleanupError.message}`);
  }
  console.error('\n[auth-lifecycle-probe] partial summary');
  console.error(JSON.stringify(result, null, 2));
  process.exitCode = 1;
});
