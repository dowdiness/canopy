import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {gzipSync,brotliCompressSync,constants} from 'node:zlib';
import assert from 'node:assert/strict';
import {join} from 'node:path';
const [before,after,out]=process.argv.slice(2);
const sha=b=>createHash('sha256').update(b).digest('hex');
const metrics=b=>({sha256:sha(b),raw:b.length,gzip9:gzipSync(b,{level:9}).length,brotli11:brotliCompressSync(b,{params:{[constants.BROTLI_PARAM_QUALITY]:11}}).length});
const pattern=/<script type="application\/json" id="loomark-preview-worker-payload">([\s\S]*?)<\/script>/g;
for(const dir of [before,after]){
 const html=readFileSync(join(dir,'index.html'),'utf8');const matches=[...html.matchAll(pattern)];assert.equal(matches.length,1);assert(!matches[0][1].includes('<'));
 const payload=JSON.parse(matches[0][1]);const worker=readFileSync(join(dir,'preview-worker.js'));
 assert.equal(payload.code,worker.toString('utf8'));assert.equal(payload.version,sha(worker));
}
assert.equal(readFileSync(join(before,'index.js'),'utf8'),readFileSync(join(after,'index.js'),'utf8'));
assert.equal(readFileSync(join(before,'index.html'),'utf8').replace(pattern,'PAYLOAD'),readFileSync(join(after,'index.html'),'utf8').replace(pattern,'PAYLOAD'));
const result={node:process.version,terser:'5.51.2',options:['-c','toplevel=true','-m','toplevel=true'],compression:'Offline encoded-size estimates: gzip level9, Brotli quality11; no server compression changed or network transfer measured.',files:{}};
for(const name of ['preview-worker.js','index.html']){
 const a=metrics(readFileSync(join(before,name)));const b=metrics(readFileSync(join(after,name)));
 result.files[name]={before:a,after:b,reductionPercent:Object.fromEntries(['raw','gzip9','brotli11'].map(k=>[k,100*(1-b[k]/a[k])]))};
}
writeFileSync(out,JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result,null,2));
