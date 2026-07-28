#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, relative, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(process.argv[2] || 'source-bundle');
const paths = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', 'contracts/src', 'contracts/script', 'contracts/foundry.toml'], { cwd: root, encoding: 'utf8' })
  .split(/\r?\n/).filter(path => path && existsSync(resolve(root, path))).sort();
const parts = [];
const files = paths.map(path => {
  const content = readFileSync(resolve(root, path), 'utf8').replace(/\r\n/g, '\n');
  const bytes = Buffer.from(content, 'utf8');
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  parts.push(Buffer.from(`FILE ${path} ${bytes.length} ${sha256}\n`, 'utf8'), bytes, Buffer.from('\nEND\n', 'utf8'));
  return { path, bytes: bytes.length, sha256 };
});
const bundle = Buffer.concat(parts);
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, 'ember-source.bundle'), bundle);
writeFileSync(resolve(output, 'manifest.json'), `${JSON.stringify({ format: 1, files, bundleSha256: createHash('sha256').update(bundle).digest('hex') }, null, 2)}\n`);
console.log(`Wrote ${relative(root, output)} (${files.length} files)`);
