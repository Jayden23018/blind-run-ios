#!/usr/bin/env node

const baseURL = 'http://47.114.113.171';
const defaultVerificationCode = '000000';
const defaultBlindPhone = '13800000001';
const defaultVolunteerPhone = '13800000002';
const timeoutMs = Number(process.env.AIDRUN_E2E_TIMEOUT_MS ?? 25000);
const dispatchWaitMs = Number(process.env.AIDRUN_E2E_DISPATCH_WAIT_MS ?? 30000);
const attributionWaitMs = Number(process.env.AIDRUN_E2E_ATTRIBUTION_WAIT_MS ?? 20000);
const redactDiagnostics = process.env.AIDRUN_REDACT_DIAGNOSTICS === '1';
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
  emergencyContractOrderId: null,
  emergencyContractEventId: null,
  finalOrderStatus: null,
  enRouteAttribution: {
    postStatus: null,
    postLatencyMs: null,
    detailStatus: null,
    detailLatencyMs: null,
    blindStatusEvent: false,
    volunteerStatusEvent: false,
    blindMessageId: null,
    volunteerMessageId: null,
    blindMessageTypes: [],
    volunteerMessageTypes: [],
    outcome: null
  },
  webSocket: {
    blindConnected: false,
    volunteerConnected: false,
    blindPong: false,
    volunteerPong: false,
    blindReceivedVolunteerLocation: false,
    volunteerReceivedBlindLocation: false,
    volunteerReceivedNewOrder: false,
    statusEvents: {},
    blindMessages: [],
    volunteerMessages: []
  },
  dispatchReadiness: {
    readyVia: null,
    preOrderLocationReports: 0,
    postOrderLocationReports: 0,
    lastAvailable: null
  },
  track: null
};

const runtime = {
  blindToken: null,
  volunteerToken: null,
  blindSocket: null,
  volunteerSocket: null
};

function log(step, detail = '') {
  const suffix = detail && !redactDiagnostics ? ` ${detail}` : '';
  console.log(`[cloud-e2e] ${step}${suffix}`);
}

function logAttribution() {
  const result = created.enRouteAttribution;
  console.log(
    `[cloud-e2e] en-route-attribution`
    + ` outcome=${result.outcome ?? 'unknown'}`
    + ` postStatus=${result.postStatus ?? 'unknown'}`
    + ` postLatencyMs=${result.postLatencyMs ?? 'unknown'}`
    + ` detailStatus=${result.detailStatus ?? 'unknown'}`
    + ` detailLatencyMs=${result.detailLatencyMs ?? 'unknown'}`
    + ` blindEvent=${result.blindStatusEvent}`
    + ` volunteerEvent=${result.volunteerStatusEvent}`
  );
}

