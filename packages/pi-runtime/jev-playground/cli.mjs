#!/usr/bin/env node
import {resolve,join} from 'node:path';
import {readFileSync} from 'node:fs';
import {generateCampaign,runCampaign} from './campaigns.mjs';
import {generate,mutatedSource} from './generate.mjs';
import {run} from './run.mjs';
import {score} from './score.mjs';
const [command,name,...args]=process.argv.slice(2);
const option=(key,fallback)=>{const i=args.indexOf('--'+key);return i<0?fallback:args[i+1];};
if(!['generate','run','score','campaign'].includes(command)||!name)throw Error('Usage: node jev-playground/cli.mjs generate|run|campaign NAME --out DIR [--count N --seed N --policies jev,random,heuristic]; generate source --proposal JSON; run instance; score instance --run-path DIR');
const directory=resolve(option('out',`.tmp/jev-playground/${name}`));
if(command==='score'){
 const output=resolve(option('run-path',''));
 const record=JSON.parse(readFileSync(join(output,'receipt.json'),'utf8')),spec=JSON.parse(readFileSync(join(directory,'private/manifest.json'),'utf8'));
 console.log(JSON.stringify(await score(directory,{record,output,spec})));
}else if(name==='source'&&command==='generate'){
 const proposal=JSON.parse(readFileSync(option('proposal',''),'utf8'));
 console.log(JSON.stringify(await generate(directory,mutatedSource(proposal),{id:'source'})));
}else if(name==='instance'&&command==='run'){
 for(const policy of option('policies','jev,random,heuristic').split(','))console.log(JSON.stringify(await score(directory,await run(directory,policy))));
}else{
 if(command!=='run')await generateCampaign(directory,name,{count:Number(option('count',5)),seed:Number(option('seed',42))});
 if(command!=='generate')await runCampaign(directory,{policies:option('policies','jev,random,heuristic').split(',')});
}
console.log(JSON.stringify({directory}));
