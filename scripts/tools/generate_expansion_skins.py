import json
from pathlib import Path

root = Path(__file__).resolve().parents[2] / 'skins'
def tint(base, accent, amount):
    a = bytes.fromhex(base.lstrip('#'))
    b = bytes.fromhex(accent.lstrip('#'))
    return '#' + ''.join(f'{round(x * (1 - amount) + y * amount):02x}' for x,y in zip(a,b))
variants = [
 ('y2k-chrome','Y2K Chrome','#8ee8ff','metal', '<ellipse cx="256" cy="44" rx="160" ry="33" fill="url(#metal)"/><ellipse cx="256" cy="44" rx="140" ry="23" fill="#081a20"/><path d="M130 44h42l18-17 20 34 20-26 16 18 18-20 18 15h100" fill="none" stroke="ACCENT" stroke-width="3"/>'),
 ('neon-ronin','Neon Ronin / Anime','#e87aff','plastic', '<path d="M153 79l24-54 36-23 64 2 37 22 28 53-45-15-83 13z" fill="#241139" stroke="ACCENT"/><path d="M207 26q49-32 99 0l-11 35-39 26-39-26z" fill="#e8b8cc"/><path d="M184 40l34-38 86 4 23 39-39-24-17 19-12-18-24 22-5-23z" fill="#56326b" stroke="ACCENT"/><path d="M221 47l20-3m31 0 20 3" stroke="#321633" stroke-width="5"/><path d="M247 67q10 5 20 0" fill="none" stroke="#8d415e"/><path d="M179 12l-18 43m173-43 16 43" stroke="ACCENT" stroke-width="4"/>'),
 ('v12-redline','V12 Redline / Cars','#ff4c45','metal','<path d="M93 58l31-21 67-8 38-25h88l44 30 56 14 7 23H92z" fill="url(#metal)" stroke="ACCENT" stroke-width="2"/><path d="M203 29l29-19h75l30 23z" fill="#07161f" stroke="ACCENT"/><path d="M268 11v20M115 50h42m205 0h39" stroke="ACCENT" stroke-width="3"/><circle cx="173" cy="67" r="19" fill="#080b10" stroke="#82909c" stroke-width="4"/><circle cx="353" cy="67" r="19" fill="#080b10" stroke="#82909c" stroke-width="4"/><path d="M160 67h26m-13-13v26m167-13h26m-13-13v26" stroke="ACCENT" stroke-width="3"/>'),
 ('arsenal-titanium','Arsenal Titanium / Guns','#d5b984','mech','<path d="M112 22h235v-9h47v34H236l-24 38h-41l13-39h-72z" fill="url(#metal)" stroke="ACCENT" stroke-width="2"/><path d="M247 47v20h-30m27-13h-19m-43-2-8 26M135 30h181" fill="none" stroke="#10151a" stroke-width="5"/><path d="M330 16v29m12-29v29m12-29v29" stroke="ACCENT"/><path d="M115 18h42v-9h-31z" fill="#56616a"/>'),
 ('velvet-muse','Velvet Muse / Women','#f69baa','plastic','<path d="M163 85q8-56 30-66Q255-22 314 19q23 29 34 66l-44-5-97 4z" fill="#291e30" stroke="ACCENT"/><path d="M220 17q37-16 70 4l6 27-18 26-24 12-28-18-12-28z" fill="#e4bdc2"/><path d="M203 39q4-44 71-36l32 15-40 3-28 19-14-12-7 29z" fill="#473044"/><path d="M229 44l17-2m23 0 17 3" stroke="#311b30" stroke-width="4"/><path d="M247 65q12 7 25-1" fill="none" stroke="#9c465f" stroke-width="3"/><path d="M301 48v19m-87-17v19" stroke="ACCENT" stroke-width="3"/><circle cx="302" cy="72" r="4" fill="ACCENT"/>'),
 ('orbital-eva','Orbital EVA / Astronauts','#ffa761','metal','<path d="M180 83V39q3-37 77-38t77 38v44z" fill="url(#metal)" stroke="ACCENT" stroke-width="2"/><rect x="194" y="18" width="126" height="53" rx="24" fill="#101e2b" stroke="#8099ad" stroke-width="4"/><path d="M214 30q27-15 68-5" fill="none" stroke="ACCENT" stroke-width="4"/><path d="M194 82h126m-110-8v13m93-13v13" stroke="#8795a6" stroke-width="5"/><rect x="170" y="37" width="14" height="25" rx="4" fill="#8099ad"/><rect x="330" y="37" width="14" height="25" rx="4" fill="#8099ad"/>'),
 ('sentinel-head','Sentinel Head / Robots','#70eeec','mech','<path d="M197 9l60-8 61 8 18 30-14 39-65 10-64-10-15-39z" fill="url(#metal)" stroke="ACCENT" stroke-width="2"/><path d="M205 28h104l-7 27h-91z" fill="#070c13"/><path d="M214 39h28m30 0h28" stroke="ACCENT" stroke-width="7"/><path d="M224 69h66m-54-6v12m13-12v12m13-12v12m13-12v12" stroke="#10151d" stroke-width="4"/><path d="M257 1v18m-70 11-15 7v30l16 5m140-42 15 7v30l-16 5" fill="none" stroke="#849caf" stroke-width="5"/>'),
 ('xeno-pod','Xeno Pod / Weird Pods','#b3ef6f','plastic','<path d="M145 64Q157 2 256 1t111 63q-15 25-111 24T145 64z" fill="url(#metal)" stroke="ACCENT" stroke-width="2"/><ellipse cx="256" cy="42" rx="64" ry="32" fill="#0c211b" stroke="ACCENT"/><path d="M214 43q44-43 85 0-40 41-85 0z" fill="#466947"/><ellipse cx="257" cy="43" rx="8" ry="23" fill="ACCENT"/><path d="M162 62l29 11m139-11-29 11M176 36l15 7m144-7-15 7" stroke="ACCENT" stroke-width="4"/>'),
]
for slug,name,accent,surface,art in variants:
    defs = f'<defs><linearGradient id="metal" x2="0.15" y2="1"><stop stop-color="#74818f"/><stop offset=".22" stop-color="#d5dce3"/><stop offset=".28" stop-color="#323c48"/><stop offset=".6" stop-color="#596773"/><stop offset="1" stop-color="#131a23"/></linearGradient><linearGradient id="frame" x2="0" y2="1"><stop stop-color="#64717e"/><stop offset=".07" stop-color="#252d38"/><stop offset=".85" stop-color="#11151e"/><stop offset="1" stop-color="#424e5c"/></linearGradient></defs>'
    (root / f'{slug}-art.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="96" viewBox="0 0 512 96">{defs}<path d="M0 48h120m272 0h120" stroke="{accent}" stroke-opacity=".3"/>{art.replace("ACCENT",accent)}</svg>',encoding='utf-8')
    # The nine-sliced panel has transparent chamfers and moulded metal bevels.
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96">{defs}<path d="M16 1h64l15 15v64L80 95H16L1 80V16z" fill="url(#frame)" stroke="{accent}"/><path d="M17 5h62l12 12v62L79 91H17L5 79V17z" fill="none" stroke="#86939f" stroke-opacity=".3"/><path d="M14 22h68M14 74h68" stroke="{accent}" stroke-opacity=".2"/><circle cx="17" cy="17" r="2" fill="#090d13"/><circle cx="79" cy="17" r="2" fill="#090d13"/><circle cx="17" cy="79" r="2" fill="#090d13"/><circle cx="79" cy="79" r="2" fill="#090d13"/></svg>'
    (root/f'{slug}.svg').write_text(svg,encoding='utf-8')
    glyphs = {
      'y2k-chrome':['|<','>','||','>|'], 'neon-ronin':['<<','▷','Ⅱ','>>'],
      'v12-redline':['- REV','IGN','IDLE','REV +'], 'arsenal-titanium':['<<','ARM','SAFE','>>'],
      'velvet-muse':['‹','▶','Ⅱ','›'], 'orbital-eva':['|◁','▷','Ⅱ','▷|'],
      'sentinel-head':['[<]','[>]','[II]','[>>]'], 'xeno-pod':['‹‹','◈','◌','››'],
    }[slug]
    colors = dict(background=tint('#080b12',accent,.025),panel=tint('#202832',accent,.1),surface=tint('#35414d',accent,.14),border=tint('#697784',accent,.3),accent=accent,text=tint('#e4edf1',accent,.08),muted=tint('#93a4b2',accent,.18))
    data = dict(version=1,name=name,colors=colors,atlas=f'{slug}.svg',regions=dict(panel=[0,0,96,96]),margins=[20,20,20,20],chrome=dict(surface=surface,artwork=f'{slug}-art.svg',glyphs=glyphs))
    (root/f'{slug}.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
print('Generated eight original vector skin packages.')