function printableSummary() {
  if (!redactDiagnostics) return created;
  return {
    finalOrderStatus: created.finalOrderStatus,
    enRouteAttribution: created.enRouteAttribution,
    webSocket: {
      blindConnected: created.webSocket.blindConnected,
      volunteerConnected: created.webSocket.volunteerConnected,
      blindPong: created.webSocket.blindPong,
      volunteerPong: created.webSocket.volunteerPong,
      blindReceivedVolunteerLocation: created.webSocket.blindReceivedVolunteerLocation,
      volunteerReceivedBlindLocation: created.webSocket.volunteerReceivedBlindLocation,
      volunteerReceivedNewOrder: created.webSocket.volunteerReceivedNewOrder,
      statusEvents: created.webSocket.statusEvents
    },
    dispatchReadiness: {
      readyVia: created.dispatchReadiness.readyVia,
      preOrderLocationReports: created.dispatchReadiness.preOrderLocationReports,
      postOrderLocationReports: created.dispatchReadiness.postOrderLocationReports
    },
    track: created.track
  };
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

async function probeHeartbeats(blindSocket, volunteerSocket) {
  blindSocket.send(JSON.stringify({ type: 'PING' }));
  await sleep(600);
  volunteerSocket.send(JSON.stringify({ type: 'PING' }));

  await waitFor(
    () => created.webSocket.blindMessages.some(message => message.type === 'PONG'),
    'blind PONG'
  );
  created.webSocket.blindPong = true;
  await waitFor(
    () => created.webSocket.volunteerMessages.some(message => message.type === 'PONG'),
    'volunteer PONG'
  );
  created.webSocket.volunteerPong = true;
  log('ws-heartbeat', 'both roles received PONG');
}

async function probePeerLocations(orderId, blindSocket, volunteerSocket) {
  const blindBefore = created.webSocket.blindMessages.length;
  const volunteerBefore = created.webSocket.volunteerMessages.length;
  sendLocation(blindSocket, 39.9043, 116.4075);
  await sleep(600);
  sendLocation(volunteerSocket, 39.9044, 116.4076);

  await waitFor(
    () => created.webSocket.blindMessages.slice(blindBefore).some(message =>
      message.type === 'VOLUNTEER_LOCATION_UPDATE'
      && Number(message.orderId) === Number(orderId)
    ),
    'blind receiving volunteer location'
  );
  created.webSocket.blindReceivedVolunteerLocation = true;
  await waitFor(
    () => created.webSocket.volunteerMessages.slice(volunteerBefore).some(message =>
      message.type === 'BLIND_LOCATION_UPDATE'
      && Number(message.orderId) === Number(orderId)
    ),
    'volunteer receiving blind location'
  );
  created.webSocket.volunteerReceivedBlindLocation = true;
  log('ws-peer-location', `both directions orderId=${orderId}`);
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
  // 这条端点返的是 `AvailableOrderResponse` 裸数组，不是分页对象。
  // 这里曾经读 `body.content`，于是 `count` 恒为 0、`containsOrder` 恒为 false ——
  // 派单就绪的这条兜底路径静默失效了很久，日志看起来还一切正常。
  const availableOrders = Array.isArray(availableResponse.body) ? availableResponse.body : [];
  const containsOrder = availableOrders.some(order => Number(order.orderId) === Number(orderId));
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

  const ownershipDeadline = Date.now() + 5000;
  while (Date.now() < ownershipDeadline) {
    const detail = await http('GET', `/api/orders/${orderId}`, {
      token: volunteer.token,
      allowFailure: true
    });
    if (detail.ok) {
      log('order-ownership-confirmed', `id=${orderId} status=${detail.body.status ?? 'unknown'}`);
      return;
    }
    await sleep(500);
  }
  throw new Error(`Volunteer ownership was not readable after accepting order ${orderId}`);
}

async function getOrder(token, orderId) {
  const response = await http('GET', `/api/orders/${orderId}`, { token });
  return response.body;
}

function findOrderStatusEvent(messages, startIndex, orderId, toStatus) {
  return messages.slice(startIndex).find(message =>
    message.type === 'ORDER_STATUS_CHANGED'
    && Number(message.orderId) === Number(orderId)
    && message.toStatus === toStatus
  );
}

function isUUID(value) {
  return typeof value === 'string'
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function recordDualStatusEvents(fromStatus, toStatus, blindEvent, volunteerEvent) {
  for (const [role, event] of [['blind', blindEvent], ['volunteer', volunteerEvent]]) {
    if (event.fromStatus !== fromStatus) {
      throw new Error(
        `${toStatus} status event contract: ${role} fromStatus=${event.fromStatus ?? 'missing'}, expected ${fromStatus}`
      );
    }
    if (!isUUID(event.messageId)) {
      throw new Error(
        `${toStatus} status event contract: ${role} messageId is missing or not a UUID`
      );
    }
  }
  created.webSocket.statusEvents[toStatus] = {
    blindMessageId: blindEvent.messageId,
    volunteerMessageId: volunteerEvent.messageId
  };
}

async function waitForDualStatusEvents(orderId, fromStatus, toStatus, blindStartIndex, volunteerStartIndex) {
  let blindEvent;
  let volunteerEvent;
  await waitFor(() => {
    blindEvent = findOrderStatusEvent(
      created.webSocket.blindMessages,
      blindStartIndex,
      orderId,
      toStatus
    );
    volunteerEvent = findOrderStatusEvent(
      created.webSocket.volunteerMessages,
      volunteerStartIndex,
      orderId,
      toStatus
    );
    return blindEvent && volunteerEvent;
  }, `both roles receiving ${toStatus}`, attributionWaitMs);

  recordDualStatusEvents(fromStatus, toStatus, blindEvent, volunteerEvent);
  log('ws-order-status', `${fromStatus}->${toStatus} both roles received UUID events`);
  return { blindEvent, volunteerEvent };
}

async function probeEnRouteAttribution(volunteer, orderId) {
  const blindMessageIndex = created.webSocket.blindMessages.length;
  const volunteerMessageIndex = created.webSocket.volunteerMessages.length;
  const postStartedAt = Date.now();
  const post = await http('POST', `/api/orders/${orderId}/en-route`, {
    token: volunteer.token,
    allowFailure: true
  });
  created.enRouteAttribution.postStatus = post.status;
  created.enRouteAttribution.postLatencyMs = Date.now() - postStartedAt;
  if (!post.ok) {
    created.enRouteAttribution.outcome = 'backend_http_contract_or_permission';
    logAttribution();
    throw new Error(`en-route attribution probe: POST failed with ${post.status}`);
  }

  const detailStartedAt = Date.now();
  const detailDeadline = detailStartedAt + attributionWaitMs;
  while (Date.now() < detailDeadline) {
    const detail = await http('GET', `/api/orders/${orderId}`, {
      token: volunteer.token,
      allowFailure: true
    });
    if (detail.ok && detail.body.status === 'DRIVER_EN_ROUTE') {
      created.enRouteAttribution.detailStatus = detail.body.status;
      created.enRouteAttribution.detailLatencyMs = Date.now() - detailStartedAt;
      break;
    }
    await sleep(500);
  }
  if (created.enRouteAttribution.detailStatus !== 'DRIVER_EN_ROUTE') {
    created.enRouteAttribution.outcome = 'backend_state_transition';
    logAttribution();
    throw new Error('en-route attribution probe: GET did not confirm DRIVER_EN_ROUTE');
  }

  const eventDeadline = Date.now() + attributionWaitMs;
  while (Date.now() < eventDeadline) {
    const blindEvent = findOrderStatusEvent(
      created.webSocket.blindMessages,
      blindMessageIndex,
      orderId,
      'DRIVER_EN_ROUTE'
    );
    const volunteerEvent = findOrderStatusEvent(
      created.webSocket.volunteerMessages,
      volunteerMessageIndex,
      orderId,
      'DRIVER_EN_ROUTE'
    );
    created.enRouteAttribution.blindStatusEvent = Boolean(blindEvent);
    created.enRouteAttribution.volunteerStatusEvent = Boolean(volunteerEvent);
    if (
      created.enRouteAttribution.blindStatusEvent
      && created.enRouteAttribution.volunteerStatusEvent
    ) {
      try {
        recordDualStatusEvents(
          'PENDING_ACCEPT',
          'DRIVER_EN_ROUTE',
          blindEvent,
          volunteerEvent
        );
      } catch (error) {
        created.enRouteAttribution.outcome = 'backend_websocket_contract';
        logAttribution();
        throw error;
      }
      created.enRouteAttribution.blindMessageId = blindEvent.messageId;
      created.enRouteAttribution.volunteerMessageId = volunteerEvent.messageId;
      created.enRouteAttribution.outcome = 'backend_path_confirmed';
      logAttribution();
      return;
    }
    await sleep(250);
  }

  created.enRouteAttribution.blindMessageTypes = [
    ...new Set(
      created.webSocket.blindMessages
        .slice(blindMessageIndex)
        .map(message => message.type)
        .filter(Boolean)
    )
  ];
  created.enRouteAttribution.volunteerMessageTypes = [
    ...new Set(
      created.webSocket.volunteerMessages
        .slice(volunteerMessageIndex)
        .map(message => message.type)
        .filter(Boolean)
    )
  ];
  created.enRouteAttribution.outcome = 'backend_websocket_distribution';
  logAttribution();
  throw new Error('en-route attribution probe: one or both roles missed ORDER_STATUS_CHANGED');
}

async function transitionOrder(blind, volunteer, orderId, blindSocket, volunteerSocket) {
  await probeEnRouteAttribution(volunteer, orderId);
  log('order-en-route');
  sendLocation(volunteerSocket, 39.9052, 116.4082);
  await sleep(1000);

  let blindMessageIndex = created.webSocket.blindMessages.length;
  let volunteerMessageIndex = created.webSocket.volunteerMessages.length;
  await http('POST', `/api/orders/${orderId}/arrived`, { token: volunteer.token });
  await waitForDualStatusEvents(
    orderId,
    'DRIVER_EN_ROUTE',
    'DRIVER_ARRIVED',
    blindMessageIndex,
    volunteerMessageIndex
  );
  log('order-arrived', `id=${orderId}`);
  sendLocation(volunteerSocket, 39.9053, 116.4083);
  await sleep(1000);

  blindMessageIndex = created.webSocket.blindMessages.length;
  volunteerMessageIndex = created.webSocket.volunteerMessages.length;
  await http('POST', `/api/orders/${orderId}/start-service`, { token: volunteer.token });
  await waitForDualStatusEvents(
    orderId,
    'DRIVER_ARRIVED',
    'IN_PROGRESS',
    blindMessageIndex,
    volunteerMessageIndex
  );
  log('order-start-service', `id=${orderId}`);
  await probePeerLocations(orderId, blindSocket, volunteerSocket);

  blindMessageIndex = created.webSocket.blindMessages.length;
  volunteerMessageIndex = created.webSocket.volunteerMessages.length;
  const finish = await http('POST', `/api/orders/${orderId}/finish`, { token: volunteer.token });
  await waitForDualStatusEvents(
    orderId,
    'IN_PROGRESS',
    'COMPLETED',
    blindMessageIndex,
    volunteerMessageIndex
  );

  const detail = await getOrder(volunteer.token, orderId);
  created.finalOrderStatus = detail.status ?? finish.body.status ?? null;
  log('order-finished', `id=${orderId} status=${created.finalOrderStatus}`);

  const track = await http('GET', `/api/orders/${orderId}/track`, { token: blind.token });
  created.track = {
    status: track.body.status ?? null,
    blindPointCount: Array.isArray(track.body.blindTrack) ? track.body.blindTrack.length : null,
    volunteerPointCount: Array.isArray(track.body.volunteerTrack) ? track.body.volunteerTrack.length : null,
    blindStats: track.body.blindStats ?? null,
    volunteerStats: track.body.volunteerStats ?? null
  };
  if (!created.track.status || created.track.blindPointCount == null || created.track.volunteerPointCount == null) {
    throw new Error(`track returned an unexpected response: ${JSON.stringify(track.body)}`);
  }
  for (const role of ['blind', 'volunteer']) {
    const pointCount = created.track[`${role}PointCount`];
    const stats = created.track[`${role}Stats`];
    if (pointCount < 2 && (!stats || stats.distanceMeters !== 0 || stats.durationSeconds !== 0 || stats.avgPaceSecPerKm != null)) {
      throw new Error(`Track contract violation: ${role} stats must be 0/0/null below two points: ${JSON.stringify(track.body)}`);
    }
  }
  log('order-track', `status=${created.track.status} blind=${created.track.blindPointCount} volunteer=${created.track.volunteerPointCount}`);
}

async function probeEmergencyContract(blind, volunteer, volunteerMessages) {
  const orderId = await createOrder(blind, '-emergency-contract');
  created.emergencyContractOrderId = orderId;
  await acceptOrder(volunteer, orderId, volunteerMessages, runtime.volunteerSocket);
  await http('POST', `/api/orders/${orderId}/en-route`, { token: volunteer.token });

  const emergency = await http('POST', '/api/emergency/trigger', {
    token: blind.token,
    body: { orderId, gpsLat: 39.9042, gpsLng: 116.4074 }
  });
  created.emergencyContractEventId = emergency.body.eventId ?? emergency.body.id ?? emergency.body.emergencyEvent?.id ?? null;
  log('emergency-contract-probed', `orderId=${orderId} eventId=${created.emergencyContractEventId ?? 'unknown'}`);

  const arrived = await http('POST', `/api/orders/${orderId}/arrived`, {
    token: volunteer.token,
    allowFailure: true
  });
  log('emergency-contract-order-arrived', `id=${orderId} status=${arrived.status} ok=${arrived.ok}`);

  const startService = await http('POST', `/api/orders/${orderId}/start-service`, {
    token: volunteer.token,
    allowFailure: true
  });
  log('emergency-contract-order-start-service', `id=${orderId} status=${startService.status} ok=${startService.ok}`);

  const finish = await http('POST', `/api/orders/${orderId}/finish`, {
    token: volunteer.token,
    allowFailure: true
  });
  log('emergency-contract-order-finish', `id=${orderId} status=${finish.status} ok=${finish.ok}`);
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
  runtime.volunteerToken = volunteer.token;

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

  await probeHeartbeats(blindSocket, volunteerSocket);

  sendLocation(blindSocket, orderStartLocation.lat, orderStartLocation.lng);
  await reportVolunteerDispatchLocation(volunteerSocket, 3, 'pre-order');

  const orderId = await createOrder(blind);
  created.orderId = orderId;

  await acceptOrder(volunteer, orderId, created.webSocket.volunteerMessages, volunteerSocket);
  await transitionOrder(blind, volunteer, orderId, blindSocket, volunteerSocket);
  if (process.env.AIDRUN_E2E_SKIP_EMERGENCY_PROBE !== '1') {
    await probeEmergencyContract(blind, volunteer, created.webSocket.volunteerMessages);
  }

  await new Promise(resolve => setTimeout(resolve, 1500));
  blindSocket.close();
  volunteerSocket.close();

  console.log('\n[cloud-e2e] summary');
  console.log(JSON.stringify(printableSummary(), null, 2));

  if (created.finalOrderStatus !== 'COMPLETED') {
    throw new Error(`Expected final order status COMPLETED, got ${created.finalOrderStatus}`);
  }
  if (!created.webSocket.blindConnected || !created.webSocket.volunteerConnected) {
    throw new Error('Expected both WebSocket connections to open');
  }
  if (!created.webSocket.blindPong || !created.webSocket.volunteerPong) {
    throw new Error('Expected both WebSocket roles to receive PONG');
  }
  if (!created.webSocket.blindReceivedVolunteerLocation || !created.webSocket.volunteerReceivedBlindLocation) {
    throw new Error('Expected both WebSocket roles to receive peer location');
  }
  if (!created.track?.status) {
    throw new Error('Expected typed order track response');
  }
}

function closeRuntimeSockets() {
  runtime.blindSocket?.close();
  runtime.volunteerSocket?.close();
}

async function cleanupCreatedOrders() {
  if (!runtime.blindToken) return;
  const ids = [created.orderId, created.emergencyContractOrderId].filter(Boolean);
  for (const orderId of ids) {
    if (Number(orderId) === Number(created.orderId) && created.finalOrderStatus === 'COMPLETED') {
      continue;
    }
    const detail = await http('GET', `/api/orders/${orderId}`, {
      token: runtime.blindToken,
      allowFailure: true
    });
    const activeVolunteerStates = new Set([
      'PENDING_ACCEPT',
      'DRIVER_EN_ROUTE',
      'DRIVER_ARRIVED',
      'IN_PROGRESS'
    ]);
    if (
      detail.ok
      && activeVolunteerStates.has(detail.body.status)
      && runtime.volunteerToken
    ) {
      await http('POST', `/api/orders/${orderId}/cancel`, {
        token: runtime.volunteerToken,
        allowFailure: true
      });
    }
    const response = await http('POST', `/api/orders/${orderId}/cancel`, {
      token: runtime.blindToken,
      allowFailure: true
    });
    log('cleanup-order', `status=${response.status} ok=${response.ok}`);
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
  console.error(JSON.stringify(printableSummary(), null, 2));
  process.exitCode = 1;
});
