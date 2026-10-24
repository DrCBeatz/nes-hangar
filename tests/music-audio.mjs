// Actual linked 6502 sound routines; injected gameplay states, no video timing.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {dirname,resolve} from 'node:path';
const here=dirname(fileURLToPath(import.meta.url));
const args={};
for(let i=2;i<process.argv.length;i++){
 const key=process.argv[i];
 if(key==='--help'){
  console.log('Usage: node tests/music-audio.mjs --build PATH --core /path/to/jsnes/src/index.js [--output PATH]\nJSNES_CORE can supply --core. --build defaults to this checkout/build. Requires a music-enabled build; no emulator package is bundled.');
  process.exit(0);
 }
 assert.ok(['--build','--core','--output'].includes(key),'Unknown option '+key);
 assert.ok(process.argv[i+1]&&!process.argv[i+1].startsWith('--'),'Missing value for '+key);
 args[key]=process.argv[++i];
}
const build=args['--build']?resolve(args['--build']):resolve(here,'../build');
const coreArg=args['--core']||process.env.JSNES_CORE;
assert.ok(coreArg,'Supply --core PATH or JSNES_CORE for the JSNES module entry point');
const core=resolve(coreArg);
const output=args['--output']?resolve(args['--output']):resolve(build,'music-audio-verification.json');
const {NES}=await import(pathToFileURL(core));
const hash=b=>createHash('sha256').update(b).digest('hex');
const rom=readFileSync(resolve(build,'hangar-ntsc.nes'));
const labels=Object.fromEntries(readFileSync(resolve(build,'hangar.lbl'),'utf8').split('\n').map(s=>s.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));
const l=labels,checks=[],timings={},optionSamples=[];
assert.ok('music_disabled' in l,'Runtime music option must be exported');
// E1M1 uses 22 patterns of 64 rows, FamiTracker speed 4 / tempo 150.
// Exercise three complete loops; compare loops two and three after startup.
const loopFrames=22*64*4,steadyFrames=3*loopFrames+32,directFrames=12000;
const workspace={engineBytes:l.__AUDIO_ENGINE_SIZE__,driverBytes:l.__AUDIO_DRIVER_SIZE__,
 settingsBytes:l.__AUDIO_SETTINGS_SIZE__,
 totalBytes:l.__AUDIO_ENGINE_SIZE__+l.__AUDIO_DRIVER_SIZE__+l.__AUDIO_SETTINGS_SIZE__,
 spareBytes:l.audio_workspace_end-l.audio_workspace-l.__AUDIO_ENGINE_SIZE__-l.__AUDIO_DRIVER_SIZE__-l.__AUDIO_SETTINGS_SIZE__,
 zpAliasBytes:l.__AUDIO_ZP_SIZE__};
