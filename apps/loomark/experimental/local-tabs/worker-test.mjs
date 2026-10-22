import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {mkdir,writeFile} from 'node:fs/promises';

const base='http://127.0.0.1:4182/';
const workerUrl=process.env.WORKER_URL||'./worker.js';
const run=`worker-${Date.now()}`;
const epoch=2**40+9;
let browser,context,page;
const results=[];
async function record(name,fn){
  const data=await fn();results.push({name,passed:true,...data});console.log('PASS',name,data||'');
}
async function send(message){return page.evaluate(message=>window.__directWorker.request(message),message);}
async function startWorker(document,options,incarnation=epoch){
  await page.evaluate(({workerUrl})=>{
    window.__directWorker?.stop();
    const worker=new Worker(new URL(workerUrl,location.href),{type:'module'});
    const waiting=new Map();
    const fail=error=>{for(const p of waiting.values()){clearTimeout(p.timer);p.reject(error);}waiting.clear();};
    worker.onerror=event=>fail(Error(event.message||'Worker failed'));
    worker.onmessageerror=()=>fail(Error('Worker message could not be decoded'));
    worker.onmessage=({data})=>{
      window.__workerMessages.push(data);
      const p=waiting.get(data.id);if(!p||data.checkpoint)return;
      waiting.delete(data.id);clearTimeout(p.timer);
      if(data.epoch!==p.message.epoch||data.document!==p.message.document)p.reject(Error('Response envelope mismatch'));
      else p.resolve(data);
    };
    window.__workerMessages=[];
    window.__directWorker={worker,
      post:message=>worker.postMessage(message),
      request:message=>new Promise((resolve,reject)=>{
        const timer=setTimeout(()=>{waiting.delete(message.id);reject(Error(`Worker request timed out: ${message.type}`));},15000);
        waiting.set(message.id,{message,resolve,reject,timer});worker.postMessage(message);
      }),
      stop:()=>{worker.terminate();fail(Error('Worker terminated'));}};
  },{workerUrl});
  const opened=await send({epoch:incarnation,id:2**40+11,document,type:'open',...options});
  assert.equal(opened.ok,true,opened.error);
  return opened.result;
}
async function journal(document){
  return page.evaluate(async document=>{
    const {openStore,readJournal}=await import('./store.mjs');
    const db=await openStore();try{return await readJournal(db,document,0);}finally{db.close();}
  },document);
}
try{
  browser=await chromium.launch({executablePath:process.env.CHROME_PATH||(process.platform==='win32'?'C:/Program Files/Google/Chrome/Application/chrome.exe':undefined),headless:process.env.HEADED!=='1'});
  context=await browser.newContext({viewport:{width:1200,height:900}});
  page=await context.newPage();
  await page.goto(base);

  await record('overlapping requests remain FIFO; safe integers, duplicate command and rejection recovery',async()=>{
    const document=`${run}-fifo`;const opened=await startWorker(document,{seed:'alpha'});
    assert.equal(opened.info.text,'alpha');
    const seq=2**40+21,firstId=2**40+31,secondId=2**40+32;
    const first={epoch,id:firstId,document,type:'edit',command:`${document}-first`,commandSeq:seq,
      before:'alpha',after:'alpha one',input:{start:5,deleted:0,inserted:' one'},createdAt:Date.now(),delay:100};
    const second={epoch,id:secondId,document,type:'edit',command:`${document}-second`,commandSeq:seq+1,
      before:'alpha one',after:'alpha one two',input:{start:9,deleted:0,inserted:' two'},createdAt:Date.now()};
    const [a,b]=await page.evaluate(messages=>Promise.all(messages.map(message=>window.__directWorker.request(message))),[first,second]);
    assert.equal(a.ok,true,a.error);assert.equal(b.ok,true,b.error);
    assert.deepEqual((await page.evaluate(()=>window.__workerMessages.filter(m=>m.ok).map(m=>m.id))).slice(-2),[firstId,secondId]);
    assert.equal(b.result.info.text,'alpha one two');
    const replay=await send({...second,id:2**40+34});
    assert.equal(replay.ok,true,replay.error);assert.deepEqual(replay.result,b.result);
    const wrong=await send({epoch,id:2**40+35,document,type:'edit',command:`${document}-bad-basis`,commandSeq:seq+2,
      before:'not the current basis',after:'bad',input:{start:0,deleted:0,inserted:'bad'},createdAt:Date.now()});
    assert.equal(wrong.ok,false);
    const next=await send({epoch,id:2**40+36,document,type:'edit',command:`${document}-after-error`,commandSeq:seq+2,
      before:'alpha one two',after:'alpha one two!',input:{start:13,deleted:0,inserted:'!'},createdAt:Date.now()});
    assert.equal(next.ok,true,next.error);assert.equal(next.result.info.text,'alpha one two!');
    const admitted=await page.evaluate(({epoch,document,seq})=>{
      const result=window.__directWorker.request({epoch,id:2**40+37,document,type:'edit',
        command:`${document}-before-malformed`,commandSeq:seq+3,before:'alpha one two!',after:'alpha one two! FIFO',
        input:{start:14,deleted:0,inserted:' FIFO'},createdAt:Date.now(),delay:100});
      window.__directWorker.post({epoch,id:0.5,document,type:'inspect'});
      return result;
    },{epoch,document,seq});
    assert.equal(admitted.ok,true,admitted.error);assert.equal(admitted.result.info.text,'alpha one two! FIFO');
    return {requestIdsAbove32Bit:true,commandSequencesAbove32Bit:true,ordered:[firstId,secondId],duplicatePacketSame:true,rejectedThenAccepted:true,laterMalformedEnvelopePreservesEarlierAck:true};
  });

  await record('committed lost ACK recovers and retries the identical packet exactly once',async()=>{
    const document=`${run}-lost-ack`;const initial=await startWorker(document,{seed:'recover me'});
    const edited=await send({epoch,id:2**40+41,document,type:'edit',command:`${document}-edit`,commandSeq:2**40+51,
      before:'recover me',after:'recover me!',input:{start:10,deleted:0,inserted:'!'},createdAt:Date.now()});
    assert.equal(edited.ok,true,edited.error);const packet=edited.result.packet;
    assert.ok(packet);assert.equal(edited.result.info.text,'recover me!');
    await page.evaluate(message=>window.__directWorker.post(message),{epoch,id:2**40+42,document,type:'save',packet,fault:{crashAfterCommit:true}});
    await page.waitForFunction(async document=>{
      const {openStore,readJournal}=await import('./store.mjs');const db=await openStore();
      try{return (await readJournal(db,document,0)).length===1;}finally{db.close();}
    },document,{timeout:15000});
    const committed=await journal(document);
    assert.equal(committed.length,1);assert.equal(committed[0].id,packet.id);assert.equal(committed[0].payload,packet.payload);
    assert.equal(await page.evaluate(()=>window.__workerMessages.some(m=>m.id===2**40+42&&!m.checkpoint)),false);
    await page.evaluate(()=>window.__directWorker.stop());
    // Main has accepted this packet's Version before authorizing its transaction.
    const reopened=await startWorker(document,{seed:'ignored seed',basisVersion:packet.version,packets:[packet]},epoch+1);
    assert.equal(reopened.info.text,'recover me!');assert.equal(reopened.info.version,packet.version);
    assert.notEqual(reopened.writer,initial.writer);assert.equal(reopened.undoReset,true);
    const retried=await send({epoch:epoch+1,id:2**40+44,document,type:'save',packet});
    assert.equal(retried.ok,true,retried.error);assert.equal(retried.result.packetId,packet.id);
    const durable=await journal(document);
    assert.equal(durable.length,1);assert.equal(durable[0].id,packet.id);assert.equal(durable[0].payload,packet.payload);
    const inspected=await send({epoch:epoch+1,id:2**40+45,document,type:'inspect'});
    assert.equal(inspected.ok,true,inspected.error);assert.equal(inspected.result.info.text,'recover me!');
    assert.equal(inspected.result.info.version,packet.version);
    return {commitObservedBeforeTermination:true,retainedPacketIdentical:true,journalRows:durable.length,text:inspected.result.info.text,versionMatchesPacket:true};
  });

  await record('large rewrite Undo preserves explicit approximate selection mapping over the wire',async()=>{
    const document=`${run}-approximate`,before='a'.repeat(5000),after='b'.repeat(5000);
    await startWorker(document,{seed:before});
    const edited=await send({epoch,id:61,document,type:'edit',command:`${document}-replace`,commandSeq:1,
      before,after,input:{full:true,inserted:after},createdAt:Date.now()});
    assert.equal(edited.ok,true,edited.error);assert.equal(edited.result.info.text,after);
    // Inspect the received array in-page: Playwright's own JSON boundary also drops expandos.
    const undone=await page.evaluate(async({epoch,document,after})=>{
      const response=await window.__directWorker.request({epoch,id:62,document,type:'history',command:`${document}-undo`,commandSeq:2,
        before:after,redo:false,createdAt:Date.now()});
      if(!response.ok)throw Error(response.error);
      const {mapChanges}=await import('./core.mjs');
      const mapped=mapChanges(after,[100,100],response.result.changes);
      return {text:response.result.info.text,mappedText:mapped.text,approximate:mapped.approximate};
    },{epoch,document,after});
    assert.equal(undone.text,before);assert.equal(undone.mappedText,before);assert.equal(undone.approximate,true);
    return {undoRestoresOriginal:true,approximate:true};
  });
}catch(error){
  results.push({passed:false,error:error.stack});console.error(error);process.exitCode=1;
}finally{
  try{if(page)await page.evaluate(()=>window.__directWorker?.stop());}catch{}
  try{
    await mkdir('evidence',{recursive:true});
    if(browser)await writeFile('evidence/worker-results.json',JSON.stringify({date:new Date().toISOString(),browser:browser.version(),headless:process.env.HEADED!=='1',workerUrl,results},null,2));
  }finally{await context?.close();await browser?.close();}
}
