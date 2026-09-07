import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
const require = createRequire('/home/antisatori/ghq/github.com/dowdiness/canopy-loomark-document-lead-decision/apps/loomark/examples/vanilla/package.json');
const { chromium } = require('playwright');
const root = '/home/antisatori/ghq/github.com/dowdiness/canopy-loomark-document-lead-decision';
const browser = await chromium.launch();
const result = { browser: browser.version(), input: [], large: [] };
async function open(body, source) {
  const context = await browser.newContext({viewport: {width:1280,height:720}});
  const page = await context.newPage();
  await page.route('**/index.js', r => r.fulfill({contentType:'application/javascript',body}));
  await page.addInitScript(() => {
    globalThis.__leadTimes=[];globalThis.__longTasks=[];
    new PerformanceObserver(list => globalThis.__longTasks.push(...list.getEntries().map(e=>({start:e.startTime,duration:e.duration})))).observe({type:'longtask',buffered:true});
  });
  await page.goto('http://127.0.0.1:4347/');
  await page.getByRole('textbox',{name:'Text',exact:true}).waitFor();
  await page.evaluate(async source => {
    const db = await new Promise((resolve,reject)=>{const r=indexedDB.open('loomark',1);r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
    await new Promise((resolve,reject)=>{const tx=db.transaction('documents','readwrite');const store=tx.objectStore('documents');store.clear();store.put(JSON.stringify({document_id:'diagnostic',text:source,change_order:1}),'source/v1/diagnostic');tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error)});db.close();
  },source);
  await page.reload();
  await page.waitForFunction(source=>document.querySelector('textarea')?.value===source,source);
  return {context,page};
}
try {
  // Profile the exact native replacement operation, with phase times. These
  // diagnostic times are separate from the unchanged 10ms regression test.
  for (const variant of (process.env.LOOMARK_LARGE_ONLY ? [] : ['baseline','current','no-extraction'])) {
    const {context,page} = await open(await readFile(`/tmp/loomark-${variant}.min.js`,'utf8'),'# Equality fixture\n'+'x'.repeat(1024*1024));
    const cdp=await context.newCDPSession(page);
    await cdp.send('Profiler.enable');await cdp.send('Profiler.start');
    const samples=await page.getByRole('textbox',{name:'Text',exact:true}).evaluate(t=>{
      const dispatch=(replacement)=>{
        const start=performance.now(); const end=t.value.length;t.setSelectionRange(end-1,end); const selected=performance.now();
        t.dispatchEvent(new InputEvent('beforeinput',{bubbles:true,cancelable:true,composed:true,data:replacement,inputType:'insertReplacementText'}));const before=performance.now();
        t.setRangeText(replacement,end-1,end,'end');const native=performance.now();
        t.dispatchEvent(new InputEvent('input',{bubbles:true,composed:true,data:replacement,inputType:'insertReplacementText'}));const done=performance.now();
        return {total:done-start,select:selected-start,beforeinput:before-selected,setRangeText:native-before,input:done-native};
      };
      for(let i=0;i<10;i++){dispatch('y');dispatch('x')}
      return Array.from({length:25},()=>[dispatch('y'),dispatch('x')]).flat();
    });
    const {profile}=await cdp.send('Profiler.stop');await writeFile(`/tmp/loomark-input-${variant}.cpuprofile`,JSON.stringify(profile));
    result.input.push({variant,samples});await context.close();
  }
  const original = await readFile(root+'/_build/js/release/build/dowdiness/loomark/main/main.js','utf8');
  const match=original.match(/function (\w*document__lead\d+extract)\(source, limits\) \{/);
  if(!match) throw Error('extract entry missing');
  const name=match[1];
  const body=`function ${name}(source,limits){const start=performance.now();let output;try{return output=${name}_diagnostic(source,limits)}finally{const duration=performance.now()-start;globalThis.__leadOutput=JSON.stringify(output,(k,v)=>v&&typeof v==='object'&&typeof v.$tag==='number'?{...v,$tag:v.$tag}:v);globalThis.__leadTimes.push({bytes:new TextEncoder().encode(source).length,start,duration})}}\n`+original.replace(match[0],`function ${name}_diagnostic(source, limits) {`);
  const source=Array.from({length:Number(process.env.LOOMARK_BLOCKS ?? 1000)},(_,i)=>`# Note ${i}\n\nParagraph **content** with some detail.\n\n`).join('');
  const {context,page}=await open(body,source);
  await page.waitForTimeout(100);
  result.large.push({phase:'cold',...(await page.evaluate(()=>({leads:__leadTimes,longTasks:__longTasks})))});
  await page.evaluate(()=>{__leadTimes=[];__longTasks=[]});
  const text = page.getByRole('textbox',{name:'Text',exact:true});
  await text.focus();await text.press('ControlOrMeta+End');await text.pressSequentially('!');
  await page.waitForFunction(()=>__leadTimes.length>0,null,{timeout:30000});
  await page.waitForTimeout(100);
  result.large.push({phase:'quiet',...(await page.evaluate(()=>({leads:__leadTimes,longTasks:__longTasks})))});
  if(process.env.LOOMARK_WORKER_PROBE) {
    await page.getByRole('button',{name:'Toggle documents',exact:true}).click();
    const footer=original.lastIndexOf('\n(() => {');
    if(footer<0 || !original.slice(footer).includes('mount')) throw Error('bootstrap missing');
    const leadFor=original.match(/function (\w*recent__documents\d+lead__for)\(source\)/)[1];
    const workerBody=original.slice(0,footer)+`\nself.onmessage=event=>{const start=performance.now();self.postMessage({type:'started',startAbsolute:performance.timeOrigin+start});const lead=${leadFor}(event.data);const end=performance.now();const duration=end-start;self.postMessage({duration,startAbsolute:performance.timeOrigin+start,endAbsolute:performance.timeOrigin+end,lead:JSON.stringify(lead,(k,v)=>v&&typeof v==='object'&&typeof v.$tag==='number'?{...v,$tag:v.$tag}:v)})};`;
    await page.evaluate(({workerBody,source})=>{
      const url=URL.createObjectURL(new Blob([workerBody],{type:'application/javascript'}));
      const worker=new Worker(url);const start=performance.now();let last=start;const gaps=[];
      const timer=setInterval(()=>{const now=performance.now();gaps.push(now-last);last=now},10);
      globalThis.__workerStarted=false;globalThis.__workerDone=false;globalThis.__workerInputTimes=[];
      document.addEventListener('input',()=>globalThis.__workerInputTimes.push(performance.timeOrigin+performance.now()));
      globalThis.__workerResult=new Promise((resolve,reject)=>{
        worker.onmessage=event=>{if(event.data.type==='started'){globalThis.__workerStarted=true;return}globalThis.__workerDone=true;resolve({...event.data,wall:performance.now()-start,gaps,equal:event.data.lead===globalThis.__leadOutput})};
        worker.onerror=event=>reject(Error(event.message));
      }).finally(()=>{clearInterval(timer);worker.terminate();URL.revokeObjectURL(url)});
      worker.postMessage(source);
    },{workerBody,source});
    await page.waitForFunction(()=>globalThis.__workerStarted);
    await text.focus();await text.press('ControlOrMeta+End');await text.pressSequentially('?');
    const editing=await page.evaluate(()=>({replyPending:!globalThis.__workerDone,inputTimes:globalThis.__workerInputTimes,appended:document.querySelector('textarea').value.endsWith('?')}));
    result.worker={...(await page.evaluate(()=>globalThis.__workerResult)),editing};
    if(!result.worker.equal || !editing.appended || !editing.inputTimes.length || !editing.inputTimes.every(t=>result.worker.startAbsolute<t && t<result.worker.endAbsolute)) throw Error('input was not inside the worker computation interval');
  }
  await context.close();
} finally {
  await browser.close();await writeFile('/tmp/loomark-browser-diagnosis.json',JSON.stringify(result,null,2));
}
console.log(JSON.stringify({browser:result.browser,input:result.input.map(({variant,samples})=>({variant,means:Object.fromEntries(Object.keys(samples[0]).map(k=>[k,samples.reduce((a,s)=>a+s[k],0)/samples.length]))})),large:result.large},null,2));
