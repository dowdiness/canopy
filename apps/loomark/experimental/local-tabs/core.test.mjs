import {test} from 'node:test';
import assert from 'node:assert/strict';
import {scalarAt,utf16At,project,snapshotChanges,mapChanges,requireClosure,extend,contains,savedLabel,boundedPacket} from './core.mjs';
test('UTF-16/scalar conversion rejects split emoji',()=>{
  assert.equal(scalarAt('a😀日',3),2);assert.equal(utf16At('a😀日',2),3);
  assert.throws(()=>scalarAt('a😀日',2));
});
test('sequential exact effects retain distant selection with emoji',()=>{
  const r=project('a😀bcdef',[5,7],[{kind:'insert',start:0,text:'日'},{kind:'delete',start:3,end:4}]);
  assert.equal(r.text,'日a😀cdef');assert.deepEqual(r.selection,[5,7]);
});
test('snapshot alignment keeps middle selection for distant changes',()=>{
  const a='aaaa LEFT middle RIGHT zzzz',b='aaaa XLEFT middle RIGHTY zzzz';
  const r=mapChanges(a,[10,16],snapshotChanges(a,b));
  assert.equal(r.text,b);assert.deepEqual(r.selection,[11,17]);
});
test('durable closure rejects absent parent; union is immutable',()=>{
  const id={replica_id:'a',sequence:0};const known={a:[{start:0,end:1}]};
  const op={id:{replica_id:'b',sequence:0},parents:[id],origin_left:id,origin_right:null};
  requireClosure(known,[op]);assert.throws(()=>requireClosure({},[op]));
  const next=extend(known,[op]);assert.ok(contains(next,op.id));assert.equal(known.b,undefined);
});
test('failure and later queued edits cannot be called saved',()=>{
  assert.match(savedLabel({failure:true}),/failed/);assert.equal(savedLabel({queue:1}),'Saving…');
  assert.throws(()=>boundedPacket(JSON.stringify({operations:Array(100001).fill(null)})));
});
test('large paste undo is linear; large rewrite fallback is explicit',()=>{
  assert.deepEqual(snapshotChanges('x'.repeat(5000),''),[{start:0,deleted:5000,inserted:''}]);
  const changes=snapshotChanges('x'.repeat(5000),'y'.repeat(5000));
  assert.equal(changes.approximate,true);
  assert.equal(mapChanges('x'.repeat(5000),[20,20],changes).text,'y'.repeat(5000));
});
test('coalesced exact effects preserve Unicode and sequential selection',()=>{
  const result=project('abc',[2,2],[{kind:'insert',start:1,text:'😀'},{kind:'insert',start:2,text:'日'},{kind:'delete',start:3,end:4},{kind:'delete',start:3,end:4}]);
  assert.equal(result.text,'a😀日');assert.deepEqual(result.selection,[4,4]);assert.equal(result.changes.length,2);
});
test('coalesced vs original effects agree at every caret/range including same-position inserts',()=>{
  const source='a😀b日c';
  const cases=[
    [{kind:'insert',start:1,text:'X'},{kind:'insert',start:1,text:'Y'}],
    [{kind:'insert',start:1,text:'X'},{kind:'insert',start:2,text:'😀'}],
    [{kind:'delete',start:1,end:2},{kind:'delete',start:1,end:3}],
    [{kind:'delete',start:1,end:3},{kind:'insert',start:1,text:'🌱'},{kind:'insert',start:2,text:'語'}],
  ];
  for(const effects of cases)for(let a=0;a<=source.length;a++)for(let b=a;b<=source.length;b++){
    let text=source,selection=[a,b];
    for(const e of effects){
      const chars=[...text];const start=chars.slice(0,e.start).join('').length;
      const end=chars.slice(0,e.kind==='delete'?e.end:e.start).join('').length;
      const inserted=e.kind==='insert'?e.text:'';
      selection=selection.map(p=>p<start?p:p>end?p+inserted.length-(end-start):start+inserted.length);
      text=text.slice(0,start)+inserted+text.slice(end);
    }
    const actual=project(source,[a,b],effects);assert.equal(actual.text,text);assert.deepEqual(actual.selection,selection);
  }
  assert.equal(project('abc',[1,1],cases[0]).text,'aYXbc');
});
