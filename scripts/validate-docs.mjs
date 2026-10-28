#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
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
  'docs/08-ios-architecture.md',
  'docs/09-accessibility-and-voice-guidelines.md',
  'docs/10-ai-coding-tasks.md',
  'docs/test-accounts.md'
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

// The HTTP/WebSocket API contract is no longer maintained in this repository.
// It was archived on 2026-07-28 (see docs/07-api-contract-MOVED.md); the single
// source of truth now lives in the backend repository. This script therefore only
// validates the markdown docs this repository still owns.

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

// Tracked markdown must not teach a hardcoded signing team (#441, #442).
// The team changes with the person and the machine; copying an old one fails with
// `No Account for Team`. Same pattern as the `hardcoded-team-id` rule in
// scripts/hooks/guard.mjs, which only blocks new writes; this check also covers old files.
const TEAM_ID_ARG = /\b(?:DEVELOPMENT_TEAM|AIDRUN_TEAM)=["']?[A-Z0-9]{10}\b/;
const trackedMarkdown = execFileSync('git', ['ls-files', '*.md'], { cwd: repoRoot, encoding: 'utf8' })
  .split('\n')
  .filter(Boolean);
for (const relativePath of trackedMarkdown) {
  const absolutePath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(absolutePath)) continue;
  fs.readFileSync(absolutePath, 'utf8').split('\n').forEach((line, index) => {
    if (TEAM_ID_ARG.test(line) && !line.includes('guard:allow hardcoded-team-id')) {
      console.error(`[validate-docs] ${relativePath}:${index + 1} hardcodes a signing team; point to skill aidrun-device-test instead`);
      failed = true;
    }
  });
}

// Every repo path quoted in the always-loaded instructions must exist (#499:
// AGENTS.md pointed at a docs/error-codes.json that was never in the repo).
// Placeholders such as `{topic}`, `<name>`, `*` or `…` are skipped. Paths that live in the
// backend repository are skipped: the contract files by name, and any path written right
// after a mention of the backend (for example 「详见后端 `docs/research/…`」).
const REPO_PATH = /`((?:docs|scripts|blindRun|blindRunTests|blindRunUITests|openspec|\.claude|\.github)\/[^`\s]+\.[A-Za-z0-9]+)`/g;
const BACKEND_REPO_PATHS = new Set(['docs/api_spec.yaml', 'docs/websocket-protocol.md', 'docs/handoff.md']);
const BACKEND_MENTION_WINDOW = 12;
const NAMES_BACKEND_REPO = /后端|backend|demo\//;
for (const relativePath of ['AGENTS.md', 'CLAUDE.md']) {
  const lines = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8').split('\n');
  lines.forEach((line, index) => {
    for (const match of line.matchAll(REPO_PATH)) {
      const quoted = match[1];
      const target = quoted.replace(/:\d+(?:[-–]\d+)?$/, '');
      if (/[{}<>*…]/.test(target) || BACKEND_REPO_PATHS.has(target)) continue;
      const before = line.slice(Math.max(0, match.index - BACKEND_MENTION_WINDOW), match.index);
      if (NAMES_BACKEND_REPO.test(before)) continue;
      if (!fs.existsSync(path.join(repoRoot, target))) {
        console.error(`[validate-docs] ${relativePath}:${index + 1} quotes \`${quoted}\`, which does not exist`);
        failed = true;
      }
    }
  });
}

// App Store Connect cuts the Beta App Review notes at 4000 characters. The notes grow with
// every new permission or review rule (2026-10-28: 3720 -> 4291 after two short additions),
// and nobody counts by hand before pasting.
const REVIEW_NOTES_DOC = 'docs/testflight/test-information.md';
const REVIEW_NOTES_LIMIT = 4000;
{
  const text = fs.readFileSync(path.join(repoRoot, REVIEW_NOTES_DOC), 'utf8');
  const section = text.indexOf('### 2.2 Review Notes');
  const open = section < 0 ? -1 : text.indexOf('```text\n', section);
  const close = open < 0 ? -1 : text.indexOf('```', open + '```text\n'.length);
  if (close < 0) {
    console.error(`[validate-docs] ${REVIEW_NOTES_DOC}: cannot find the §2.2 Review Notes code block`);
    failed = true;
  } else {
    const length = [...text.slice(open + '```text\n'.length, close)].length;
    if (length > REVIEW_NOTES_LIMIT) {
      console.error(`[validate-docs] ${REVIEW_NOTES_DOC}: Review Notes has ${length} characters (limit ${REVIEW_NOTES_LIMIT})`);
      failed = true;
    }
  }
}

if (failed) {
  process.exitCode = 1;
} else {
  console.log('[validate-docs] maintained docs passed');
}
