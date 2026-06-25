#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');

const maintainedDocs = [
  'docs/01-product-requirements.md',
  'docs/02-mvp-scope.md',
  'docs/03-user-stories.md',
  'docs/04-user-flows-and-state-machine.md',
  'docs/05-page-specs.md',
  'docs/06-data-model.md',
  'docs/07-api-contract.openapi.yaml',
  'docs/08-ios-architecture.md',
  'docs/09-accessibility-and-voice-guidelines.md',
  'docs/10-ai-coding-tasks.md',
  'docs/test-accounts.md',
  'docs/websocket-protocol.md'
];

const forbiddenFragments = [
  '`matching`',
  '`accepted`',
  '`arrived`',
  '`in_progress`',
  '`completed`',
  '`cancelled`',
  'terminal `emergency`',
  'status: "matching"',
  'status: "accepted"',
  'status: "arrived"',
  'status: "in_progress"',
  'status: "completed"',
  'status: "cancelled"',
  '状态流转为 emergency',
  '`/api/orders/{orderId}/arrive`',
  '`/api/orders/{id}/arrive`'
];

const requiredOpenAPIFragments = [
  '/api/volunteer/registration/step2/id-card',
  'frontFile',
  'backFile',
  '/api/volunteer/registration/step3/face-verify',
  'facePhoto',
  '/api/admin/volunteers/review/id',
  '/api/admin/volunteers/review/cert',
  '/api/cs/auth/login'
];

let failed = false;

for (const relativePath of maintainedDocs) {
  const absolutePath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(absolutePath)) {
    console.error(`[validate-docs] missing ${relativePath}`);
    failed = true;
    continue;
  }

  const text = fs.readFileSync(absolutePath, 'utf8');
  for (const fragment of forbiddenFragments) {
    if (text.includes(fragment)) {
      console.error(`[validate-docs] ${relativePath} contains forbidden fragment: ${fragment}`);
      failed = true;
    }
  }
}

const openAPIText = fs.readFileSync(path.join(repoRoot, 'docs/07-api-contract.openapi.yaml'), 'utf8');
for (const fragment of requiredOpenAPIFragments) {
  if (!openAPIText.includes(fragment)) {
    console.error(`[validate-docs] docs/07-api-contract.openapi.yaml is missing required backend contract fragment: ${fragment}`);
    failed = true;
  }
}

if (failed) {
  process.exitCode = 1;
} else {
  console.log('[validate-docs] maintained docs passed');
}
