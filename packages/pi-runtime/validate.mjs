// Host validation; no raw transcript, auth, environment or provider error bodies.
import {spawnSync} from 'node:child_process';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=dirname(fileURLToPath(import.meta.url));
for(const script of ['semantic-control.test.mjs','semantic-trace.test.mjs','jev-agent/fixtures.test.mjs','jev-agent/tasks.test.mjs']) {
  const result=spawnSync(process.execPath,[join(root,script)],{cwd:root,stdio:'inherit',timeout:120000});
  if(result.status!==0)process.exit(result.status??1);
}
if(process.argv.includes('--live')) {
  const result=spawnSync(process.execPath,[join(root,'jev-agent/fixtures.test.mjs'),'--live','--only-live'],{cwd:root,stdio:'inherit',timeout:600000});
  if(result.status!==0)process.exit(result.status??1);
}
console.log('PASS Pi runtime semantic validation');
