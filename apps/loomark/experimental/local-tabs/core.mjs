import { diffChars } from './node_modules/diff/libesm/diff/character.js';

export const MAX_BYTES = 16 * 1024 * 1024;
export const MAX_OPS = 100000;
export const MAX_JOURNAL_OPS = 200000; // trial admission budget; no eviction
export const key = id => JSON.stringify([id.replica_id, id.sequence]);

export function scalarAt(text, utf16) {
  if (!Number.isInteger(utf16) || utf16 < 0 || utf16 > text.length) throw Error('Invalid UTF-16 offset');
  if (utf16 && utf16 < text.length && /[\uD800-\uDBFF]/u.test(text[utf16-1]) && /[\uDC00-\uDFFF]/u.test(text[utf16])) throw Error('Offset splits a Unicode scalar');
  return [...text.slice(0, utf16)].length;
}
export function utf16At(text, scalar) {
  let offset = 0, count = 0;
  for (const ch of text) {
    if (count === scalar) return offset;
    count++; offset += ch.length;
  }
  if (count === scalar) return offset;
  throw Error('Invalid scalar offset');
}
export function mapPoint(point, start, deleted, inserted) {
  if (point < start) return point;
  if (point > start + deleted) return point + inserted - deleted;
  return start + inserted; // right affinity, also for collapsed carets
}
export function project(text, selection, effects) {
  let [start, end] = selection;
  const changes = [];
  for (const e of coalesceEffects(effects)) {
    const a = utf16At(text, e.start);
    const b = e.kind === 'delete' ? utf16At(text, e.end) : a;
    const inserted = e.kind === 'insert' ? e.text : '';
    start = mapPoint(start, a, b-a, inserted.length);
    end = mapPoint(end, a, b-a, inserted.length);
    text = text.slice(0,a) + inserted + text.slice(b);
    changes.push({start:a, deleted:b-a, inserted});
  }
  return {text, selection:[start,end], changes};
}
// EGW effects are sequential. Adjacent scalar inserts and repeated deletes at
// one position can be combined without changing text or right-affinity mapping.
export function coalesceEffects(effects) {
  const output=[];
  for(const e of effects){
    const tail=output.at(-1);
    if(tail?.kind==='insert'&&e.kind==='insert'&&e.start===tail.start+tail.scalars){tail.text+=e.text;tail.scalars+=[...e.text].length;}
    else if(tail?.kind==='delete'&&e.kind==='delete'&&e.start===tail.start){tail.end+=e.end-e.start;}
    else output.push({...e,...(e.kind==='insert'?{scalars:[...e.text].length}:{})});
  }
  return output;
}
// Snapshot fallback is a text alignment, never claimed to be CRDT provenance.
// Bound its work. Large rewrites keep canonical text but explicitly degrade
// selection mapping to the containing replacement, never an invented anchor.
export function snapshotChanges(before, after) {
  if(before===after)return [];
  // Large pure paste/delete needs no quadratic alignment and is unambiguous.
  let prefix=0;
  while(prefix<before.length&&prefix<after.length&&before[prefix]===after[prefix])prefix++;
  if(prefix && /[\uD800-\uDBFF]/u.test(before[prefix-1]))prefix--;
  let suffix=0;
  while(suffix<before.length-prefix&&suffix<after.length-prefix&&before[before.length-1-suffix]===after[after.length-1-suffix])suffix++;
  if(suffix && /[\uDC00-\uDFFF]/u.test(before[before.length-suffix]))suffix--;
  const deleted=before.length-prefix-suffix,inserted=after.slice(prefix,after.length-suffix);
  if(!deleted||!inserted.length)return [{start:prefix,deleted,inserted}];
  const parts = diffChars(before, after, {maxEditLength:4096, timeout:100});
  if (!parts) {
    const changes=[{start:prefix,deleted,inserted}];
    changes.approximate=true;
    return changes;
  }
  let pos = 0;
  const changes=[];
  for (const p of parts) {
    if (p.removed) changes.push({start:pos, deleted:p.value.length, inserted:''});
    else if (p.added) { changes.push({start:pos, deleted:0, inserted:p.value}); pos += p.value.length; }
    else pos += p.value.length;
  }
  return changes;
}
export function mapChanges(text, selection, changes) {
  let [a,b]=selection;
  for(const c of changes) {
    a=mapPoint(a,c.start,c.deleted,c.inserted.length);
    b=mapPoint(b,c.start,c.deleted,c.inserted.length);
    text=text.slice(0,c.start)+c.inserted+text.slice(c.start+c.deleted);
  }
  return {text,selection:[a,b],changes,approximate:!!changes.approximate};
}
export function boundedPacket(payload) {
  if(typeof payload !== 'string' || payload.length > MAX_BYTES || new TextEncoder().encode(payload).length > MAX_BYTES) throw Error('Whole packet exceeds encoded limit');
  const packet=JSON.parse(payload);
  if(!Array.isArray(packet.operations) || packet.operations.length > MAX_OPS) throw Error('Whole packet exceeds operation limit');
  return packet; // structural/schema admission remains EGW-owned
}
export function knowledge(version) {
  return Object.fromEntries(JSON.parse(version).ranges.map(r=>[r.replica_id,r.ranges]));
}
export function contains(known,id) {
  return (known[id.replica_id]||[]).some(r=>id.sequence >= r.start && id.sequence < r.end);
}
export function extend(known,operations) {
  const next=structuredClone(known);
  for(const op of operations) {
    const list=next[op.id.replica_id] ||= [];
    list.push({start:op.id.sequence,end:op.id.sequence+1});
  }
  for(const actor of Object.keys(next)) {
    const merged=[];
    for(const r of next[actor].sort((a,b)=>a.start-b.start)) {
      const tail=merged.at(-1);
      if(tail && r.start <= tail.end) tail.end=Math.max(tail.end,r.end);
      else merged.push({...r});
    }
    next[actor]=merged;
  }
  if(Object.values(next).reduce((n,r)=>n+r.length,0)>4096) throw Error('Version global interval budget reached; no history discarded');
  if(new TextEncoder().encode(JSON.stringify(next)).length>500*1024) throw Error('Version budget reached; no history discarded');
  return next;
}
export function requireClosure(known, operations) {
  const incoming = new Set(operations.map(o=>key(o.id)));
  for(const op of operations) for(const dep of [...op.parents,op.origin_left,op.origin_right].filter(Boolean)) {
    if(!contains(known,dep) && !incoming.has(key(dep))) throw Error('Missing durable dependency');
  }
}
export function savedLabel({failure,blocked,composing,queue,busy}) {
  if(blocked) return 'Unsaved draft — '+blocked;
  if(failure) return `Save failed — ${failure}. Draft retained; Retry.`;
  if(composing) return 'Composing — not saved';
  if(queue || busy) return 'Saving…';
  return 'Saved locally';
}
