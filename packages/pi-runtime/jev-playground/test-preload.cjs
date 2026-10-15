// Exact tests have no network or subprocess capabilities. Node permission flags
// separately restrict their reads to the bounded workspace and runtime modules.
const {syncBuiltinESMExports}=require('node:module');
const deny=()=>{throw Error('Challenge checks cannot use network or generation');};
globalThis.fetch=deny;
for(const name of ['node:http','node:https']){const api=require(name);api.request=deny;api.get=deny;}
require('node:net').Socket.prototype.connect=deny;
require('node:tls').connect=deny;
syncBuiltinESMExports();
