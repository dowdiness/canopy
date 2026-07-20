import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

const SOURCE_EXTENSIONS = ['.ts', '.tsx', '.mts', '.cts', '.js', '.jsx', '.mjs', '.cjs'];
const FEATURE_NAMES = new Set([
  'lambda',
  'json',
  'markdown',
  'memo',
  'posts',
  'resume',
  'genui',
  'genui-possibilities',
]);
const ENTRY_FEATURES = new Map([
  ['index.html', 'lambda'],
  ['json.html', 'json'],
  ['markdown.html', 'markdown'],
  ['memo.html', 'memo'],
  ['posts.html', 'posts'],
  ['resume.html', 'resume'],
  ['genui.html', 'genui'],
  ['genui-possibilities.html', 'genui-possibilities'],
]);
const CURRENT_ENTRY_SCRIPTS = new Map([
  ['index.html', 'src/main.ts'],
  ['json.html', 'src/entries/json.ts'],
  ['markdown.html', 'src/entries/markdown.ts'],
  ['memo.html', 'src/entries/memo.ts'],
  ['posts.html', 'src/entries/posts.ts'],
  ['resume.html', 'src/resume-app.tsx'],
  ['genui.html', 'src/genui.js'],
  ['genui-possibilities.html', 'src/genui-possibilities.js'],
]);
const ROOT_SERVER_FILES = new Set([
  'signaling-server.js',
  'signaling-worker.js',
  'vite.config.ts',
  'vite-plugin-genui-feasibility.ts',
  'vite-plugin-moonbit.ts',
  'vite-plugin-pi-resume-chat.ts',
]);

