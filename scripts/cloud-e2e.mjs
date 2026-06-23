#!/usr/bin/env node

const baseURL = 'http://47.114.113.171';
const defaultVerificationCode = '000000';
const timeoutMs = Number(process.env.AIDRUN_E2E_TIMEOUT_MS ?? 25000);

const created = {
  baseURL,
  blindPhone: '',
  volunteerPhone: '',
  blindUserId: null,
  volunteerUserId: null,
  orderId: null,
  emergencyOrderId: null,
  emergencyEventId: null,
  finalOrderStatus: null,
  webSocket: {
    blindConnected: false,
    volunteerConnected: false,
    volunteerReceivedNewOrder: false,
    blindMessages: [],
    volunteerMessages: []
  },
  backendStartEndpointNeeded: false
};

function log(step, detail = '') {
  const suffix = detail ? ` ${detail}` : '';
  console.log(`[cloud-e2e] ${step}${suffix}`);
}

function uniquePhones() {
  const seed = Number(String(Date.now()).slice(-8));
  const blindTail = String(seed).padStart(8, '0').slice(-8);
  const volunteerTail = String((seed + 1) % 100000000).padStart(8, '0');
  return [`139${blindTail}`, `139${volunteerTail}`];
}

function selectedPhones() {
  const blindPhone = process.env.AIDRUN_E2E_BLIND_PHONE;
  const volunteerPhone = process.env.AIDRUN_E2E_VOLUNTEER_PHONE;
  if (blindPhone && volunteerPhone) {
    return [blindPhone, volunteerPhone, true];
  }
  const [generatedBlindPhone, generatedVolunteerPhone] = uniquePhones();
  return [blindPhone ?? generatedBlindPhone, volunteerPhone ?? generatedVolunteerPhone, false];
}

function shouldSkipProfileSetup(usingSeedAccounts) {
  return process.env.AIDRUN_E2E_SKIP_PROFILE_SETUP === '1' || (
    usingSeedAccounts && process.env.AIDRUN_E2E_SKIP_PROFILE_SETUP !== '0'
  );
}

function jsonHeaders(token) {
  return {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {})
  };
}

function unwrap(value) {
  if (value && typeof value === 'object' && 'data' in value && value.data && typeof value.data === 'object') {
    return value.data;
  }
  return value;
}

async function http(method, path, { token, body, allowFailure = false, retry429 = true } = {}) {
  const response = await fetch(new URL(path, baseURL), {
    method,
    headers: jsonHeaders(token),
    body: body === undefined ? undefined : JSON.stringify(body)
  });

  const text = await response.text();
  let parsed = null;
  if (text.trim()) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { raw: text };
    }
  }

  if (response.status === 429 && retry429) {
    const retryAfterSeconds = Number(parsed?.retryAfterSeconds ?? 60);
    log('rate-limit', `${method} ${path}; retry after ${retryAfterSeconds}s`);
    await sleep((retryAfterSeconds + 1) * 1000);
    return http(method, path, { token, body, allowFailure, retry429: false });
  }

  if (!response.ok && !allowFailure) {
    const error = new Error(`${method} ${path} failed with ${response.status}: ${text}`);
    error.status = response.status;
    error.body = parsed;
    throw error;
  }

  return {
    ok: response.ok,
    status: response.status,
    body: unwrap(parsed ?? {})
  };
}

function verificationCodeFromSendResponse(response, fallback) {
  return response.body.code
    ?? response.body.verificationCode
    ?? response.body.smsCode
    ?? fallback;
}

async function login(phone, role, codeFallback) {
  log('send-code', `${phone}`);
  const sendResponse = await http('POST', '/api/auth/send-code', { body: { phone } });
  const code = verificationCodeFromSendResponse(sendResponse, codeFallback);

  log('verify-code', `${phone}`);
  const loginResponse = await http('POST', '/api/auth/verify-code', {
    body: { phone, code }
  });
  const loginBody = loginResponse.body;
  if (!loginBody.token || !loginBody.userId) {
    throw new Error(`verify-code returned an unexpected response for ${phone}: ${JSON.stringify(loginBody)}`);
  }

  log('set-role', `${phone} -> ${role}`);
  const roleResponse = await http('POST', '/api/user/role', {
    token: loginBody.token,
    body: { role },
    allowFailure: true
  });
  if (!roleResponse.ok) {
    if (roleResponse.status === 409 && loginBody.role === role) {
      log('set-role-skip', `${phone} already ${role}`);
    } else {
      throw new Error(`set-role failed for ${phone} with ${roleResponse.status}: ${JSON.stringify(roleResponse.body)}`);
    }
  }
  return {
    phone,
    userId: loginBody.userId,
    token: roleResponse.body.token ?? loginBody.token,
    role: roleResponse.body.role ?? loginBody.role ?? role
  };
}

