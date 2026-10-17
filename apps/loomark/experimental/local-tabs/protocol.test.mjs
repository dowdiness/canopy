import test from 'node:test';
import assert from 'node:assert/strict';
import {acceptOffer,acceptEnvelope,saved} from './protocol.mjs';
test('old epoch, request and document cannot mutate the current document',()=>{
 const pending={epoch:2,id:9,document:'B'};
 for(const r of [{epoch:1,id:9,document:'B'},{epoch:2,id:8,document:'B'},{epoch:2,id:9,document:'A'}])assert.equal(acceptEnvelope(pending,r),false);
 assert.equal(acceptEnvelope(pending,pending),true);
});
test('a generation match cannot overwrite optimistic input or composition',()=>{
 const state={revision:4,composing:false,editing:false,queued:0,text:'old'};
 const offer={revision:4,before:'old'};
 assert.equal(acceptOffer(state,offer),true);
 for(const changed of [{revision:5},{composing:true},{editing:true},{queued:1},{text:'new'}])assert.equal(acceptOffer({...state,...changed},offer),false);
});
test('commit R does not mark R+1 saved',()=>{
 const state={ready:true,queued:1,packets:0,failure:null,blocked:null,composing:false};
 assert.equal(saved(state),false);assert.equal(saved({...state,queued:0}),true);
 assert.equal(saved({...state,queued:0,packets:1}),false);
});
