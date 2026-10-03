import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:process.env.HEADED!=='1'}),context=await browser.newContext(),results=[];
try{for(const phase of ['ready','opening','inflight']){
 const p=await context.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.goto(`http://127.0.0.1:4182/fixture.html?local-tabs-worker=1&doc=lifecycle-${Date.now()}&seed=base${phase==='opening'?'&size=100000':''}`);await p.waitForSelector('textarea');
 if(phase!=='opening')await p.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly);
 if(phase==='inflight'){await p.evaluate(()=>trial.state.delayEdit=1000);await p.locator('textarea').focus();await p.keyboard.press('Control+End');await p.keyboard.insertText(' X');}
 await p.getByRole('button',{name:'Toggle Loomark app',exact:true}).click();await p.waitForFunction(()=>!document.querySelector('textarea'));
 assert.equal(await p.evaluate(()=>trial.state.client.worker),null);
 await p.getByRole('button',{name:'Toggle Loomark app',exact:true}).click();await p.waitForFunction(()=>trial.state.ready&&!trial.state.running&&!trial.state.queue.length&&!trial.state.packets.length&&!document.querySelector('textarea').readOnly,{},{timeout:60000});
 assert.equal(await p.locator('textarea').inputValue(),phase==='opening'?'0123456789'.repeat(10000):phase==='inflight'?'base X':'base');assert.deepEqual(errors,[]);
 results.push({phase,passed:true});console.log('PASS lifecycle',phase);await p.close();
}}catch(e){results.push({passed:false,error:e.stack});console.error(e);process.exitCode=1;}finally{await fs.mkdir('evidence',{recursive:true});await fs.writeFile('evidence/lifecycle-results.json',JSON.stringify({results,headless:process.env.HEADED!=='1'},null,2));await browser.close();}