const check=(name,fn)=>{fn();checks.push(name);};
let calls=0;
function machine(){
 const n=new NES();n.loadROM(rom.toString('latin1'));
 const c=n.cpu;c.mem.fill(0,0,0x800);n.ppu.updateControlReg1(0);n.ppu.updateControlReg2(0);
 let writes=[];const raw=c.write.bind(c);c.write=(addr,value)=>{writes.push({addr,value,pc:c.REG_PC});raw(addr,value);};
 function set(name,v,offset=0){assert.ok(name in l,name);c.mem[l[name]+offset]=v;}
 function get(name,offset=0){assert.ok(name in l,name);return c.mem[l[name]+offset];}
 function run(name,{a=0,x=0,y=0}={}){
  assert.ok(name in l,name);writes=[];c.REG_ACC=a;c.REG_X=x;c.REG_Y=y;c.REG_SP=0x1ff;c.push(0x4f);c.push(0xff);c.REG_PC=l[name]-1;c.F_INTERRUPT=1;c.irqRequested=false;
  let cycles=0,steps=0;
  while(c.REG_PC!==0x4fff){assert.ok(++steps<200000,`${name} must return at ${c.REG_PC.toString(16)}`);cycles+=c.emulate();c.irqRequested=false;c.nmiPending=false;c.nmiRaised=false;}
  assert.equal(c.REG_SP&255,255,name+' stack');calls++;
  const t=timings[name]??={calls:0,min:Infinity,max:0,total:0};t.calls++;t.min=Math.min(t.min,cycles);t.max=Math.max(t.max,cycles);t.total+=cycles;
  const output={cycles,writes:writes.slice(),apu:writes.filter(w=>w.addr>=0x4000&&w.addr<=0x4017),mapper:writes.filter(w=>w.addr>=0x8000)};
  if(name==='music_init'&&l.audio_reset<0xA000){
   // Reset runs with NMI off. Only this startup wrapper may select boot bank2,
   // initialize its reset helper, then restore map bank0 before returning.
   assert.deepEqual(output.mapper.map(w=>[w.addr,w.value]),[2,1,0,0,0,0,0,0,0,0].map(v=>[0xE000,v]));
   assert.equal(n.mmap.romBankSelect,0,'Startup restores map bank0');
  }else assert.equal(output.mapper.length,0,`${name} must not write mapper`);
  return output;
 }
 const bytes=(name,len)=>Array.from(c.mem.slice(l[name],l[name]+len));
 const last=(out,addr)=>out.apu.filter(w=>w.addr===addr).at(-1)?.value;
 const engine=()=>bytes('__AUDIO_ENGINE_RUN__',l.__AUDIO_ENGINE_SIZE__);
 const owner=()=>bytes('audio_owner',4);
 function game(){run('music_init');set('pistol_health',100);set('pistol_ammo',6);set('audio_music_active',1);return run('music_tick');}
 return{n,c,set,get,run,bytes,last,engine,owner,game};
}
check('Linked engine and mixer fit reserved216 bytes; no larger ZP alias',()=>{
 assert.ok(workspace.engineBytes>0);assert.equal(workspace.driverBytes,69);assert.equal(workspace.zpAliasBytes,8);
 assert.equal(l.audio_workspace_end-l.audio_workspace,216);assert.ok(workspace.totalBytes<=216);
 assert.equal(l.__AUDIO_ENGINE_RUN__,l.audio_workspace);
 assert.equal(l.audio_driver_begin,l.__AUDIO_ENGINE_RUN__+workspace.engineBytes);
 assert.equal(l.audio_driver_end-l.audio_driver_begin,workspace.driverBytes);assert.ok(l.audio_driver_end<=l.audio_workspace_end);
 assert.equal(workspace.settingsBytes,1);assert.equal(l.__AUDIO_SETTINGS_RUN__,l.audio_driver_end);assert.equal(l.music_disabled,l.__AUDIO_SETTINGS_RUN__);
 assert.ok(l.music_disabled<l.audio_workspace_end);
});
check('Init enables exactly four channels once; no DPCM/frame-counter writes',()=>{
 const m=machine(),o=m.run('music_init');assert.deepEqual(o.apu.map(w=>w.addr),[0x4000,0x4004,0x400c,0x4008,0x4001,0x4005,0x4015]);assert.equal(m.last(o,0x4015),15);
});
check('Music initialization preserves runtime OFF outside the cleared engine and mixer',()=>{
 const m=machine();m.set('music_disabled',1);m.run('music_init');assert.equal(m.get('music_disabled'),1);m.set('pistol_health',100);
 const before=m.engine();m.run('music_tick');assert.deepEqual(m.engine(),before);assert.deepEqual(m.owner(),[0,0,0,0]);assert.equal(m.get('audio_music_active'),0);
});
check('FamiStudio writes shadows only for 12000 updates; state confined to audio +8 scratch bytes',()=>{
 const m=machine();m.game();let transitions=0;
 for(let frame=0;frame<directFrames;frame++){
  const before=m.bytes('audio_music_regs',24),o=m.run('famistudio_update');assert.equal(o.apu.length,0);
  for(const w of o.writes){const ok=w.addr>=0x100&&w.addr<0x200||w.addr>=l.audio_workspace&&w.addr<l.audio_driver_end||w.addr>=l.__AUDIO_ZP_RUN__&&w.addr<l.__AUDIO_ZP_RUN__+8;assert.ok(ok,'Unexpected engine write '+w.addr.toString(16));}
  if(JSON.stringify(before)!==JSON.stringify(m.bytes('audio_music_regs',24)))transitions++;
 }
 assert.ok(transitions>30);
});
check('Music exposes all four channels; repeated unchanged high registers are suppressed',()=>{
 const m=machine();m.game();assert.deepEqual(m.owner(),[1,1,1,1]);
 const a=m.run('audio_mix');assert.equal(a.apu.filter(w=>[0x4003,0x4007,0x400b,0x400f].includes(w.addr)).length,0);
 m.set('audio_music_regs',m.get('audio_music_regs',3)^1,3);const b=m.run('audio_mix');assert.equal(b.apu.filter(w=>w.addr===0x4003).length,1);assert.equal(b.apu.length,a.apu.length+1);
});
check('Runtime OFF freezes engine and music shadows, mutes all four voices, and ON resumes',()=>{
 const m=machine();m.game();for(let i=0;i<120;i++)m.run('music_tick');
 const before=m.engine(),shadows=m.bytes('audio_music_regs',24);
 m.set('music_disabled',1);let total=0,max=0;
 for(let i=0;i<600;i++){
  const o=m.run('music_tick');total+=o.cycles;max=Math.max(max,o.cycles);
  assert.equal(m.get('audio_music_active'),0);assert.deepEqual(m.engine(),before);assert.deepEqual(m.bytes('audio_music_regs',24),shadows);
  assert.deepEqual(m.owner(),[0,0,0,0]);assert.deepEqual(o.apu.map(w=>[w.addr,w.value]),[[0x4000,0x30],[0x4004,0x30],[0x400c,0x30],[0x4008,0x80]]);
  assert.ok(o.writes.every(w=>!(w.addr>=l.__AUDIO_ENGINE_RUN__&&w.addr<l.__AUDIO_ENGINE_RUN__+l.__AUDIO_ENGINE_SIZE__)),'OFF must not execute engine writes');
 }
 optionSamples.push({mode:'runtime OFF, no effects',frames:600,maxCycles:max,meanCycles:total/600,engineAndMusicShadowsFrozen:true});
 m.set('music_disabled',0);const o=m.run('music_tick');assert.equal(m.get('audio_music_active'),1);assert.deepEqual(m.owner(),[1,1,1,1]);assert.notDeepEqual(m.engine(),before);assert.ok(o.cycles>max,'OFF skips the engine CPU work');
});
check('Runtime OFF preserves all four SFX owners and returns each channel to silence',()=>{
 const m=machine();m.game();m.set('music_disabled',1);m.run('music_tick');const before=m.engine(),shadows=m.bytes('audio_music_regs',24);
 m.set('pistol_health',70);m.run('medkit_collect');
 m.set('zombie_hp',3);m.set('zombie_visible',1);m.set('zombie_attack_state',1);m.run('zombie_attack_warning_uploaded');
 m.run('pistol_shot_accepted');m.set('pause_cue_timer',13);m.run('pause_cue_tick');
 const o=m.run('music_tick');assert.deepEqual(m.owner(),[2,2,2,2]);assert.equal(m.last(o,0x4002),0x90);assert.equal(m.last(o,0x4006),0xa9);assert.equal(m.last(o,0x400e),6);assert.ok((m.last(o,0x4008)&127)>0);
 assert.deepEqual(m.engine(),before);assert.deepEqual(m.bytes('audio_music_regs',24),shadows);assert.ok(o.apu.every(w=>w.addr<0x4010));
 m.set('medkit_state',0);m.set('zombie_audio_timer',0);m.set('pistol_flash_timer',0);m.set('pause_cue_timer',0);
 const silent=m.run('music_tick');assert.deepEqual(m.owner(),[0,0,0,0]);assert.deepEqual(silent.apu.map(w=>[w.addr,w.value]),[[0x4000,0x30],[0x4004,0x30],[0x400c,0x30],[0x4008,0x80]]);
 m.set('pistol_ammo',0);m.run('pistol_dry_fire_accepted');const dry=m.run('music_tick');assert.equal(m.last(dry,0x400e),0x8c);assert.deepEqual(m.owner(),[0,0,0,2]);
 m.set('pistol_flash_timer',0);m.run('exit_complete');const completed=m.run('music_tick');assert.deepEqual(m.owner(),[2,0,0,0]);assert.equal(m.last(completed,0x4002),0xfd);
});
check('Medkit heals and takes only pulse2, note retriggers once, returns to music',()=>{
 const m=machine();m.game();m.set('pistol_health',70);m.run('medkit_collect');assert.equal(m.get('pistol_health'),95);assert.equal(m.get('medkit_state')&31,16);
 let o=m.run('music_tick');assert.deepEqual(m.owner(),[1,2,1,1]);assert.equal(m.last(o,0x4004),0xb8);assert.equal(m.last(o,0x4006),0xa9);assert.equal(m.last(o,0x4007),0xf8);
 o=m.run('audio_mix');assert.equal(m.last(o,0x4007),undefined);
 for(let i=0;i<8;i++)m.run('medkit_sound_tick');o=m.run('music_tick');assert.equal(m.last(o,0x4006),0x70);assert.equal(m.last(o,0x4007),0xf8);
 for(let i=0;i<8;i++)m.run('medkit_sound_tick');o=m.run('music_tick');assert.deepEqual(m.owner(),[1,1,1,1]);assert.equal(m.last(o,0x4007),m.get('audio_music_regs',7));
});
check('Ammo uses original descending pulse2 cue without disabling music channels',()=>{
 const m=machine();m.game();m.set('pistol_ammo',0);m.run('ammo_collect');assert.equal(m.get('pistol_ammo'),10);let o=m.run('music_tick');assert.equal(m.last(o,0x4006),0x54);assert.deepEqual(m.owner(),[1,2,1,1]);
 for(let i=0;i<4;i++)m.run('medkit_sound_tick');o=m.run('music_tick');assert.equal(m.last(o,0x4006),0x8e);assert.equal(m.last(o,0x4007),0xf8);assert.ok(!o.apu.some(w=>w.addr===0x4015));
});
check('Soldier warning owns pulse1 independently, then returns to song',()=>{
 const m=machine();m.game();m.set('zombie_hp',3);m.set('zombie_visible',1);m.set('zombie_attack_state',1);m.run('zombie_attack_warning_uploaded');assert.equal(m.get('zombie_audio_timer'),9);
 let o=m.run('music_tick');assert.deepEqual(m.owner(),[2,1,1,1]);assert.equal(m.last(o,0x4002),0x90);assert.equal(m.last(o,0x4003),0xf9);
 for(let i=0;i<9;i++)m.run('zombie_attack_tick');o=m.run('music_tick');assert.deepEqual(m.owner(),[1,1,1,1]);
});
check('Door -> enemy gun -> player gun priority retains three music channels',()=>{
 const m=machine();m.game();m.run('door_request');let o=m.run('music_tick');assert.equal(m.last(o,0x400e),11);assert.deepEqual(m.owner(),[1,1,1,2]);
 m.set('zombie_x_hi',1);m.run('zombie_attack_fire');m.run('door_sound_tick');o=m.run('music_tick');assert.equal(m.last(o,0x400e),7);assert.equal(m.get('door_sound_timer'),0);assert.equal(m.last(o,0x400f),0xf8);
 m.run('pistol_shot_accepted');m.run('zombie_attack_tick');o=m.run('music_tick');assert.equal(m.last(o,0x400e),6);assert.equal(m.last(o,0x400f),0xf8);assert.equal(m.get('zombie_audio_timer'),0);assert.deepEqual(m.owner(),[1,1,1,2]);
 m.set('input_buttons',0);for(let i=0;i<6;i++)m.run('pistol_tick');m.run('music_tick');assert.deepEqual(m.owner(),[1,1,1,1]);
});
check('Dry trigger uses original deep buzz, returns to music without a shot',()=>{
 const m=machine();m.game();m.set('pistol_ammo',0);m.run('pistol_dry_fire_accepted');let o=m.run('music_tick');assert.equal(m.last(o,0x400e),0x8c);assert.equal(m.last(o,0x400c),0x1a);assert.equal(m.get('pistol_shot_count'),0);
 for(let i=0;i<8;i++)m.run('pistol_tick');m.run('music_tick');assert.deepEqual(m.owner(),[1,1,1,1]);
});
check('Repeated same-high effect triggers, including counter wrap, reload exactly once',()=>{
 const m=machine();m.game();for(let i=0;i<260;i++){
  m.run('pistol_dry_fire_accepted');let o=m.run('audio_mix');assert.equal(m.last(o,0x400f),0xf8);o=m.run('audio_mix');assert.equal(m.last(o,0x400f),undefined);
 }
 assert.equal(m.get('audio_sfx_trigger',3),4);assert.equal(m.get('audio_seen_trigger',3),4);
});
check('Paused song is frozen; triangle cue has two notes; resume restores music',()=>{
 const m=machine();m.game();m.set('pause_active',1);m.set('pause_cue_timer',13);const before=m.engine();let high=0;
 for(let i=0;i<20;i++){
  m.run('pause_cue_tick');const o=m.run('music_tick');assert.deepEqual(m.engine(),before);assert.equal(m.last(o,0x4000),0x30);assert.equal(m.last(o,0x4004),0x30);assert.equal(m.last(o,0x400c),0x30);high+=o.apu.filter(w=>w.addr===0x400b).length;
 }
 assert.equal(high,2);assert.equal(m.get('pause_cue_timer'),0);assert.equal(m.get('audio_owner',2),0);
 m.set('pause_active',0);const oldHigh=m.get('audio_high');const o=m.run('music_tick');assert.deepEqual(m.owner(),[1,1,1,1]);assert.equal(m.last(o,0x400b),m.get('audio_music_regs',11));
 // A new song may legitimately change pitch on the resumed update. Rewriting
 // pulse high is permitted only for that change, never just for resume.
 assert.equal(m.last(o,0x4003),oldHigh===m.get('audio_music_regs',3)?undefined:m.get('audio_music_regs',3));
});
check('Title, results, and dead player freeze engine and mute all music channels',()=>{
 for(const [name,val] of [['title_state',1],['results_screen_state',1],['pistol_health',0]]){
  const m=machine();m.game();m.set(name,val);const before=m.engine();for(let i=0;i<30;i++){const o=m.run('music_tick');assert.deepEqual(m.engine(),before);assert.deepEqual(m.owner(),[0,0,0,0]);assert.deepEqual(o.apu.map(w=>[w.addr,w.value]),[[0x4000,0x30],[0x4004,0x30],[0x400c,0x30],[0x4008,0x80]]);}
 }
});
check('Completion chime takes pulse1 while all other channels are silent',()=>{
 const m=machine();m.game();m.run('exit_complete');let o=m.run('music_tick');assert.deepEqual(m.owner(),[2,0,0,0]);assert.equal(m.last(o,0x4002),0xfd);assert.equal(m.last(o,0x4003),0xf8);
 for(let i=0;i<16;i++)m.run('exit_sound_tick');o=m.run('music_tick');assert.equal(m.last(o,0x4002),0xa9);assert.equal(m.last(o,0x4003),0xf8);
 for(let i=0;i<16;i++)m.run('exit_sound_tick');m.run('music_tick');assert.deepEqual(m.owner(),[0,0,0,0]);
});
check('Fatal damage suppresses active gun and stale warning/pickup sounds',()=>{
 const m=machine();m.game();m.set('pistol_health',1);m.set('zombie_attack_state',2);m.set('zombie_audio_timer',9);m.set('medkit_state',16);m.set('pistol_flash_timer',5);m.run('player_damage',{a:10});m.run('music_tick');assert.deepEqual(m.owner(),[0,0,0,0]);
});
const samples=[];
check('Three E1M1 loops plus simultaneous SFX stress: periodic state, bounded time, no mapper/enable writes',()=>{
 const m=machine();m.game();let max={cycles:0,frame:-1},total=0;
 const loopStates=[];let comparedFrames=0;
 const channelActivity=[0,4,8,12].map(offset=>({offset,frames:0,firstFrame:null}));
 for(let frame=0;frame<steadyFrames;frame++){
  const o=m.run('music_tick');total+=o.cycles;if(o.cycles>max.cycles)max={cycles:o.cycles,frame};assert.ok(o.apu.every(w=>w.addr<0x4010));
  const state=Buffer.from([...m.engine(),...m.bytes('audio_music_regs',24)]);
  if(frame>=loopFrames&&frame<2*loopFrames)loopStates.push(state);
  if(frame>=2*loopFrames&&frame<3*loopFrames){assert.deepEqual(state,loopStates[frame-2*loopFrames],'Engine and APU shadows repeat after one complete E1M1 loop at frame '+frame);comparedFrames++;}
  for(const ch of channelActivity){if(m.get('audio_music_regs',ch.offset)&(ch.offset===8?127:15)){ch.frames++;if(ch.firstFrame===null)ch.firstFrame=frame;}}
 }
 // Ownership exists even during a rest. These observations measure actual
 // nonzero software-volume/linear values without assuming immediate entrances.
 assert.ok(channelActivity.every(ch=>ch.frames>0),'Four-channel song must eventually exercise each voice');
 assert.equal(comparedFrames,loopFrames);
 samples.push({mode:'music, no effects',frames:steadyFrames,max,mean:total/steadyFrames,channelActivity,
  looping:{periodFrames:loopFrames,comparedFrames,completeLoops:3,engineAndShadowStateIdentical:true}});
 m.set('medkit_state',16);m.set('zombie_attack_state',2);m.set('zombie_audio_timer',9);m.set('pistol_flash_timer',5);m.set('pause_cue_timer',12);
 max={cycles:0,frame:-1};total=0;
 for(let frame=0;frame<600;frame++){
  for(let ch=0;ch<4;ch++)m.set('audio_sfx_trigger',(m.get('audio_sfx_trigger',ch)+1)&255,ch);
  const o=m.run('music_tick');total+=o.cycles;if(o.cycles>max.cycles)max={cycles:o.cycles,frame};assert.deepEqual(m.owner(),[2,2,2,2]);assert.ok(o.apu.every(w=>w.addr<0x4010));
 }
 samples.push({mode:'all four SFX owners, retrigger every frame (synthetic upper stress)',frames:600,max,mean:total/600});
});
check('All 8 mapped PRG banks preserve always-visible audio code/data',()=>{
 for(let bank=0;bank<8;bank++){
  const m=machine();m.game();m.n.mmap.loadRomBank(bank,0x8000);m.n.mmap.loadRomBank(7,0xc000);assert.deepEqual(m.owner(),[1,1,1,1]);for(let i=0;i<60;i++)m.run('music_tick');
 }
});
for(const t of Object.values(timings))t.mean=t.total/t.calls;
const report={passed:true,checks,calls,workspace,timings,samples,optionSamples,scope:'Actual linked 6502 routines with injected game state. CPU cycle counts, APU register-write/ownership tests; no full NMI, PPU deadlines, acoustics or controller route claim. Mesen tests are separate.',sha256:{rom:hash(rom),driver:hash(readFileSync(fileURLToPath(import.meta.url))),labels:hash(readFileSync(resolve(build,'hangar.lbl'))),core:hash(readFileSync(core))}};
mkdirSync(dirname(output),{recursive:true});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({passed:true,checks:checks.length,calls,samples,rom:report.sha256.rom}));
