import {acceptEnvelope,acceptOffer,saved} from './protocol.mjs';
import {mapChanges} from './core.mjs';
import {DB_NAME} from './store.mjs';

export class WorkerLost extends Error {}
export class Client {
 constructor(document,onFault=()=>{}){this.document=document;this.onFault=onFault;this.epoch=0;this.serial=0;this.pending=null;this.worker=null;}
 start(){this.stop();const epoch=this.epoch;this.worker=new Worker(new URL('./worker.js',import.meta.url),{type:'module'});this.worker.onmessage=e=>this.receive(e.data);this.worker.onerror=this.worker.onmessageerror=()=>{if(epoch===this.epoch)this.fail(new WorkerLost('Worker stopped; recovering retained edits'));};}
 #watch(p){clearTimeout(p.timer);p.timer=setTimeout(()=>this.fail(new WorkerLost('Worker stopped making progress')),15000);}
 receive(message){const p=this.pending;if(!acceptEnvelope(p,message))return;if(message.checkpoint){this.checkpoint=message.checkpoint;this.#watch(p);return;}clearTimeout(p.timer);this.pending=null;message.ok?p.resolve(message.result):p.reject(Error(message.error));}
 request(type,data={}){if(this.pending)throw Error('Overlapping Worker request');return new Promise((resolve,reject)=>{const p={epoch:this.epoch,id:++this.serial,document:this.document,resolve,reject};this.#watch(p);this.pending=p;this.worker.postMessage({epoch:p.epoch,id:p.id,document:p.document,type,...data});});}
 fail(error){const p=this.pending;this.pending=null;if(p){clearTimeout(p.timer);p.reject(error);}this.stop();this.onFault(error);}
 stop(){this.epoch++;if(this.pending){clearTimeout(this.pending.timer);this.pending.reject(new WorkerLost('Worker restarted'));this.pending=null;}if(this.worker){this.worker.onmessage=this.worker.onerror=this.worker.onmessageerror=null;this.worker.terminate();this.worker=null;}}
}

const sessions=new Map(),params=new URLSearchParams(location.search);
let active,element,channel,timer,disposed=false,activation=0;
const sessionId=crypto.randomUUID();
const metrics=[],longTasks=[];
const observer=new PerformanceObserver(list=>longTasks.push(...list.getEntries().map(e=>({start:e.startTime,duration:e.duration}))));observer.observe({type:'longtask',buffered:true});
function mark(kind,start,extra={}){const workMs=performance.now()-start,visibility=document.visibilityState,phase=active?.metricPhase||'functional';requestAnimationFrame(()=>requestAnimationFrame(()=>metrics.push({kind,start,phase,workMs,usableMs:performance.now()-start,visibility,...extra})));}
function label(s){return s.blocked?'Not saved — '+s.blocked:s.failure?'Not saved — '+s.failure:!s.ready?'Restoring — editor is read-only':s.composing?'Composing — not saved':saved({...s,queued:s.queue.length,packets:s.packets.length})?'Saved on this device':(s.queue.length||s.packets.length?'Saving on this device':'Saved on this device');}
function paint(){if(!active||disposed)return;const s=active;document.getElementById('status').textContent=label(s);document.getElementById('retry').disabled=!s.failure&&!s.blocked;document.getElementById('diagnostics').textContent=`${s.documentId} · ${s.count||0} operations · ${s.recoveries} recoveries${s.undoReset?' · Undo reset after Worker restart':''}`;element.readOnly=!s.ready||!!s.blocked||s.historyPending;}
function applyDom(target,result){const top=target.scrollTop,left=target.scrollLeft,direction=target.selectionDirection;for(const c of result.changes)target.setRangeText(c.inserted,c.start,c.start+c.deleted,'preserve');target.setSelectionRange(...result.selection,direction);target.scrollTop=top;target.scrollLeft=left;}
function remember(s,info){s.ackText=info.text;s.version=info.version;s.basisVersion=info.version;s.count=info.count;s.pending=info.pending;s.canUndo=info.canUndo;s.canRedo=info.canRedo;}
function current(s){return active===s&&!disposed;}
function newSession(documentId,seed){
 if(!/^[a-zA-Z0-9_-]{1,100}$/.test(documentId))throw Error('Invalid synthetic document name');
 const s={documentId,seed,ready:false,text:'',ackText:'',basisVersion:null,queue:[],packets:[],revision:0,serial:0,composing:false,editing:false,paused:false,failure:null,blocked:null,running:false,needPull:true,recoveries:0,selection:[0,0,'none',0],metrics,longTasks,ignoreNotifications:false};
 s.client=new Client(documentId,()=>{s.ready=false;s.recoveries++;paint();if(!s.running&&!disposed)queueMicrotask(()=>void pump(s));});sessions.set(documentId,s);return s;
}
async function pump(s){
 if(s.running||disposed||s.blocked)return;s.running=true;
 try{
  if(!s.ready){
   const start=performance.now();s.client.start();
   const r=await s.client.request('open',{seed:s.seed,basisVersion:s.basisVersion,packets:s.packets});
   if(s.basisVersion&&s.ackText!==r.info.text)throw Error('Recovery changed the accepted editing basis');
   remember(s,r.info);s.writer=r.writer;s.undoReset=r.undoReset;s.ready=true;s.needPull=true;
   if(!s.queue.length&&!s.composing){s.text=r.info.text;if(current(s))element.value=s.text;}
   paint();mark('open',start,{document:s.documentId,...r.timings,navigationReadyMs:performance.now()});
  }
  while(!disposed&&s.ready&&!s.blocked){
   if(s.queue.length){
    const item=s.queue[0],start=performance.now();
    const r=await s.client.request(item.type,{...item,delay:s.delayEdit||0});s.delayEdit=0;
    if(s.queue[0]!==item)throw Error('Local intent lane changed');
    // Retain immutable operations before the Worker can start their commit.
    if(r.packet)s.packets.push(r.packet);
    s.queue.shift();remember(s,r.info);
    if(item.type==='history'){
     const selection=current(s)?[element.selectionStart,element.selectionEnd]:s.selection.slice(0,2);
     const result=mapChanges(s.text,selection,r.changes);s.text=result.text;s.historyPending=false;
     s.selection=[...result.selection,...s.selection.slice(2)];if(current(s))applyDom(element,result);
    }
    s.needPull=true;paint();mark('local-accepted',start,{document:s.documentId});continue;
   }
   if(s.packets.length&&!s.paused&&!s.failure&&!s.composing){
    const packet=s.packets[0];const fault={abort:!!s.abortNext,hold:s.holdNext||0,beforeCommit:s.beforeCommit||0,crashAfterCommit:!!s.crashAfterCommit};s.abortNext=false;s.holdNext=0;s.beforeCommit=0;s.crashAfterCommit=false;
    const r=await s.client.request('save',{packet,fault});
    if(r.packetId!==packet.id||s.packets[0]!==packet)throw Error('Save acknowledgement identity mismatch');
    s.packets.shift();s.ackVersion=packet.version;s.metrics.push({kind:'save',...r.timings,document:s.documentId});
    channel.postMessage({type:'changed',document:s.documentId});s.needPull=true;paint();continue;
   }
   if(s.needPull&&!s.composing&&!s.editing&&!s.paused&&!s.packets.length){
    s.needPull=false;const start=performance.now(),generation=activation;
    const r=await s.client.request('pull',{revision:s.revision,delay:s.delayPull||0});s.delayPull=0;
    if(r.offer){
     const allowed=generation===activation&&acceptOffer({revision:s.revision,composing:s.composing,editing:s.editing,queued:s.queue.length,text:s.text},r.offer);
     if(!allowed){s.needPull=true;if(s.composing||s.editing)break;continue;}
     const selected=current(s)?[element.selectionStart,element.selectionEnd]:s.selection.slice(0,2);
     const result=mapChanges(s.text,selected,r.offer.changes);
     if(result.text!==r.offer.info.text)throw Error('Remote projection mismatch');
     s.text=result.text;remember(s,r.offer.info);
     s.selection=[...result.selection,...s.selection.slice(2)];
     if(current(s)){applyDom(element,result);if(result.approximate)document.getElementById('alignment').textContent='Snapshot selection alignment is approximate; stable CRDT anchors are unavailable.';}
     // FIFO sends this acknowledgement before any later native input command.
     await s.client.request('project',{token:r.offer.token});
     mark('remote-apply',start,{document:s.documentId});paint();
    }
    continue;
   }
   break;
  }
 }catch(error){
  if(s.queue[0]?.type==='history'){
   s.uncertainHistory=true;s.historyPending=false;s.ready=false;
   s.blocked='Undo/Redo interrupted before acknowledgement. The request and accepted text are retained; editing is blocked. Retry does not cancel it. Use Cancel interrupted Undo/Redo only to deliberately abandon this request and restore accepted text.';
   s.failure=s.blocked;
  }
  else if(error instanceof WorkerLost){s.ready=false;s.failure=null;if(s.recoveries>3)s.failure='Worker repeatedly failed. Retry keeps the draft.';}
  else{s.failure=String(error.message||error);if(!s.packets.length||s.queue.length)s.blocked=s.failure;}
 }finally{s.running=false;paint();if(!disposed&&!s.ready&&!s.failure)queueMicrotask(()=>void pump(s));}
}
// Binding acceptance already happened. Readonly blocks new input, not the
// terminal event of an input begun before failure; retain it on its old basis.
function onChange(change){const s=active;if(!s.basisVersion)return;const start=performance.now();const before=s.text,after=element.value;s.text=after;s.revision++;s.queue.push({type:'edit',command:`${sessionId}:${s.documentId}:${++s.serial}`,commandSeq:s.serial,input:change,before,after,createdAt:performance.timeOrigin+(s.inputStarted||start)});paint();mark('local-input',s.inputStarted||start,{document:s.documentId});void pump(s);}
function onComposing(value){const s=active;s.composing=value;if(!value){s.editing=false;s.needPull=true;void pump(s);}paint();}
function history(redo){const s=active;if(!s.ready||s.composing||s.editing||s.queue.length||s.historyPending||s.blocked)return;s.revision++;s.historyPending=true;s.queue.push({type:'history',command:`${sessionId}:${s.documentId}:${++s.serial}`,commandSeq:s.serial,before:s.text,redo,createdAt:Date.now()});paint();void pump(s);}
function switchDocument(id,seed='# Synthetic document\n'){if(active?.composing)return false;if(active){active.selection=[element.selectionStart,element.selectionEnd,element.selectionDirection,element.scrollTop];}activation++;active=sessions.get(id)||newSession(id,seed);element.value=active.text;element.setSelectionRange(...active.selection.slice(0,3));element.scrollTop=active.selection[3];paint();void pump(active);return true;}
function retry(){const s=active;if(s.uncertainHistory){paint();return;}s.failure=null;if(s.blocked){s.blocked=null;s.ready=false;}paint();void pump(s);}
function cancelInterruptedHistory(){const s=active;if(!s.uncertainHistory)return;
 if(!confirm('Cancel the interrupted Undo/Redo request? Its result was not accepted or authorized for saving. This explicitly abandons that request and restores the previously accepted text.'))return;
 s.queue.shift();s.uncertainHistory=false;s.historyPending=false;s.blocked=null;s.failure=null;s.ready=false;paint();void pump(s);
}
function mount(target){
 element=target;disposed=false;element.spellcheck=false;
 channel=new BroadcastChannel(DB_NAME);channel.onmessage=e=>{const s=sessions.get(e.data?.document);if(s&&!s.ignoreNotifications){s.needPull=true;void pump(s);}};
 const controller=new AbortController();globalThis.localTabs.controller=controller;
 const listen=(target,name,fn,capture=false)=>target.addEventListener(name,fn,{capture,signal:controller.signal});
 listen(element,'beforeinput',event=>{const s=active;if(event.inputType==='historyUndo'||event.inputType==='historyRedo'){event.preventDefault();event.stopImmediatePropagation();history(event.inputType==='historyRedo');return;}s.editing=true;s.inputStarted=performance.now();queueMicrotask(()=>{if(event.defaultPrevented){s.editing=false;void pump(s);}});},true);
 listen(element,'input',()=>{const s=active;queueMicrotask(()=>{s.editing=false;s.needPull=true;void pump(s);});},true);
 listen(element,'compositionstart',()=>{active.composing=true;paint();},true);
 listen(element,'keydown',event=>{if((event.ctrlKey||event.metaKey)&&!event.altKey&&['z','y'].includes(event.key.toLowerCase())){event.preventDefault();event.stopImmediatePropagation();history(event.shiftKey||event.key.toLowerCase()==='y');}},true);
 listen(window,'beforeunload',event=>{if([...sessions.values()].some(s=>s.queue.length||s.packets.length||s.composing||s.blocked)){event.preventDefault();event.returnValue='';}});
 for(const event of ['focus','pageshow'])listen(window,event,()=>{for(const s of sessions.values()){s.needPull=true;void pump(s);}});
 listen(document,'visibilitychange',()=>{for(const s of sessions.values()){s.needPull=true;void pump(s);}});
 timer=setInterval(()=>{for(const s of sessions.values()){s.needPull=true;void pump(s);}},750);
 document.getElementById('undo').onclick=()=>history(false);document.getElementById('redo').onclick=()=>history(true);document.getElementById('retry').onclick=retry;
 let cancel=document.getElementById('cancel-interrupted-history');
 if(!cancel){cancel=document.createElement('button');cancel.id='cancel-interrupted-history';cancel.textContent='Cancel interrupted Undo/Redo';document.getElementById('retry').after(cancel);}
 cancel.onclick=cancelInterruptedHistory;
 document.getElementById('export').onclick=()=>{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([element.value],{type:'text/markdown'}));a.download=active.documentId+'-draft.md';a.click();URL.revokeObjectURL(a.href);};
 document.getElementById('switch').onclick=()=>switchDocument(document.getElementById('document-name').value);
 const size=Number(params.get('size')||0);if(![0,10000,100000].includes(size))throw Error('Unsupported synthetic fixture size');
 switchDocument(params.get('doc')||'synthetic-demo',size?'0123456789'.repeat(size/10):(params.get('seed')||'# Shared synthetic note\n\nalpha beta gamma\n'));
}
// The disposed element cannot finish its native input; accepted intents stay queued.
function dispose(){disposed=true;activation++;clearInterval(timer);channel?.close();localTabs.controller?.abort();observer.disconnect();for(const s of sessions.values()){s.composing=false;s.editing=false;s.ready=false;s.client.stop();}}
globalThis.localTabs={mount,onChange,onComposing,dispose};
// Explicit experiment only. Deterministic fault hooks never ship in normal mode.
async function diagnostic(s,type){
 while(s.running)await new Promise(r=>setTimeout(r,10));
 s.running=true;
 try{return await s.client.request(type);}
 finally{s.running=false;void pump(s);}
}
globalThis.trial={get state(){return active;},history,switchDocument,retry,metrics,longTasks,
 pause(value){active.paused=value;active.needPull=true;if(!value)void pump(active);},
 catchUp(){active.needPull=true;return pump(active);},flush(){return pump(active);},
 notify(){channel.postMessage({type:'changed',document:active.documentId});},
 crash(){active.client.fail(new WorkerLost('Injected Worker failure'));active.ready=false;void pump(active);},
 async inspect(){return (await diagnostic(active,'inspect')).info;},
 test(type){return diagnostic(active,type);},
 durable(){return diagnostic(active,'durable');},
};
