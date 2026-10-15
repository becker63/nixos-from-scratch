import {createHash} from 'node:crypto';
import {readdirSync,readFileSync,lstatSync,writeFileSync,mkdirSync,chmodSync} from 'node:fs';
import {join,resolve,relative} from 'node:path';
export const hash=data=>createHash('sha256').update(data).digest('hex');
export function manifest(root){const files={};function walk(dir){for(const name of readdirSync(dir).sort()){const path=join(dir,name),stat=lstatSync(path);if(stat.isSymbolicLink())throw Error('No symlinks in challenge');if(stat.isDirectory())walk(path);else if(stat.isFile())files[relative(root,path)]=hash(readFileSync(path));else throw Error('Nonregular challenge file');}}walk(root);return files;}
export const workspaceHash=root=>hash(JSON.stringify(manifest(root)));
export function rejectLeakage(root,task,oracle){
 const forbidden=/solution|correct[-_ ]?fix|hidden[-_ ]?oracle|TODO\s+use|should\s+(?:subtract|replace|use minus)/i;
 for(const name of Object.keys(manifest(root))){
  if(forbidden.test(name)||/(?:generate|playground|oracle)\.(?:mjs|ts|json)$/.test(name))throw Error('Oracle leakage in filename');
  const text=readFileSync(join(root,name),'utf8');
  const comments=text.match(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g)??[];
  const tests=text.match(/(?:test|it)\s*\(\s*['"`][^'"`]+/g)??[];
  const metadata=/\.(json|md|yaml|yml)$/.test(name)?[text]:[];
  for(const value of [name,...comments,...tests,...metadata,task])if(forbidden.test(value)||oracle.leakIdentifiers.some(id=>id.length>=4&&value.split(/[^A-Za-z0-9_$]+/).includes(id)||id.length>=4&&/[^A-Za-z0-9_$]/.test(id)&&value.includes(id)))throw Error('Oracle leakage in visible annotation');
 }
}
export function freeze(root,hidden,spec,oracle){
 if(resolve(hidden)===resolve(root)||resolve(hidden).startsWith(resolve(root)+'/'))throw Error('Oracle must be outside workspace');
 rejectLeakage(root,spec.task,oracle);const files=manifest(root);mkdirSync(hidden,{recursive:true,mode:0o700});
 const oracleText=JSON.stringify(oracle,null,2)+'\n';writeFileSync(join(hidden,'oracle.json'),oracleText,{mode:0o600});
 const frozen={...spec,version:1,state:'ChallengeFrozen',manifest:files,workspaceHash:hash(JSON.stringify(files)),oracleHash:hash(oracleText)};
 writeFileSync(join(hidden,'manifest.json'),JSON.stringify(frozen,null,2)+'\n');
 for(const file of Object.keys(files))chmodSync(join(root,file),0o444);
 return frozen;
}
export function assertFrozen(root,spec){if(spec.state!=='ChallengeFrozen'||workspaceHash(root)!==spec.workspaceHash)throw Error('Frozen workspace changed');}
