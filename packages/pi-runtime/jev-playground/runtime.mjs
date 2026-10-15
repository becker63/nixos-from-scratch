import {createRequire} from 'node:module';
import {readFileSync,existsSync,mkdtempSync,mkdirSync,writeFileSync,symlinkSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {tmpdir,homedir} from 'node:os';
import {fileURLToPath} from 'node:url';
export const runtime=dirname(dirname(fileURLToPath(import.meta.url)));
function modules(){
 if(process.env.PI_PLAYGROUND_RUNTIME)return join(process.env.PI_PLAYGROUND_RUNTIME,'node_modules');
 if(existsSync(join(runtime,'node_modules/typescript')))return join(runtime,'node_modules');
 const wrapper=readFileSync(join(homedir(),'.nix-profile/bin/pi'),'utf8');
 const match=wrapper.match(/(\/nix\/store\/[^\s]+\/lib\/pi-runtime)\/node_modules\/.*cli\.js/);
 if(!match)throw Error('Set PI_PLAYGROUND_RUNTIME to an installed patched Pi runtime');
 return join(match[1],'node_modules');
}
export const dependencyModules=modules();
export const ts=createRequire(join(dependencyModules,'typescript/package.json'))('typescript');
export function compileKernel(){
 const output=mkdtempSync(join(tmpdir(),'jev-playground-kernel-'));mkdirSync(join(output,'jev-agent'));
 symlinkSync(dependencyModules,join(output,'node_modules'));writeFileSync(join(output,'package.json'),'{"type":"module"}');
 for(const name of ['semantic-state','semantic-policy','semantic-controller',...['state','actions','transforms','policy','tasks','controller','retrieval'].map(n=>'jev-agent/'+n)])
 writeFileSync(join(output,name+'.js'),ts.transpileModule(readFileSync(join(runtime,name+'.ts'),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText);
 return output;
}
