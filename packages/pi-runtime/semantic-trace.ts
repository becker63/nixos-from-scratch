import { createConnection } from 'node:net';
import { fileURLToPath } from 'node:url';
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';

type Kind = 'human' | 'codex' | 'fabric' | 'jev' | 'search' | 'read' | 'edit' | 'tool' | 'test' | 'verify' | 'worker' | 'shell-command';
type Status = 'active' | 'passed' | 'failed' | 'cancelled';
type Event = { id: number; parent?: number; kind: Kind; phase: 'start' | 'update' | 'finish'; status: Status; count: number; uncertainty: number };
const kinds = new Set<Kind>(['human','codex','fabric','jev','search','read','edit','tool','test','verify','worker','shell-command']);
const classify = (name: string): Kind => ({fabric_exec:'fabric', read:'read', grep:'search', find:'search', ls:'search', edit:'edit', write:'edit', bash:'shell-command'} as Record<string, Kind>)[name] ?? 'tool';

/** Serial bounded IPC, no subprocess per event; failures cannot block model streams. */
export class TraceTransport {
  private queue: string[] = [];
  private running = false;
  disabled = false;
  constructor(private socket: string | undefined, private window: string | undefined) {
    this.disabled = !socket || !window || !/^\d+$/.test(window);
  }
  send(event: Event | null) {
    if (this.disabled) return;
    // Never drop one half of a lifecycle: disable the projection on overflow.
    if (this.queue.length >= 256) { this.disabled = true; this.queue = []; return; }
    const window_id = Number(this.window);
    if (!Number.isSafeInteger(window_id)) { this.disabled = true; return; }
    this.queue.push(JSON.stringify(event ? {TraceEvent:{event, window_id}} : {TraceReset:{window_id}}) + '\n');
    void this.drain();
  }
  private async drain() {
    if (this.running) return;
    this.running = true;
    try {
      while (this.queue.length && !this.disabled) {
        const payload = this.queue.shift()!;
        const accepted = await new Promise<boolean>((resolve) => {
          const client = createConnection(this.socket!);
          let reply = ''; let done = false;
          const finish = (ok: boolean) => { if (done) return; done = true; client.destroy(); resolve(ok); };
          client.setTimeout(800, () => finish(false));
          client.on('connect', () => client.end(payload));
          client.on('error', () => finish(false));
          client.on('data', chunk => { reply += chunk; if (reply.length > 2048) finish(false); });
          client.on('end', () => {
            try { const result = JSON.parse(reply).TraceEvent; finish(result && 'Ok' in result); } catch { finish(false); }
          });
        });
        if (!accepted) { this.disabled = true; this.queue = []; }
      }
    } finally { this.running = false; }
  }
  async flush() { while (this.running || this.queue.length) await new Promise(resolve => setTimeout(resolve, 10)); }
}

