import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import os from 'node:os';
import assert from 'node:assert/strict';
const headed=process.env.HEADED==='1',browser=await chromium.launch({executablePath:process.env.CHROME_PATH||(process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined),headless:!headed});
const context=await browser.newContext({viewport:{width:1200,height:900}}),errors=[];context.on('page',p=>p.on('pageerror',e=>errors.push(e.message)));
const result={date:new Date().toISOString(),browser:browser.version(),headless:!headed,cpu:os.cpus()[0].model,node:process.version,viewport:{width:1200,height:900},cases:[],errors};
const run='worker-perf-'+Date.now();
const stat=xs=>{const a=xs.toSorted((a,b)=>a-b);return {n:a.length,median:a.length?(a[(a.length-1)>>1]+a[a.length>>1])/2:null,p95:a[Math.ceil(a.length*.95)-1]??null,max:a.at(-1)??null};};
async function frames(p){await p.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));}
async function ready(p){await p.bringToFront();await p.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly,{},{timeout:60000});await frames(p);}
async function settle(p){await p.waitForFunction(()=>trial.state.ready&&!trial.state.running&&!trial.state.queue.length&&!trial.state.packets.length&&!trial.state.failure&&!trial.state.blocked,{},{timeout:60000});}
async function edit(p,start,end,text){await p.bringToFront();await p.locator('textarea').focus();await p.locator('textarea').evaluate((e,[a,b])=>e.setSelectionRange(a,b),[start,end]);if(text)await p.keyboard.insertText(text);else await p.keyboard.press('Backspace');await settle(p);await frames(p);}
async function sync(a,b){await settle(a);await b.evaluate(()=>trial.catchUp());await settle(b);await b.waitForFunction(text=>trial.state.text===text,await a.locator('textarea').inputValue());}
async function raw(p){return p.evaluate(()=>({metrics:trial.metrics,longTasks:trial.longTasks,ready:trial.state.ready,textLength:trial.state.text.length,operations:trial.state.count}));}
try{
 for(const size of [10000,100000]){
  const url=`http://127.0.0.1:4182/?local-tabs-worker=1&doc=${run}-${size}&size=${size}`;
  const a=await context.newPage();await a.goto(url);await ready(a);const initial=await raw(a);
  const b=await context.newPage();await b.goto(url);await ready(b);
  for(const history of ['basic','churn-10000']){
   if(history!=='basic'){await edit(a,size/2,size/2,'x'.repeat(5000));await sync(a,b);await edit(a,size/2,size/2+5000,'');await sync(a,b);}
   const reloads=[];
   for(let i=0;i<5;i++){await a.reload();await ready(a);const r=await raw(a);assert.equal(r.textLength,size);reloads.push(r);}
   await Promise.all([a,b].map(p=>p.evaluate(()=>{trial.metrics.length=0;trial.longTasks.length=0;trial.state.metricPhase='local';})));
   for(let i=0;i<10;i++){await edit(a,size/2,size/2,'X');await sync(a,b);await edit(a,size/2,size/2+1,'');await sync(a,b);}
   const local=await raw(a);
   await Promise.all([a,b].map(p=>p.evaluate(()=>{trial.metrics.length=0;trial.longTasks.length=0;trial.state.metricPhase='remote';})));await b.bringToFront();await frames(b);
   for(let i=0;i<10;i++){
    const text=i%2?'':'Y',end=i%2?size/2+1:size/2;
    const started=Date.now();
    await a.evaluate(([start,end,text])=>{const e=document.querySelector('textarea'),inputType=text?'insertText':'deleteContentBackward';e.setSelectionRange(start,end);e.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,inputType,data:text||null}));e.setRangeText(text,start,end,'end');e.dispatchEvent(new InputEvent('input',{bubbles:true,inputType,data:text||null}));},[size/2,end,text]);
    await sync(a,b);await frames(b);result.lastRemoteRoundtripMs=Date.now()-started;
   }
   const remote=await raw(b),save=await raw(a);
   local.metrics=local.metrics.filter(m=>m.kind==='save'||m.phase==='local');
   remote.metrics=remote.metrics.filter(m=>m.kind==='save'||m.phase==='remote');
   const opens=reloads.flatMap(r=>r.metrics.filter(m=>m.kind==='open'));
   const allTasks=reloads.flatMap(r=>r.longTasks),restoreTasks=reloads.flatMap(r=>r.longTasks.filter(t=>t.start+t.duration>=r.metrics.find(m=>m.kind==='open')?.start));
   const summary={loadToReadyMs:stat(opens.map(m=>m.navigationReadyMs)),restoreToUsableProxyMs:stat(opens.map(m=>m.usableMs)),workerRestoreMs:stat(opens.map(m=>m.restoreMs)),workerReplayMs:stat(opens.map(m=>m.replayMs)),navigationLongTaskMs:stat(allTasks.map(t=>t.duration)),restoreLongTaskMs:stat(restoreTasks.map(t=>t.duration)),localInputProxyMs:stat(local.metrics.filter(m=>m.kind==='local-input').map(m=>m.usableMs)),localAcceptedMs:stat(local.metrics.filter(m=>m.kind==='local-accepted').map(m=>m.workMs)),remoteApplyProxyMs:stat(remote.metrics.filter(m=>m.kind==='remote-apply').map(m=>m.usableMs)),commitMs:stat([...local.metrics,...save.metrics].filter(m=>m.kind==='save').map(m=>m.commitMs)),steadyLongTasks:[...local.longTasks,...remote.longTasks]};
   result.cases.push({size,history,initial:history==='basic'?initial:undefined,summary,reloads,local,remote,save});console.log(JSON.stringify({size,history,summary}));
  }await a.close();await b.close();
 }assert.deepEqual(errors,[]);
}catch(e){result.error=e.stack;process.exitCode=1;console.error(e);}
finally{await fs.mkdir('evidence',{recursive:true});await fs.writeFile(`evidence/performance-${headed?'headed':'headless'}.json`,JSON.stringify(result,null,2));await browser.close();}
