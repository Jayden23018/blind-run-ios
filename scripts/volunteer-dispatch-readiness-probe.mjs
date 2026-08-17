#!/usr/bin/env node

const baseURL = 'http://47.114.113.171';
const phone = process.env.AIDRUN_DISPATCH_PROBE_PHONE;
const fallbackCode = process.env.AIDRUN_DISPATCH_PROBE_CODE ?? '000000';
const shouldSendCode = process.env.AIDRUN_DISPATCH_PROBE_SKIP_SEND_CODE !== '1';
const latitude = Number(process.env.AIDRUN_DISPATCH_PROBE_LAT ?? '25.0389');
const longitude = Number(process.env.AIDRUN_DISPATCH_PROBE_LNG ?? '102.7183');
const pollCount = Number(process.env.AIDRUN_DISPATCH_PROBE_POLL_COUNT ?? '3');
const pollIntervalMs = Number(process.env.AIDRUN_DISPATCH_PROBE_POLL_INTERVAL_MS ?? '2000');
const timeoutMs = Number(process.env.AIDRUN_DISPATCH_PROBE_TIMEOUT_MS ?? '20000');

if (!phone || !/^1[3-9]\d{9}$/.test(phone)) {
  throw new Error('Set AIDRUN_DISPATCH_PROBE_PHONE to an approved volunteer test phone number.');
}
if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
  throw new Error('Probe latitude and longitude must be finite numbers.');
}

const maskedPhone = `${phone.slice(0, 3)}****${phone.slice(-4)}`;

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
    throw new Error(`${method} ${path} failed with ${reply.status}: ${JSON.stringify(reply.body)}`);
  }
  return reply;
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

function profileSnapshot(body = {}) {
  return {
    namePresent: typeof body.name === 'string' && body.name.trim().length > 0,
    verificationStatus: body.verificationStatus ?? null,
    adminReviewStatus: body.adminReviewStatus ?? null,
    registrationStep: body.registrationStep ?? null,
    canAcceptOrders: body.canAcceptOrders ?? null,
    wantsDispatch: body.wantsDispatch ?? body.isAvailable ?? null,
    availableTimeSlotCount: Array.isArray(body.availableTimeSlots) ? body.availableTimeSlots.length : null
  };
}

function registrationSnapshot(body = {}) {
  const details = body.stepDetails ?? {};
  return {
    currentStep: body.currentStep ?? body.currentStepCode ?? null,
    canAcceptOrders: body.canAcceptOrders ?? null,
    idVerifyStatus: body.idVerifyStatus ?? details.idVerifyStatus ?? null,
    faceVerifyStatus: body.faceVerifyStatus ?? details.faceVerifyStatus ?? null
  };
}

function summarySnapshot(body = {}) {
  return {
    canDispatch: body.canDispatch ?? null,
    notAvailableReasons: Array.isArray(body.notAvailableReasons) ? body.notAvailableReasons : null,
    wantsDispatch: body.wantsDispatch ?? null,
    isOnline: body.isOnline ?? null,
    hasLastLocation: Number.isFinite(body.lastLat) && Number.isFinite(body.lastLng),
    lastLocationAt: body.lastLocationAt ?? null,
    coverageRadiusKm: body.coverageRadiusKm ?? null,
    isWithinServiceTime: body.isWithinServiceTime ?? null,
    activeOrderCount: Array.isArray(body.activeOrders) ? body.activeOrders.length : null,
    recentOrderCount: Array.isArray(body.recentOrders) ? body.recentOrders.length : null
  };
}

