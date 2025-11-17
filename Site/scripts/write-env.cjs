#!/usr/bin/env node

/**
 * Writes runtime environment variables into public/assets/env.js so the Angular
 * app can read them off window.__env at startup. Designed for local dev/tests.
 */

const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

const projectRoot = process.cwd();
const envCandidates = ['.env.local', '.env']
  .map((relative) => path.resolve(projectRoot, relative))
  .filter((filePath) => fs.existsSync(filePath));

if (envCandidates.length) {
  envCandidates.forEach((filePath) => {
    dotenv.config({ path: filePath, override: true });
  });
} else {
  dotenv.config();
}

const apiBaseUrl = process.env.API_BASE_URL ?? '';
const outputRelativePath = process.argv[2] ?? 'public/assets/env.js';
const outputPath = path.resolve(projectRoot, outputRelativePath);

fs.mkdirSync(path.dirname(outputPath), { recursive: true });

const escapeValue = (value) => value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
const sanitized = escapeValue(apiBaseUrl);

const fileContents = `(function (window) {
  window.__env = window.__env || {};
  window.__env.apiBaseUrl = "${sanitized}";
})(window);
`;

fs.writeFileSync(outputPath, fileContents, 'utf8');

const sourceLabel = envCandidates.length ? envCandidates.map((file) => path.basename(file)).join(',') : 'process.env';
const status = apiBaseUrl ? 'set' : 'empty';
console.log(`[env] API_BASE_URL (${status}) from ${sourceLabel} -> ${path.relative(projectRoot, outputPath)}`);
