import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||(process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined),headless:process.env.HEADED!=='1'});
const context=await browser.newContext({viewport:{width:1200,height:900}}),results=[],errors=[];
context.on('page',p=>p.on('pageerror',e=>errors.push(e.message)));
const run='fault-'+Date.now();
async function page(name,extra=''){const p=await context.newPage();await p.goto(`http://127.0.0.1:4182/?local-tabs-worker=1&doc=${run}-${name}&seed=base${extra}`);await ready(p);return p;}
async function ready(p){await p.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly,{},{timeout:30000});}
async function settled(p){await p.waitForFunction(()=>trial.state.ready&&!trial.state.running&&!trial.state.queue.length&&!trial.state.packets.length&&!trial.state.failure&&!trial.state.blocked,{},{timeout:60000});}
async function edit(p,text){await p.locator('textarea').focus();await p.keyboard.press('Control+End');await p.keyboard.insertText(text);}
async function record(name,fn){if(process.env.TEST_FILTER&&!name.includes(process.env.TEST_FILTER))return;const start=Date.now();const data=await fn();results.push({name,passed:true,ms:Date.now()-start,...data});console.log('PASS',name,data||'');}
async function committedCount(p){return p.evaluate(async()=>{const {openStore,readJournal}=await import('./store.mjs');const db=await openStore();const rows=await readJournal(db,trial.state.documentId,0);db.close();return rows.length;});}
try{
 for(const fault of ['worker-loss','blocked-save'])await record('composition terminal input survives '+fault,async()=>{
  const p=await page('composition-'+fault);
  if(fault==='blocked-save'){
   await p.evaluate(()=>{
    trial.state.abortNext=true;
    const client=trial.state.client,request=client.request.bind(client);
    let release;trial.releaseSaveFailure=()=>release();
    const gate=new Promise(resolve=>release=resolve);
    client.request=async(type,args)=>{try{return await request(type,args);}catch(error){if(type==='save'){trial.saveFailed=true;await gate;}throw error;}};
   });
   await edit(p,' X');await p.waitForFunction(()=>trial.saveFailed);
   // Queue another native intent while the save is in flight, then start IME.
   await edit(p,' Y');
  }
  const before=await p.locator('textarea').inputValue(),basis=await p.evaluate(()=>trial.state.basisVersion);
  await p.locator('textarea').evaluate(e=>{
   e.focus();e.setSelectionRange(e.value.length,e.value.length);
   e.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true,data:''}));
   e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType:'insertCompositionText',data:'に',isComposing:true}));
   e.setRangeText('に',e.selectionStart,e.selectionEnd,'end');
   e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertCompositionText',data:'に',isComposing:true}));
  });
  if(fault==='worker-loss')await p.evaluate(()=>{
   const client=trial.state.client,request=client.request.bind(client);
   let release;trial.releaseRecovery=()=>release();
   const gate=new Promise(resolve=>release=resolve);
   client.request=async(type,args)=>{if(type==='open')await gate;return request(type,args);};
   trial.crash();
  });
  else {await p.evaluate(()=>trial.releaseSaveFailure());await p.waitForFunction(()=>!!trial.state.blocked);}
  await p.locator('textarea').evaluate(e=>{
   const end=e.value.length;e.setRangeText('日本語',end-1,end,'end');
   e.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:'日本語'}));
   e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType:'insertFromComposition',data:'日本語',isComposing:false}));
   e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertFromComposition',data:'日本語',isComposing:false}));
  });
  const retained=await p.evaluate(before=>({text:trial.state.text,basis:trial.state.basisVersion,item:trial.state.queue.find(item=>item.before===before&&item.after===before+'日本語'),composing:trial.state.composing}),before);
  assert.equal(retained.text,before+'日本語');assert.equal(retained.basis,basis);
  assert.equal(retained.item.before,before);assert.equal(retained.item.after,before+'日本語');
  assert.equal(retained.composing,false);assert.notEqual(await p.locator('#status').innerText(),'Saved on this device');
  if(fault==='worker-loss')await p.evaluate(()=>trial.releaseRecovery());else await p.locator('#retry').click();
  await ready(p);await settled(p);assert.equal(await p.locator('textarea').inputValue(),before+'日本語');
  await p.reload();await ready(p);assert.equal(await p.locator('textarea').inputValue(),before+'日本語');
  await p.close();
 });
 await record('Saved then Worker termination restores each accepted operation exactly once',async()=>{
  const p=await page('saved');await edit(p,' A');await settled(p);await edit(p,' B');await settled(p);
  const before=await p.evaluate(()=>trial.inspect()),writer=await p.evaluate(()=>trial.state.writer);
  assert.equal(await p.locator('#status').innerText(),'Saved on this device');
  await p.evaluate(()=>trial.crash());await ready(p);await settled(p);const after=await p.evaluate(()=>trial.inspect());
  assert.equal(after.text,before.text);assert.equal(after.version,before.version);assert.equal(after.count,before.count);assert.notEqual(await p.evaluate(()=>trial.state.writer),writer);
  assert.equal((await p.evaluate(()=>trial.durable())).journal.length,2);
  await p.reload();await ready(p);assert.equal((await p.evaluate(()=>trial.inspect())).version,before.version);await p.close();return {operations:after.count};
 });
 await record('crash before local response retains all optimistic edits and rejects old epoch',async()=>{
  const p=await page('local');await p.evaluate(()=>trial.state.delayEdit=1000);await edit(p,' X');await edit(p,' Y');
  const old=await p.evaluate(()=>{const q=trial.state.client.pending;return {epoch:q.epoch,id:q.id,document:q.document,ok:true,result:{info:{text:'CORRUPT'}}};});
  await p.evaluate(()=>trial.crash());await ready(p);await p.evaluate(old=>trial.state.client.receive(old),old);await settled(p);
  assert.equal(await p.locator('textarea').inputValue(),'base X Y');const info=await p.evaluate(()=>trial.inspect());assert.equal(info.count,8);assert.equal(await committedCount(p),2);await p.close();
 });
 await record('delayed remote offer cannot overwrite newer native input',async()=>{
  const a=await page('offer'),b=await page('offer');await a.evaluate(()=>trial.pause(true));await edit(b,' REMOTE');await settled(b);
  await a.evaluate(()=>{trial.state.delayPull=600;trial.pause(false);});await a.waitForTimeout(80);await edit(a,' LOCAL');
  assert.equal(await a.locator('textarea').inputValue(),'base LOCAL');await settled(a);await b.evaluate(()=>trial.catchUp());await settled(b);
  const ia=await a.evaluate(()=>trial.inspect()),ib=await b.evaluate(()=>trial.inspect());assert.equal(ia.version,ib.version);assert.ok(ia.text.includes('LOCAL'));assert.ok(ia.text.includes('REMOTE'));await a.close();await b.close();
 });
 for(const phase of ['before-save','during-transaction','after-commit-before-ack'])await record('same immutable packet survives '+phase,async()=>{
  const p=await page(phase);await p.evaluate(phase=>{if(phase==='before-save')trial.pause(true);if(phase==='during-transaction')trial.state.beforeCommit=2000;if(phase==='after-commit-before-ack')trial.state.holdNext=2000;},phase);
  await edit(p,' PACKET');await p.waitForFunction(()=>trial.state.packets.length===1);
  const packet=await p.evaluate(()=>trial.state.packets[0]);
  if(phase==='during-transaction')await p.waitForFunction(()=>trial.state.client.checkpoint==='before-commit');
  if(phase==='after-commit-before-ack')while(await committedCount(p)!==1)await p.waitForTimeout(10);
  await p.evaluate(()=>trial.crash());await ready(p);await p.evaluate(()=>trial.pause(false));await settled(p);
  const rows=(await p.evaluate(()=>trial.durable())).journal;assert.equal(rows.length,1);assert.equal(rows[0].id,packet.id);assert.equal(rows[0].payload,packet.payload);assert.equal(await p.locator('textarea').inputValue(),'base PACKET');
  const info=await p.evaluate(()=>trial.inspect());assert.equal(info.count,11);await p.close();return {packetId:packet.id};
 });
 await record('silent Worker exit after commit times out and recovers the same packet',async()=>{
  const p=await page('silent-exit');await p.evaluate(()=>trial.state.crashAfterCommit=true);
  await edit(p,' PACKET');await p.waitForFunction(()=>trial.state.packets.length===1);
  const packet=await p.evaluate(()=>trial.state.packets[0]);
  await p.waitForFunction(()=>trial.state.recoveries===1,{},{timeout:30000});await settled(p);
  const rows=(await p.evaluate(()=>trial.durable())).journal;
  assert.equal(rows.length,1);assert.equal(rows[0].id,packet.id);assert.equal(rows[0].payload,packet.payload);
  assert.equal(await p.locator('textarea').inputValue(),'base PACKET');
  assert.equal((await p.evaluate(()=>trial.inspect())).count,11);await p.close();
 });
 await record('100k restore gates native input until Ready',async()=>{
  const p=await context.newPage();await p.goto(`http://127.0.0.1:4182/?local-tabs-worker=1&doc=${run}-restore&size=100000`);await p.waitForSelector('textarea');
  assert.equal(await p.locator('textarea').evaluate(e=>e.readOnly),true);await p.locator('textarea').focus();await p.keyboard.insertText('MUST_NOT_APPEAR');await ready(p);assert.equal((await p.locator('textarea').inputValue()).length,100000);await p.close();
 });
 await record('A-B-A fences old responses and preserves inactive selection; save ACK is document scoped',async()=>{
  const a=await page('switch'),remote=await page('switch');const id=await a.evaluate(()=>trial.state.documentId);
  await a.locator('textarea').evaluate(e=>e.setSelectionRange(2,2));
  await a.evaluate(()=>trial.switchDocument('synthetic-B','B'));await ready(a);await a.evaluate(()=>trial.state.holdNext=1500);await edit(a,' dirty');
  await remote.locator('textarea').focus();await remote.locator('textarea').evaluate(e=>e.setSelectionRange(0,0));await remote.keyboard.insertText('XX');await settled(remote);
  await a.waitForTimeout(850);assert.equal(await a.locator('#status').innerText(),'Saving on this device');
  await a.evaluate(id=>trial.switchDocument(id),id);await ready(a);await settled(a);assert.equal(await a.locator('textarea').inputValue(),'XXbase');assert.equal(await a.locator('textarea').evaluate(e=>e.selectionStart),4);
  await a.evaluate(()=>trial.switchDocument('synthetic-B'));await ready(a);await settled(a);assert.equal(await a.locator('textarea').inputValue(),'B dirty');
  await a.close();await remote.close();
 });
 await record('unacknowledged Undo crash is retained as unresolved, never silently Saved',async()=>{
  const p=await page('undo-crash');await edit(p,' X');await settled(p);await p.evaluate(()=>{trial.state.delayEdit=1000;trial.history(false);});await p.waitForTimeout(50);await p.evaluate(()=>trial.crash());
  await p.waitForFunction(()=>trial.state.uncertainHistory);assert.match(await p.locator('#status').innerText(),/Not saved.*Undo\/Redo interrupted/);assert.equal(await p.locator('textarea').inputValue(),'base X');
  const retained=await p.evaluate(()=>trial.state.queue[0]);
  await p.locator('#retry').click();assert.equal(await p.evaluate(()=>trial.state.uncertainHistory),true);assert.deepEqual(await p.evaluate(()=>trial.state.queue[0]),retained);
  assert.equal(await p.locator('textarea').evaluate(e=>e.readOnly),true);
  await p.locator('textarea').focus();await p.keyboard.insertText('MUST_NOT_APPEAR');assert.equal(await p.locator('textarea').inputValue(),'base X');
  p.once('dialog',dialog=>dialog.dismiss());await p.locator('#cancel-interrupted-history').click();assert.deepEqual(await p.evaluate(()=>trial.state.queue[0]),retained);
  p.once('dialog',dialog=>dialog.accept());await p.locator('#cancel-interrupted-history').click();await ready(p);await settled(p);assert.equal(await p.locator('textarea').inputValue(),'base X');await p.close();
 });
 await record('ordinary error after Undo execution retains the unresolved request across Retry',async()=>{
  const p=await page('undo-ordinary-error');await edit(p,' X');await settled(p);
  await p.evaluate(()=>{
   const client=trial.state.client,request=client.request.bind(client);let inject=true;
   client.request=async(type,args)=>{const result=await request(type,args);if(type==='history'&&inject){inject=false;throw Error('Injected ordinary error after history result, before main acceptance');}return result;};
   trial.history(false);
  });
  await p.waitForFunction(()=>trial.state.uncertainHistory);
  const retained=await p.evaluate(()=>trial.state.queue[0]);
  assert.equal(await p.locator('textarea').inputValue(),'base X');assert.equal(await committedCount(p),1);
  assert.match(await p.locator('#status').innerText(),/Not saved/);
  await p.locator('#retry').click();assert.deepEqual(await p.evaluate(()=>trial.state.queue[0]),retained);
  assert.equal(await p.locator('textarea').evaluate(e=>e.readOnly),true);
  p.once('dialog',dialog=>dialog.accept());await p.locator('#cancel-interrupted-history').click();await ready(p);await settled(p);
  assert.equal(await p.locator('textarea').inputValue(),'base X');assert.equal(await committedCount(p),1);await p.close();
 });
 await record('missed history over 100k operations replays original valid packets without slicing',async()=>{
  const a=await page('capacity'),b=await page('capacity');await b.evaluate(()=>trial.pause(true));
  const recoveries=await b.evaluate(()=>trial.state.recoveries);
  for(let i=0;i<3;i++){await edit(a,'x'.repeat(20000));await settled(a);await a.locator('textarea').evaluate(e=>e.setSelectionRange(4,20004));await a.keyboard.press('Backspace');await settled(a);}
  assert.equal(await a.locator('textarea').inputValue(),'base');await b.evaluate(()=>trial.pause(false));await settled(b);
  const ia=await a.evaluate(()=>trial.inspect()),ib=await b.evaluate(()=>trial.inspect());assert.equal(ia.version,ib.version);assert.equal(ib.count,120004);assert.equal(ib.pending,0);assert.equal(await b.evaluate(()=>trial.state.recoveries),recoveries);await a.close();await b.close();return {journalOperations:120000,packets:6};
 });
 assert.deepEqual(errors,[]);
}catch(e){results.push({passed:false,error:e.stack});process.exitCode=1;console.error(e);}
finally{await fs.mkdir('evidence',{recursive:true});await fs.writeFile('evidence/fault-results.json',JSON.stringify({date:new Date().toISOString(),browser:browser.version(),headless:process.env.HEADED!=='1',results,errors},null,2));await browser.close();}