export default function semanticTrace(pi: ExtensionAPI) {
  let transport: TraceTransport;
  let next = 1;
  let agent: Event | undefined;
  let generation: Event | undefined;
  const scopes = new Map<string, Event>();
  function start(kind: Kind, parent?: number, count = 0): Event {
    const event: Event = {id: next++, parent, kind, phase:'start', status:'active', count:Math.min(65535, Math.max(0, Math.floor(count))), uncertainty:0};
    transport?.send(event); return event;
  }
  function finish(event: Event | undefined, status: Status = 'passed') {
    if (event) transport?.send({...event, phase:'finish', status});
  }
  pi.on('session_start', (_event, ctx) => {
    // Headless workers share the parent's environment but do not own its chrome.
    transport = new TraceTransport(ctx.mode === 'tui' ? process.env.ALACRITTY_SOCKET : undefined, process.env.ALACRITTY_WINDOW_ID);
    transport.send(null); scopes.clear(); agent = generation = undefined; next = 1;
  });
  pi.on('agent_start', () => { agent = start('human'); });
  pi.on('message_start', e => { if (e.message.role === 'assistant') generation = start('codex', agent?.id); });
  pi.on('message_end', e => {
    if (e.message.role !== 'assistant') return;
    const reason = 'stopReason' in e.message ? e.message.stopReason : undefined;
    finish(generation, reason === 'error' ? 'failed' : reason === 'aborted' ? 'cancelled' : 'passed'); generation = undefined;
  });
  pi.on('tool_execution_start', e => {
    if (scopes.size >= 256) return;
    scopes.set(e.toolCallId, start(classify(e.toolName), scopes.get(e.parentToolCallId ?? '')?.id ?? agent?.id));
  });
  pi.on('tool_execution_end', e => {
    finish(scopes.get(e.toolCallId), e.isError ? 'failed' : 'passed'); scopes.delete(e.toolCallId);
  });
  pi.events.on('pi-fabric:semantic-v1', (raw: unknown) => {
    if (!raw || typeof raw !== 'object') return;
    const data = raw as Record<string, unknown>;
    if (data.version !== 1 || typeof data.key !== 'string' || data.key.length > 512 || typeof data.parent !== 'string' || !kinds.has(data.kind as Kind)) return;
    const key = `fabric:${data.key}`;
    if (data.phase === 'start' && data.status === 'active' && !scopes.has(key) && scopes.size < 256) {
      const count = typeof data.count === 'number' && Number.isFinite(data.count) ? data.count : 0;
      scopes.set(key, start(data.kind as Kind, scopes.get(data.parent)?.id ?? agent?.id, count));
    } else if (data.phase === 'finish' && (data.status === 'passed' || data.status === 'failed' || data.status === 'cancelled')) {
      finish(scopes.get(key), data.status); scopes.delete(key);
    }
  });
  pi.events.on('pi-semantic:signal', (raw: unknown) => {
    if (!raw || typeof raw !== 'object') return;
    const data = raw as Record<string, unknown>;
    if(data.version!==1||typeof data.key!=='string'||!['jev','fabric','tool','verify','edit','search'].includes(String(data.kind)))return;
    const key=`control:${data.key}`;
    const count=typeof data.count==='number'&&Number.isFinite(data.count)?data.count:0;
    if(data.phase==='finish') {finish(scopes.get(key),data.passed===true?'passed':'failed');scopes.delete(key);return;}
    const scope=start(data.kind as Kind,agent?.id,count);
    if(data.phase==='start'&&scopes.size<256)scopes.set(key,scope);
    else finish(scope,data.passed===true?'passed':'failed');
  });
  pi.on('agent_end', () => {
    for (const scope of scopes.values()) finish(scope, 'cancelled'); scopes.clear();
    finish(generation, 'cancelled'); generation = undefined; finish(agent); agent = undefined;
  });
  pi.on('session_shutdown', async () => {
    for (const scope of scopes.values()) finish(scope, 'cancelled'); scopes.clear();
    finish(generation, 'cancelled'); finish(agent, 'cancelled'); await transport?.flush();
  });
  pi.registerCommand('trace-check', {
    description: 'Run the installed bridge verification with a native verify scope',
    handler: async (_args, ctx) => {
      const scope = start('verify', agent?.id);
      try {
        const result = await pi.exec(process.execPath, [fileURLToPath(new URL('./semantic-trace.test.mjs', import.meta.url))], {timeout:10000});
        finish(scope, result.code === 0 ? 'passed' : 'failed');
        ctx.ui.notify(result.code === 0 ? 'Semantic bridge verification passed' : 'Semantic bridge verification failed', result.code === 0 ? 'info' : 'error');
      } catch { finish(scope, 'failed'); ctx.ui.notify('Semantic bridge verification failed', 'error'); }
      await transport?.flush();
    },
  });
  pi.registerCommand('trace-smoke', {
    description: 'Exercise bounded native trace geometry (synthetic, no model/provider calls)',
    handler: async () => {
      const main = start('codex'); const fabric = start('fabric', main.id);
      const read = start('read', fabric.id); finish(read);
      const jev = start('jev', fabric.id, 24); await new Promise(resolve => setTimeout(resolve, 350)); finish(jev);
      const verification = start('verify', fabric.id); finish(verification);
      const rejection = start('test', fabric.id); finish(rejection, 'failed');
      finish(fabric); finish(main); await transport?.flush();
    },
  });
}
