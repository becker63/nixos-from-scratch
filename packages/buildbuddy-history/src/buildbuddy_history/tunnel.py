"""Independent history tunnel; existing BuildBuddy and Jev daemons are untouched."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

NAME='buildbuddy-history'


def config_root():
    p=Path.home()/'.config/tunnel-client';p.mkdir(parents=True,mode=0o700,exist_ok=True);return p


def private_write(p,value):
    fd,tmp=tempfile.mkstemp(dir=p.parent,prefix='.history-')
    with os.fdopen(fd,'w') as f:os.fchmod(f.fileno(),0o600);f.write(value)
    os.replace(tmp,p)


def prepare():
    p=config_root();meta=json.loads((p/(NAME+'.json')).read_text());tid=meta['tunnel_id']
    if not re.fullmatch('tunnel_[A-Za-z0-9_-]+',tid):raise ValueError()
    for existing in ('buildbuddy','jev'):
        file=p/(existing+'.yaml')
        if file.exists() and json.loads(file.read_text())['control_plane']['tunnel_id']==tid:
            raise ValueError()
    key=p/'buildbuddy-secrets/openai-runtime-key'
    if key.stat().st_mode & 0o077 or key.stat().st_uid!=os.getuid():raise ValueError()
    command=os.environ['HISTORY_MCP_COMMAND']
    cfg={'config_version':1,'control_plane':{'base_url':'https://api.openai.com','tunnel_id':tid,'api_key':'file:'+str(key)},
         'mcp':{'commands':[{'channel':'main','command':command}],'stdio_send_initialized_notification':True},
         'health':{'listen_addr':'127.0.0.1:0','url_file':str(p/(NAME+'-health-url'))},'admin_ui':{'open_browser':False},'log':{'level':'info','format':'json'}}
    private_write(p/(NAME+'.yaml'),json.dumps(cfg,indent=2)+'\n');return p,tid


def main():
    os.umask(0o077);p=argparse.ArgumentParser();p.add_argument('action',choices=['configure','run','doctor','health']);p.add_argument('--tunnel-id');args=p.parse_args()
    try:
        root=config_root();binary=os.environ['HISTORY_TUNNEL_CLIENT']
        if args.action=='configure':
            meta=root/(NAME+'.json')
            if meta.exists() or not args.tunnel_id:raise ValueError()
            private_write(meta,json.dumps({'tunnel_id':args.tunnel_id})+'\n')
            try:prepare()
            except Exception:meta.unlink();raise
            print('History tunnel configured. Start buildbuddy-history-tunnel.service and its health timer.')
        elif args.action=='health':
            subprocess.run([binary,'health','--url-file',str(root/(NAME+'-health-url')),'--require-control-plane-poll'],check=True,capture_output=True,timeout=10)
            print('History tunnel ready and polling.')
        else:
            root,tid=prepare()
            if args.action=='run':
                runtime=Path(os.environ.get('XDG_RUNTIME_DIR',f'/run/user/{os.getuid()}'))
                fd=os.open(runtime/(NAME+'-'+tid+'.lock'),os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
                fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB);os.set_inheritable(fd,True)
                (root/(NAME+'-health-url')).unlink(missing_ok=True)
            env={k:v for k,v in os.environ.items() if not k.startswith(('CONTROL_PLANE_','MCP_','TUNNEL_CLIENT_','HEALTH_','CLOUDFLARED_')) and k not in ('OPENAI_API_KEY','OPENAI_ADMIN_KEY','JEV_KEY','TYPESAFE_API_KEY','ALLOW_REMOTE_UI','OPEN_WEB_UI')}
            os.execve(binary,[binary,args.action,'--profile-file',str(root/(NAME+'.yaml')),'--control-plane.max-inflight','2'],env)
    except Exception:
        sys.exit('History tunnel operation failed; check private metadata, permissions, or service status.')


if __name__=='__main__':main()
