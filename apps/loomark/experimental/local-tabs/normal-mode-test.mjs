import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true});
const context=await browser.newContext();await context.route('**/api/**',route=>route.fulfill({status:503,body:'isolated test: account service unavailable'}));
const p=await context.newPage(),errors=[];p.on('pageerror',e=>errors.push(e.message));
try{await p.goto('http://127.0.0.1:4182/');const area=p.getByRole('textbox',{name:'Text',exact:true});await area.waitFor();await area.fill('Synthetic normal-mode smoke');
assert.equal(await area.inputValue(),'Synthetic normal-mode smoke');assert.deepEqual(await p.evaluate(()=>({trial:typeof globalThis.trial,egw:typeof globalThis.egw,localTabs:typeof globalThis.localTabs})),{trial:'undefined',egw:'undefined',localTabs:'undefined'});
assert.equal(await p.evaluate(async()=>(await indexedDB.databases()).some(db=>db.name==='loomark-egw-worker-experiment-v1')),false);assert.deepEqual(errors,[]);
await fs.writeFile('evidence/normal-mode-results.json',JSON.stringify({passed:true,errors,notes:'Fresh isolated Playwright context; all account HTTP routes returned synthetic 503; no experiment globals or DB.'},null,2));console.log('PASS ordinary Loomark route excludes experimental runtime and storage');
}finally{await browser.close();}
