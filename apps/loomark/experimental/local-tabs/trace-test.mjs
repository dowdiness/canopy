import {chromium} from 'playwright';
import fs from 'node:fs/promises';
import {gzipSync} from 'node:zlib';
import assert from 'node:assert/strict';
const headed=process.env.HEADED==='1',browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:!headed});
const context=await browser.newContext({viewport:{width:1200,height:900}}),p=await context.newPage(),records=[];
const url=`http://127.0.0.1:4182/?local-tabs-worker=1&doc=trace-${Date.now()}&size=100000`;
async function ready(){await p.bringToFront();await p.waitForFunction(()=>globalThis.trial?.state?.ready&&!document.querySelector('textarea').readOnly,{},{timeout:60000});await p.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));}
async function settle(){await p.waitForFunction(()=>trial.state.ready&&!trial.state.running&&!trial.state.queue.length&&!trial.state.packets.length&&!trial.state.failure&&!trial.state.blocked,{},{timeout:60000});}
await fs.mkdir('evidence/traces',{recursive:true});
try{
 await p.goto(url);await ready();
 for(const history of ['basic','churn']){
  if(history==='churn'){await p.locator('textarea').focus();await p.keyboard.press('Control+End');await p.keyboard.insertText('x'.repeat(5000));await settle();await p.locator('textarea').evaluate(e=>e.setSelectionRange(100000,105000));await p.keyboard.press('Backspace');await settle();}
  for(let i=0;i<3;i++){
   const cdp=await context.newCDPSession(p);
   await cdp.send('Tracing.start',{categories:'toplevel,devtools.timeline',transferMode:'ReturnAsStream'});
   await p.reload();await ready();await settle();
   const ui=await p.evaluate(()=>({metrics:trial.metrics,longTasks:trial.longTasks,textLength:trial.state.text.length}));
   const completed=new Promise(resolve=>cdp.once('Tracing.tracingComplete',resolve));await cdp.send('Tracing.end');const {stream}=await completed;
   let raw='';while(true){const r=await cdp.send('IO.read',{handle:stream});raw+=r.base64Encoded?Buffer.from(r.data,'base64').toString():r.data;if(r.eof)break;}await cdp.send('IO.close',{handle:stream});await cdp.detach();
   const trace=JSON.parse(raw),main=new Set(trace.traceEvents.filter(e=>e.name==='thread_name'&&e.args?.name==='CrRendererMain').map(e=>`${e.pid}:${e.tid}`));
   const tasks=trace.traceEvents.filter(e=>main.has(`${e.pid}:${e.tid}`)&&e.ph==='X'&&/^(RunTask|ThreadControllerImpl::RunTask)$/.test(e.name));
   assert.ok(tasks.length>0,'Trace must contain renderer main tasks');
   const maximum=Math.max(...tasks.map(t=>t.dur/1000));
   const file=`evidence/traces/${headed?'headed':'headless'}-${history}-${i}.json.gz`;await fs.writeFile(file,gzipSync(raw));
   const record={history,iteration:i,file,mainThreads:[...main],taskCount:tasks.length,maxMainTaskMs:maximum,over50:tasks.filter(t=>t.dur>50000).map(t=>({name:t.name,durationMs:t.dur/1000})),ui};records.push(record);console.log(JSON.stringify({history,i,maximum,over50:record.over50}));
   assert.equal(ui.textLength,100000);assert.equal(record.over50.length,0,'No >50ms renderer main task across reopen through usable text');
  }
 }
 await p.screenshot({path:`evidence/worker-${headed?'headed':'headless'}.png`});
}catch(e){records.push({error:e.stack});process.exitCode=1;console.error(e);}
finally{await fs.writeFile(`evidence/trace-${headed?'headed':'headless'}.json`,JSON.stringify({date:new Date().toISOString(),browser:browser.version(),headless:!headed,records},null,2));await browser.close();}
