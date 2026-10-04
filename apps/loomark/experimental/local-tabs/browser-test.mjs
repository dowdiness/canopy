import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';
const browser=await chromium.launch({executablePath:process.env.CHROME_PATH||(process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined),headless:process.env.HEADED!=='1'});
const context=await browser.newContext({viewport:{width:1200,height:900}});
const errors=[],results=[];
context.on('page',p=>p.on('pageerror',e=>errors.push(e.message)));
const base='http://127.0.0.1:4182/';
const run=Date.now().toString(36);
async function page(doc,seed='alpha beta gamma',extra=''){
  const p=await context.newPage();await p.goto(`${base}?local-tabs-worker=1&doc=${run}-${doc}&seed=${encodeURIComponent(seed)}${extra}`);
  await p.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly);
  return p;
}
async function settled(p){await p.waitForFunction(()=>trial.state.ready&&!trial.state.running&&!trial.state.queue.length&&!trial.state.packets.length&&!trial.state.failure&&!trial.state.blocked,{},{timeout:15000});}
async function edit(p,start,end,text){
  await p.locator('textarea').focus();
  await p.locator('textarea').evaluate((e,[a,b])=>e.setSelectionRange(a,b),[start,end]);
  if(text)await p.keyboard.insertText(text);else await p.keyboard.press('Backspace');
}
async function same(a,b){
  await settled(a);await settled(b);
  await a.evaluate(()=>trial.catchUp());await b.evaluate(()=>trial.catchUp());
  await settled(a);await settled(b);
  const aa=await a.evaluate(()=>trial.inspect()),bb=await b.evaluate(()=>trial.inspect());
  assert.equal(aa.text,bb.text);assert.equal(aa.version,bb.version);assert.equal(aa.count,bb.count);assert.equal(aa.pending,0);assert.equal(bb.pending,0);
  assert.equal(await a.locator('textarea').inputValue(),aa.text);assert.equal(await b.locator('textarea').inputValue(),bb.text);
  // Version ranges encode the complete accepted operation identity set.
  const ids=v=>JSON.parse(v).ranges.flatMap(r=>r.ranges.flatMap(i=>Array.from({length:i.end-i.start},(_,n)=>[r.replica_id,i.start+n]))).sort();
  assert.deepEqual(ids(aa.version),ids(bb.version));return aa;
}
async function record(name,fn){if(process.env.TEST_FILTER&&!name.includes(process.env.TEST_FILTER))return;const start=Date.now();const detail=await fn();results.push({name,passed:true,ms:Date.now()-start,...detail});console.log('PASS',name,detail||'');}
try{
  await record('ReplaceAll separated hunks are one native Undo group',async()=>{
    const seed='alpha middle omega',replacement='ALPHA middle OMEGA';
    const a=await page('replace-all',seed);
    // An input without beforeinput makes the real binding admit ReplaceAll.
    await a.locator('textarea').evaluate((e,text)=>{e.value=text;e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertReplacementText',data:text}));},replacement);
    await settled(a);assert.equal((await a.evaluate(()=>trial.inspect())).text,replacement);
    await edit(a,replacement.length,replacement.length,'!');await settled(a);
    await a.keyboard.press('Control+z');await settled(a);assert.equal(await a.locator('textarea').inputValue(),replacement);
    await a.keyboard.press('Control+z');await settled(a);assert.equal(await a.locator('textarea').inputValue(),seed);
    await a.keyboard.press('Control+Shift+z');await settled(a);assert.equal(await a.locator('textarea').inputValue(),replacement);
    await a.keyboard.press('Control+Shift+z');await settled(a);assert.equal(await a.locator('textarea').inputValue(),replacement+'!');
    await a.close();
  });
  await record('two real tabs: edit, save, close both, reopen',async()=>{
    let [a,b]=await Promise.all([page('basic'),page('basic')]);
    await edit(a,0,0,'A ');await settled(a);await b.evaluate(()=>trial.catchUp());
    await edit(b,18,18,' B');const info=await same(a,b);
    const writers=await Promise.all([a,b].map(p=>p.evaluate(()=>trial.state.writer)));
    await a.close();await b.close();
    [a,b]=await Promise.all([page('basic'),page('basic')]);
    const reopened=await same(a,b);assert.equal(reopened.text,info.text);
    for(const p of [a,b])assert.ok(!writers.includes(await p.evaluate(()=>trial.state.writer)));
    await mkdir('evidence',{recursive:true});await a.screenshot({path:'evidence/two-tabs-a.png'});await b.screenshot({path:'evidence/two-tabs-b.png'});
    await a.close();await b.close();return {text:info.text,operations:info.count};
  });
  await record('disjoint concurrent edits, reverse save order, duplicate notifications',async()=>{
    const [a,b]=await Promise.all([page('reverse'),page('reverse')]);
    await Promise.all([a,b].map(p=>p.evaluate(()=>trial.pause(true))));
    await edit(a,0,0,'LEFT ');await edit(b,16,16,' RIGHT');
    await b.evaluate(()=>trial.pause(false));await settled(b);
    await a.evaluate(()=>trial.pause(false));const info=await same(a,b);
    assert.equal(info.text,'LEFT alpha beta gamma RIGHT');
    await a.evaluate(()=>{for(let i=0;i<10;i++)trial.notify();});
    await b.evaluate(()=>trial.catchUp());assert.equal((await same(a,b)).count,info.count);
    await a.close();await b.close();return {text:info.text,operations:info.count};
  });
  await record('overlapping rewrites converge without semantic rewriting',async()=>{
    const [a,b]=await Promise.all([page('overlap','color'),page('overlap','color')]);
    await Promise.all([a,b].map(p=>p.evaluate(()=>trial.pause(true))));
    await edit(a,0,5,'red');await edit(b,0,5,'green');
    await Promise.all([a,b].map(p=>p.evaluate(()=>trial.pause(false))));
    const info=await same(a,b);assert.ok(['redgreen','greenred'].includes(info.text));
    await a.close();await b.close();return {text:info.text};
  });
  await record('same-position inserts, concurrent delete and tab-local Undo/Redo',async()=>{
    const [a,b]=await Promise.all([page('same','abc'),page('same','abc')]);
    await Promise.all([a,b].map(p=>p.evaluate(()=>trial.pause(true))));
    await edit(a,1,1,'X');await edit(b,1,1,'Y');
    await Promise.all([a,b].map(p=>p.evaluate(()=>trial.pause(false))));
    const inserted=await same(a,b);assert.match(inserted.text,/^a[XY]{2}bc$/);
    await a.locator('textarea').focus();await a.keyboard.press('Control+z');
    const undone=await same(a,b);assert.equal(undone.text,'aYbc');
    await a.keyboard.press('Control+Shift+z');assert.equal((await same(a,b)).text,inserted.text);
    const pos=inserted.text.indexOf('b');
    await Promise.all([a,b].map(p=>p.evaluate(()=>trial.pause(true))));
    await edit(a,pos,pos+1,'');await edit(b,pos,pos+1,'');
    await Promise.all([a,b].map(p=>p.evaluate(()=>trial.pause(false))));
    assert.ok(!(await same(a,b)).text.includes('b'));
    await a.locator('textarea').focus();await a.keyboard.press('Control+z');
    const revived=await same(a,b);
    await a.close();await b.close();return {afterConcurrentDeleteUndo:revived.text,behavior:'EGW may revive a concurrently deleted character'};
  });
  await record('missed notifications, third tab, out-of-order replay and duplicates',async()=>{
    const [a,b]=await Promise.all([page('missed'),page('missed')]);
    await b.evaluate(()=>{trial.state.ignoreNotifications=true;trial.pause(true);});
    await edit(a,0,0,'1');await settled(a);await edit(a,1,1,'2');await settled(a);
    const c=await page('missed');assert.equal((await same(a,c)).text,'12alpha beta gamma');
    await b.evaluate(()=>trial.pause(false));await same(b,c);
    const replay=await c.evaluate(()=>trial.test('test-replay'));
    const expected=await same(a,c);
    assert.equal(replay.info.text,expected.text);assert.equal(replay.info.version,expected.version);assert.equal(replay.info.count,expected.count);assert.equal(replay.info.pending,0);
    await Promise.all([a,b,c].map(p=>p.close()));return {reorderedPending:replay.pending};
  });
  await record('IndexedDB abort retries same IDs, delayed completion retains newer unsaved edit',async()=>{
    const a=await page('abort');await a.evaluate(()=>trial.state.abortNext=true);
    await edit(a,0,0,'X');await a.waitForFunction(()=>!!trial.state.failure);
    const packet=await a.evaluate(()=>trial.state.packets[0]);
    assert.equal((await a.evaluate(()=>trial.durable())).journal.length,0);
    assert.equal(await a.locator('textarea').inputValue(),'Xalpha beta gamma');
    await a.locator('#retry').click();await settled(a);
    const durable=await a.evaluate(()=>trial.durable());assert.equal(durable.journal[0].payload,packet.payload);assert.equal(durable.journal[0].id,packet.id);
    await a.evaluate(()=>trial.state.holdNext=500);
    await edit(a,1,1,'Y');await a.waitForFunction(()=>trial.state.running);
    await edit(a,2,2,'Z');
    assert.equal(await a.locator('#status').innerText(),'Saving on this device');
    await settled(a);const b=await page('abort');assert.equal((await same(a,b)).text,'XYZalpha beta gamma');
    await a.close();await b.close();return {retryPacket:packet.id};
  });
  await record('emoji UTF-16, repeated characters, distant edits, selection and scroll',async()=>{
    const seed='😀aaaa\n'+'middle line\n'.repeat(80)+'zzzz';
    const [a,b]=await Promise.all([page('unicode',seed),page('unicode',seed)]);
    await b.locator('textarea').evaluate(e=>{e.focus();e.setSelectionRange(120,130,'backward');e.scrollTop=240;});
    const scroll=await b.locator('textarea').evaluate(e=>e.scrollTop);
    await a.evaluate(()=>trial.pause(true));await edit(a,2,2,'日');await edit(a,seed.length+1,seed.length+1,'終');
    await a.evaluate(()=>trial.pause(false));await same(a,b);
    const selection=await b.locator('textarea').evaluate(e=>[e.selectionStart,e.selectionEnd,e.selectionDirection,e.scrollTop]);
    assert.deepEqual(selection,[121,131,'backward',scroll]);
    await edit(b,0,2,'🌱');await same(a,b);
    const info=await a.evaluate(()=>trial.inspect());assert.ok(info.text.startsWith('🌱日aaaa'));
    await a.close();await b.close();return {selection};
  });
  await record('remote arriving between beforeinput/input uses original basis',async()=>{
    const [a,b]=await Promise.all([page('between','abcdef'),page('between','abcdef')]);
    await b.locator('textarea').evaluate(e=>{e.focus();e.setSelectionRange(3,3);e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType:'insertText',data:'B'}));});
    await edit(a,0,0,'A');await settled(a);await b.evaluate(()=>trial.catchUp());
    assert.equal(await b.locator('textarea').inputValue(),'abcdef');
    await b.locator('textarea').evaluate(e=>{e.setRangeText('B',3,3,'end');e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertText',data:'B'}));});
    assert.equal((await same(a,b)).text,'AabcBdef');
    await a.close();await b.close();return {events:'synthetic split-task beforeinput/input'};
  });
  await record('Japanese synthetic composition defers remote DOM and commits original basis',async()=>{
    const [a,b]=await Promise.all([page('composition','abcdef'),page('composition','abcdef')]);
    await b.locator('textarea').evaluate(e=>{e.focus();e.setSelectionRange(3,3);e.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true,data:''}));e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType:'insertCompositionText',data:'に',isComposing:true}));e.setRangeText('に',3,3,'end');e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertCompositionText',data:'に',isComposing:true}));});
    await edit(a,0,0,'A');await settled(a);await b.evaluate(()=>trial.catchUp());
    assert.equal(await b.locator('textarea').inputValue(),'abcにdef');
    assert.equal(await b.locator('#status').innerText(),'Composing — not saved');
    await b.locator('textarea').evaluate(e=>{e.setRangeText('日本語',3,4,'end');e.dispatchEvent(new CompositionEvent('compositionend',{bubbles:true,data:'日本語'}));e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType:'insertFromComposition',data:'日本語',isComposing:false}));e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType:'insertFromComposition',data:'日本語',isComposing:false}));});
    assert.equal((await same(a,b)).text,'Aabc日本語def');
    await a.close();await b.close();return {events:'synthetic; not OS IME'};
  });
  await record('10k and 100k first usable text / local input / remote apply',async()=>{
    const measurements=[];
    for(const size of [10000,100000]){
      const a=await page(`perf-${size}`,'',`&size=${size}`);const b=await page(`perf-${size}`,'',`&size=${size}`);
      await edit(a,Math.floor(size/2),Math.floor(size/2),'😀');await same(a,b);
      await edit(b,size+2,size+2,'Z');await same(a,b);
      await a.waitForTimeout(100);
      measurements.push({size,a:await a.evaluate(()=>trial.state.metrics),b:await b.evaluate(()=>trial.state.metrics)});
      await a.reload();await a.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly);await same(a,b);await a.waitForTimeout(100);
      measurements.at(-1).reopen=await a.evaluate(()=>trial.state.metrics);
      await a.close();await b.close();
    }
    return {measurements};
  });
  await record('5000-character paste Undo/Redo and canceled beforeinput release',async()=>{
    const [a,b]=await Promise.all([page('large-undo','base'),page('large-undo','base')]);
    await edit(a,4,4,'x'.repeat(5000));await same(a,b);
    await a.locator('textarea').focus();await a.keyboard.press('Control+z');assert.equal((await same(a,b)).text,'base');
    await a.keyboard.press('Control+Shift+z');assert.equal((await same(a,b)).text.length,5004);
    await b.locator('textarea').evaluate(e=>{
      e.addEventListener('beforeinput',event=>event.preventDefault(),{once:true});
      e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,inputType:'insertText',data:'Q'}));
    });
    await edit(a,0,0,'A');assert.ok((await same(a,b)).text.startsWith('Abase'));
    await a.close();await b.close();
  });
  await record('whole malformed/schema/resource packets rejected with unchanged state',async()=>{
    const a=await page('admission','safe');
    const outcome=await a.evaluate(()=>trial.test('test-admission'));
    assert.equal(outcome.errors.length,3);assert.equal(outcome.before.version,outcome.after.version);assert.equal(outcome.after.text,'safe');
    assert.match(outcome.errors[2],/LimitExceeded/);
    await a.close();return {rejected:outcome.errors.length,limitError:outcome.errors[2]};
  });
  assert.deepEqual(errors,[]);
}catch(e){results.push({passed:false,error:e.stack});console.error(e);process.exitCode=1;}
finally{await mkdir('evidence',{recursive:true});await writeFile('evidence/browser-results.json',JSON.stringify({date:new Date().toISOString(),browser:browser.version(),headless:process.env.HEADED!=='1',results,errors},null,2));await browser.close();}
