#!/usr/bin/env node

const baseURL = 'http://47.114.113.171';
const defaultVerificationCode = '000000';
const defaultBlindPhone = '13800000001';
const defaultVolunteerPhone = '13800000002';
const timeoutMs = Number(process.env.AIDRUN_E2E_TIMEOUT_MS ?? 25000);
const dispatchWaitMs = Number(process.env.AIDRUN_E2E_DISPATCH_WAIT_MS ?? 30000);
const orderStartLocation = { lat: 39.9042, lng: 116.4074 };
const volunteerDispatchLocation = { lat: 39.9050, lng: 116.4080 };
const allWeekAvailabilitySlots = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY'
].map(dayOfWeek => ({ dayOfWeek, startTime: '00:00', endTime: '23:59' }));

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
  dispatchReadiness: {
    readyVia: null,
    preOrderLocationReports: 0,
    postOrderLocationReports: 0,
    lastAvailable: null
  },
  backendStartEndpointNeeded: false
};

const runtime = {
  blindToken: null,
  blindSocket: null,
  volunteerSocket: null
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
  if (process.env.AIDRUN_E2E_USE_GENERATED_PHONES === '1') {
    const [generatedBlindPhone, generatedVolunteerPhone] = uniquePhones();
    return [blindPhone ?? generatedBlindPhone, volunteerPhone ?? generatedVolunteerPhone, false];
  }
  return [blindPhone ?? defaultBlindPhone, volunteerPhone ?? defaultVolunteerPhone, true];
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

async function reportVolunteerDispatchLocation(socket, count, phase) {
  for (let index = 0; index < count; index += 1) {
    sendLocation(socket, volunteerDispatchLocation.lat, volunteerDispatchLocation.lng);
    if (phase === 'pre-order') {
      created.dispatchReadiness.preOrderLocationReports += 1;
    } else {
      created.dispatchReadiness.postOrderLocationReports += 1;
    }
    log('volunteer-location', `${phase} lat=${volunteerDispatchLocation.lat} lng=${volunteerDispatchLocation.lng}`);
    if (index < count - 1) {
      await sleep(1000);
    }
  }
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

  const contactsPath = `/api/users/${blind.userId}/emergency-contacts`;
  const existingContacts = await http('GET', contactsPath, {
    token: blind.token,
    allowFailure: true
  });
  if (existingContacts.ok && Array.isArray(existingContacts.body) && existingContacts.body.length > 0) {
    log('emergency-contact', `reuse id=${existingContacts.body[0].id ?? 'unknown'}`);
    return;
  }

  const contact = await http('POST', contactsPath, {
    token: blind.token,
    body: {
      name: 'E2E紧急联系人',
      phone: '13800001111',
      relationship: '家人',
      isPrimary: true
    },
    allowFailure: true
  });
  if (contact.ok) {
    log('emergency-contact', `id=${contact.body.id ?? 'unknown'}`);
    return;
  }

  const fallbackContacts = await http('GET', contactsPath, {
    token: blind.token,
    allowFailure: true
  });
  if (fallbackContacts.ok && Array.isArray(fallbackContacts.body) && fallbackContacts.body.length > 0) {
    log('emergency-contact', `reuse-after-create-failure id=${fallbackContacts.body[0].id ?? 'unknown'}`);
    return;
  }

  throw new Error(`Emergency contact setup failed with ${contact.status}: ${JSON.stringify(contact.body)}`);
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
      wantsDispatch: true,
      availableTimeSlots: allWeekAvailabilitySlots
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
      wantsDispatch: true,
      availableTimeSlots: allWeekAvailabilitySlots
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
      startLatitude: orderStartLocation.lat,
      startLongitude: orderStartLocation.lng,
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

function findNewOrder(volunteerMessages, orderId) {
  return volunteerMessages.find(message => message.type === 'NEW_ORDER' && Number(message.orderId) === Number(orderId));
}

async function checkAvailableOrder(volunteer, orderId) {
  const availableResponse = await http('GET', '/api/orders/available', { token: volunteer.token, allowFailure: true });
  const availableOrders = Array.isArray(availableResponse.body.content) ? availableResponse.body.content : [];
  const containsOrder = availableOrders.some(order => Number(order.id ?? order.orderId) === Number(orderId));
  const summary = {
    status: availableResponse.status,
    count: availableOrders.length,
    containsOrder
  };
  created.dispatchReadiness.lastAvailable = summary;
  log('available-orders', `status=${summary.status} count=${summary.count} containsOrder=${summary.containsOrder}`);
  return summary;
}

async function waitForDispatchReadiness(volunteer, orderId, volunteerMessages, volunteerSocket) {
  const started = Date.now();
  let nextLocationReportAt = 0;

  while (Date.now() - started < dispatchWaitMs) {
    const newOrder = findNewOrder(volunteerMessages, orderId);
    if (newOrder) {
      created.webSocket.volunteerReceivedNewOrder = true;
      created.dispatchReadiness.readyVia = 'NEW_ORDER';
      log('dispatch-ready', `NEW_ORDER orderId=${newOrder.orderId}`);
      return;
    }

    if (Date.now() >= nextLocationReportAt) {
      await reportVolunteerDispatchLocation(volunteerSocket, 1, 'post-order');
      nextLocationReportAt = Date.now() + 2000;
    }

    const available = await checkAvailableOrder(volunteer, orderId);
    if (available.containsOrder) {
      created.dispatchReadiness.readyVia = 'available-orders';
      log('dispatch-ready', `available orderId=${orderId}`);
      return;
    }

    await sleep(1000);
  }

  throw new Error(
    `Dispatch readiness timed out after ${dispatchWaitMs}ms: no NEW_ORDER and /api/orders/available did not contain order ${orderId}`
  );
}

async function acceptOrder(volunteer, orderId, volunteerMessages, volunteerSocket) {
  const newOrder = findNewOrder(volunteerMessages, orderId);
  if (newOrder) {
    created.webSocket.volunteerReceivedNewOrder = true;
    created.dispatchReadiness.readyVia = 'NEW_ORDER';
    log('ws-new-order', `orderId=${newOrder.orderId}`);
  } else {
    log('ws-new-order', 'not received yet; waiting for dispatch readiness');
    await waitForDispatchReadiness(volunteer, orderId, volunteerMessages, volunteerSocket);
  }

  await http('POST', `/api/orders/${orderId}/respond`, {
    token: volunteer.token,
    body: { action: 'ACCEPT' }
  });
  log('order-respond-accept', `id=${orderId}`);
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
  await acceptOrder(volunteer, orderId, volunteerMessages, runtime.volunteerSocket);
  await http('POST', `/api/orders/${orderId}/en-route`, { token: volunteer.token });

  const emergency = await http('POST', '/api/emergency/trigger', {
    token: blind.token,
    body: { orderId, gpsLat: 39.9042, gpsLng: 116.4074 }
  });
  created.emergencyEventId = emergency.body.eventId ?? emergency.body.id ?? emergency.body.emergencyEvent?.id ?? null;
  log('emergency-triggered', `orderId=${orderId} eventId=${created.emergencyEventId ?? 'unknown'}`);

  const arrived = await http('POST', `/api/orders/${orderId}/arrived`, {
    token: volunteer.token,
    allowFailure: true
  });
  log('emergency-order-arrived', `id=${orderId} status=${arrived.status} ok=${arrived.ok}`);

  const finish = await http('POST', `/api/orders/${orderId}/finish`, {
    token: volunteer.token,
    allowFailure: true
  });
  log('emergency-order-finish', `id=${orderId} status=${finish.status} ok=${finish.ok}`);
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
  runtime.blindToken = blind.token;

  if (shouldSkipProfileSetup(usingSeedAccounts)) {
    log('profile-setup', 'seeded accounts: ensure blind contact and volunteer availability');
    await updateBlindProfile(blind);
    await setVolunteerAvailable(volunteer);
  } else {
    await updateBlindProfile(blind);
    await updateVolunteerProfile(volunteer);
  }

  const blindSocket = await openSocket('/ws/blind', blind.token, 'blind', created.webSocket.blindMessages);
  runtime.blindSocket = blindSocket;
  created.webSocket.blindConnected = true;
  const volunteerSocket = await openSocket('/ws/volunteer', volunteer.token, 'volunteer', created.webSocket.volunteerMessages);
  runtime.volunteerSocket = volunteerSocket;
  created.webSocket.volunteerConnected = true;

  sendLocation(blindSocket, orderStartLocation.lat, orderStartLocation.lng);
  await reportVolunteerDispatchLocation(volunteerSocket, 3, 'pre-order');

  const orderId = await createOrder(blind);
  created.orderId = orderId;

  await acceptOrder(volunteer, orderId, created.webSocket.volunteerMessages, volunteerSocket);
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

function closeRuntimeSockets() {
  runtime.blindSocket?.close();
  runtime.volunteerSocket?.close();
}

async function cleanupCreatedOrders() {
  if (!runtime.blindToken) return;
  const ids = [created.orderId, created.emergencyOrderId].filter(Boolean);
  for (const orderId of ids) {
    if (Number(orderId) === Number(created.orderId) && created.finalOrderStatus === 'COMPLETED') {
      continue;
    }
    const response = await http('POST', `/api/orders/${orderId}/cancel`, {
      token: runtime.blindToken,
      allowFailure: true
    });
    log('cleanup-order', `id=${orderId} status=${response.status} ok=${response.ok}`);
  }
}

main().catch(async error => {
  closeRuntimeSockets();
  try {
    await cleanupCreatedOrders();
  } catch (cleanupError) {
    log('cleanup-error', cleanupError.message);
  }
  console.error('\n[cloud-e2e] failed');
  console.error(error.stack || error.message);
  console.error('\n[cloud-e2e] partial summary');
  console.error(JSON.stringify(created, null, 2));
  process.exitCode = 1;
});