function classify(profile, registration, summary) {
  const issues = [];
  const step = registration.currentStep ?? profile.registrationStep;
  const canAcceptOrders = registration.canAcceptOrders ?? profile.canAcceptOrders;
  if (step === 'STEP_4_TRAINING' && canAcceptOrders !== true) {
    issues.push('LEGACY_REGISTRATION_NOT_MIGRATED');
  }
  if (summary.canDispatch === false && (!summary.notAvailableReasons || summary.notAvailableReasons.length === 0)) {
    issues.push('SUMMARY_MISSING_REASONS');
  }
  if (summary.coverageRadiusKm === null) {
    issues.push('SUMMARY_MISSING_COVERAGE');
  }
  for (const reason of summary.notAvailableReasons ?? []) {
    issues.push(`BACKEND_REASON_${reason}`);
  }
  return [...new Set(issues)];
}

function sleep(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function openVolunteerSocket(token) {
  const url = new URL('/ws/volunteer', baseURL);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.searchParams.set('token', token);

  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const timer = setTimeout(() => {
      socket.close();
      reject(new Error('Volunteer WebSocket did not open before the timeout.'));
    }, timeoutMs);
    socket.addEventListener('open', () => {
      clearTimeout(timer);
      resolve(socket);
    }, { once: true });
    socket.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error('Volunteer WebSocket connection failed.'));
    }, { once: true });
  });
}

async function main() {
  let selectedCode = fallbackCode;
  if (shouldSendCode) {
    const sent = await http('POST', '/api/auth/send-code', { body: { phone } });
    selectedCode = sixDigitCode(sent, fallbackCode);
  }
  if (!selectedCode) {
    throw new Error('No six-digit verification code is available. Set AIDRUN_DISPATCH_PROBE_CODE.');
  }

  const login = await http('POST', '/api/auth/verify-code', {
    body: { phone, code: selectedCode },
    allowFailure: true
  });
  if (!login.ok) {
    console.log(JSON.stringify({
      baseURL,
      phone: maskedPhone,
      persistentProfileOrAvailabilityMutation: false,
      reportedEphemeralLocation: false,
      authenticated: false,
      errorCode: login.body?.errorCode ?? login.body?.code ?? null,
      message: login.body?.message ?? 'Verification failed',
      issues: ['AUTH_FIXED_CODE_REJECTED'],
      nextAction: 'Set AIDRUN_DISPATCH_PROBE_CODE to the current SMS code and rerun the probe.'
    }, null, 2));
    process.exitCode = 2;
    return;
  }
  const token = login.body?.token;
  if (!token) {
    throw new Error(`verify-code returned no token: ${JSON.stringify(login.body)}`);
  }
  if (login.body.role !== 'VOLUNTEER') {
    throw new Error(`Probe refuses to switch roles; current role is ${login.body.role ?? 'unset'}.`);
  }

  const [me, profileReply, registrationReply, initialSummaryReply] = await Promise.all([
    http('GET', '/api/auth/me', { token }),
    http('GET', '/api/volunteer/profile', { token }),
    http('GET', '/api/volunteer/registration/status', { token }),
    http('GET', '/api/volunteer/dispatch-summary', { token })
  ]);
  const profile = profileSnapshot(profileReply.body);
  const registration = registrationSnapshot(registrationReply.body);
  const summaries = [summarySnapshot(initialSummaryReply.body)];

  const socket = await openVolunteerSocket(token);
  socket.send(JSON.stringify({ type: 'LOCATION_UPDATE', lat: latitude, lng: longitude }));
  for (let index = 0; index < pollCount; index += 1) {
    await sleep(pollIntervalMs);
    const reply = await http('GET', '/api/volunteer/dispatch-summary', { token });
    summaries.push(summarySnapshot(reply.body));
  }
  socket.close();

  const finalSummary = summaries.at(-1);
  const report = {
    baseURL,
    phone: maskedPhone,
    userId: me.body?.userId ?? login.body.userId ?? null,
    role: me.body?.role ?? login.body.role,
    persistentProfileOrAvailabilityMutation: false,
    reportedEphemeralLocation: true,
    profile,
    registration,
    summaries,
    issues: classify(profile, registration, finalSummary)
  };
  console.log(JSON.stringify(report, null, 2));
  if (report.issues.length > 0 || finalSummary.canDispatch !== true) {
    process.exitCode = 2;
  }
}

await main();
