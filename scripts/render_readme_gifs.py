"""Render the bundled animation frames, without capturing the screen. Requires Pillow."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
root=Path(__file__).resolve().parents[1]
out=root/'docs/images';out.mkdir(parents=True,exist_ok=True)
manifest=json.loads((root/'Resources/mascots.json').read_text())
styles=['running','chasing','parkour','delivery','portal','peekaboo','celebration','floating']
font=ImageFont.load_default(size=18)
for row in range(2):
    frames=[]
    chosen=styles[row*4:row*4+4]
    sheets={(c['id'],s):Image.open(root/'Resources'/c['animations'][s]['sheets']['east']).convert('RGBA') for c in manifest['characters'] for s in chosen}
    for i in range(64):
        canvas=Image.new('RGB',(800,250),'#eef2f7');d=ImageDraw.Draw(canvas)
        for j,s in enumerate(chosen):
            d.text((j*200+16,16),s.capitalize(),fill='#223047',font=font)
            for k,c in enumerate(manifest['characters']):
                sprite=sheets[c['id'],s].crop((i*192,0,(i+1)*192,192)).resize((128,128),Image.Resampling.LANCZOS)
                canvas.paste(sprite,(j*200+(0 if k==0 else 74),55+(0 if k==0 else 54)),sprite)
        frames.append(canvas)
    frames[0].save(out/f'animations-{row+1}.gif',save_all=True,append_images=frames[1:],duration=42,loop=0,optimize=True)
    if row==0: frames[18].save(out/'companions.png')
print('Rendered all eight bundled styles; no screen capture.')
