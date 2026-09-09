// Prototype-only reuse of the production browser suite. The only changed
// assertion expects the one dedicated Preview Worker instead of zero Workers.
import {readFileSync,writeFileSync,mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
const root=fileURLToPath(new URL('../',import.meta.url));
const vanilla=join(root,'apps/loomark/examples/vanilla');
const module=join(vanilla,'node_modules/@playwright/test/index.mjs');
const output=mkdtempSync(join(tmpdir(),'loomark-worker-e2e-'));
let source=readFileSync(join(vanilla,'tests/standalone.spec.ts'),'utf8');
const original='import { expect, test, type Page } from "@playwright/test"';
const assertion='expect(workerUrls).toEqual([])';
if(source.split(original).length!==2 || source.split(assertion).length!==2)throw Error('production test seam changed; review adapter');
source=source.replace(original,`import {expect,test as base,type Page} from ${JSON.stringify(module)};
const test=base.extend({page:async({page},use)=>{
 await page.addInitScript(()=>{const url=new URL(location.href);if(url.protocol.startsWith('http')){url.searchParams.set('preview-worker','1');history.replaceState(null,'',url);}});
 await use(page);
}});`).replace(assertion,'expect(workerUrls).toHaveLength(1); expect(workerUrls[0]).toMatch(/^blob:/)');
writeFileSync(join(output,'worker-all.spec.ts'),source);
writeFileSync(join(output,'worker-focused.spec.ts'),readFileSync(join(vanilla,'tests/worker-preview.spec.ts'),'utf8').replace("from '@playwright/test'",`from ${JSON.stringify(module)}`));
writeFileSync(join(output,'config.mjs'),`import {defineConfig} from ${JSON.stringify(module)};
export default defineConfig({testDir:${JSON.stringify(output)},testMatch:'*.spec.ts',workers:1,timeout:30000,reporter:'list',outputDir:${JSON.stringify(join(output,'results'))},use:{baseURL:${JSON.stringify(process.env.URLBASE??'http://127.0.0.1:4325/')}}});`);
console.log('Generated tests and retained results:',output);
const result=spawnSync(process.execPath,[join(vanilla,'node_modules/playwright/cli.js'),'test',`--config=${join(output,'config.mjs')}`,...process.argv.slice(2)],{stdio:'inherit',cwd:vanilla});
process.exitCode=result.status??1;
