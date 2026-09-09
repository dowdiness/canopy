///|
#external
priv type WorkerClient

///|
extern "js" fn new_worker_client() -> WorkerClient =
  #| () => ({worker:null, epoch:0, pending:null, timer:null, busy:false, codeURL:null, disposed:false})

///|
extern "js" fn stop_worker_client(c : WorkerClient) -> Unit =
  #| c => {
  #|   c.epoch++; clearTimeout(c.timer); c.timer=null; c.pending=null; c.busy=false;
  #|   if(c.worker){c.worker.onmessage=null;c.worker.onerror=null;c.worker.onmessageerror=null;c.worker.terminate();c.worker=null;}
  #| }

///|
extern "js" fn dispose_worker_client(c : WorkerClient) -> Unit =
  #| c => {
  #|   if(c.disposed)return;
  #|   c.disposed=true; c.epoch++; clearTimeout(c.timer);c.timer=null;c.pending=null;c.busy=false;
  #|   if(c.worker){c.worker.onmessage=null;c.worker.onerror=null;c.worker.onmessageerror=null;c.worker.terminate();c.worker=null;}
  #|   if(c.codeURL){URL.revokeObjectURL(c.codeURL);c.codeURL=null;}
  #| }

///|
extern "js" fn preview_worker_request(
  c : WorkerClient,
  generation : Int,
  sequence : Int,
  source : String,
  edit : String,
  callback : (String) -> Unit,
) -> Unit =
  #| (c,generation,sequence,source,edit,callback) => {
  #|   if(c.disposed)return;
  #|   if(c.busy || c.pending!==null) throw Error("overlapping preview request");
  #|   const epoch=c.epoch;
  #|   let finished=false;
  #|   const fail=()=>{
  #|     if(epoch!==c.epoch || finished)return;
  #|     finished=true; clearTimeout(c.timer);c.timer=null;c.busy=false;c.pending=null;
  #|     if(c.worker){c.worker.onmessage=null;c.worker.onerror=null;c.worker.onmessageerror=null;c.worker.terminate();c.worker=null;}
  #|     c.epoch++;
  #|     callback(JSON.stringify({type:"error",generation,sequence}));
  #|   };
  #|   try{
  #|     if(!c.codeURL){
  #|       const element=document.getElementById("loomark-preview-worker-payload");
  #|       if(!element || typeof element.textContent!=="string") throw Error("missing Preview Worker payload");
  #|       const payload=JSON.parse(element.textContent);
  #|       if(!payload || typeof payload.version!=="string" || !payload.version || typeof payload.code!=="string" || !payload.code) throw Error("corrupt Preview Worker payload");
  #|       c.codeURL=URL.createObjectURL(new Blob([payload.code],{type:"text/javascript"}));
  #|     }
  #|     c.worker ??= new Worker(c.codeURL,{type:"classic"});
  #|     c.busy=true;
  #|     c.worker.onerror=fail;c.worker.onmessageerror=fail;
  #|     c.worker.onmessage=e=>{
  #|       if(epoch!==c.epoch || finished)return;
  #|       try{
  #|         if(typeof e.data!=="string" || e.data.length>16777216){fail();return;}
  #|         const v=JSON.parse(e.data);
  #|         if(v.type==="ack")return;
  #|         if(v.type==="preview" && Number.isInteger(v.sequence) && v.sequence<sequence)return;
  #|         if(v.type!=="preview" || v.generation!==generation || v.sequence!==sequence){fail();return;}
  #|         finished=true;clearTimeout(c.timer);c.timer=null;c.busy=false;
  #|         c.pending={generation,sequence};callback(e.data);
  #|       }catch(_){fail();}
  #|     };
  #|     c.timer=setTimeout(fail,10000);
  #|     c.worker.postMessage(JSON.stringify({type:"preview",generation,sequence,source,edit:JSON.parse(edit)}));
  #|   }catch(_){fail();}
  #| }

///|
extern "js" fn preview_worker_ack(c : WorkerClient, accepted : Bool) -> Unit =
  #| (c,accepted)=>{
  #|   if(c.disposed || c.pending===null)return;
  #|   const p=c.pending;c.pending=null;
  #|   try{c.worker.postMessage(JSON.stringify({type:"ack",generation:p.generation,sequence:p.sequence,accepted}));}
  #|   catch(_){c.worker?.terminate();c.worker=null;c.epoch++;}
  #| }

///|
fn worker_edit_json(change : @text_change.TextChange?) -> String {
  match change {
    Some(@text_change.ReplaceRange(start~, delete_len~, inserted~)) =>
      Json::object({
        "start": Json::number(start.to_double()),
        "delete_len": Json::number(delete_len.to_double()),
        "inserted": Json::string(inserted),
      }).stringify()
    _ => "null"
  }
}
