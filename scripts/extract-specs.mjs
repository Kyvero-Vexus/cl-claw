import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const src = path.resolve(process.argv[2] || path.join(process.env.HOME, 'openclaw'));
const out = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', 'specs');
fs.mkdirSync(out, { recursive: true });

function walk(dir, pred, acc = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ent.name === '.git' || ent.name === 'node_modules' || ent.name === 'dist') continue;
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, pred, acc);
    else if (pred(p)) acc.push(p);
  }
  return acc;
}

function rel(p) { return path.relative(src, p).replaceAll(path.sep, '/'); }
function read(p) { return fs.readFileSync(p, 'utf8'); }
function mdEscape(s) { return s.replace(/`/g, '\\`'); }

const docs = walk(path.join(src, 'docs'), p => /\.mdx?$/.test(p)).sort();
const tests = [
  ...walk(path.join(src, 'src'), p => /(\.test|\.spec)\.ts$/.test(p) || /\.e2e\.test\.ts$/.test(p)),
  ...walk(path.join(src, 'test'), p => /(\.test|\.spec)\.ts$/.test(p) || /\.e2e\.test\.ts$/.test(p)),
].sort();
const specFiles = walk(path.join(src, 'src'), p => /spec\.ts$/.test(p) && !/\.test\.ts$/.test(p)).sort();

const manifest = {
  source: {
    path: src,
    gitRemote: execSync(`git -C ${JSON.stringify(src)} remote get-url origin`, { encoding: 'utf8' }).trim(),
    gitBranch: execSync(`git -C ${JSON.stringify(src)} rev-parse --abbrev-ref HEAD`, { encoding: 'utf8' }).trim(),
    gitCommit: execSync(`git -C ${JSON.stringify(src)} rev-parse HEAD`, { encoding: 'utf8' }).trim(),
  },
  counts: {
    docs: docs.length,
    tests: tests.length,
    codeSpecFiles: specFiles.length,
  },
  files: {
    docs: docs.map(rel),
    tests: tests.map(rel),
    codeSpecFiles: specFiles.map(rel),
  }
};
fs.writeFileSync(path.join(out, 'source-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');

// docs-index
let docsMd = '# Docs index\n\n';
for (const f of docs) {
  const txt = read(f);
  const title = txt.match(/^title:\s*"([^"]+)"/m)?.[1] || txt.match(/^#\s+(.+)$/m)?.[1] || path.basename(f);
  const summary = txt.match(/^summary:\s*"([^"]+)"/m)?.[1] || '';
  const readWhen = [...txt.matchAll(/^\s*-\s+(.+)$/gm)].map(m => m[1]).slice(0, 6);
  docsMd += `## ${mdEscape(rel(f))}\n\n`;
  docsMd += `- Title: ${title}\n`;
  if (summary) docsMd += `- Summary: ${summary}\n`;
  if (readWhen.length) docsMd += `- Read when:\n${readWhen.map(x => `  - ${x}`).join('\n')}\n`;
  docsMd += '\n';
}
fs.writeFileSync(path.join(out, 'docs-index.md'), docsMd);

// code-spec-files
let specMd = '# Code spec files\n\n';
for (const f of specFiles) {
  specMd += `## ${mdEscape(rel(f))}\n\n`;
  specMd += '```ts\n' + read(f).trimEnd() + '\n```\n\n';
}
fs.writeFileSync(path.join(out, 'code-spec-files.md'), specMd);

function extractTitles(txt) {
  return [...txt.matchAll(/\b(?:describe|it|test)\s*\(\s*(["'`])([\s\S]*?)\1/g)]
    .map(m => m[2].replace(/\s+/g, ' ').trim())
    .filter(Boolean);
}

let testsMd = '# Test specs\n\n';
const domains = new Map();
for (const f of tests) {
  const titles = extractTitles(read(f));
  testsMd += `## ${mdEscape(rel(f))}\n\n`;
  for (const t of titles) testsMd += `- ${t}\n`;
  testsMd += '\n';

  const r = rel(f);
  const parts = r.split('/');
  const domain = parts[0] === 'test' ? 'test' : (parts[1] || parts[0]);
  if (!domains.has(domain)) domains.set(domain, []);
  domains.get(domain).push({ file: r, titles });
}
fs.writeFileSync(path.join(out, 'test-specs.md'), testsMd);

let byDomain = '# Test specs by domain\n\n';
for (const domain of [...domains.keys()].sort()) {
  byDomain += `## ${domain}\n\n`;
  for (const { file, titles } of domains.get(domain)) {
    byDomain += `### ${mdEscape(file)}\n`;
    for (const t of titles) byDomain += `- ${t}\n`;
    byDomain += '\n';
  }
}
fs.writeFileSync(path.join(out, 'test-specs-by-domain.md'), byDomain);
