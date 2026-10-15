import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,symlinkSync,readdirSync,cpSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {dependencyModules} from '../semantic-check.mjs';
const root=dirname(dirname(fileURLToPath(import.meta.url))),ts=createRequire(import.meta.url)('typescript');
const temporary=mkdtempSync(join(tmpdir(),'jev-task-tests-'));const compiled=join(temporary,'kernel');mkdirSync(compiled);mkdirSync(join(compiled,'jev-agent'));writeFileSync(join(compiled,'package.json'),'{"type":"module"}');symlinkSync(dependencyModules,join(compiled,'node_modules'));
try {
 for(const folder of ['','jev-agent'])for(const name of readdirSync(join(root,folder)).filter(n=>n.endsWith('.ts')))writeFileSync(join(compiled,folder,name.replace(/\.ts$/,'.js')),ts.transpileModule(readFileSync(join(root,folder,name),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText);
 const {classifyTask}=await import(join(compiled,'jev-agent/tasks.js'));
 const {runJevAgent}=await import(join(compiled,'jev-agent/controller.js'));const {RepositoryWorld}=await import(join(compiled,'jev-agent/actions.js'));
 const workspace=join(temporary,'repo');mkdirSync(join(workspace,'config/alacritty'),{recursive:true});writeFileSync(join(workspace,'config/alacritty/alacritty.toml'),'[window]\nopacity = 0.9\n');writeFileSync(join(workspace,'config/alacritty/notes.md'),'Documentation, not active configuration');writeFileSync(join(workspace,'sentinel.test.mjs'),'throw new Error("Read-only requests must not run me");');writeFileSync(join(workspace,'example.ts'),'export function behavior(value:number):number {return value;}\n');writeFileSync(join(workspace,'example.test.mjs'),'// references example module\n');
 const mock=async request=>{const task=request.state.task??'';const answers={};for(const [key,q]of Object.entries(request.questions)) {if(q.type==='choice'){let choice=key==='taskKind'?(/fix/i.test(task)?'Repair':/function|reference|covers/i.test(task)?'Inspect':'Locate'):key==='relation'?(/function/i.test(task)?'Symbol':/reference/i.test(task)?'References':/covers/i.test(task)?'Tests':'File'):key==='target'?(task.includes('nonexistent')?'unknown':Object.keys(q.criteria).find(k=>String(q.criteria[k]).endsWith(task.includes('behavior')||task.includes('reference')?'example.ts':'alacritty.toml'))):Object.keys(q.criteria).find(k=>k!=='unknown');choice??='unknown';answers[key]={type:'choice',choice,confidence:1,probabilities:Object.fromEntries(Object.keys(q.criteria).map(k=>[k,k===choice?1:0]))};}else answers[key]={type:'noul',noul:.99};}return {model:'mock',answers,usage:{input_tokens:1,output_tokens:1}};};
 assert.equal((await classifyTask('Fix the failing semantic-policy behavior',new RepositoryWorld(workspace,'J2'),'jev',mock)).kind,'Repair');
 const locate=await runJevAgent({root:workspace,task:'find the Alacritty config file and produce its full path',evaluate:mock});assert.equal(locate.taskKind,'Locate');assert.equal(locate.kind,'Success');assert.equal(locate.result.path,join(workspace,'config/alacritty/alacritty.toml'));assert.equal(locate.metrics.checks,0);assert.equal(locate.metrics.mutations,0);assert.equal(locate.metrics.codexCalls,0);assert.equal(locate.metrics.workerCalls,0);
 const absent=await runJevAgent({root:workspace,task:'find nonexistent configuration',evaluate:mock});assert.equal(absent.kind,'NotFound');assert.equal(absent.metrics.checks,0);
 const inspect=await runJevAgent({root:workspace,task:'which function defines behavior?',evaluate:mock});assert.equal(inspect.taskKind,'Inspect');assert.equal(inspect.result.symbol,'behavior');assert.equal(inspect.metrics.checks,0);
 const references=await runJevAgent({root:workspace,task:'which files reference example?',evaluate:mock});assert.equal(references.taskKind,'Inspect');assert(references.result.facts.some(f=>f.path.endsWith('example.test.mjs')));assert.equal(references.metrics.checks,0);
 // Real current source, NO checkout node_modules: NODE_PATH plus immutable compiler
 // dependency fallback must execute the actual semantic-controller assertions.
 const real=join(temporary,'current-runtime');mkdirSync(real);
 for(const name of readdirSync(root)){if(name==='node_modules'||name==='__pycache__')continue;if(name==='jev-agent'||name==='skill')cpSync(join(root,name),join(real,name),{recursive:true});else if(/\.(?:ts|mjs|json)$/.test(name))cpSync(join(root,name),join(real,name));}
 const regionWorld=new RepositoryWorld(workspace,'J2');const region=regionWorld.files[0].family;regionWorld.family=region;for(const f of regionWorld.files.filter(f=>f.family===region))regionWorld.rejected.add(`inspect:${f.id}`);regionWorld.advanceRegion();assert.equal(regionWorld.family,undefined);assert(regionWorld.rejected.has(`family:${region}`));
 const world=new RepositoryWorld(real,'J2');assert(!readdirSync(real).includes('node_modules'));const verified=await world.verify(90000);assert.equal(verified.passed,true,JSON.stringify(verified));
 console.log('PASS TaskKind Locate/Inspect routing, deterministic real paths/symbols/references, NotFound, zero mutations/checks/generation for navigation, actual source semantic-control.test with pinned dependencies and no checkout node_modules');
}finally{rmSync(temporary,{recursive:true,force:true});}
