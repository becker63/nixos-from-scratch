import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createServer } from 'node:net';
const require = createRequire(import.meta.url);
const ts = require('typescript');
const source = new URL('./semantic-trace.ts', import.meta.url);
const moduleRoot = dirname(dirname(require.resolve('typescript/package.json')));
const options = {strict:true,noEmit:true,target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext,moduleResolution:ts.ModuleResolutionKind.Bundler,skipLibCheck:true,types:['node'],typeRoots:[join(moduleRoot,'@types')]};
const host = ts.createCompilerHost(options);
host.resolveModuleNames = (names, file) => names.map(name => ts.resolveModuleName(name, file.endsWith('semantic-trace.ts') ? join(moduleRoot,'..','semantic-trace.ts') : file, options, host).resolvedModule);
const diagnostics = ts.getPreEmitDiagnostics(ts.createProgram([fileURLToPath(source)], options, host));
assert.equal(diagnostics.length,0,ts.formatDiagnosticsWithColorAndContext(diagnostics,{getCanonicalFileName:file=>file,getCurrentDirectory:()=>process.cwd(),getNewLine:()=> '\n'}));
const directory = mkdtempSync(join(tmpdir(), 'pi-trace-test-'));
try {
  const output = ts.transpileModule(readFileSync(source, 'utf8'), {compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}, reportDiagnostics:true});
  assert.equal(output.diagnostics?.length ?? 0, 0);
  const file = join(directory, 'bridge.mjs'); writeFileSync(file, output.outputText);
  const { default: extension, TraceTransport } = await import(file);
  const records = []; const active = new Map(); const identities = new Map();
  const socket = join(directory, 'ipc.sock');
  const server = createServer({allowHalfOpen:true}, client => {
    let data = ''; client.on('data', chunk => data += chunk);
    client.on('end', () => {
      const record = JSON.parse(data); records.push(record);
      const e = record.TraceEvent?.event;
      if (record.TraceReset) { active.clear(); identities.clear(); }
      else {
        assert(e && Number.isInteger(e.id) && e.id > 0);
        assert(e.count >= 0 && e.count <= 65535 && Number.isInteger(e.count));
        if (e.phase === 'start') {
          assert.equal(e.status, 'active'); assert(!identities.has(e.id));
          assert(e.parent === undefined || active.has(e.parent), 'parent must still be active');
          identities.set(e.id, {kind:e.kind, parent:e.parent}); active.set(e.id, e);
        } else {
          assert(active.has(e.id), 'update/finish needs active scope');
          assert.deepEqual(identities.get(e.id), {kind:e.kind, parent:e.parent});
          if (e.phase === 'finish') { assert.notEqual(e.status, 'active'); active.delete(e.id); }
          else { assert.equal(e.phase, 'update'); assert.equal(e.status, 'active'); }
        }
      }
      client.end(JSON.stringify({TraceEvent:{Ok:null}}));
    });
  });
  await new Promise(resolve => server.listen(socket, resolve));
  process.env.ALACRITTY_SOCKET = socket; process.env.ALACRITTY_WINDOW_ID = '42';
  const handlers = new Map(); const events = new Map(); const commands = new Map();
  extension({on:(name, handler) => handlers.set(name,handler),events:{on:(name, handler) => events.set(name,handler)},registerCommand:(name, command) => commands.set(name, command)});
  handlers.get('session_start')({}, {mode:'tui'}); handlers.get('agent_start')();
  handlers.get('message_start')({message:{role:'assistant'}});
  handlers.get('message_end')({message:{role:'assistant',stopReason:'toolUse'}});
  handlers.get('tool_execution_start')({toolCallId:'f',toolName:'fabric_exec',args:{code:'SECRET PROMPT'}});
  const semantic = events.get('pi-fabric:semantic-v1');
  semantic({version:1,key:'j',parent:'f',kind:'jev',phase:'start',status:'active',count:24,state:'SECRET STATE'});
  semantic({version:1,key:'j',parent:'f',kind:'jev',phase:'finish',status:'passed',count:24,result:'SECRET ANSWERS'});
  const control=events.get('pi-semantic:signal');
  control({version:1,key:'dirty',kind:'tool',count:5,passed:true,secret:'SECRET'});
  control({version:1,key:'batch',kind:'jev',phase:'start',count:8,passed:true});
  control({version:1,key:'batch',kind:'jev',phase:'finish',count:8,passed:true});
  control({version:1,key:'mutation',kind:'edit',count:1,passed:true});
  control({version:1,key:'needs-generation',kind:'tool',count:1,passed:false});
  handlers.get('tool_execution_end')({toolCallId:'f',isError:false});
  handlers.get('agent_end')();
  await commands.get('trace-smoke').handler();
  await handlers.get('session_shutdown')();
  const text = JSON.stringify(records);
  assert(!text.includes('SECRET')); assert(!text.includes('PROMPT'));
  assert(records.some(r => r.TraceEvent?.event.kind === 'jev' && r.TraceEvent.event.count === 24));
  assert(records.some(r => r.TraceEvent?.event.kind === 'fabric'));
  assert.equal(active.size, 0, 'shutdown must leave no active scopes');
  assert(records.some(r => r.TraceEvent?.event.status === 'failed'));
  assert(records.some(r => r.TraceEvent?.event.kind === 'verify' && r.TraceEvent.event.status === 'passed'));
  for (const record of records) {
    const e = record.TraceEvent?.event; if (!e) continue;
    assert.equal(record.TraceEvent.window_id,42); assert(Number.isInteger(e.id));
    assert(Object.keys(e).every(key => ['id','parent','kind','phase','status','count','uncertainty','window_id'].includes(key)));
  }
  // Headless workers must never reset or instrument their inherited window.
  const beforeHeadless = records.length;
  handlers.get('session_start')({}, {mode:'print'});
  handlers.get('agent_start')(); handlers.get('agent_end')();
  await handlers.get('session_shutdown')();
  assert.equal(records.length, beforeHeadless);
  await new Promise(resolve => server.close(resolve));
  // Transport rejects an old/failed receiver and unsafe addressing, and stops
  // bounded overload instead of silently dropping one half of a lifecycle.
  const rejectionSocket = join(directory, 'reject.sock');
  const rejecting = createServer({allowHalfOpen:true}, client => {
    client.resume(); client.on('end', () => client.end(JSON.stringify({TraceEvent:{Err:'rejected'}})));
  });
  await new Promise(resolve => rejecting.listen(rejectionSocket, resolve));
  const rejected = new TraceTransport(rejectionSocket, '42'); rejected.send(null); await rejected.flush();
  assert(rejected.disabled);
  const unsafe = new TraceTransport(rejectionSocket, '9007199254740992'); unsafe.send(null);
  assert(unsafe.disabled);
  assert(new TraceTransport(rejectionSocket, undefined).disabled);
  const overflow = new TraceTransport(rejectionSocket, '42');
  for (let i=0;i<258;i++) overflow.send(null);
  assert(overflow.disabled, 'queue must fail closed at its bounded budget');
  await overflow.flush();
  await new Promise(resolve => rejecting.close(resolve));
  console.log(`PASS semantic bridge: ${records.length} bounded messages, lifecycle, Jev count, failure, verification, no content leak; headless isolation, negative acknowledgement, unsafe address, queue budget`);
} finally { rmSync(directory,{recursive:true,force:true}); }
