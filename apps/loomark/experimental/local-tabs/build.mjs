import {spawnSync} from 'node:child_process';
import {copyFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('.',import.meta.url));
const moon=process.platform==='win32'?'moon.exe':'moon';
for(const args of [
  ['check','../../internal/local_tabs','--target','js','--deny-warn'],
  ['check','engine/main','--target','js','--deny-warn'],
  ['build','../../main','--target','js','--release'],
  ['build','engine/main','--target','js','--release'],
  ['build','fixture','--target','js','--release'],
]){
  const result=spawnSync(moon,args,{cwd:root,stdio:'inherit'});
  if(result.error)throw result.error;
  if(result.status!==0)process.exit(result.status??1);
}
for(const [source,target] of [
  ['dowdiness/loomark/main/main.js','loomark.js'],
  ['trial/local_tabs/main/main.js','worker.js'],
  ['dowdiness/loomark/experimental/local-tabs/fixture/fixture.js','fixture.js'],
]){
  await copyFile(new URL('_build/js/release/build/'+source,import.meta.url),new URL(target,import.meta.url));
}
