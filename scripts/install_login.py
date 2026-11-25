#!/usr/bin/env python3
"""Start the canonical AlienPing app once per graphical login, without keeping it alive."""
import os,plistlib,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
app=root.parent/'Psst.app'
if not app.is_dir():app=root.parent/'AlienPing.app'
if not app.is_dir():raise SystemExit('Build/install AlienPing first')
label='local.alienping.login'
path=Path.home()/'Library/LaunchAgents'/f'{label}.plist'
path.parent.mkdir(parents=True,exist_ok=True)
data={'Label':label,'ProgramArguments':['/usr/bin/open','-g',str(app),'--args','--login-item'],'RunAtLoad':True,'LimitLoadToSessionType':'Aqua','ProcessType':'Background'}
path.write_bytes(plistlib.dumps(data));path.chmod(0o644)
subprocess.run(['plutil','-lint',str(path)],check=True)
domain=f'gui/{os.getuid()}'
subprocess.run(['launchctl','bootout',f'{domain}/{label}'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['launchctl','enable',f'{domain}/{label}'],check=True)
subprocess.run(['launchctl','bootstrap',domain,str(path)],check=True)
print(f'Login startup installed: {path}')
