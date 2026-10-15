// Conventional finite retrieval only: no graph, generated queries, or persistent index.
import {execFileSync} from 'node:child_process';
import {readFileSync,lstatSync} from 'node:fs';
import {join,posix} from 'node:path';
import ts from 'typescript';
import {sensitivePath} from '../semantic-controller.js';
import type {FileTarget} from './state.js';
export type Signal={kind:'issue-token'|'path'|'identifier'|'code-span'|'diagnostic'|'import'|'test-adjacency'|'package';value:string;weight:number};
export type Candidate=FileTarget&{signals:Signal[];score:number;definitions:string[];imports:string[]};
export type Retrieval={terms:string[];generated:Candidate[];compressed:Candidate[];ms:number};
const stop=new Set('the and for with this that from when where what which how have does should would could issue bug report expected actual behavior reproduction steps version javascript typescript return function const export import'.split(' '));
export function inventory(root:string):FileTarget[]{
 const paths=execFileSync('git',['ls-files','-z'],{cwd:root,timeout:10000,maxBuffer:8*1024*1024}).toString().split('\0').filter(Boolean).sort();
 const result:FileTarget[]=[];
 for(const path of paths){
  if(sensitivePath(path)||path.split('/').some(p=>['node_modules','vendor','dist','build','.git'].includes(p))||!/[.](?:[cm]?js|[jt]sx?|json|md|ya?ml|toml)$/.test(path))continue;
  try{const stat=lstatSync(join(root,path));if(!stat.isFile()||stat.size>512000)continue;result.push({id:'F'+result.length,path,bytes:stat.size,family:'G'+(path.includes('/')?path.split('/').slice(0,2).join('/'):'root')});}catch{}
  if(result.length===10000)break;
 }
 return result;
}
export function compileCandidates(root:string,files:FileTarget[],task:string,failures:string[]=[]):Retrieval{
 const start=Date.now();
 const identifiers=[...new Set((task.match(/\b[A-Za-z_$][\w$]*\b/g)??[]).filter(t=>/[A-Z_$]/.test(t)))].slice(0,64);
 const spans=[...task.matchAll(/`([^`\n]{3,120})`/g)].map(m=>m[1]).slice(0,24);
 const terms=[...new Set((task+' '+failures.join(' ')).toLowerCase().split(/[^a-z0-9_$]+/).filter(t=>t.length>2&&!stop.has(t)))].slice(0,160);
 const documents:Array<{file:FileTarget;text:string;counts:Map<string,number>;length:number;definitions:string[];imports:string[]}>=[];
 const df=new Map<string,number>();let bytes=0;
 for(const file of files){
  if(!/[.](?:[cm]?js|[jt]sx?)$/.test(file.path))continue;
  // Bounded streaming text; only sparse issue-term counts survive compilation.
  const text=readFileSync(join(root,file.path),'utf8').slice(0,96000);bytes+=text.length;if(bytes>96*1024*1024)break;
  const tokens=text.toLowerCase().split(/[^a-z0-9_$]+/),counts=new Map<string,number>();
  for(const token of tokens)if(terms.includes(token))counts.set(token,(counts.get(token)??0)+1);
  for(const term of counts.keys())df.set(term,(df.get(term)??0)+1);
  const ast=ts.createSourceFile(file.path,text,ts.ScriptTarget.Latest,true),definitions:string[]=[],imports:string[]=[];
  const visit=(node:ts.Node)=>{
   if((ts.isFunctionDeclaration(node)||ts.isClassDeclaration(node)||ts.isMethodDeclaration(node)||ts.isVariableDeclaration(node))&&node.name&&ts.isIdentifier(node.name)&&definitions.length<80)definitions.push(node.name.text);
   if((ts.isImportDeclaration(node)||ts.isExportDeclaration(node))&&node.moduleSpecifier&&ts.isStringLiteral(node.moduleSpecifier)&&imports.length<32)imports.push(node.moduleSpecifier.text);
   if(ts.isCallExpression(node)&&ts.isIdentifier(node.expression)&&node.expression.text==='require'&&node.arguments[0]&&ts.isStringLiteral(node.arguments[0])&&imports.length<32)imports.push(node.arguments[0].text);
   ts.forEachChild(node,visit);
  };visit(ast);documents.push({file,text,counts,length:tokens.length,definitions,imports});
 }
 const average=documents.reduce((n,d)=>n+d.length,0)/Math.max(1,documents.length);
 const candidates:Candidate[]=documents.map(d=>{
  const signals:Signal[]=[],add=(kind:Signal['kind'],value:string,weight:number)=>signals.push({kind,value,weight});
  for(const term of terms){
   const frequency=d.counts.get(term)??0;
   if(frequency){const idf=Math.log(1+(documents.length-(df.get(term)??0)+.5)/((df.get(term)??0)+.5));add('issue-token',term,idf*frequency*2.2/(frequency+1.2*(.25+.75*d.length/average)));}
   if(d.file.path.toLowerCase().includes(term))add('path',term,5);
  }
  for(const identifier of identifiers)if(d.definitions.includes(identifier)||new RegExp('\\b'+identifier.replace(/[$]/g,'\\$')+'\\b').test(d.text))add('identifier',identifier,12);
  for(const span of spans)if(d.text.includes(span)||d.file.path.includes(span))add('code-span',span,15);
  for(const failure of failures)if(failure.includes(d.file.path)||failure.includes(posix.basename(d.file.path)))add('diagnostic',failure.slice(0,180),20);
  return {...d.file,signals,score:signals.reduce((n,s)=>n+s.weight,0),definitions:d.definitions,imports:d.imports};
 });
 const byPath=new Map(candidates.map(c=>[c.path,c]));
 // Resolve conventional one-hop imports in both directions, including JS-to-TS source imports.
 const resolveImport=(owner:Candidate,imported:string)=>{
  const path=posix.normalize(posix.join(posix.dirname(owner.path),imported));
  return [path,...['.ts','.tsx','.js','.jsx','/index.ts','/index.js'].map(ext=>path+ext),path.replace(/\.js$/,'.ts')].map(p=>byPath.get(p)).find(Boolean);
 };
 const seeds=candidates.filter(c=>c.score>0).sort((a,b)=>b.score-a.score||a.path.localeCompare(b.path)).slice(0,32);
 for(const seed of seeds){
  for(const imported of seed.imports.filter(i=>i.startsWith('.'))){
   const target=resolveImport(seed,imported);
   if(target){target.signals.push({kind:'import',value:seed.path,weight:8});target.score+=8;}
  }
  for(const target of candidates)if(target.imports.some(i=>i.startsWith('.')&&resolveImport(target,i)?.id===seed.id)){target.signals.push({kind:'import',value:'references:'+seed.path,weight:8});target.score+=8;}
  const stem=posix.basename(seed.path).replace(/\.(?:test|spec)?\.?[jt]sx?$/,'');
  for(const target of candidates)if(target.id!==seed.id&&posix.basename(target.path).startsWith(stem+'.')){target.signals.push({kind:'test-adjacency',value:seed.path,weight:8});target.score+=8;}
 }
 const generated=candidates.filter(c=>c.signals.length).sort((a,b)=>b.score-a.score||a.path.localeCompare(b.path));
 return {terms,generated,compressed:generated.slice(0,256),ms:Date.now()-start};
}
