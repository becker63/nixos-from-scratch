// Host-only seam; pinned anchors fail loudly. Not guest globals or model-writable state.
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
const root=process.argv[2];
function replace(file,anchor,replacement){const path=join(root,file);const source=readFileSync(path,'utf8');if(source.split(anchor).length!==2)throw new Error(`Semantic control anchor drift: ${file}`);writeFileSync(path,source.replace(anchor,replacement));}
replace('chunks/chunk-5QMCSJ42.js','  async invoke(ref, args, context) {',`  async invoke(ref, args, context) {
    if (process.env.PI_AGENT_MODE === "jev" && /^agents\./.test(ref)) throw new Error("Generative worker forbidden in pure Jev mode");
    if (!this.semanticControl) throw new Error("Host semantic controller not installed");
    return this.semanticControl(ref, args, context, () => this.semanticInvoke(ref, args, context));
  }
  async semanticInvoke(ref, args, context) {`);
replace('fabric-runtime-state.js','    this.#emitEvent = emit;',`    this.#emitEvent = emit;
    emit("pi-fabric:semantic-control-bind", {
      install: (control) => { this.registry.semanticControl = control; },
      evaluate: (request, context) => this.registry.semanticInvoke("jev.evaluate", request, context)
    });`);
