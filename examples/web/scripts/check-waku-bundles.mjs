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
  return { serverLeaks, missingClientModules };
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
  if (result.serverLeaks.length > 0 || result.missingClientModules.length > 0) {
    process.exitCode = 1;
  } else {
    console.log('Waku generated-module bundle boundary: OK');
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  main();
}
