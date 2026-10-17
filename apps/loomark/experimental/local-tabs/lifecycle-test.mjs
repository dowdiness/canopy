import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||(process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined),headless:process.env.HEADED!=='1'}),context=await browser.newContext(),results=[];
try{for(const phase of ['composing','ready','opening','inflight']){
 const p=await context.newPage();const errors=[];p.on('pageerror',e=>errors.push(e.message));
 await p.goto(`http://127.0.0.1:4182/fixture.html?local-tabs-worker=1&doc=lifecycle-${Date.now()}&seed=base${phase==='opening'?'&size=100000':''}`);await p.waitForSelector('textarea');
 if(phase!=='opening')await p.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly);
 if(phase==='inflight'||phase==='composing'){
  await p.evaluate(delay=>trial.state.delayEdit=delay,phase==='composing'?10000:1000);
  await p.locator('textarea').focus();await p.keyboard.press('Control+End');await p.keyboard.insertText(' X');
 }
 if(phase==='composing'){
  assert.equal(await p.evaluate(()=>trial.state.queue.some(item=>item.after==='base X')),true);
  await p.locator('textarea').evaluate(e=>{
   e.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true}));
   e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType:'insertCompositionText',data:'未',isComposing:true}));
   e.setRangeText('未',e.selectionStart,e.selectionEnd,'end');
  });
 }
 // Programmatic activation avoids a focus/blur transition ending composition first.
 await p.getByRole('button',{name:'Toggle Loomark app',exact:true}).evaluate(button=>button.click());await p.waitForFunction(()=>!document.querySelector('textarea'));
 assert.equal(await p.evaluate(()=>trial.state.client.worker),null);
 await p.getByRole('button',{name:'Toggle Loomark app',exact:true}).click();
 await p.waitForFunction(()=>trial.state.ready&&!document.querySelector('textarea').readOnly,{},{timeout:60000});
 const expected=phase==='opening'?'0123456789'.repeat(10000):phase==='ready'?'base':'base X';
 assert.equal(await p.locator('textarea').inputValue(),expected);
 await p.waitForFunction(()=>!trial.state.running&&!trial.state.queue.length&&!trial.state.packets.length&&!trial.state.failure&&!trial.state.blocked,{},{timeout:60000});
 if(phase==='composing'){
  const peer=await context.newPage();await peer.goto(p.url());
  await peer.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly);
  await peer.locator('textarea').focus();await peer.keyboard.press('Control+End');await peer.keyboard.insertText(' R');
  await peer.waitForFunction(()=>document.getElementById('status').textContent==='Saved on this device');
  // No new local input may be needed to release the old beforeinput gate.
  await p.waitForFunction(()=>document.querySelector('textarea').value==='base X R');
  await peer.close();
  await p.locator('textarea').focus();await p.keyboard.press('Control+End');await p.keyboard.insertText(' Y');
  await p.waitForFunction(()=>document.getElementById('status').textContent==='Saved on this device');
  await p.reload();await p.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly);
  assert.equal(await p.locator('textarea').inputValue(),'base X R Y');
 }
 assert.deepEqual(errors,[]);
 results.push({phase,passed:true});console.log('PASS lifecycle',phase);await p.close();
}}catch(e){results.push({passed:false,error:e.stack});console.error(e);process.exitCode=1;}finally{await fs.mkdir('evidence',{recursive:true});await fs.writeFile('evidence/lifecycle-results.json',JSON.stringify({results,headless:process.env.HEADED!=='1'},null,2));await browser.close();}
