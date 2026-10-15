import childProcess from 'node:child_process';
import {promisify} from 'node:util';
import {syncBuiltinESMExports} from 'node:module';
import {dirname,join,resolve,relative} from 'node:path';
import {fileURLToPath} from 'node:url';
export function installTestBoundary(modules){
 const original=childProcess.execFile;if(original.playgroundBoundary)return;
 const preload=join(dirname(fileURLToPath(import.meta.url)),'test-preload.cjs');
 const safeArgs=(file,args,options)=>{
  if(file!==process.execPath||args[0]!=='--test')return args;
  const root=resolve(options.cwd);if(args.slice(1).some(path=>!resolve(path).startsWith(root+'/')))throw Error('Check outside workspace');
  return ['--permission',`--allow-fs-read=${root}`,`--allow-fs-read=${modules}`,`--allow-fs-read=${preload}`,'--require',preload,'--test-isolation=none','--test',...args.slice(1).map(path=>relative(root,path))];
 };
 function wrapped(file,args,options,callback){return original(file,safeArgs(file,args,options),options,callback);}
 wrapped[promisify.custom]=(file,args,options)=>promisify(original)(file,safeArgs(file,args,options),options);
 wrapped.playgroundBoundary=true;childProcess.execFile=wrapped;syncBuiltinESMExports();
}
