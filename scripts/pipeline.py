#!/usr/bin/env python3
"""Local, staged AlienPing releases. No screen capture or TCC edits."""
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import time
from sign_app import configuration, sign

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = ROOT.parent
LIVE = OUTPUTS / 'AlienPing.app'
RELEASES = OUTPUTS / 'AlienPing-releases'
LOGS = Path.home() / 'Library/Logs/Psst'

def run(args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)

def match_pids(text, executable):
    found = set()
    for line in text.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and (parts[1] == executable or parts[1].startswith(executable+' ')):
            found.add(int(parts[0]))
    return found

def pids():
    return match_pids(subprocess.check_output(['ps','-axo','pid=,command='], text=True),str(LIVE/'Contents/MacOS/AlienPing'))

def stop():
    for pid in pids():
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
    until = time.monotonic()+10
    while pids() and time.monotonic()<until: time.sleep(.2)
    if pids(): raise RuntimeError('AlienPing did not quit gracefully. Installed app was not replaced.')

def fresh_status(state, running, started):
    try:
        return state['pid'] in running and datetime.fromisoformat(state['updatedAt'].replace('Z','+00:00')).timestamp() >= int(started)
    except (KeyError, TypeError, ValueError): return False

def swap_bundle(candidate, live, backup):
    if backup.exists(): raise RuntimeError('Backup destination already exists')
    had_old = live.exists()
    if had_old: live.rename(backup)
    try: candidate.rename(live)
    except BaseException:
        if had_old: backup.rename(live)
        raise

def verify(app):
    for rel in ['Contents/MacOS/AlienPing','Contents/Resources/AppIcon.icns']:
        if not (app/rel).is_file(): raise RuntimeError('Missing bundle resource: '+rel)
    resources=app/'Contents/Resources'
    if not (resources/'mascots.json').is_file() and not (resources/'Companions.png').is_file():
        raise RuntimeError('Missing companion resources')
    with (app/'Contents/Info.plist').open('rb') as f: info=plistlib.load(f)
    if info['CFBundleIdentifier'] != 'local.alienping.mac': raise RuntimeError('Unexpected app identity')
    run(['codesign','--verify','--deep','--strict',app])
    return info['CFBundleShortVersionString']

def launch(preview=False):
    started=time.time()
    command=['open','-n','-g',str(LIVE)]
    if preview: command+=['--args','--preview-all']
    run(command)
    deadline=time.monotonic()+20
    while time.monotonic()<deadline:
        try:
            state=json.loads((LOGS/'AlienPing-status.json').read_text())
            if fresh_status(state,pids(),started): return state,started
        except (OSError,json.JSONDecodeError): pass
        time.sleep(.4)
    raise RuntimeError('No fresh runtime heartbeat from the updated app')

def smoke(state,started):
    deadline=time.monotonic()+50
    while time.monotonic()<deadline:
        apps=set()
        for file in [LOGS/'AlienPing-diagnostics.jsonl.1', LOGS/'AlienPing-diagnostics.jsonl']:
            if not file.exists(): continue
            for line in file.read_text().splitlines():
                try: e=json.loads(line)
                except json.JSONDecodeError: continue
                if e.get('pid')==state['pid'] and e.get('preview') and e.get('event')=='message_presented':
                    if datetime.fromisoformat(e['time'].replace('Z','+00:00')).timestamp() >= int(started): apps.add(e['app'])
        if apps >= {'Claude','Codex'}: return
        time.sleep(.5)
    raise RuntimeError('Both preview delivery events were not observed; move the pointer off the card and retry')

def install_and_start(candidate,backup,preview,failed):
    try:
        swap_bundle(candidate,LIVE,backup)
    except BaseException:
        if LIVE.exists(): launch()
        raise
    try:
        return launch(preview)
    except BaseException:
        stop()
        LIVE.rename(failed)
        if backup.exists():
            backup.rename(LIVE)
            launch()
        raise

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['check','update','rollback'],nargs='?',default='update')
    parser.add_argument('--preview',action='store_true',help='Show and verify two synthetic notifications after launch')
    args=parser.parse_args()
    if args.action == "update" and (ROOT/"PROTOTYPE_ONLY").exists():
        raise SystemExit("This sprite prototype was rejected. Live AlienPing is unchanged. Use check to test the prototype; revise the artwork before releasing it.")
    RELEASES.mkdir(exist_ok=True)
    with (RELEASES/'pipeline.lock').open('w') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: raise SystemExit('Another AlienPing pipeline is running.')
        stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        release=RELEASES/stamp; release.mkdir()
        report={'action':args.action,'release':stamp,'steps':[], 'signing':configuration()['identity']}
        def step(label):
            print('\n'+label,flush=True); report['steps'].append(label)
        try:
            candidate=release/'AlienPing.app'
            if args.action == 'rollback':
                pointer=RELEASES/'rollback.json'
                old=Path(json.loads(pointer.read_text())['bundle'])
                if not old.is_relative_to(RELEASES) or not old.is_dir(): raise RuntimeError('No valid rollback bundle')
                step('Preparing previous version'); shutil.copytree(old,candidate,symlinks=True)
                sign(candidate)
            else:
                step('Testing notification behavior and update safety')
                run(['python3',ROOT/'scripts/test_pipeline.py'])
                run(['python3',ROOT/'scripts/test_signing.py'])
                run(['python3',ROOT/'scripts/validate_sprites.py'])
                run(['swift','run','--package-path',ROOT,'AlienCoreTests'])
                step('Building isolated candidate')
                run([ROOT/'build.sh'],env={**os.environ,'APP_OUTPUT':str(candidate)})
            report['version']=verify(candidate)
            step('Signature and resources verified')
            archive=release/'AlienPing.zip'
            run(['ditto','-c','-k','--sequesterRsrc','--keepParent',candidate,archive])
            if args.action == 'check':
                report['result']='candidate_verified'; print('Candidate ready; installed app unchanged.')
                return
            step('Backing up and updating installed app')
            stop()
            backup=release/'previous.app'
            state,started=install_and_start(candidate,backup,args.preview,release/'failed.app')
            if backup.exists():
                (RELEASES/'rollback.json').write_text(json.dumps({'bundle':str(backup)}))
            # Package canonical bundle name for distribution.
            run(['ditto','-c','-k','--sequesterRsrc','--keepParent',LIVE,OUTPUTS/'AlienPing.zip'])
            report['runtime']=state
            step('Fresh startup heartbeat verified')
            if args.preview:
                smoke(state,started); step('Claude and Codex preview delivery verified')
            report['result']='updated' if state.get('trusted') else 'updated_permission_required'
            if not state.get('trusted'): print('App updated. Accessibility permission is required for real notifications; preview still works.',flush=True)
            else: print('App updated and listening.',flush=True)
        except BaseException as exc:
            report['result']='failed'; report['error']=str(exc)
            raise
        finally:
            (release/'report.json').write_text(json.dumps(report,indent=2)+'\n')
            (RELEASES/'latest-report.json').write_text(json.dumps(report,indent=2)+'\n')
            print('Report: '+str(release/'report.json'),flush=True)

if __name__=='__main__': main()
