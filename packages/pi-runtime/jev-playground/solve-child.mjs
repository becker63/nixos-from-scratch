// Fresh pure context. No generator/scorer/oracle imports and no Pi model runtime,
// worker registry, extension loader, conversation, or generative dispatch exists.
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {homedir} from 'node:os';
import {installTestBoundary} from './test-boundary.mjs';
import {classifierTransport} from './isolation.mjs';
const chunks=[];for await(const chunk of process.stdin)chunks.push(chunk);
const input=JSON.parse(Buffer.concat(chunks).toString());
if(process.env.PI_AGENT_MODE!=='jev')throw Error('Pure process required');
installTestBoundary(input.modules);
const {RepositoryWorld}=await import(join(input.kernel,'jev-agent/actions.js'));
const {ExactVerificationUnavailable}=await import(join(input.kernel,'jev-agent/state.js'));
let verifierSequence=0;
const exactVerifier=input.externalVerifier?{verificationScope:input.verificationScope??'canonical',verify:()=>new Promise((resolve,reject)=>{
 const requestId=++verifierSequence;
 const listener=message=>{if(message.kind!=='verification-result'||message.requestId!==requestId)return;process.off('message',listener);
  if(message.infrastructureFailure)reject(new ExactVerificationUnavailable());else resolve({passed:message.passed,failures:message.failures,fingerprint:message.fingerprint});
 };
 process.on('message',listener);process.send({kind:'verify',requestId});
})}:undefined;
const {runJevAgent}=await import(join(input.kernel,'jev-agent/controller.js'));
const events=[];let verificationMs=0;
const frontierWorld=new RepositoryWorld(input.options.root,input.options.grammar,undefined,{retrieval:input.options.retrieval});frontierWorld.prioritize(input.options.task);
events.push({kind:'frontier',files:frontierWorld.files.map(f=>({...f})),retrieval:frontierWorld.retrieval,objects:frontierWorld.navigationCandidates(input.options.task).map(f=>({...f}))});
for(const method of ['legal','prepare','apply','revert','inspect','verify','execute']){
 const original=RepositoryWorld.prototype[method];
 RepositoryWorld.prototype[method]=function(...args){
  const start=Date.now();const finish=result=>{
   const event={kind:method,ms:Date.now()-start,args,result:method==='legal'?result:method==='verify'?result:undefined,focus:this.focus?{...this.focus}:undefined,file:this.focus?this.file(this.focus.file).path:undefined};
   if(method==='inspect'){event.symbols=this.symbols.map(s=>({...s}));event.symbolUniverse=this.symbolUniverse.map(s=>({...s}));}
   if(method==='prepare')event.edits=this.edits.map(e=>({...e,file:this.file(e.file).path}));
   if(method==='verify'){verificationMs+=Date.now()-start;event.ms=Date.now()-start;}
   events.push(structuredClone(event));return result;
  };
  const result=original.apply(this,args);return result instanceof Promise?result.then(finish):finish(result);
 };
}
let client;let jevRequests=0;const transportAudit={classifierRequests:0,deniedRequests:0};
const evaluate=async request=>{
 if(input.policy!=='jev')throw Error('Baseline requested provider');
 if(!client){
  const {JevClient,JevCredentials,normalizeJevConfig,resolveJevModelRoute}=await import(join(input.modules,'pi-fabric/dist/jev.js'));
  const configuration=JSON.parse(readFileSync(join(homedir(),'.pi/agent/fabric.json'),'utf8'));
  const config=normalizeJevConfig(configuration.jev),route=resolveJevModelRoute(config.model).route;
  client=new JevClient(config,classifierTransport(route.endpoint,resolveJevModelRoute(config.model).model,fetch,transportAudit),new JevCredentials(config.credentialCommand,process.env,undefined,route.envKeys),route);
 }
 jevRequests++;const response=await client.evaluate(request,AbortSignal.timeout(20000));
 events.push({kind:'evaluation',request,response});return response;
};
try{
 const receipt=await runJevAgent({...input.options,policy:input.policy,evaluate,exactVerifier});
 let composition;
 if(input.relationChain&&receipt.kind==='Success'&&receipt.result?.kind==='LocatedSymbol'){
  const path=receipt.result.path;const name=path.split('/').at(-1).replace(/\.[^.]+$/,'');
  const tests=frontierWorld.checks.filter(t=>readFileSync(join(input.options.root,t.path),'utf8').includes(name)).map(t=>join(input.options.root,t.path));
  composition={relations:['Symbol','ContainingFile','Tests'],symbol:receipt.result.symbol,path,tests,completed:tests.length>0};
 }
 process.stdout.write(JSON.stringify({receipt,composition,events,verificationMs,isolation:{freshPid:process.pid,mode:process.env.PI_AGENT_MODE,allowedProvider:'JevClient.evaluate only',jevRequests,codexCalls:0,workerCalls:0,generativeRuntimeLoaded:false,oracleSupplied:false,checksRestricted:true,transportAudit}})+'\n');
}finally{client?.close();if(process.connected)process.disconnect();}
