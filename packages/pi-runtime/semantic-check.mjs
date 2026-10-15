// Source-local checks use immutable runtime dependencies, not ambient/global npm.
import {createRequire} from 'node:module';
import {dirname,join,basename} from 'node:path';
export const dependencyModules=dirname(dirname(createRequire(import.meta.url).resolve('typescript/package.json')));
export function checkedProgram(ts,files,options) {
  options={...options,typeRoots:[join(dependencyModules,'@types')]};
  const host=ts.createCompilerHost(options);
  host.resolveModuleNames=(names,file)=>names.map(name=>ts.resolveModuleName(name,name.startsWith('.')||name.startsWith('/')?file:join(dependencyModules,'..',basename(file)),options,host).resolvedModule);
  return ts.createProgram(files,options,host);
}
