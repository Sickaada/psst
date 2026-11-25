#!/usr/bin/env python3
"""Manifest structure and asset inventory checks, without third-party dependencies."""
import json,struct,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'Resources'
m=json.loads((root/'mascots.json').read_text())
paths=set()
for c in m['characters']:
 for name,a in c['animations'].items():
  assert 0 < a['fps'] <= 120
  assert all(0 <= i < a['frameCount'] for i in a['sequence'])
  for direction,path in a['sheets'].items():
   p=root/path;data=p.read_bytes();assert data[:8]==b'\x89PNG\r\n\x1a\n'
   w,h=struct.unpack('>II',data[16:24]);assert (w,h)==(a['cellWidth']*a['frameCount'],a['cellHeight'])
   assert data[25] == 6,'Expected RGBA PNG'
   paths.add(path)
 print(c['id'], {name:{'uniqueFrames':a['frameCount'],'timelineSteps':len(a['sequence']),'fps':a['fps']} for name,a in c['animations'].items()})
fx=m['arrivalEffect'];path=root/fx['sheets']['east'];data=path.read_bytes();assert struct.unpack('>II',data[16:24])==(fx['cellWidth']*fx['frameCount'],fx['cellHeight'])
print('Validated',len(paths)+1,'sprite sheets;',sum((root/p).stat().st_size for p in paths)+path.stat().st_size,'bytes')
