import {boundedPacket,knowledge,contains,extend,requireClosure,key,MAX_JOURNAL_OPS} from './core.mjs';

export const DB_NAME='loomark-egw-worker-experiment-v1';
const request = req => new Promise((resolve,reject)=>{req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);});
const complete = tx => new Promise((resolve,reject)=>{tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error||Error('Injected transaction abort'));tx.onerror=()=>{};});

export async function openStore() {
  const req=indexedDB.open(DB_NAME,1);
  req.onupgradeneeded=()=>{
    const db=req.result;
    db.createObjectStore('seeds');
    db.createObjectStore('documents');
    db.createObjectStore('operations');
    db.createObjectStore('journal',{autoIncrement:true}).createIndex('document','document');
    db.createObjectStore('receipts');
  };
  return request(req);
}
export async function readSeed(db,document) {
  const tx=db.transaction('seeds'); const done=complete(tx);
  const value=await request(tx.objectStore('seeds').get(document)); await done; return value;
}
// Concurrent initializers serialize here. Only the winning seed is authoritative.
export async function initialize(db,document,candidate) {
  const tx=db.transaction(['seeds','documents'],'readwrite'); const done=complete(tx);
  const store=tx.objectStore('seeds');
  let seed=await request(store.get(document));
  if(!seed) {
    seed=candidate;
    store.add(seed,document);
    tx.objectStore('documents').add({known:knowledge(candidate.version),seedKnown:knowledge(candidate.version),journalOps:0},document);
  }
  await done; return seed;
}
export async function readJournal(db,document,after) {
  const tx=db.transaction('journal'); const done=complete(tx);
  const rows=[];
  await new Promise((resolve,reject)=>{
    const req=tx.objectStore('journal').openCursor(IDBKeyRange.lowerBound(after,true));
    req.onerror=()=>reject(req.error);
    req.onsuccess=()=>{const c=req.result;if(!c)return resolve();if(c.value.document===document)rows.push({...c.value,cursor:c.primaryKey});c.continue();};
  });
  await done; return rows;
}
// EGW validates the entire payload before this call. This transaction enforces
// append-only identity, durable closure and the resource policy against races.
export async function append(db,document,packet,{abort=false,hold=0,beforeCommit=0,checkpoint=()=>{}}={}) {
  const started=performance.now();let requestMs=null;
  const decoded=boundedPacket(packet.payload);
  const tx=db.transaction(['documents','operations','journal','receipts'],'readwrite');
  const done=complete(tx); done.catch(()=>{});
  try {
    const docs=tx.objectStore('documents'), ops=tx.objectStore('operations'), receipts=tx.objectStore('receipts');
    const receiptKey=[document,packet.id];
    const receipt=await request(receipts.get(receiptKey));
    if(receipt) {
      if(receipt!==packet.payload) throw Error('Packet identity conflict');
      await done; return {requestMs:performance.now()-started,commitMs:performance.now()-started,retryDuplicate:true};
    }
    const meta=await request(docs.get(document));
    requireClosure(meta.known,decoded.operations);
    const existing=await Promise.all(decoded.operations.map(op=>request(ops.get([document,key(op.id)]))));
    const fresh=[];
    decoded.operations.forEach((op,i)=>{
      const encoded=JSON.stringify(op);
      if(existing[i]!==undefined) {if(existing[i]!==encoded)throw Error('Immutable operation conflict');}
      else {
        if(contains(meta.seedKnown,op.id))throw Error('Seed identity collision');
        fresh.push(op);ops.add(encoded,[document,key(op.id)]);
      }
    });
    if(meta.journalOps+fresh.length>MAX_JOURNAL_OPS)throw Error('Trial journal capacity reached; no history discarded');
    docs.put({...meta,known:extend(meta.known,fresh),journalOps:meta.journalOps+fresh.length},document);
    const journalRequest=tx.objectStore('journal').add({...packet,document});
    journalRequest.onsuccess=()=>{requestMs=performance.now()-started;};
    receipts.add(packet.payload,receiptKey);
    if(abort)tx.abort();
    if(beforeCommit){checkpoint();const until=performance.now()+beforeCommit;while(performance.now()<until)await request(receipts.get(receiptKey));}
    await done;
    const commitMs=performance.now()-started;
    if(hold)await new Promise(r=>setTimeout(r,hold)); // test delayed acknowledgment, after actual commit
    return {requestMs,commitMs,operations:fresh.length};
  } catch(error) {try{tx.abort();}catch{} await done.catch(()=>{});throw error;}
}
