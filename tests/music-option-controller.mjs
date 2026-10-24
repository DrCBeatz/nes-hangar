/** Stock NTSC JSNES integration: controller input and read-only observations.
 * No ROM, game RAM, CPU/PPU state, save-state, or emulator timing patches.
 */
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {dirname,resolve} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const here=dirname(fileURLToPath(import.meta.url)),args={};
for(let i=2;i<process.argv.length;i+=2){
 if(process.argv[i]==='--help'){console.log('Usage: node tests/music-option-controller.mjs --build PATH --core PATH --output PATH');process.exit(0);}
 assert.ok(['--build','--core','--output'].includes(process.argv[i])&&process.argv[i+1]);args[process.argv[i]]=process.argv[i+1];
}
for(const key of ['--build','--core','--output'])assert.ok(args[key],key);
const build=resolve(args['--build']),core=resolve(args['--core']),output=resolve(args['--output']);
const hash=b=>createHash('sha256').update(b).digest('hex'),sha=p=>hash(readFileSync(p));
const rom=readFileSync(resolve(build,'hangar-ntsc.nes'));
const labelsPath=resolve(build,'hangar.lbl'),manifestPath=resolve(build,'manifest.json');
const labels=Object.fromEntries(readFileSync(labelsPath,'utf8').split('\n').map(s=>s.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));
const manifest=JSON.parse(readFileSync(manifestPath,'utf8'));
assert.equal(hash(rom),manifest.sha256);assert.equal(manifest.music.enabled,true);
const coreCommit='5b27c4243f1cb2528c54941e13c29c4ced7d5a45';
assert.equal(sha(core),'0531f69c4e9e2973bdcdc89bf3ad6e6dfa3257572f8e7eccd405fa158cc3a1a7');
assert.equal(sha(resolve(dirname(core),'cpu.js')),'17469b310738c4b3092d648289c8537a4584f6b45bc1735adb540968a75308f2');
const {NES,Controller}=await import(pathToFileURL(core));
const buttons=Object.fromEntries(['a','b','select','start','up','down','left','right'].map(k=>[k,Controller['BUTTON_'+k.toUpperCase()]]));
const routePath=resolve(here,'music-option-route.json'),route=JSON.parse(readFileSync(routePath,'utf8')).phases;
const titleLayout=JSON.parse(readFileSync(resolve(build,'title-layout.json'),'utf8'));
const layout=titleLayout.musicOption;
const hudLayout=JSON.parse(readFileSync(resolve(build,'pistol-assets.json'),'utf8'));
const creditsLayout=JSON.parse(readFileSync(resolve(build,'credits-layout.json'),'utf8'));
for(const name of ['credits_present','credits_wait_start','credits_back','credits_start'])assert.ok(name in labels,name);
assert.ok(layout&&layout.width===3);const fieldOffset=layout.row*32+layout.col;
const names=['music_disabled','title_state','pause_active','results_screen_state','publish_count','results_frames','results_seconds','results_minutes','simulation_count','player_x','player_z','player_x_hi','player_z_hi','visible_x','visible_z','visible_x_hi','visible_z_hi','pending_angle','visible_angle','pistol_health','pistol_ammo','pistol_shot_count','requested_mode','zombie_hp','zombie_x','zombie_z','zombie_x_hi','zombie_z_hi','zombie_visible_target','zombie_epoch','visible_zombie_epoch','zombie_attack_state','zombie_kills','medkit_state','encounter_visual_pending','zombie_dirty','medkit_dirty','upload_busy','door_state','visible_door','audio_music_active','audio_music_regs','audio_owner','__AUDIO_ENGINE_RUN__','__AUDIO_ENGINE_SIZE__'];
for(const name of names)assert.ok(name in labels,name);
const checks=[],runs=[];
function check(name,fn){fn();checks.push(name);}
check('guide advertises explicit music choices, performance tradeoff and inset Start prompt',()=>{
 for(const [row,text] of [[23,'LEFT OFF / RIGHT ON'],[24,'MUSIC OFF: FASTER PLAY'],[27,'PRESS START TO PLAY']])assert.ok(titleLayout.lines.some(line=>line.row===row&&line.text===text));
 assert.equal(layout.row,22);
});
check('credits use the public project alias and distinguish composition, arrangement and engine authors',()=>{
 assert.ok(creditsLayout.lines.some(line=>line.row===6&&line.text==='DR C BEATZ'));
 assert.equal(creditsLayout.lines.filter(line=>line.text==='DR C BEATZ').length,2);
 for(const text of ['NES PROTOTYPE BY','ID SOFTWARE','COMPOSED BY BOBBY PRINCE','NES ARRANGEMENT BY','DR C BEATZ','FAMISTUDIO BY','MATHIEU GAUTHIER','BASED ON FAMITONE2','BY SHIRU'])assert.ok(creditsLayout.lines.some(line=>line.text===text));
});
function machine(choice){
 let frames=0,pictures=0,audioSamples=0,picture=new Uint32Array(256*240),apuWrites=[],observedSfx=new Set();
 const n=new NES({onFrame(p){picture=Uint32Array.from(p);pictures++;},onAudioSample(l,r){assert.ok(Number.isFinite(l)&&Number.isFinite(r));audioSamples++;}});
 n.loadROM(rom.toString('latin1'));assert.equal(n.rom.mapperType,1);assert.equal(n.rom.romCount,8);assert.equal(n.rom.vromCount,0);
 // This wrapper records hardware writes, then forwards every call unchanged.
 const write=n.cpu.write.bind(n.cpu);n.cpu.write=(a,v)=>{if(a>=0x4000&&a<=0x4017&&a!==0x4014&&a!==0x4016)apuWrites.push({frame:frames,address:a,value:v});return write(a,v);};
 const byte=k=>n.cpu.mem[labels[k]],word=k=>byte(k)+256*n.cpu.mem[labels[k]+1],coord=k=>word(k)+65536*byte(k+'_hi');
 const clock=()=>byte('results_minutes')*3600+byte('results_seconds')*60+byte('results_frames');
 const bytes=(k,len)=>Buffer.from(n.cpu.mem.slice(labels[k],labels[k]+len));
 const engine=()=>hash(bytes('__AUDIO_ENGINE_RUN__',labels.__AUDIO_ENGINE_SIZE__));
 const ppu=(a,len)=>Buffer.from(Array.from({length:len},(_,i)=>n.ppu.mirroredLoad(a+i)));
 const pixelHash=()=>hash(new Uint8Array(picture.buffer));
 const state=()=>({title:byte('title_state'),paused:byte('pause_active'),results:byte('results_screen_state'),musicDisabled:byte('music_disabled'),musicActive:byte('audio_music_active'),clock:clock(),x:coord('player_x'),z:coord('player_z'),angle:byte('pending_angle'),health:byte('pistol_health'),ammo:byte('pistol_ammo'),shots:word('pistol_shot_count'),kills:byte('zombie_kills')});
 const snapshots={},phases=[];
 const snapshot=name=>snapshots[name]={frame:frames,state:state(),engineSha256:engine(),pixelSha256:pixelHash(),ppuSha256:hash(ppu(0,0x4000)),chrSha256:hash(ppu(0,8192))};
 const step=(pressed=[])=>{const active=new Set(pressed);for(const[k,id]of Object.entries(buttons))n[active.has(k)?'buttonDown':'buttonUp'](1,id);n.frame();frames++;assert.equal(n.crashed,false);for(let i=0;i<4;i++)if(n.cpu.mem[labels.audio_owner+i]===2)observedSfx.add(i);};
 const run=(count,pressed=[])=>{for(let i=0;i<count;i++)step(pressed);};
 const until=(test,max,pressed=[])=>{let elapsed=0;while(!test()&&elapsed++<max)step(pressed);assert.ok(test(),'Controller condition timed out: '+JSON.stringify(state()));};
 function drive(p){
  const initialHealth=byte('pistol_health'),start=frames;
  const ready=()=>{
   const elapsed=frames-start;
   if(p.duration!==undefined)return elapsed>=p.duration;
   if(p.walk)return (p.walk[0]*256-coord('player_x'))**2+(p.walk[1]*256-coord('player_z'))**2<=(p.tolerance??.6)**2*65536;
   if(p.face!==undefined)return byte('pending_angle')===p.face;
   if(p.kill)return byte('zombie_hp')===0;
   if(p.healthBelow!==undefined)return byte('pistol_health')<=p.healthBelow;
   if(p.damageDelta!==undefined)return byte('pistol_health')<=initialHealth-p.damageDelta;
   if(p.fieldEquals)return Object.entries(p.fieldEquals).every(([k,v])=>byte(k)===v);
   if(p.settle)return elapsed>=3&&coord('visible_x')===coord('player_x')&&coord('visible_z')===coord('player_z')&&byte('visible_angle')===byte('pending_angle')&&byte('encounter_visual_pending')===0&&byte('zombie_dirty')===0&&byte('medkit_dirty')===0&&byte('upload_busy')===0&&byte('visible_door')===(byte('door_state')===0?0:1);
   throw new Error('Unsupported phase '+p.id);
  };
  while(!ready()){
   assert.ok(frames-start<(p.maxFrames??1600),'Phase timed out '+p.id+' '+JSON.stringify(state()));
   const pressed=(p.buttons??'').split(/\s+/).filter(Boolean);let wanted=p.face;
   if(p.walk)wanted=Math.floor(Math.atan2(p.walk[0]*256-coord('player_x'),p.walk[1]*256-coord('player_z'))*128/Math.PI+.5)&255;
   if(p.kill)wanted=Math.floor(Math.atan2(coord('zombie_x')-coord('player_x'),coord('zombie_z')-coord('player_z'))*128/Math.PI+.5)&255;
   if(wanted!==undefined){const delta=(wanted-byte('pending_angle'))&255;if(delta)pressed.push(delta<128?'right':'left');if(p.walk&&[0,1,255].includes(delta))pressed.push('up');if(p.kill&&byte('zombie_visible_target')&&byte('visible_angle')===byte('pending_angle')&&byte('visible_zombie_epoch')===byte('zombie_epoch'))pressed.push('b');}
   step(pressed);
   // Warm boot clears RAM before restoring the preference saved on stack.
   // Check its retained value after this explicitly requested restart phase.
   if(p.id!=='reset-start')assert.equal(byte('music_disabled'),choice,'Choice persists during '+p.id);
  }
  phases.push({id:p.id,startFrame:start,endFrame:frames,state:state()});
 }
 return {n,byte,word,coord,clock,bytes,engine,ppu,state,pixelHash,step,run,until,drive,snapshot,snapshots,phases,get frames(){return frames;},report:()=>({choice:choice?'OFF':'ON',frames,pictures,audioSamples,observedSfxChannels:[...observedSfx].sort(),snapshots,phases,apu:{writes:apuWrites.length,dpcmControlWrites:apuWrites.filter(w=>w.address===0x4010),dpcmDataWrites:apuWrites.filter(w=>w.address>=0x4011&&w.address<=0x4013),dpcmEnabled:apuWrites.filter(w=>w.address===0x4015&&(w.value&16))}})};
}
function startup(m,choice){
 const readAsset=name=>readFileSync(resolve(build,name));
 const expectBank=bank=>assert.deepEqual(Buffer.from(m.n.cpu.mem.slice(0x8000,0xA000)),rom.subarray(16+bank*16384,16+bank*16384+8192));
 const expectPage=(prefix,bank)=>{
  assert.deepEqual(m.ppu(0x2000,1024),readAsset(prefix+'-nametable.bin'));
  assert.deepEqual(m.ppu(0x3F00,32),readAsset(prefix+'-palette.bin'));
  assert.equal(m.n.ppu.f_nmiOnVblank,0);assert.equal(m.n.ppu.f_spVisibility,0);assert.equal(m.n.ppu.f_bgVisibility,1);
  assert.equal(m.n.ppu.regH,0,'Visible nametable horizontal bit must be restored after palette upload');assert.equal(m.n.ppu.regV,0,'Visible nametable vertical bit must be restored after palette upload');
  assert.equal(m.byte('title_state'),1);assert.equal(m.clock(),0);assert.equal(m.byte('simulation_count'),0);assert.equal(m.byte('audio_music_active'),0);
  expectBank(bank);
 };
 m.run(120,['start','left','select']);check('held power-on Start and Select stay on logo '+choice,()=>{expectPage('newtitle-logo',2);assert.equal(m.byte('music_disabled'),0);});
 const logo=m.pixelHash(),logoChr=m.ppu(0,8192),titleEngine=m.engine();
 check('logo uploads the exact generated artwork and preserves the fixed font '+choice,()=>{
  assert.deepEqual(m.ppu(0,1024),readAsset('fixed-patterns.bin'));
  const art=readAsset('newtitle-logo-patterns.bin');assert.deepEqual(m.ppu(titleLayout.logoExperiment.firstPattern*16,art.length),art);
 });m.snapshot('bronze-logo');
 m.run(30,['left','a','b']);assert.equal(m.pixelHash(),logo);
 m.run(2);m.run(90,['select','b']);
 check('fresh Select opens exact credits page and held B cannot immediately return '+choice,()=>{expectPage('credits',4);assert.deepEqual(m.ppu(0,8192),logoChr);assert.equal(m.engine(),titleEngine);assert.equal(m.byte('music_disabled'),0);});m.snapshot('credits');
 const credits=m.pixelHash();m.run(90,['select','b','left','right','up','down','a']);
 check('held credits buttons keep the page stable with frozen simulation and music '+choice,()=>{expectPage('credits',4);assert.equal(m.pixelHash(),credits);assert.equal(m.engine(),titleEngine);});
 m.run(2);m.run(90,['b','select']);
 check('fresh B returns to exact logo and held Select cannot reopen credits '+choice,()=>{expectPage('newtitle-logo',2);assert.equal(m.pixelHash(),logo);assert.deepEqual(m.ppu(0,8192),logoChr);assert.equal(m.engine(),titleEngine);});m.snapshot('credits-back-to-logo');
 m.run(2);m.run(60,['select']);expectPage('credits',4);
 if(choice){
  m.run(2);m.run(60,['b']);expectPage('newtitle-logo',2);m.run(2);
  m.run(90,['start','select','left']);
  check('simultaneous Start and Select prioritize guide on logo '+choice,()=>expectPage('title',2));
 }else{
  m.run(2);m.run(90,['start','select','left']);
  check('Start from credits continues to guide and restores boot bank '+choice,()=>expectPage('title',2));
 }
 check('held Start and inherited Left cannot skip guide or change default '+choice,()=>{assert.equal(m.byte('title_state'),1);assert.equal(m.byte('music_disabled'),0);assert.notEqual(m.pixelHash(),logo);assert.deepEqual(m.ppu(0,8192),logoChr);assert.equal(m.engine(),titleEngine);});m.snapshot('controls-guide');
 m.run(30,['left']);assert.equal(m.byte('music_disabled'),0);m.run(2);m.run(90,['left']);
 const off=m.ppu(0x2000,1024),enabled=readFileSync(resolve(build,'title-nametable.bin'));
 check('fresh and held Left select OFF with only three status tiles changed '+choice,()=>{assert.equal(m.byte('music_disabled'),1);assert.deepEqual([...off.subarray(fieldOffset,fieldOffset+3)],[29,20,20]);const expected=Buffer.from(enabled);off.copy(expected,fieldOffset,fieldOffset,fieldOffset+3);assert.deepEqual(off,expected);assert.equal(m.clock(),0);});
 m.run(2);m.run(90,['right']);check('fresh and held Right select ON '+choice,()=>{assert.equal(m.byte('music_disabled'),0);assert.deepEqual(m.ppu(0x2000,1024),enabled);});
 m.run(2);m.run(30,['left','right']);check('simultaneous Left and Right preserve selection '+choice,()=>assert.equal(m.byte('music_disabled'),0));
 m.run(2);if(choice)m.run(2,['left']);m.run(2);m.snapshot('guide-choice');
 let loading=0;const start=m.frames;
 while(!(m.byte('title_state')===0&&m.byte('publish_count')===1)&&m.frames-start<300){m.step(['start',choice?'left':'right','up','b','select']);if(m.byte('title_state')===2){loading++;assert.equal(m.clock(),0);assert.equal(m.byte('simulation_count'),0);assert.equal(m.n.ppu.f_bgVisibility,0);assert.equal(m.n.ppu.f_spVisibility,0);}}
 check('Start launches selected option through frozen first picture '+choice,()=>{assert.ok(loading>0);assert.equal(m.byte('title_state'),0);assert.equal(m.byte('publish_count'),1);assert.equal(m.byte('music_disabled'),choice);assert.equal(m.clock(),0);assert.equal(m.coord('player_x'),52*256);assert.equal(m.coord('player_z'),172*256);assert.equal(m.word('pistol_shot_count'),0);assert.equal(m.byte('requested_mode'),0);});
 check('both gameplay pages show WEAPON and PISTOL instead of unused armor '+choice,()=>{
  const fields=hudLayout.textLines.filter(line=>['WEAPON','PISTOL'].includes(line.text));assert.equal(fields.length,2);
  for(const base of [0x2000,0x2400])for(const line of fields)assert.deepEqual([...m.ppu(base+line.row*32+line.col,line.text.length)],[...line.text].map(c=>hudLayout.fontMap[c]));
 });
 m.snapshot('first-publication');m.run(60,['start']);check('held launch Start does not pause '+choice,()=>{assert.equal(m.byte('pause_active'),0);assert.equal(m.clock(),60);assert.equal(m.byte('music_disabled'),choice);});
 m.run(2);const shots=m.word('pistol_shot_count');m.run(8,['b']);check('pistol works with option '+choice,()=>{assert.equal(m.word('pistol_shot_count'),shots+1);assert.equal(m.byte('pistol_ammo'),5);});m.run(90);
 const engine=m.engine(),shadows=m.bytes('audio_music_regs',24);m.run(600);
 check('engine eligibility matches selected option '+choice,()=>{assert.equal(m.byte('audio_music_active'),choice?0:1);if(choice){assert.equal(m.engine(),engine);assert.deepEqual(m.bytes('audio_music_regs',24),shadows);assert.deepEqual([...m.bytes('audio_owner',4)],[0,0,0,0]);}else assert.notEqual(m.engine(),engine);});
 m.run(2,['start']);assert.equal(m.byte('pause_active'),1);const paused=m.engine(),clock=m.clock();m.run(90,['start','left','right','a','b']);
 check('pause freezes engine and game without changing option '+choice,()=>{assert.equal(m.engine(),paused);assert.equal(m.clock(),clock);assert.equal(m.byte('music_disabled'),choice);});
 m.run(2);m.run(2,['start']);m.run(90);check('resume preserves selected music behavior '+choice,()=>{assert.equal(m.byte('pause_active'),0);assert.equal(m.byte('music_disabled'),choice);assert.equal(m.byte('audio_music_active'),choice?0:1);assert.ok(m.clock()>clock);if(choice)assert.equal(m.engine(),paused);else assert.notEqual(m.engine(),paused);});m.snapshot('after-pause');
}
for(const choice of [0,1]){
 const m=machine(choice);startup(m,choice);
 if(choice){
  for(const p of route.filter(p=>p.id.startsWith('opening-')||p.id==='first-zombie-face'))m.drive(p);
  m.drive({id:'natural-death',healthBelow:0,maxFrames:6000});m.run(30);m.snapshot('dead');
  const deadEngine=m.engine();m.run(60);assert.equal(m.engine(),deadEngine);
  m.run(2,['start']);m.run(120,['start']);check('natural death retry retains OFF and held Start does not pause',()=>{assert.equal(m.byte('pistol_health'),100);assert.equal(m.byte('pistol_ammo'),6);assert.equal(m.coord('player_x'),52*256);assert.equal(m.coord('player_z'),172*256);assert.equal(m.byte('music_disabled'),1);assert.equal(m.byte('audio_music_active'),0);assert.equal(m.byte('pause_active'),0);assert.equal(m.byte('title_state'),0);});m.run(2);m.snapshot('death-retry');
  for(const p of route){m.drive(p);if(['results-presented','final-spawn','first-zombie-killed','ammo-collected','door-open-settled'].includes(p.id))m.snapshot(p.id);}
  check('completion restart retains OFF and resets the level',()=>{assert.equal(m.snapshots['results-presented'].state.results,5);assert.equal(m.byte('results_screen_state'),0);assert.equal(m.byte('title_state'),0);assert.equal(m.byte('music_disabled'),1);assert.equal(m.byte('audio_music_active'),0);assert.equal(m.byte('pistol_health'),100);assert.equal(m.byte('pistol_ammo'),6);assert.equal(m.byte('zombie_kills'),0);assert.equal(m.byte('pause_active'),0);assert.equal(m.coord('player_x'),52*256);assert.equal(m.coord('player_z'),172*256);});
  check('OFF controller route exercised all four SFX channels',()=>assert.deepEqual(m.report().observedSfxChannels,[0,1,2,3]));
  // Console reset is the sole non-controller action; use the public API.
  m.n.cpu.requestIrq(m.n.cpu.IRQ_RESET);m.run(120,['start']);check('console reset returns to default ON and cold title',()=>{assert.equal(m.byte('music_disabled'),0);assert.equal(m.byte('title_state'),1);assert.equal(m.clock(),0);});m.snapshot('console-reset');
 }
 const report=m.report();check('DPCM remains disabled throughout '+choice,()=>{assert.deepEqual(report.apu.dpcmDataWrites,[]);assert.deepEqual(report.apu.dpcmEnabled,[]);assert.ok(report.apu.dpcmControlWrites.every(w=>w.value===0));});runs.push(report);
 console.log(JSON.stringify({choice:report.choice,passed:true,frames:report.frames,routePhases:report.phases.length}));
}
const imageComparisons=[];
for(const name of ['first-publication','after-pause'])check('ON and OFF have identical stationary game images: '+name,()=>{
 const [on,off]=runs.map(r=>r.snapshots[name]);for(const field of ['pixelSha256','ppuSha256','chrSha256'])assert.equal(on[field],off[field]);
 const gameplay=s=>Object.fromEntries(Object.entries(s.state).filter(([k])=>!['musicDisabled','musicActive'].includes(k)));assert.deepEqual(gameplay(on),gameplay(off));
 imageComparisons.push({snapshot:name,pixelsIdentical:true,ppuIdentical:true,chrIdentical:true,gameplayIdentical:true});
});
const report={passed:true,romSha256:hash(rom),checks,tests:{count:checks.length,failures:0},runs,imageComparisons,controllerOnly:true,consoleResetApiUsed:true,ramInjected:false,romUnmodified:true,extraScanlines:0,scope:'Pinned stock JSNES core. Controller-only logo/credits navigation, held-key suppression and Start priority, exact PPU artwork/palette/font checks, frozen title simulation/audio, WEAPON/PISTOL HUD, guide selection, launch, shoot, pause/resume, natural death retry, full accepted completion route and level restart; final public CPU reset interrupt API verifies cold default ON. Read-only CPU write observer; no game or emulator state injection. CPU timing/PPU deadline conclusions require the separate Mesen checks.',provenance:{jsnesCommit:coreCommit,coreEntrySha256:sha(core),coreCpuSha256:sha(resolve(dirname(core),'cpu.js')),coreNesSha256:sha(resolve(dirname(core),'nes.js')),corePpuSha256:sha(resolve(dirname(core),'ppu/index.js')),corePapuSha256:sha(resolve(dirname(core),'papu/index.js')),driverSha256:sha(fileURLToPath(import.meta.url)),routeSha256:sha(routePath),labelsSha256:sha(labelsPath),manifestSha256:sha(manifestPath),titleLayoutSha256:sha(resolve(build,'title-layout.json')),creditsLayoutSha256:sha(resolve(build,'credits-layout.json')),hudLayoutSha256:sha(resolve(build,'pistol-assets.json')),readOnlySymbols:Object.fromEntries(names.map(k=>[k,labels[k]]))}};
mkdirSync(dirname(output),{recursive:true});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({passed:true,checks:checks.length,output}));