function normalize(filePath) {
  return filePath.replaceAll('\\', '/').replace(/^\.\//, '');
}

function capabilityImport(specifier) {
  return specifier.startsWith('node:') ||
    specifier === 'vite' ||
    specifier.startsWith('@vitejs/') ||
    specifier.startsWith('@tailwindcss/') ||
    specifier === 'react' ||
    specifier.startsWith('react/') ||
    specifier === 'react-dom' ||
    specifier.startsWith('react-dom/') ||
    specifier === 'ai' ||
    specifier.startsWith('ai/') ||
    specifier.startsWith('@ai-sdk/');
}

export function describePath(filePath) {
  const normalized = normalize(filePath);
  const base = path.posix.basename(normalized);
  if (/\.(test|spec)\./.test(base) || /^(tests|preview-tests)\//.test(normalized)) {
    return { kind: 'test' };
  }
  if (
    /(^|\/)server\//.test(normalized) ||
    ROOT_SERVER_FILES.has(normalized) ||
    base === 'genui-feasibility-provider.js'
  ) {
    return { kind: 'server' };
  }

  const entryMatch = normalized.match(/(^|\/)entries\/([^/]+)\.[^.]+$/);
  if (entryMatch) return { kind: 'entry', owner: entryMatch[2] };

  const featureMatch = normalized.match(/(^|\/)features\/([^/]+)(?:\/([^/]+))?/);
  if (featureMatch) {
    return {
      kind: 'feature',
      owner: featureMatch[2],
      layer: featureMatch[3],
    };
  }

  if (/(^|\/)shared\//.test(normalized) || base === 'vite-env.d.ts') {
    return { kind: 'shared' };
  }
  if (/^(main|editor|ast-grep-runner)\./.test(base)) return { kind: 'feature', owner: 'lambda' };
  if (base === 'resume.css') return { kind: 'feature', owner: 'resume' };
  if (base === 'tailwind.css') return { kind: 'feature', owner: 'genui' };
  if (base === 'genui-possibilities.css') {
    return { kind: 'feature', owner: 'genui-possibilities' };
  }
  if (/^(resume-app|pi-resume-)/.test(base) || normalized.includes('components/ai-elements/')) {
    return { kind: 'feature', owner: 'resume' };
  }
  if (/^genui-possibilities\./.test(base) || base.startsWith('genui-journey-state.')) {
    return { kind: 'feature', owner: 'genui-possibilities' };
  }
  if (/^genui(?:-|\.)/.test(base) || normalized.includes('/fixtures/')) {
    return { kind: 'feature', owner: 'genui' };
  }
  return { kind: 'unclassified' };
}

export function classifyPath(filePath) {
  const description = describePath(filePath);
  return description.owner ?? description.kind;
}

export function resolveLocalImport(from, specifier, files = new Set()) {
  if (!specifier.startsWith('.') && !specifier.startsWith('/')) return null;
  const fromDir = path.posix.dirname(normalize(from));
  const requested = specifier.startsWith('/')
    ? path.posix.normalize(specifier.slice(1))
    : path.posix.normalize(path.posix.join(fromDir, specifier));
  const requestedExtension = path.posix.extname(requested);
  const candidates = requestedExtension
    ? [
        requested,
        ...SOURCE_EXTENSIONS
          .filter(extension => extension !== requestedExtension)
          .map(extension => requested.slice(0, -requestedExtension.length) + extension),
      ]
    : SOURCE_EXTENSIONS.flatMap(extension => [
        requested + extension,
        path.posix.join(requested, 'index' + extension),
      ]);
  return candidates.find(candidate => files.has(candidate)) ?? requested;
}

export function staticImports(sourceText, fileName = 'file.ts') {
  const source = ts.createSourceFile(fileName, sourceText, ts.ScriptTarget.Latest, true);
  const imports = new Set();
  function visit(node) {
    if (ts.isImportDeclaration(node) && ts.isStringLiteral(node.moduleSpecifier)) {
      imports.add(node.moduleSpecifier.text);
    } else if (
      ts.isExportDeclaration(node) &&
      node.moduleSpecifier &&
      ts.isStringLiteral(node.moduleSpecifier)
    ) {
      imports.add(node.moduleSpecifier.text);
    } else if (
      ts.isCallExpression(node) &&
      node.arguments.length === 1 &&
      ts.isStringLiteral(node.arguments[0]) &&
      (
        node.expression.kind === ts.SyntaxKind.ImportKeyword ||
        (ts.isIdentifier(node.expression) && node.expression.text === 'require')
      )
    ) {
      imports.add(node.arguments[0].text);
    } else if (
      ts.isImportEqualsDeclaration(node) &&
      ts.isExternalModuleReference(node.moduleReference) &&
      node.moduleReference.expression &&
      ts.isStringLiteral(node.moduleReference.expression)
    ) {
      imports.add(node.moduleReference.expression.text);
    }
    ts.forEachChild(node, visit);
  }
  visit(source);
  return [...imports];
}

export function evaluateEdge(from, to, specifier = to) {
  const source = describePath(from);
  const target = describePath(to);
  const violations = [];

  if (source.kind === 'unclassified') violations.push('source module has no declared owner');
  if (target.kind === 'unclassified' && specifier.startsWith('.')) {
    violations.push('local dependency has no declared owner');
  }
  if (source.kind !== 'server' && source.kind !== 'test' && target.kind === 'server') {
    violations.push('browser code cannot import server code');
  }
  if (source.kind === 'shared' && target.kind === 'feature') {
    violations.push('shared code cannot import feature code');
  }
  if (
    source.kind === 'feature' &&
    target.kind === 'feature' &&
    source.owner !== target.owner
  ) {
    violations.push('a feature cannot import another feature internals');
  }
  if (source.kind === 'entry') {
    if (
      target.kind !== 'feature' ||
      target.owner !== source.owner ||
      target.layer !== 'browser'
    ) {
      violations.push('entry can only compose its corresponding feature browser surface');
    }
  }
  if (
    source.kind === 'server' &&
    target.kind === 'feature' &&
    target.layer !== undefined &&
    target.layer !== 'core' &&
    target.layer !== 'protocol'
  ) {
    violations.push('server code can only import explicit feature core/protocol surfaces');
  }
  if (
    source.kind === 'feature' &&
    (source.layer === 'core' || source.layer === 'protocol')
  ) {
    if (
      (target.kind === 'feature' && target.layer === 'browser') ||
      (target.kind === 'shared' && /(^|\/)shared\/browser\//.test(normalize(to)))
    ) {
      violations.push('core/protocol code cannot import browser layers');
    }
    if (capabilityImport(specifier)) {
      violations.push('core/protocol code cannot import Node/Vite/React/provider capabilities');
    }
  }
  return [...new Set(violations)];
}

function filesBelow(root) {
  if (!fs.existsSync(root)) return [];
  const found = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) found.push(...filesBelow(full));
    else if (SOURCE_EXTENSIONS.includes(path.extname(entry.name))) found.push(full);
  }
  return found;
}

