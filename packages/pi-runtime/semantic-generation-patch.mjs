import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
const path=join(process.argv[2],'@earendil-works/pi-coding-agent/dist/core/model-runtime.js');
let text=readFileSync(path,'utf8');
for(const signature of ['stream(model, context, options)','streamSimple(model, context, options)','streamDeferred(model, handle, options)']) {
  const anchor=`    ${signature} {`;
  if(text.split(anchor).length!==2)throw new Error(`Generation guard anchor drift: ${signature}`);
  text=text.replace(anchor,`${anchor}\n        if (process.env.PI_AGENT_MODE === "jev") throw new Error("Generative provider request forbidden in pure Jev mode");`);
}
writeFileSync(path,text);
