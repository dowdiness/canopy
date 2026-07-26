import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const generatedModules = [
  { id: '@moonbit/crdt-lambda', fingerprint: 'assemble_lambda_handle' },
  { id: '@moonbit/crdt-json', fingerprint: 'assemble_json_handle' },
  { id: '@moonbit/crdt-markdown', fingerprint: 'assemble_markdown_handle' },
  { id: '@moonbit/crdt-jsx', fingerprint: 'jsx_session_new' },
  { id: '@moonbit/graphviz', fingerprint: 'render_dot_to_svg' },
];

const forbiddenProductionResumeArtifacts = [
  { capability: 'Resume chat request', fingerprint: '/api/pi-resume-chat' },
  { capability: 'Resume chat secret', fingerprint: 'DEEPSEEK_API_KEY' },
  { capability: 'Resume chat relay', fingerprint: 'pi-resume-chat-relay' },
];

const forbiddenProductionClientArtifacts = [
  { capability: 'Mini-ML AST Grep request', fingerprint: '/api/ast-grep' },
  { capability: 'Memo development shell', fingerprint: 'data-memo-ready' },
  {
    capability: 'Memo client module',
    fingerprint: 'The Memo runtime is unavailable on the client',
  },
  // Mini-ML intentionally reuses the monolithic Lambda artifact. Provider
  // fingerprints are allowed only inside that generated bundle, never in
  // route/client glue that would make the production Memo capability reachable.
  {
    capability: 'Memo provider URL',
    fingerprint: 'https://generativelanguage.googleapis.com/v1beta/models/',
    allowedBundleFingerprint: 'assemble_lambda_handle',
  },
  {
    capability: 'Memo provider function',
    fingerprint: 'canopy_llm_fix_typos',
    allowedBundleFingerprint: 'assemble_lambda_handle',
  },
  {
    capability: 'Memo provider function',
    fingerprint: 'canopy_llm_edit',
    allowedBundleFingerprint: 'assemble_lambda_handle',
  },
  ...forbiddenProductionResumeArtifacts,
];

export function inspectWakuBundles({ serverBundles, clientBundles }) {
  const serverLeaks = generatedModules.flatMap(({ id, fingerprint }) =>
    serverBundles
      .filter(({ source }) => source.includes(fingerprint))
      .map(({ name }) => ({ id, file: name })),
  );
  const missingClientModules = generatedModules
    .filter(({ fingerprint }) =>
      !clientBundles.some(({ source }) => source.includes(fingerprint)),
    )
    .map(({ id }) => id);
  const productionClientArtifactLeaks = forbiddenProductionClientArtifacts.flatMap(({
    capability,
    fingerprint,
    allowedBundleFingerprint,
  }) => clientBundles
    .filter(({ source }) =>
      source.includes(fingerprint) &&
      !(allowedBundleFingerprint && source.includes(allowedBundleFingerprint))
    )
    .map(({ name }) => ({ capability, fingerprint, file: name })));
  const productionServerArtifactLeaks = forbiddenProductionResumeArtifacts.flatMap(({
    capability,
    fingerprint,
  }) => serverBundles
    .filter(({ source }) => source.includes(fingerprint))
    .map(({ name }) => ({ capability, fingerprint, file: name })));
  return {
    serverLeaks,
    missingClientModules,
    productionClientArtifactLeaks,
    productionServerArtifactLeaks,
  };
}

function javascriptBundlesBelow(root) {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(root, entry.name);
    if (entry.isDirectory()) return javascriptBundlesBelow(file);
    if (!entry.name.endsWith('.js')) return [];
    return [{ name: path.relative('.', file), source: fs.readFileSync(file, 'utf8') }];
  });
}

function main() {
  const result = inspectWakuBundles({
    serverBundles: javascriptBundlesBelow(path.resolve('dist/server')),
    clientBundles: javascriptBundlesBelow(path.resolve('dist/public/assets')),
  });
  for (const { id, file } of result.serverLeaks) {
    console.error(`Generated module ${id} leaked into server/RSC bundle: ${file}`);
  }
  for (const id of result.missingClientModules) {
    console.error(`Generated module is missing from Waku client bundles: ${id}`);
  }
  for (const { capability, fingerprint, file } of result.productionClientArtifactLeaks) {
    console.error(`${capability} fingerprint ${fingerprint} leaked into production client bundle: ${file}`);
  }
  for (const { capability, fingerprint, file } of result.productionServerArtifactLeaks) {
    console.error(`${capability} fingerprint ${fingerprint} leaked into production server bundle: ${file}`);
  }
  if (
    result.serverLeaks.length > 0 ||
    result.missingClientModules.length > 0 ||
    result.productionClientArtifactLeaks.length > 0 ||
    result.productionServerArtifactLeaks.length > 0
  ) {
    process.exitCode = 1;
  } else {
    console.log('Waku generated-module bundle boundary: OK');
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main();
}