async function openSocket(path, token, label, messages) {
  const url = new URL(path, baseURL);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.searchParams.set('token', token);

  log('ws-connect', `${label} ${url.origin}${url.pathname}`);

  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    const timer = setTimeout(() => {
      try {
        socket.close();
      } catch {}
      reject(new Error(`${label} WebSocket did not open within ${timeoutMs}ms`));
    }, timeoutMs);

    socket.addEventListener('open', () => {
      clearTimeout(timer);
      resolve(socket);
    });

    socket.addEventListener('message', event => {
      const text = typeof event.data === 'string' ? event.data : String(event.data);
      try {
        messages.push(JSON.parse(text));
      } catch {
        messages.push({ raw: text });
      }
    });

    socket.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error(`${label} WebSocket failed to connect`));
    });
  });
}

function sendLocation(socket, lat, lng) {
  socket.send(JSON.stringify({ type: 'LOCATION_UPDATE', lat, lng }));
}

function formatBackendDateTime(date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}T${values.hour}:${values.minute}:${values.second}`;
}

async function sleep(ms) {
  await new Promise(resolve => setTimeout(resolve, ms));
}

async function waitFor(predicate, label, waitMs = timeoutMs) {
  const started = Date.now();
  while (Date.now() - started < waitMs) {
    const result = predicate();
    if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  throw new Error(`Timed out waiting for ${label}`);
}

async function updateBlindProfile(blind) {
  log('blind-profile', `${blind.userId}`);
  await http('PUT', '/api/blind/profile', {
    token: blind.token,
    body: {
      name: `E2E盲人${blind.phone.slice(-4)}`,
      runningPace: 'MODERATE',
      visionLevel: 'LOW_VISION',
      hasGuideDog: false,
      tetherPreference: 'TETHER_ROPE',
      chatPreference: 'NO_PREFERENCE',
      defaultPace: 'MODERATE'
    }
  });

  const contact = await http('POST', `/api/users/${blind.userId}/emergency-contacts`, {
    token: blind.token,
    body: {
      name: 'E2E紧急联系人',
      phone: '13800001111',
      relationship: '家人',
      isPrimary: true
    }
  });
  log('emergency-contact', `id=${contact.body.id ?? 'unknown'}`);
}

async function updateVolunteerProfile(volunteer) {
  log('volunteer-profile', `${volunteer.userId}`);
  const response = await http('PUT', '/api/volunteer/profile', {
    token: volunteer.token,
    body: {
      name: `E2E志愿者${volunteer.phone.slice(-4)}`,
      paceRange: 'MODERATE',
      acceptsGuideDog: true,
      isAvailable: true,
      availableTimeSlots: [
        { dayOfWeek: 'SATURDAY', startTime: '09:00', endTime: '12:00' },
        { dayOfWeek: 'SUNDAY', startTime: '09:00', endTime: '12:00' }
      ]
    },
    allowFailure: true
  });

  if (!response.ok) {
    throw new Error(`Volunteer profile/availability update failed with ${response.status}: ${JSON.stringify(response.body)}`);
  }
}

async function setVolunteerAvailable(volunteer) {
  log('volunteer-availability', `${volunteer.userId}`);
  const response = await http('PUT', '/api/volunteer/profile', {
    token: volunteer.token,
    body: {
      name: `E2E志愿者${volunteer.phone.slice(-4)}`,
      paceRange: 'MODERATE',
      acceptsGuideDog: true,
      isAvailable: true,
      availableTimeSlots: [
        { dayOfWeek: 'SATURDAY', startTime: '09:00', endTime: '12:00' },
        { dayOfWeek: 'SUNDAY', startTime: '09:00', endTime: '12:00' }
      ]
    },
    allowFailure: true
  });

  if (!response.ok) {
    throw new Error(`Volunteer availability update failed with ${response.status}: ${JSON.stringify(response.body)}`);
  }
}

async function createOrder(blind, suffix = '') {
  const start = new Date(Date.now() + 60 * 60 * 1000);
  const end = new Date(Date.now() + 2 * 60 * 60 * 1000);
  const response = await http('POST', '/api/orders', {
    token: blind.token,
    body: {
      startLatitude: 39.9042,
      startLongitude: 116.4074,
      startAddress: `E2E云端联调起点${suffix}`,
      plannedStartTime: formatBackendDateTime(start),
      plannedEndTime: formatBackendDateTime(end),
      expectedDurationMinutes: 60,
      pacePreference: 'MODERATE',
      routePreference: 'PARK_TRAIL',
      routeNotes: '云端E2E自动化测试',
      hasGuideDogThisRun: false,
      specialNotes: '可删除的测试数据'
    }
  });

  const orderId = response.body.id ?? response.body.orderId;
  if (!orderId) {
    throw new Error(`create order returned an unexpected response: ${JSON.stringify(response.body)}`);
  }
  log('order-created', `id=${orderId} status=${response.body.status ?? 'unknown'}`);
  return orderId;
}

async function acceptOrder(volunteer, orderId, volunteerMessages) {
  const newOrder = volunteerMessages.find(message => message.type === 'NEW_ORDER' && Number(message.orderId) === Number(orderId));
  if (newOrder) {
    created.webSocket.volunteerReceivedNewOrder = true;
    log('ws-new-order', `orderId=${newOrder.orderId}`);
  } else {
    log('ws-new-order', 'not received before fallback; checking available orders');
    await http('GET', '/api/orders/available', { token: volunteer.token, allowFailure: true });
  }

  await http('POST', `/api/orders/${orderId}/accept`, { token: volunteer.token });
  log('order-accept', `id=${orderId}`);
}

async function getOrder(token, orderId) {
  const response = await http('GET', `/api/orders/${orderId}`, { token });
  return response.body;
}

async function transitionOrder(volunteer, orderId, volunteerSocket) {
  await http('POST', `/api/orders/${orderId}/en-route`, { token: volunteer.token });
  log('order-en-route', `id=${orderId}`);
  sendLocation(volunteerSocket, 39.9052, 116.4082);
  await sleep(1000);

  await http('POST', `/api/orders/${orderId}/arrived`, { token: volunteer.token });
  log('order-arrived', `id=${orderId}`);
  sendLocation(volunteerSocket, 39.9053, 116.4083);
  await sleep(1000);

  const finish = await http('POST', `/api/orders/${orderId}/finish`, {
    token: volunteer.token,
    allowFailure: true
  });
  if (!finish.ok) {
    const payload = JSON.stringify(finish.body);
    if (payload.includes('INVALID_ORDER_STATUS') || payload.includes('IN_PROGRESS')) {
      created.backendStartEndpointNeeded = true;
    }
    throw new Error(`finish from DRIVER_ARRIVED failed with ${finish.status}: ${payload}`);
  }

  const detail = await getOrder(volunteer.token, orderId);
  created.finalOrderStatus = detail.status ?? finish.body.status ?? null;
  log('order-finished', `id=${orderId} status=${created.finalOrderStatus}`);
}

async function triggerEmergency(blind, volunteer, volunteerMessages) {
  const orderId = await createOrder(blind, '-emergency');
  created.emergencyOrderId = orderId;
  await sleep(3000);
  await acceptOrder(volunteer, orderId, volunteerMessages);
  await http('POST', `/api/orders/${orderId}/en-route`, { token: volunteer.token });

  const emergency = await http('POST', '/api/emergency/trigger', {
    token: blind.token,
    body: { orderId, gpsLat: 39.9042, gpsLng: 116.4074 }
  });
  created.emergencyEventId = emergency.body.eventId ?? emergency.body.id ?? emergency.body.emergencyEvent?.id ?? null;
  log('emergency-triggered', `orderId=${orderId} eventId=${created.emergencyEventId ?? 'unknown'}`);
}

async function main() {
  const [blindPhone, volunteerPhone, usingSeedAccounts] = selectedPhones();
  created.blindPhone = blindPhone;
  created.volunteerPhone = volunteerPhone;

  const blind = await login(
    blindPhone,
    'BLIND',
    defaultVerificationCode
  );
  const volunteer = await login(
    volunteerPhone,
    'VOLUNTEER',
    defaultVerificationCode
  );
  created.blindUserId = blind.userId;
  created.volunteerUserId = volunteer.userId;

  if (shouldSkipProfileSetup(usingSeedAccounts)) {
    log('profile-setup', 'seeded accounts: ensure blind contact and volunteer availability');
    await updateBlindProfile(blind);
    await setVolunteerAvailable(volunteer);
  } else {
    await updateBlindProfile(blind);
    await updateVolunteerProfile(volunteer);
  }

  const blindSocket = await openSocket('/ws/blind', blind.token, 'blind', created.webSocket.blindMessages);
  created.webSocket.blindConnected = true;
  const volunteerSocket = await openSocket('/ws/volunteer', volunteer.token, 'volunteer', created.webSocket.volunteerMessages);
  created.webSocket.volunteerConnected = true;

  sendLocation(blindSocket, 39.9042, 116.4074);
  sendLocation(volunteerSocket, 39.905, 116.408);
  sendLocation(volunteerSocket, 39.9051, 116.4081);

  const orderId = await createOrder(blind);
  created.orderId = orderId;

  await sleep(5000);
  await acceptOrder(volunteer, orderId, created.webSocket.volunteerMessages);
  await transitionOrder(volunteer, orderId, volunteerSocket);
  await triggerEmergency(blind, volunteer, created.webSocket.volunteerMessages);

  await new Promise(resolve => setTimeout(resolve, 1500));
  blindSocket.close();
  volunteerSocket.close();

  console.log('\n[cloud-e2e] summary');
  console.log(JSON.stringify(created, null, 2));

  if (created.finalOrderStatus !== 'COMPLETED') {
    throw new Error(`Expected final order status COMPLETED, got ${created.finalOrderStatus}`);
  }
  if (!created.webSocket.blindConnected || !created.webSocket.volunteerConnected) {
    throw new Error('Expected both WebSocket connections to open');
  }
}

main().catch(error => {
  console.error('\n[cloud-e2e] failed');
  console.error(error.stack || error.message);
  console.error('\n[cloud-e2e] partial summary');
  console.error(JSON.stringify(created, null, 2));
  process.exitCode = 1;
});
