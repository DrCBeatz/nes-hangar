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
    logo_module = load('newtitle_logo', TOOLS/'newtitle_logo.py')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-music', action='store_true', help='Build the same bank layout with music updates disabled')
    parser.add_argument('--no-exact-arithmetic', action='store_true', help='Disable exact arithmetic shortcuts for comparison')
    parser.add_argument('--no-upload-completion', action='store_true', help='Keep the original upload-completion schedule for comparison')
    parser.add_argument('--no-stream-upload', action='store_true', help='Use the accepted per-block pattern uploader for comparison')
    parser.add_argument('--no-pattern8', action='store_true', help='Retain the seven-slot streaming uploader for comparison')
    parser.add_argument('--no-floor-projector', action='store_true', help='Retain the general cosmetic floor projector for exact comparison')
    parser.add_argument('--no-setup-checkpoint', action='store_true', help='Retain raster-only input restart checkpoints for comparison')
    parser.add_argument('--no-quotient16', action='store_true', help='Retain original24/32iteration exact divider for comparison')
    parser.add_argument('--no-masked-paint', action='store_true', help='Retain generic partial-tile paint composition for exact comparison')
    parser.add_argument('--no-camera-retry', action='store_true', help='Retain actor-sensitive soft-retry predicate for comparison')
    parser.add_argument('--no-sprite-mask', action='store_true', help='Retain the general per-row sprite visibility loop for comparison')
    parser.add_argument('--verify', action='store_true', help='Require exact identity with the included accepted release')
    parser.add_argument('--title-palette', choices=logo_module.PALETTES, default=logo_module.DEFAULT_PALETTE,
                        help='Logo colours only; guide and gameplay stay unchanged (default: bronze)')
    args = parser.parse_args()
    if args.no_stream_upload and not args.no_pattern8:
        parser.error('The guarded eighth pattern block requires streaming; use --no-pattern8 with --no-stream-upload.')
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
        # Early axis rejection depends on the existing positive-facing winding.
        dx,dz=wall['x2']-wall['x1'],wall['z2']-wall['z1']
        assert dx*wall['nx']+dz*wall['nz']==0
        assert dx*wall['nz']-dz*wall['nx']>0
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
    # The shared pickup square tables measure conservative eighth-unit deltas.
    # Emit an integer threshold so fractional radii need no new runtime math.
    ammo_radius_eighths=ammo['pickup_radius']*8
    assert ammo_radius_eighths==int(ammo_radius_eighths) and 0<ammo_radius_eighths<=31*8
    (BUILD/'ammo-config.inc').write_text(''.join('AMMO_'+k.upper()+' = '+str(ammo[k])+'\n' for k in ('x','z','floor','amount','maximum'))
        +f'AMMO_PICKUP_RADIUS_EIGHTHS = {int(ammo_radius_eighths)}\n')
    font=art['fontMap']
    results_layout=load('results_assets',TOOLS/'results_assets.py').write_assets(BUILD,font,enemy_total=len(scene['encounters']))
    title_layout=load('title_assets',TOOLS/'title_assets.py').write_assets(BUILD,font,PREVIEWS,logo_palette=args.title_palette)
    credits_layout=load('credits_assets',TOOLS/'credits_assets.py').write_assets(BUILD,font,preview_dir=PREVIEWS)
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
    if not args.no_sprite_mask:
        # $FF is reserved for the compositor's nonuniform-cutoff fallback.
        # Check all users of its shared row-mask path, including padded rows.
        for filename in ('zombie-assets.json', 'corpse-assets.json', 'medkit-assets.json', 'ammo-assets.json'):
            variants = json.loads((BUILD/filename).read_text())['variants']
            assert all(0 < v['height'] < 255 and ((v['height']+7)//8)*8 < 255 for v in variants), filename
    defines=[arg for flag in flags for arg in ('-D',flag+'=1')]+['-D','FRESHNESS_MARGIN=0','-D',f'MUSIC_ENABLED={0 if args.no_music else 1}']
    defines += ['-D', f'EXACT_ARITHMETIC={0 if args.no_exact_arithmetic else 1}',
                '-D', f'UPLOAD_COMPLETION_FAST={0 if args.no_upload_completion else 1}',
                '-D', f'STREAM_PATTERN_UPLOAD={0 if args.no_stream_upload else 1}',
                '-D', f'GUARDED_PATTERN8={0 if args.no_pattern8 else 1}',
                '-D', f'FLOOR_PROJECTOR={0 if args.no_floor_projector else 1}',
                '-D', f'SETUP_CHECKPOINT={0 if args.no_setup_checkpoint else 1}',
                '-D', f'QUOTIENT16={0 if args.no_quotient16 or args.no_exact_arithmetic else 1}',
                '-D', f'MASKED_PAINT={0 if args.no_masked_paint else 1}',
                '-D', f'CAMERA_RETRY={0 if args.no_camera_retry else 1}',
                '-D', f'SPRITE_MASK={0 if args.no_sprite_mask else 1}']
    modules=[SOURCE/'walkable.s',SOURCE/'geometry.s',SOURCE/'movement.s',SOURCE/'raster.s',
             SOURCE/'ntsc_movement.s',SOURCE/'ntsc_upload.s',SOURCE/'freshness.s',
             SOURCE/'latency_restart.s',SOURCE/'pistol.s',
             SOURCE/'zombie_render.s',SOURCE/'zombie_gameplay.s',SOURCE/'zombie_ai.s',SOURCE/'zombie_attack.s',SOURCE/'door.s',SOURCE/'exit.s',SOURCE/'medkit.s',SOURCE/'medkit_render.s',SOURCE/'corpse_prepare.s',SOURCE/'corpse_fast.s',SOURCE/'prg_banks.s',SOURCE/'coordinate_math.s',SOURCE/'encounters.s',SOURCE/'encounter_select.s',SOURCE/'slime_damage.s',SOURCE/'results.s',SOURCE/'results_screen.s',SOURCE/'pause.s',SOURCE/'title.s',SOURCE/'credits.s',SOURCE/'world_reuse.s',SOURCE/'music.s',SOURCE/'audio.s',SOURCE/'axis_gate.s']
    for source in modules:
        subprocess.run([ca65,'-g',*defines,'-I',str(BUILD),'-I',str(ROOT/'vendor/famistudio'),'-l',source.stem+'.lst',
                        '-o',source.stem+'.o',os.path.relpath(source,BUILD)],cwd=BUILD,check=True)
    subprocess.run([ld65,'-C',str(SOURCE/'hangar.cfg'),'-o',str(ROM),
                    '-m','hangar.map','--dbgfile','hangar.dbg','-Ln','hangar.lbl',
                    *[p.stem+'.o' for p in modules]],cwd=BUILD,check=True)
    data=ROM.read_bytes()
    assert len(data)==131088
    assert data[:16]==b'NES\x1a\x08\x00\x10\x08\x00\x00\x07\x07\x00\x00\x00\x00'
    sizes={}
    for line in (BUILD/'hangar.map').read_text().splitlines():
        m=re.fullmatch(r'(ZEROPAGE|BSS|CODE|AUDIO_CODE|AUDIO_ENGINE|AUDIO_DRIVER|AUDIO_SETTINGS|AUDIO_ZP|RENDER_CODE|RODATA|MAPDATA|ACTOR_ART|BOOTDATA|CREDITSDATA|WORLD_REUSE_RAM|WORLD_REUSE_CODE|AXIS_INIT|STARTUP)\s+[0-9A-F]{6}\s+[0-9A-F]{6}\s+([0-9A-F]{6})\s+[0-9A-F]+',line)
        if m:sizes[m[1]]=int(m[2],16)
    assert set(sizes)-{'AUDIO_CODE','AUDIO_ENGINE','AUDIO_DRIVER','AUDIO_SETTINGS','AUDIO_ZP','WORLD_REUSE_RAM','WORLD_REUSE_CODE','AXIS_INIT'}=={'ZEROPAGE','BSS','CODE','RENDER_CODE','RODATA','MAPDATA','ACTOR_ART','BOOTDATA','CREDITSDATA','STARTUP'}
    assert sizes['ZEROPAGE']<=256 and sizes['BSS']<=1536
    audio_ram_bytes=sum(sizes[n] for n in ('AUDIO_ENGINE','AUDIO_DRIVER','AUDIO_SETTINGS'))
    assert audio_ram_bytes+sizes['WORLD_REUSE_RAM']<=216 and sizes['AUDIO_ZP']<=8 and sizes['AUDIO_SETTINGS']==1
    # Common routines/data have identical CPU addresses in every switchable
    # bank. Copy the linked common window and the fixed-bank reset trampoline.
    # The latter establishes a known mapping even with non-default power-on mode.
    assert sizes['RODATA'] <= 0x1FF0
    assert sizes['CODE']+sizes.get('AUDIO_CODE',0) <= 0x3FF0 and sizes['STARTUP'] <= 10
    assert all(sizes[n] <= 0x2000 for n in ('MAPDATA','ACTOR_ART','BOOTDATA','CREDITSDATA'))
    packed=bytearray(data)
    common=data[16+0x2000:16+0x4000]
    startup=data[16+7*0x4000+0x3FF0:16+8*0x4000]
    # Bank3 is a phase overlay: setup-only visibility tables are dead once
    # geometry_begin returns. Preserve every other byte of the linked map,
    # including per-column slime/occlusion code and segment material tables.
    labels={m[2]:int(m[1],16) for line in (BUILD/'hangar.lbl').read_text().splitlines()
            if (m:=re.fullmatch(r'al ([0-9A-Fa-f]+) \.(\S+)',line))}
    assert labels['__AUDIO_ENGINE_RUN__']==labels['audio_workspace']==0x543
    assert labels['__AUDIO_DRIVER_RUN__']+sizes['AUDIO_DRIVER']<=labels['audio_workspace_end']
    assert labels['__AUDIO_SETTINGS_RUN__']==labels['music_disabled']==labels['audio_driver_end']
    assert labels['music_disabled']+sizes['AUDIO_SETTINGS']<=labels['audio_workspace_end']
    assert labels['__AUDIO_ZP_RUN__']==labels['movement_scratch_begin']==0xB9
    assert sizes['WORLD_REUSE_RAM']==5 and sizes['WORLD_REUSE_CODE']<=0x2000
    assert labels['__WORLD_REUSE_RAM_RUN__']==labels['music_disabled']+1
    assert labels['__WORLD_REUSE_RAM_RUN__']+5<=labels['audio_workspace_end']
    assert labels['__WORLD_REUSE_CODE_LOAD__']==0x8000
    assert labels['__AXIS_INIT_LOAD__']==labels['axis_gate_init']==0x8000
    assert sizes['AXIS_INIT']==labels['axis_gate_init_end']-labels['axis_gate_init']<=0x2000
    assert 0xC000 <= labels['axis_gate_begin'] < 0xFFF0
    assert labels['axis_gate_end'] <= 0xA000
    assert labels['axis_gate'] >= labels['map_render_overlay_end']
    assert labels['gate_axis_offset']==labels['opening_candidate']
    assert labels['gate_polarity'] < labels['opening_cache']
    assert 0xA000 <= labels['title_credits_gateway'] < 0xBFF0
    assert 0x8000 <= labels['credits_present'] < 0xA000
    assert labels['__CREDITSDATA_SIZE__'] == sizes['CREDITSDATA']
    render_start=labels['__RENDER_CODE_LOAD__']
    render_size=labels['__RENDER_CODE_SIZE__']
    render_end=render_start+render_size
    assert render_size==sizes['RENDER_CODE'] and render_size<=0x1100
    assert labels['map_render_overlay_start']<=render_start<render_end<=labels['map_render_overlay_end']
    assert render_start<=labels['geometry_column']<render_end
    # Reset-only code may use bank2; NMI audio and all song data must remain fixed.
    for name in ('famistudio_init','famistudio_music_stop','famistudio_music_play',
                 'famistudio_music_pause','music_init_banked','pistol_init','zombie_init','pause_init'):
        assert 0x8000 <= labels[name] < 0xA000, name
    for name in ('music_init','music_tick','famistudio_update','famistudio_get_note_pitch',
                 'famistudio_sample_stop','music_data_untitled','movement_init'):
        assert 0xC000 <= labels[name] < 0xFFF0, name
    for name in ('geometry_zombie_transform','zombie_occlude','zombie_compare_inverse'):
        assert render_start <= labels[name] < render_end, name
    assert 0x8000<=labels['slime_visibility_exact']<labels['slime_column_visible']<=render_start
    render_offset=16+3*0x4000
    overlay_lo,overlay_hi=render_start-0x8000,render_end-0x8000
    render_code=data[render_offset+overlay_lo:render_offset+overlay_hi]
    packed[render_offset:render_offset+0x2000]=data[16:16+0x2000]
    packed[render_offset+overlay_lo:render_offset+overlay_hi]=render_code
    assert packed[render_offset:render_offset+overlay_lo]==data[16:16+overlay_lo]
    assert packed[render_offset+overlay_hi:render_offset+0x2000]==data[16+overlay_hi:16+0x2000]
    for bank in range(7):
        offset=16+bank*0x4000
        packed[offset+0x2000:offset+0x4000]=common
        packed[offset+0x3FF0:offset+0x4000]=startup
    ROM.write_bytes(packed)
    data=bytes(packed)
    # Verify common data and reset-vector trampolines in each physical bank.
    for bank in range(7):
        offset=16+bank*0x4000
        assert data[offset+0x2000:offset+0x3FF0] == common[:0x1FF0]
        assert data[offset+0x3FF0:offset+0x4000] == startup
    source_files = sorted(p for directory in (SOURCE,TOOLS,ROOT/'assets',ROOT/'music',ROOT/'vendor')
                          for p in directory.rglob('*')
                          if p.is_file() and '__pycache__' not in p.parts
                          and not any(part.startswith('.') for part in p.relative_to(ROOT).parts))
    report = dict(rom='build/hangar-ntsc.nes', sha256=sha(ROM), bytes=len(data),
        rendererOptimizations=dict(geometryListPixels=16,
                        exactPositionAxisGate=True, axisInitBank=6, axisScratchBytes=4,
                        cameraRetry=not args.no_camera_retry,
                        spriteMask=not args.no_sprite_mask, maskedPaint=not args.no_masked_paint,
                        exactArithmetic=not args.no_exact_arithmetic,
                        uploadCompletion=not args.no_upload_completion,
                        streamPatternUpload=not args.no_stream_upload,
                        guardedPattern8=not args.no_pattern8,
                        cachedFloorProjector=not args.no_floor_projector,
                        geometrySetupCheckpoint=not args.no_setup_checkpoint,
                        quotient16=not (args.no_quotient16 or args.no_exact_arithmetic),
                        reclaimedLegacyHelpers=True),
        region='NTSC', mapper='MMC1', prgBytes=131072, chrRamBytes=8192, workRamBytes=8192,
        viewport=[256,144], worldGeometryColumns=128, segmentBytes=sizes,
        music=dict(enabled=not args.no_music, engine='FamiStudio', channels=4, dpcm=False,
                   song='E1M1 (Dr. C Beatz arrangement)', source='music/e1m1/e1m1-drcbeatz.s',
                   sourceSha256=sha(ROOT/'music/e1m1/e1m1-drcbeatz.s'),
                   features=dict(famiTrackerTempo=False, volumeTrack=True, vibrato=True, dutyCycleEffect=False),
                   ramBytes=audio_ram_bytes, zpAliasBytes=sizes['AUDIO_ZP'],
                   playerOption=dict(screen='controls guide', default='on' if not args.no_music else 'off',
                                     left='off', right='on' if not args.no_music else 'off',
                                     skipsSequencerWhenOff=True, preservesSoundEffects=True,
                                     survivesLevelRestart=True, coldResetRestoresDefault=True)),
        banking=dict(fixedBank=7, mapBank=0, artBank=1, bootBank=2, renderBank=3, creditsBank=4,
                     worldReuseBank=5, axisInitBank=6, commonCopies=7, nmiSwitchesBanks=False, musicInitBank=2, musicPlaybackBank=7,
                     renderOverlay=dict(start=render_start,end=render_end,bytes=render_size,
                                        availableStart=labels['map_render_overlay_start'],
                                        availableEnd=labels['map_render_overlay_end'],
                                        outsideOverlayMatchesMap=True,
                                        columnProjectorInRenderBank=True,
                                        exactSlimeProbeInMirroredPrefix=True)),
        initialHealth=100, initialAmmo=STARTING_AMMO,
        map='assets/map.json', title=title_layout, credits=credits_layout, results=results_layout,
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
