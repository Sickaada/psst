#!/usr/bin/env python3
"""Create a drag-to-Applications DMG and ZIP; no signing keys or runtime logs included."""
import hashlib,json,plistlib,shutil,subprocess,sys,tempfile
from pathlib import Path
from sign_app import sign
root=Path(__file__).resolve().parents[1]
app=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
info=plistlib.loads((app/'Contents/Info.plist').read_bytes());version=info['CFBundleShortVersionString']
if info['CFBundleIdentifier']!='local.alienping.mac':raise SystemExit('Unexpected app identity')
run=lambda args:subprocess.run([str(a) for a in args],check=True)
with tempfile.TemporaryDirectory(prefix='psst-package-') as d:
 stage=Path(d)/'Psst';stage.mkdir();bundle=stage/'Psst.app';shutil.copytree(app,bundle)
 # Keep release attribution and referenced assets synchronized with the source tree.
 shutil.rmtree(bundle/'Contents/Resources/Mascots')
 run([sys.executable,root/'scripts/copy_resources.py',bundle/'Contents/Resources'])
 sign(bundle)
 shutil.copy2(root/'GETTING_STARTED.txt',stage/'START HERE.txt');shutil.copy2(root/'LICENSE',stage/'LICENSE.txt')
 zipfile=out/f'Psst-{version}-universal.zip'
 if zipfile.exists():raise SystemExit('Release ZIP already exists; choose a fresh output directory')
 run(['ditto','-c','-k','--sequesterRsrc','--keepParent',stage,zipfile])
 (stage/'Applications').symlink_to('/Applications')
 dmg=out/f'Psst-{version}-universal.dmg'
 run(['hdiutil','create','-volname',f'Psst {version}','-srcfolder',stage,'-ov','-format','UDZO',dmg])
 hashes=[]
 for file in [zipfile,dmg]:hashes.append(hashlib.sha256(file.read_bytes()).hexdigest()+'  '+file.name)
 (out/'SHA256SUMS.txt').write_text('\n'.join(hashes)+'\n')
 print('Shareable packages:',out)
