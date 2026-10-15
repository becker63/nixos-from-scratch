import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { JevClient, JevCredentials, normalizeJevConfig, resolveJevModelRoute } from 'pi-fabric/jev';
import { getAgentDir } from '@earendil-works/pi-coding-agent';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { AsyncLocalStorage } from 'node:async_hooks';
import { runJevAgent } from './jev-agent/controller.js';
import { formatReceipt } from './jev-agent/tasks.js';
import type { Grammar } from './jev-agent/state.js';
import type { PurePolicy } from './jev-agent/policy.js';
import { SemanticController, safeText } from './semantic-controller.js';
import type { PolicyMode } from './semantic-policy.js';

type HostContext=Record<string,unknown>;
type HostBridge={install:(control:(ref:string,args:Record<string,unknown>,context:HostContext,run:()=>Promise<unknown>)=>Promise<unknown>)=>void;evaluate:(request:unknown,context:HostContext)=>Promise<unknown>};
export default function semanticExtension(pi:ExtensionAPI) {
  pi.registerFlag('agent-mode',{type:'string',default:'hybrid',description:'hybrid or jev (finite policy only; no generative model requests)'});
  pi.registerFlag('jev-grammar',{type:'string',default:'J2',description:'Finite repair grammar J0, J1, J2, or J3'});
  pi.registerFlag('jev-policy',{type:'string',default:'jev',description:'Experimental pure-mode policy: jev, random, heuristic'});
  pi.registerFlag('jev-receipt',{type:'boolean',default:false,description:'Print full structured Jev receipts instead of concise results'});
  pi.registerFlag('jev-seed',{type:'string',default:'0',description:'Deterministic seed offset for random baseline'});
  let lastReceipt:unknown;
  pi.registerCommand('jev-receipt',{description:'Show the last full Jev receipt and distributions',handler:async()=>{pi.sendMessage({customType:'jev-receipt',content:lastReceipt?JSON.stringify(lastReceipt,null,2):'No Jev receipt yet.',display:true});}});
  let client:JevClient|undefined;
  let providerRequests=0;
  pi.on('before_provider_request',()=>{providerRequests++;});
  let activePureTask:AbortController|undefined;
  let selectedMode:'jev'|'hybrid'|undefined;
  pi.registerCommand('jev-stop',{description:'Cancel the active finite Jev task',handler:async()=>{activePureTask?.abort();}});
  let hybridTools:string[]=[];
  const pure=()=>selectedMode==='jev'||selectedMode===undefined&&pi.getFlag('agent-mode')==='jev';
  pi.registerCommand('mode',{
    description:'Show or switch agent mode: /mode jev | /mode hybrid',
    handler:async(args,ctx)=>{
      const mode=args.trim();
      if(!mode){ctx.ui.notify(pure()?'Agent mode: jev':'Agent mode: hybrid','info');return;}
      if(mode!=='jev'&&mode!=='hybrid'){ctx.ui.notify('Usage: /mode jev | /mode hybrid','error');return;}
      if(activePureTask||!ctx.isIdle()){ctx.ui.notify('Wait until the current task is idle before switching modes.','warning');return;}
      if(mode==='jev'){
        if(!pure())hybridTools=pi.getActiveTools();
        selectedMode='jev';process.env.PI_AGENT_MODE='jev';pi.setActiveTools([]);
      }else{
        selectedMode='hybrid';delete process.env.PI_AGENT_MODE;
        if(hybridTools.length)pi.setActiveTools(hybridTools);
      }
      ctx.ui.notify(mode==='jev'?'Jev-only mode: finite actions; no generative requests or fallback.':'Hybrid mode restored.','info');
      pi.appendEntry('agent-mode',{mode});
    },
  });
  // Trusted process startup only; never a model-callable settings action.
  const requested=process.env.PI_SEMANTIC_POLICY??'jev';
  if(!['jev','constant','heuristic','off'].includes(requested))throw new Error('Invalid semantic policy mode');
  let bridge:HostBridge|undefined;
  let lastContext:HostContext|undefined;
  let traceId=0;
  const fabricCalls=new Set<string>();
  const registryScope=new AsyncLocalStorage<boolean>();
  let controlKey='';
  const pureTrace=new Map<string,string>();
  const controller=new SemanticController(requested as PolicyMode,async request=>{
    if(!client)throw new Error('No host Fabric Jev client');
    return await client.evaluate(request,AbortSignal.timeout(30000));
  },signal=>{
    // Reuse existing wire enums: no Alacritty protocol rewrite.
    if(signal.kind==='control'&&signal.phase==='start')controlKey=`semantic-control:${++traceId}`;
    const key=signal.kind==='control'?controlKey:`semantic-control:${++traceId}`;
    const kind=signal.kind==='control'?'jev':signal.kind==='permit'?'verify':signal.kind==='barrier'?'fabric':'tool';
    pi.events.emit('pi-semantic:signal',{version:1,key,kind,count:signal.count,passed:signal.passed,phase:signal.phase});
  });
  const unbind=pi.events.on('pi-fabric:semantic-control-bind',(raw:unknown)=>{
    const candidate=raw as HostBridge;
    if(typeof candidate?.install!=='function'||typeof candidate.evaluate!=='function')return;
    bridge=candidate;
    bridge.install((ref,args,context,run)=>controller.exclusive(()=>registryScope.run(true,async()=>{
      if(pure()&&/^agents\./.test(ref))throw new Error('Generative workers forbidden in pure Jev mode');
      lastContext=context;
      if(typeof context.parentToolCallId==='string')fabricCalls.add(context.parentToolCallId);
      try {return await controller.intercept(ref,args,run);}
      catch(error){pi.appendEntry('semantic-control-denial',controller.snapshot());throw error;}
    })));
  });
  pi.on('session_start',(_event,ctx)=>{
    const selected=pi.getFlag('agent-mode');
    if(selected!=='hybrid'&&selected!=='jev')throw new Error('Unknown agent mode');
    if(pure())process.env.PI_AGENT_MODE='jev';
    const configuration=JSON.parse(readFileSync(join(getAgentDir(),'fabric.json'),'utf8')) as {jev?:unknown};
    const config=normalizeJevConfig(configuration.jev);
    const route=resolveJevModelRoute(config.model).route;
    client=new JevClient(config,undefined,new JevCredentials(config.credentialCommand,process.env,{configured:()=>ctx.modelRegistry.getProviderAuthStatus(route.providerId).configured,resolve:()=>ctx.modelRegistry.getApiKeyForProvider(route.providerId)},route.envKeys),route);
  });
  pi.on('input',async(event,ctx)=>{
    if(!pure()){if(event.source!=='extension')controller.input(event.text);return;}
    if(activePureTask){pi.appendEntry('jev-agent-result',{kind:'Exhausted',missingCapability:'TaskAlreadyActive',codexCalls:0,workerCalls:0});return {action:'handled' as const};}
    const requestsBefore=providerRequests;
    activePureTask=new AbortController();
    const taskSignal=ctx.signal?AbortSignal.any([activePureTask.signal,ctx.signal]):activePureTask.signal;
    // Always return handled, even on provider/config/action errors. Pi's normal input
    // handler error behavior otherwise falls through to the generative loop.
    try {
      const grammar=String(pi.getFlag('jev-grammar'));
      const policy=String(pi.getFlag('jev-policy'));
      if(!['J0','J1','J2','J3'].includes(grammar)||!['jev','random','heuristic'].includes(policy))throw new Error('Invalid finite grammar/policy');
      const result=await runJevAgent({root:ctx.cwd,task:event.text,grammar:grammar as Grammar,policy:policy as PurePolicy,seed:Number(pi.getFlag('jev-seed'))||0,evaluate:async request=>{
        if(!client)throw new Error('No Fabric Jev client');
        return await client.evaluate(request,AbortSignal.any([AbortSignal.timeout(20000),taskSignal]));
      },signal:taskSignal,trace:event=>{
        let key=pureTrace.get(event.kind);
        if(event.phase==='start'){key=`pure-jev:${++traceId}`;pureTrace.set(event.kind,key);}
        const paired=key!==undefined;key??=`pure-jev:${++traceId}`;
        const kind=event.kind==='jev-policy'?'jev':event.kind==='mutation'?'edit':event.kind==='verification'?'verify':event.kind==='candidate-generation'?'search':'tool';
        pi.events.emit('pi-semantic:signal',{version:1,key,kind,count:event.count,passed:event.kind==='NeedsGeneration'?false:event.passed,phase:paired?event.phase:undefined});
        if(event.phase==='finish')pureTrace.delete(event.kind);
      }});
      result.metrics.codexCalls=providerRequests-requestsBefore;
      if(result.metrics.codexCalls!==0){result.kind='ProviderFailure';result.missingCapability='ZeroGenerationInvariant';}
      pi.appendEntry('jev-agent-result',result);
      lastReceipt=result;
      const text=pi.getFlag('jev-receipt')===true?JSON.stringify(result):formatReceipt(result);
      if(ctx.mode==='print')process.stdout.write(text+'\n');
      else pi.sendMessage({customType:'jev-agent-result',content:text,display:true});
    } catch {
      const result={kind:'ProviderFailure',missingCapability:'Pure-mode initialization or deterministic action unavailable',codexCalls:0,workerCalls:0};
      pi.appendEntry('jev-agent-result',result);
      lastReceipt=result;
      if(ctx.mode==='print')process.stdout.write(pi.getFlag('jev-receipt')===true?JSON.stringify(result)+'\n':'Jev · Unsupported · ProviderFailure\nPure-mode initialization or action unavailable.\n');
      else pi.sendMessage({customType:'jev-agent-result',content:'Jev · Unsupported · ProviderFailure\nPure-mode initialization or action unavailable.',display:true});
    }
    activePureTask=undefined;
    return {action:'handled' as const};
  });
  pi.on('before_agent_start',(_event,ctx)=>{if(pure())ctx.abort();});
  pi.on('turn_start',()=>{controller.metrics.codexTurns++;});
  // Registry guards Fabric calls. Guard direct AND nested non-Fabric Pi tools too.
  // Fabric's tool middleware duplicates observations conservatively, never widens authority.
  pi.on('tool_call',async event=>{
    if(pure())return {block:true,reason:'Model tool execution is forbidden in pure Jev mode'};
    if(event.toolName==='fabric_exec'){fabricCalls.add(event.toolCallId);controller.metrics.fabricExecutions++;return;}
    if(registryScope.getStore()||event.parentToolCallId&&fabricCalls.has(event.parentToolCallId))return;
    if(['read','grep','find','ls','bash','powershell','write','edit'].includes(event.toolName)) {
      try {await controller.intercept(`pi.${event.toolName}`,event.input as Record<string,unknown>,async()=>undefined,'prepare');}
      catch {return {block:true,reason:'Host semantic policy denied the tool; use bounded evidence and current verification.'};}
    }
  });
  pi.on('tool_result',async event=>{
    if(registryScope.getStore()||event.parentToolCallId&&fabricCalls.has(event.parentToolCallId))return;
    if(['read','grep','find','ls','bash','powershell','write','edit'].includes(event.toolName)) {
      await controller.intercept(`pi.${event.toolName}`,event.input,async()=>({content:event.content,isError:event.isError}),'observe');
    } else if(event.toolName!=='fabric_exec')return;
    fabricCalls.delete(event.toolCallId);
    // Model-authored return values are NOT admission authority. Replace the outer
    // result with a host projection; raw values remain local to QuickJS only.
    return await controller.exclusive(async()=>{
      const selected=await controller.admit();
      const snapshot=controller.snapshot();
      const text=JSON.stringify({semantic:snapshot,evidence:selected,executionFailed:event.isError,executionNotice:event.isError?safeText(event.content.filter(c=>c.type==='text').map(c=>c.type==='text'?c.text:'').join('\n'),384):undefined});
      return {content:[{type:'text' as const,text}],details:undefined};
    });
  });
  pi.on('turn_end',async()=>{
    // A completed evidence phase is a meaningful barrier, not every tool.
    await controller.exclusive(()=>controller.barrier('reasoning'));
  });
  pi.on('agent_before_settle',async event=>{
    if(pure()||event.outcome==='aborted')return;
    const result=await controller.exclusive(()=>controller.settlement());
    pi.appendEntry('semantic-control-metrics',controller.snapshot());
    if(!result.ready)return {continue:result.continue,entries:[{type:'custom_message' as const,customType:'semantic-control',content:result.message,display:true}]};
  });
  pi.on('session_shutdown',()=>{unbind();activePureTask?.abort();client?.close();client=undefined;bridge=undefined;lastContext=undefined;});
}