export function discoverSourceFiles(projectRoot) {
  return [
    ...filesBelow(path.join(projectRoot, 'src')),
    ...filesBelow(path.join(projectRoot, 'server')),
    ...[...ROOT_SERVER_FILES]
      .map(file => path.join(projectRoot, file))
      .filter(file => fs.existsSync(file)),
  ];
}

export function checkBoundaries({
  root,
  files = discoverSourceFiles(root),
  readFile = file => fs.readFileSync(file, 'utf8'),
}) {
  const relativeFiles = new Set(files.map(file => normalize(path.relative(root, file))));
  const violations = [];
  for (const file of files) {
    const relative = normalize(path.relative(root, file));
    const source = describePath(relative);
    if (source.kind === 'unclassified') {
      violations.push({ from: relative, to: relative, rule: 'source module has no declared owner' });
    }
    for (const specifier of staticImports(readFile(file), relative)) {
      const target = resolveLocalImport(relative, specifier, relativeFiles);
      if (target !== null) {
        violations.push(...evaluateEdge(relative, target, specifier).map(rule => ({
          from: relative,
          to: target,
          rule,
        })));
      } else {
        violations.push(...evaluateEdge(relative, specifier, specifier).map(rule => ({
          from: relative,
          to: specifier,
          rule,
        })));
      }
    }
  }
  return violations;
}

export function htmlEntryAccepted(script, feature, currentScript) {
  const relative = script.startsWith('/') ? script.slice(1) : script;
  const target = describePath(relative);
  return relative === currentScript ||
    (target.kind === 'entry' && target.owner === feature);
}

export function evaluateHtmlEntryScripts(html, feature, scripts, currentScript) {
  const violations = [];
  let acceptedCount = 0;
  for (const script of scripts) {
    const relative = script.startsWith('/') ? script.slice(1) : script;
    if (htmlEntryAccepted(script, feature, currentScript)) {
      acceptedCount += 1;
    } else {
      violations.push({
        from: html,
        to: relative,
        rule: 'HTML entry must load its corresponding browser entry module',
      });
    }
  }
  if (acceptedCount === 0) {
    violations.push({
      from: html,
      to: '<missing>',
      rule: 'HTML entry must load at least one corresponding browser entry module',
    });
  }
  return violations;
}

export function checkHtmlEntries(root) {
  const violations = [];
  for (const [html, feature] of ENTRY_FEATURES) {
    const htmlText = fs.readFileSync(path.join(root, html), 'utf8');
    const scripts = [...htmlText.matchAll(/<script[^>]+src=["']([^"']+)["']/g)]
      .map(match => match[1]);
    violations.push(...evaluateHtmlEntryScripts(
      html,
      feature,
      scripts,
      CURRENT_ENTRY_SCRIPTS.get(html),
    ));
  }
  return violations;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const root = path.resolve(process.argv[2] ?? new URL('..', import.meta.url).pathname);
  const violations = [...checkBoundaries({ root }), ...checkHtmlEntries(root)];
  if (violations.length > 0) {
    for (const violation of violations) {
      console.error(`${violation.from} -> ${violation.to}: ${violation.rule}`);
    }
    process.exitCode = 1;
  } else {
    console.log('Web dependency boundaries: OK');
  }
}
