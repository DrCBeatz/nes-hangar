#!/usr/bin/env python3
"""Build Hangar from local 6502 sources, authored map and editable artwork.

Normal builds regenerate every included table and permit intentional changes.
--verify additionally requires byte identity with the accepted release ROM.
Python's standard library and ca65/ld65 are sufficient; Pillow is optional.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'src'
TOOLS = ROOT / 'tools'
BUILD = ROOT / 'build'
PREVIEWS = BUILD / 'previews'
ROM = BUILD / 'hangar-ntsc.nes'
REFERENCE = ROOT / 'release/hangar-ntsc.nes'
RELEASE_METADATA = ROOT / 'release/release.json'
STARTING_AMMO = 6


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def portable(value):
    """Keep metadata independent of the checkout's filesystem location."""
    if isinstance(value, dict):
        return {k: portable(v) for k,v in value.items()}
    if isinstance(value, (list,tuple)):
        return [portable(v) for v in value]
    if isinstance(value, str):
        return value.replace(str(ROOT) + '/', '')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='Require exact identity with the included accepted release')
    args = parser.parse_args()
    if sys.flags.optimize:
        raise SystemExit('Do not use python -O: build-time geometry/resource assertions are required.')
    sys.dont_write_bytecode = True
    sys.path.insert(0,str(TOOLS))
    BUILD.mkdir(parents=True,exist_ok=True)
    ca65,ld65 = shutil.which('ca65'),shutil.which('ld65')
    if not ca65 or not ld65:
        raise SystemExit('ca65 and ld65 are required. Install the cc65 toolchain and add it to PATH.')
    scene = json.loads((ROOT/'assets/map.json').read_text())
    door = load('door_reference',TOOLS/'door_reference.py')
    encounter_reference = load('encounter_reference',TOOLS/'encounter_reference.py')
    door_assets = door.write_assets(BUILD,scene)
    hazard = load('slime_damage_assets',TOOLS/'slime_damage.py').write_assets(BUILD,scene)
    scene['slime']['damageRule'] = hazard
    (BUILD/'map.json').write_text(json.dumps(scene,indent=2)+'\n')
    os.environ['E1M1_MAP_PATH'] = str(BUILD/'map.json')
    for wall in scene['segments']:
        assert wall['material'] in (1,2)
        assert (wall['nx'],wall['nz']) != (0,0)
        for end in (1,2):
            x,z=wall[f'x{end}'],wall[f'z{end}']
            assert 0<=x<=1023 and 0<=z<=1023
            assert wall['nx']*x+wall['nz']*z==wall['plane']
    art_module=load('hud_pistol_assets',TOOLS/'pistol_assets.py')
    art_module.HUD_NUMBERS=dict(art_module.HUD_NUMBERS)
    col,row,_=art_module.HUD_NUMBERS['ammo']
    art_module.HUD_NUMBERS['ammo']=(col,row,STARTING_AMMO)
    art=art_module.assets(BUILD)
    boot_names=bytearray((BUILD/'nametable.bin').read_bytes())
    heading_text='E1M1 / HANGAR PROTOTYPE'
    heading_col=(32-len(heading_text))//2
    boot_names[32:64]=bytes(32)
    boot_names[32+heading_col:32+heading_col+len(heading_text)]=bytes(art['fontMap'][c] for c in heading_text)
    controls_text='SELECT EDGES  START PAUSE'
    controls_col=(32-len(controls_text))//2
    boot_names[27*32:28*32]=bytes(32)
    boot_names[27*32+controls_col:27*32+controls_col+len(controls_text)]=bytes(art['fontMap'][c] for c in controls_text)
    (BUILD/'nametable.bin').write_bytes(boot_names)
    art['textLines']=[dict(row=27,col=controls_col,text=controls_text) if line['row']==27 else line for line in art['textLines']]
    art['textLines']=[dict(row=1,col=heading_col,text=heading_text) if line['row']==1 else line for line in art['textLines']]
    art['sha256']['nametable.bin']=sha(BUILD/'nametable.bin')
    (BUILD/'pistol-assets.json').write_text(json.dumps(art,indent=2)+'\n')
    patterns=(BUILD/'fixed-patterns.bin').read_bytes()
    art_module._previews(PREVIEWS,art_module._weapon_frames(),[patterns[i:i+16] for i in range(0,len(patterns),16)],boot_names,art)
    (BUILD/'balance-config.inc').write_text(f'PISTOL_STARTING_AMMO = {STARTING_AMMO}\n')
    zombie_art=load('zombie_assets',TOOLS/'zombie_assets.py').write_assets(BUILD,preview_dir=PREVIEWS)
    zombie_sizing=load('zombie_size',TOOLS/'zombie_size.py').write_assets(
        BUILD, [(v['width'], v['height']) for v in zombie_art['variants']])
    medkit_art=load('medkit_assets',TOOLS/'medkit_assets.py').write_assets(BUILD,preview_dir=PREVIEWS)
    ammo_art=load('ammo_assets',TOOLS/'ammo_assets.py').write_assets(BUILD,preview_dir=PREVIEWS)
    corpse_art=load('corpse_assets',TOOLS/'corpse_assets.py').write_assets(BUILD,preview_dir=PREVIEWS)
    assert [v['width'] for v in corpse_art['variants']] == [v['width'] for v in zombie_art['variants']]
    (BUILD/'medkit-assets.json').write_text(json.dumps(medkit_art,indent=2)+'\n')
    (BUILD/'ammo-assets.json').write_text(json.dumps(ammo_art,indent=2)+'\n')
    kit=scene['medkit']
    (BUILD/'medkit-config.inc').write_text(''.join('MEDKIT_'+k.upper()+' = '+str(kit[k])+'\n' for k in ('x','z','floor','heal','maximum_health','pickup_radius')))
    ammo=scene['ammo']
    (BUILD/'ammo-config.inc').write_text(''.join('AMMO_'+k.upper()+' = '+str(ammo[k])+'\n' for k in ('x','z','floor','amount','maximum','pickup_radius')))
    font=art['fontMap']
    results_layout=load('results_assets',TOOLS/'results_assets.py').write_assets(BUILD,font,enemy_total=len(scene['encounters']))
    title_layout=load('title_assets',TOOLS/'title_assets.py').write_assets(BUILD,font,PREVIEWS)
    death_text='YOU DIED - START TO RESTART'
    death_line=[0]*32
    start=(32-len(death_text))//2
    death_line[start:start+len(death_text)]=[font[c]for c in death_text]
    def centered(text):
        assert len(text)<=32
        row=[0]*32
        start=(32-len(text))//2
        row[start:start+len(text)]=[font[c]for c in text]
        return row
    door_text='PRESS A TO OPEN'
    door_line=centered(door_text)
    exit_text='PRESS A TO EXIT'
    complete_text='LEVEL COMPLETE - PRESS START'
    exit_line=centered(exit_text)
    complete_line=centered(complete_text)
    pause_text='PAUSED - PRESS START'
    pause_line=centered(pause_text)
    title_line=list((BUILD/'nametable.bin').read_bytes()[32:64])
    (BUILD/'pause-title.inc').write_text('PAUSE_TITLE_ADDR = $2020\n'+
        'pause_title_normal: .byte '+','.join(map(str,title_line))+'\n'+
        'pause_title_paused: .byte '+','.join(map(str,pause_line))+'\n')
    normal_line=list((BUILD/'nametable.bin').read_bytes()[25*32:26*32])
    (BUILD/'player-feedback.inc').write_text('HUD_MESSAGE_ADDR = $2320\n'+
        'player_alive_line: .byte '+','.join(map(str,normal_line))+'\n'+
        'player_dead_line: .byte '+','.join(map(str,death_line))+'\n'+
        'player_exit_line: .byte '+','.join(map(str,exit_line))+'\n'+
        'player_door_line: .byte '+','.join(map(str,door_line))+'\n'+
        'player_complete_line: .byte '+','.join(map(str,complete_line))+'\n'+
        'player_pause_line: .byte '+','.join(map(str,pause_line))+'\n')
    player_feedback={'messageRow':25,'messageWidth':32,'normalTiles':normal_line,'deadTiles':death_line,
                     'deathMessage':death_text,'hurtColor':0x16,'normalColor':0x30,'hurtFrames':12,
                     'doorTiles':door_line,'doorMessage':door_text,'pauseTiles':pause_line,'pauseMessage':pause_text,
                     'exitTiles':exit_line,'completeTiles':complete_line,
                     'exitMessage':exit_text,'completeMessage':complete_text}
    exit_config=scene['exit']
    assert exit_config['x_max_exclusive'] and exit_config['z_max_inclusive']
    (BUILD/'exit-config.inc').write_text('; Live Q16.8 eligibility: X maximum exclusive, Z maximum inclusive.\n'+
        ''.join('EXIT_'+name.upper()+' = '+str(exit_config[name])+'\n'
                for name in ('x_min','x_max','z_min','z_max','angle_min','angle_max')))

    enemy=scene['enemy']
    (BUILD/'zombie-config.inc').write_text(f"ZOMBIE_X = {enemy['x']}\nZOMBIE_Z = {enemy['z']}\nZOMBIE_FLOOR = {enemy['floor']}\n")
    (BUILD/'world-palette.bin').write_bytes(bytes([0x0F,0x17,0x07,0x2D]))
    assert len((BUILD/'fixed-patterns.bin').read_bytes())==1024
    solids=b''.join(bytes([255 if v & 1 else 0])*8+bytes([255 if v & 2 else 0])*8 for v in range(4))
    assert (BUILD/'fixed-patterns.bin').read_bytes()[:64]==solids
    assert len((BUILD/'nametable.bin').read_bytes())==1024
    print('Generating geometry and visibility tables...', flush=True)
    generated={stem:load(stem,TOOLS/(stem+'.py')).write_assets(BUILD,recess_depth=scene['recess_depth'])
               for stem in ('movement_reference','geometry_reference')}
    generated['innerVisibility']=load('inner_visibility',TOOLS/'inner_visibility.py').write_assets(BUILD,scene)
    visibility=load('rooms_visibility',TOOLS/'visibility.py')
    generated['visibility']=visibility.write_assets(BUILD,scene)
    generated['collisionVisibility']=visibility.write_collision_assets(BUILD,scene)
    generated['enemyAI']=load('pursuit_ai_reference',TOOLS/'ai_reference.py').write_assets(BUILD)
    generated['encounters']=encounter_reference.write_assets(BUILD)
    flags=['STEP','NTSC','NTSC_OPT','NTSC_LATENCY','COMPACT_SPANS','STRIP_ACTIVE',
           'LATENCY_RESTART','LATENCY_HEIGHT_PRIORITY','HUD_PISTOL','COMBAT','COMBAT_GROUNDED','ZOMBIE']
    defines=[arg for flag in flags for arg in ('-D',flag+'=1')]+['-D','FRESHNESS_MARGIN=0']
    modules=[SOURCE/'walkable.s',SOURCE/'geometry.s',SOURCE/'movement.s',SOURCE/'raster.s',
             SOURCE/'ntsc_movement.s',SOURCE/'ntsc_upload.s',SOURCE/'freshness.s',
             SOURCE/'latency_restart.s',SOURCE/'pistol.s',
             SOURCE/'zombie_render.s',SOURCE/'zombie_gameplay.s',SOURCE/'zombie_ai.s',SOURCE/'zombie_attack.s',SOURCE/'door.s',SOURCE/'exit.s',SOURCE/'medkit.s',SOURCE/'medkit_render.s',SOURCE/'corpse_prepare.s',SOURCE/'corpse_fast.s',SOURCE/'prg_banks.s',SOURCE/'coordinate_math.s',SOURCE/'encounters.s',SOURCE/'encounter_select.s',SOURCE/'slime_damage.s',SOURCE/'results.s',SOURCE/'results_screen.s',SOURCE/'pause.s',SOURCE/'title.s']
    for source in modules:
        subprocess.run([ca65,'-g',*defines,'-I',str(BUILD),'-l',source.stem+'.lst',
                        '-o',source.stem+'.o',os.path.relpath(source,BUILD)],cwd=BUILD,check=True)
    subprocess.run([ld65,'-C',str(SOURCE/'hangar.cfg'),'-o',str(ROM),
                    '-m','hangar.map','--dbgfile','hangar.dbg','-Ln','hangar.lbl',
                    *[p.stem+'.o' for p in modules]],cwd=BUILD,check=True)
    data=ROM.read_bytes()
    assert len(data)==65552
    assert data[:16]==b'NES\x1a\x04\x00\x10\x08\x00\x00\x07\x07\x00\x00\x00\x00'
    sizes={}
    for line in (BUILD/'hangar.map').read_text().splitlines():
        m=re.fullmatch(r'(ZEROPAGE|BSS|CODE|RODATA|MAPDATA|ACTOR_ART|BOOTDATA|STARTUP)\s+[0-9A-F]{6}\s+[0-9A-F]{6}\s+([0-9A-F]{6})\s+[0-9A-F]+',line)
        if m:sizes[m[1]]=int(m[2],16)
    assert set(sizes)=={'ZEROPAGE','BSS','CODE','RODATA','MAPDATA','ACTOR_ART','BOOTDATA','STARTUP'}
    assert sizes['ZEROPAGE']<=256 and sizes['BSS']<=1536
    # Common routines/data have identical CPU addresses in every switchable
    # bank. Copy the linked common window and the fixed-bank reset trampoline.
    # The latter establishes a known mapping even with non-default power-on mode.
    assert sizes['RODATA'] <= 0x1FF0
    assert sizes['CODE'] <= 0x3FF0 and sizes['STARTUP'] <= 10
    assert all(sizes[n] <= 0x2000 for n in ('MAPDATA','ACTOR_ART','BOOTDATA'))
    packed=bytearray(data)
    common=data[16+0x2000:16+0x4000]
    startup=data[16+0xFFF0:16+0x10000]
    for bank in range(3):
        offset=16+bank*0x4000
        packed[offset+0x2000:offset+0x4000]=common
        packed[offset+0x3FF0:offset+0x4000]=startup
    ROM.write_bytes(packed)
    data=bytes(packed)
    # Verify common data and reset-vector trampolines in each physical bank.
    for bank in range(3):
        offset=16+bank*0x4000
        assert data[offset+0x2000:offset+0x3FF0] == common[:0x1FF0]
        assert data[offset+0x3FF0:offset+0x4000] == startup
    source_files = sorted(p for directory in (SOURCE,TOOLS,ROOT/'assets')
                          for p in directory.rglob('*')
                          if p.is_file() and '__pycache__' not in p.parts)
    report = dict(rom='build/hangar-ntsc.nes', sha256=sha(ROM), bytes=len(data),
        region='NTSC', mapper='MMC1', prgBytes=65536, chrRamBytes=8192, workRamBytes=8192,
        viewport=[256,144], worldGeometryColumns=128, segmentBytes=sizes,
        initialHealth=100, initialAmmo=STARTING_AMMO,
        map='assets/map.json', title=title_layout, results=results_layout,
        artwork=dict(pistol=art,zombie=zombie_art,medkit=medkit_art,ammo=ammo_art,corpse=corpse_art),
        playerFeedback=player_feedback, zombieSizing=zombie_sizing,
        generated=generated, door=door_assets, slime=hazard,
        sources={str(p.relative_to(ROOT)):sha(p) for p in source_files},
        tools={name:subprocess.run([tool,'--version'],capture_output=True,text=True,check=True).stderr.strip()
               for name,tool in [('ca65',ca65),('ld65',ld65)]})
    (BUILD/'manifest.json').write_text(json.dumps(portable(report),indent=2)+'\n')
    # Asset generators also emit small proof/preview reports.
    for path in BUILD.rglob('*.json'):
        path.write_text(json.dumps(portable(json.loads(path.read_text())),indent=2)+'\n')
    if args.verify:
        if not REFERENCE.exists():
            raise SystemExit('Missing release/hangar-ntsc.nes reference ROM.')
        if not RELEASE_METADATA.exists():
            raise SystemExit('Missing release/release.json metadata.')
        release=json.loads(RELEASE_METADATA.read_text())
        if sha(REFERENCE) != release['sha256']:
            raise SystemExit('Reference release checksum differs from release/release.json.')
        if 'bytes' in release and REFERENCE.stat().st_size != release['bytes']:
            raise SystemExit('Reference release size differs from release/release.json.')
        if data != REFERENCE.read_bytes():
            raise SystemExit('Built ROM differs from the accepted release. Omit --verify for an intentional modified build.')
        print('Verified: byte-identical to the accepted release.')
    print(f'{ROM.relative_to(ROOT)}: {len(data)} bytes; SHA256 {sha(ROM)}')


if __name__ == '__main__':
    main()
