#!/usr/bin/env node

const baseURL = process.env.AIDRUN_ADMIN_BASE_URL ?? 'http://47.114.113.171';
const username = process.env.AIDRUN_ADMIN_USERNAME ?? 'admin';
const password = process.env.AIDRUN_ADMIN_PASSWORD ?? 'admin123';
const explicitUserId = process.env.AIDRUN_ADMIN_REVIEW_USER_ID;
const reviewPhone = process.env.AIDRUN_ADMIN_REVIEW_PHONE;
const approved = process.env.AIDRUN_ADMIN_APPROVED !== '0';
const rejectionReason = process.env.AIDRUN_ADMIN_REJECTION_REASON ?? '';
const reviewKind = process.env.AIDRUN_ADMIN_REVIEW_KIND ?? 'id';

function usage() {
  console.error([
    'Usage:',
    '  AIDRUN_ADMIN_REVIEW_USER_ID=<userId> scripts/admin-review-volunteer.mjs',
    '',
    'Optional:',
    '  AIDRUN_ADMIN_USERNAME=<username>      Default: admin.',
    '  AIDRUN_ADMIN_PASSWORD=<password>      Default: admin123.',
    '  AIDRUN_ADMIN_REVIEW_PHONE=<phone>       Find userId from pending review lists.',
      '  AIDRUN_ADMIN_REVIEW_KIND=id|cert|both  Default: id.',
    '  AIDRUN_ADMIN_APPROVED=0                Reject instead of approve.',
    '  AIDRUN_ADMIN_REJECTION_REASON=<text>   Rejection reason.'
  ].join('\n'));
}

function unwrap(value) {
  if (value && typeof value === 'object' && 'data' in value) {
    return value.data;
  }
  return value;
}

async function http(method, path, { token, body, allowFailure = false } = {}) {
  const response = await fetch(new URL(path, baseURL), {
    method,
    headers: {
      Accept: 'application/json',
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let parsed = {};
  if (text.trim()) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { raw: text };
    }
  }
  if (!response.ok && !allowFailure) {
    throw new Error(`${method} ${path} failed with ${response.status}: ${text}`);
  }
  return { ok: response.ok, status: response.status, body: unwrap(parsed) };
}

async function login() {
  if (!username || !password) {
    usage();
    throw new Error('Missing AIDRUN_ADMIN_USERNAME or AIDRUN_ADMIN_PASSWORD');
  }
  const response = await http('POST', '/api/cs/auth/login', {
    body: { username, password }
  });
  const token = response.body?.token ?? response.body?.accessToken ?? response.body?.jwt;
  if (!token) {
    throw new Error(`Admin login did not return a token: ${JSON.stringify(response.body)}`);
  }
  return token;
}

async function resolveUserId(token) {
  if (explicitUserId) return Number(explicitUserId);
  if (!reviewPhone) {
    usage();
    throw new Error('Missing AIDRUN_ADMIN_REVIEW_USER_ID or AIDRUN_ADMIN_REVIEW_PHONE');
  }

  const lists = await Promise.all([
    http('GET', '/api/admin/volunteers/review/id', { token }),
    http('GET', '/api/admin/volunteers/review/cert', { token })
  ]);
  for (const list of lists) {
    const items = Array.isArray(list.body) ? list.body : [];
    const match = items.find(item => String(item.phone) === String(reviewPhone));
    if (match?.userId) return Number(match.userId);
  }
  throw new Error(`Could not find volunteer review item for phone ${reviewPhone}`);
}

async function review(token, userId, kind) {
  const path = kind === 'cert'
    ? '/api/admin/volunteers/review/cert'
    : '/api/admin/volunteers/review/id';
  const response = await http('POST', path, {
    token,
    body: {
      userId,
      approved,
      ...(approved ? {} : { rejectionReason })
    },
    allowFailure: true
  });
  if (!response.ok) {
    const message = response.body?.message ?? '';
    if (
      response.status === 400
      && (message.includes('不待审核') || message.includes('不在待审核状态'))
    ) {
      console.log(`[admin-review] ${kind} userId=${userId} skipped=${message}`);
      return;
    }
    throw new Error(`POST ${path} failed with ${response.status}: ${JSON.stringify(response.body)}`);
  }
  console.log(`[admin-review] ${kind} userId=${userId} status=${response.status}`);
}

async function main() {
  if (!['id', 'cert', 'both'].includes(reviewKind)) {
    throw new Error('AIDRUN_ADMIN_REVIEW_KIND must be id, cert, or both');
  }
  const token = await login();
  const userId = await resolveUserId(token);
  if (reviewKind === 'id' || reviewKind === 'both') {
    await review(token, userId, 'id');
  }
  if (reviewKind === 'cert' || reviewKind === 'both') {
    await review(token, userId, 'cert');
  }
  console.log(`[admin-review] complete userId=${userId} approved=${approved}`);
}

main().catch(error => {
  console.error(`[admin-review] failed: ${error.stack || error.message}`);
  process.exitCode = 1;
});
