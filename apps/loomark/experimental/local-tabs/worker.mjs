import './egw.js';
import {scalarAt,snapshotChanges,boundedPacket,knowledge,contains,MAX_OPS} from './core.mjs';
import {openStore,readSeed,initialize,readJournal,append} from './store.mjs';

let documentId,db,editor,merged,cursor=0,offer=null,offerSequence=0,historyRows=[];
let lastCommand=null,lastSequence=0;
const info=()=>egw.inspect(editor);
function admit(handle,payload){boundedPacket(payload);const t=egw.apply(handle,payload);if(t.pending)throw Error('Durable operation union is not causally closed');return t;}
async function open(request){
 documentId=request.document;db=await openStore();let seed=await readSeed(db,documentId);
 const timings={},start=performance.now();
 if(!seed){
  const text=request.seed;if(!text.isWellFormed()||[...text].length>100000)throw Error('Invalid or oversized synthetic seed');
  const h=egw.create('seed-'+crypto.randomUUID(),'','').handle;
  const state=egw.replace(h,0,0,text,true);
  seed=await initialize(db,documentId,{archive:egw.archive(h).archive,version:state.version});
 }
 timings.seedMs=performance.now()-start;let t=performance.now();
 const writer=crypto.randomUUID();
 editor=egw.create(writer,seed.archive,seed.version).handle;
 merged=egw.create(crypto.randomUUID(),seed.archive,seed.version).handle;
 timings.restoreMs=performance.now()-t;t=performance.now();
 const rows=await readJournal(db,documentId,0);
 historyRows=rows;
 const basis=request.basisVersion?knowledge(request.basisVersion):null;
 // Select whole previously validated journal packets, never slice messages to
 // dodge admission limits. Every selected packet is re-admitted by real EGW.
 for(const row of rows){
  admit(merged,row.payload);
  if(!basis||boundedPacket(row.payload).operations.every(op=>contains(basis,op.id)))admit(editor,row.payload);
  cursor=row.cursor;
 }
 for(const packet of request.packets||[]){admit(editor,packet.payload);admit(merged,packet.payload);}
 const state=info();
 if(request.basisVersion&&state.version!==request.basisVersion)throw Error('Recovery basis unavailable; retained draft was not overwritten');
 timings.replayMs=performance.now()-t;
 return {info:state,timings,writer,undoReset:!!request.basisVersion};
}
async function execute(r){
 if(r.type==='open')return open(r);
 if(r.document!==documentId)throw Error('Wrong document');
 if(r.type==='edit'||r.type==='history'){
  const input=JSON.stringify([r.type,r.before,r.input,r.redo]);
  if(r.commandSeq<=lastSequence){if(lastCommand?.id!==r.command||lastCommand.input!==input)throw Error('Stale or conflicting command');return lastCommand.result;}
  if(!Number.isSafeInteger(r.commandSeq)||r.commandSeq<1)throw Error('Invalid command sequence');
  const before=info();
  if(before.text!==r.before)throw Error('Edit basis mismatch; draft retained');
  offer=null;
  if(r.type==='history')egw.history(editor,r.redo);
  else{
   const changes=r.input.full?snapshotChanges(before.text,r.input.inserted):[r.input];
   let text=before.text;
   const cost=changes.reduce((n,c)=>n+[...c.inserted].length+[...text.slice(c.start,c.start+c.deleted)].length,0);
   if(cost>MAX_OPS)throw Error('Input exceeds per-packet operation limit; draft retained');
   // A native intent, not each diff hunk, starts the next Undo group.
   for(let i=0;i<changes.length;i++){const c=changes[i];if(!c.inserted.isWellFormed())throw Error('Malformed UTF-16');const a=scalarAt(text,c.start),b=scalarAt(text,c.start+c.deleted);text=egw.replace(editor,a,b,c.inserted,i===0).text;}
   if(text!==r.after)throw Error('Native TextChange result mismatch');
  }
  const after=info(),payload=egw.delta(editor,before.version).payload;
  admit(editor,payload);admit(merged,payload);
  const packet=boundedPacket(payload).operations.length?{id:r.command,payload,version:after.version,createdAt:r.createdAt}:null;
  const result={info:after,packet,changes:r.type==='history'?snapshotChanges(before.text,after.text):[]};
  lastSequence=r.commandSeq;lastCommand={id:r.command,input,result};return result;
 }
 if(r.type==='save'){
  // Main must retain this immutable packet before authorizing its transaction.
  admit(merged,r.packet.payload);
  const timings=await append(db,documentId,r.packet,{...r.fault,checkpoint:()=>self.postMessage({epoch:r.epoch,id:r.id,document:r.document,checkpoint:'before-commit'})});
  if(r.fault?.crashAfterCommit){self.close();return new Promise(()=>{});}
  return {packetId:r.packet.id,timings};
 }
 if(r.type==='pull'){
  const rows=await readJournal(db,documentId,cursor);
  historyRows.push(...rows);
  for(const row of rows){admit(merged,row.payload);cursor=row.cursor;}
  const before=info(),after=egw.inspect(merged);
  if(before.version===after.version)return {offer:null};
  const known=knowledge(before.version);
  const payloads=historyRows.filter(row=>boundedPacket(row.payload).operations.some(op=>!contains(known,op.id))).map(row=>row.payload);
  offer={token:++offerSequence,payloads,before:before.text,info:after,revision:r.revision,changes:snapshotChanges(before.text,after.text)};
  return {offer:{...offer,payloads:undefined}};
 }
 if(r.type==='project'){
  if(!offer||offer.token!==r.token)throw Error('Stale projection acknowledgement');
  for(const payload of offer.payloads)admit(editor,payload);const state=info();
  if(state.version!==offer.info.version||state.text!==offer.info.text)throw Error('Projection acknowledgement mismatch');
  offer=null;return {info:state};
 }
 if(r.type==='inspect')return {info:info(),merged:egw.inspect(merged)};
 if(r.type==='durable')return {seed:await readSeed(db,documentId),journal:await readJournal(db,documentId,0)};
 if(r.type==='inject'){return {transition:admit(merged,r.payload)};}
 if(r.type==='test-replay'){
  const seed=await readSeed(db,documentId),journal=await readJournal(db,documentId,0),h=egw.create(crypto.randomUUID(),seed.archive,seed.version).handle,pending=[];
  for(const row of [...journal].reverse())pending.push(egw.apply(h,row.payload).pending);
  for(const row of journal)egw.apply(h,row.payload);
  return {info:egw.inspect(h),pending};
 }
 if(r.type==='test-admission'){
  const before=info(),errors=[],h=egw.create(crypto.randomUUID(),'','').handle,empty=egw.inspect(h).version;
  egw.replace(h,0,0,'X',true);const oversized=JSON.parse(egw.delta(h,empty).payload);oversized.operations=Array(100001).fill(oversized.operations[0]);
  for(const payload of ['{}','{"schema":1,"operations":[]}',JSON.stringify(oversized)])try{egw.apply(editor,payload);}catch(e){errors.push(e.message);}
  return {before,after:info(),errors};
 }
 throw Error('Unknown Worker request');
}
// Strict FIFO: no latest-only dropping. Duplicate command IDs return their
// original operations; persistence receipts deduplicate repeated saves.
let lane=Promise.resolve();
self.onmessage=event=>{
 const r=event.data;
 lane=lane.then(async()=>{
  if(!r||!Number.isSafeInteger(r.id)||!Number.isSafeInteger(r.epoch))throw Error('Invalid request envelope');
  try{const result=await execute(r);if(r.delay)await new Promise(resolve=>setTimeout(resolve,r.delay));self.postMessage({epoch:r.epoch,id:r.id,document:r.document,ok:true,result});}
  catch(error){self.postMessage({epoch:r.epoch,id:r.id,document:r.document,ok:false,error:String(error.message||error)});}
 }).catch(error=>{throw error;});
};
