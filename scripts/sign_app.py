#!/usr/bin/env python3
"""Sign all AlienPing releases with the same local certificate. Never fall back to ad hoc."""
import json,re,subprocess,sys
from pathlib import Path
CONFIG=Path.home()/'Library/Application Support/AlienPing/signing.json'
def configuration(path=CONFIG):
 value=json.loads(path.read_text())
 if not re.fullmatch(r'[0-9A-Fa-f]{40}',value.get('identity','')):raise ValueError('A pinned code-signing certificate is required; ad-hoc signing is disabled.')
 if not isinstance(value.get('keychain'),str) or not value['keychain'].startswith('/'):raise ValueError('Expected absolute signing keychain path')
 return value
def sign(app):
 config=configuration()
 requirement='designated => identifier "local.alienping.mac" and certificate leaf = H"'+config['identity']+'"'
 subprocess.run(['codesign','--force','--sign',config['identity'],'--keychain',config['keychain'],'--requirements','='+requirement,'--timestamp=none',str(app)],check=True)
 subprocess.run(['codesign','--verify','--deep','--strict','-R','='+requirement.removeprefix('designated => '),str(app)],check=True)
if __name__=='__main__':sign(Path(sys.argv[1]))
