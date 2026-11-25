#!/usr/bin/env python3
"""Package only assets referenced by the manifest and their attribution."""
import json,shutil,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'Resources';target=Path(sys.argv[1]);manifest=json.loads((root/'mascots.json').read_text())
paths={p for c in manifest['characters'] for a in c['animations'].values() for p in a['sheets'].values()}
paths.update(manifest['arrivalEffect']['sheets'].values())
paths.update(['Mascots/LICENSES.txt','Mascots/sources.json','vine-botanical.png'])
for path in sorted(paths):
 if Path(path).is_absolute() or '..' in Path(path).parts:raise ValueError('Unsafe asset path')
 destination=target/path;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/path,destination)
