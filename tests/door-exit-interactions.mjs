// Linked 6502 interaction checks. Poses are injected; this is not a PPU test.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {dirname, resolve} from 'node:path';

const here=dirname(fileURLToPath(import.meta.url)), args={};
for(let i=2;i<process.argv.length;i++){
 const key=process.argv[i];
 if(key==='--help'){
  console.log('Usage: node tests/door-exit-interactions.mjs --build PATH --core /path/to/jsnes/src/index.js [--baseline-build PATH] [--output PATH]\nJSNES_CORE can supply --core. --build defaults to this checkout/build. Optional baseline must use the previous +/-45-degree door cone.');
  process.exit(0);
 }
 assert.ok(['--build','--core','--baseline-build','--output'].includes(key),'Unknown option '+key);
 assert.ok(process.argv[i+1]&&!process.argv[i+1].startsWith('--'),'Missing value for '+key);
 args[key]=process.argv[++i];
}
const build=resolve(args['--build']||resolve(here,'../build'));
const core=args['--core']||process.env.JSNES_CORE;
assert.ok(core,'Supply --core PATH or JSNES_CORE for the JSNES module entry point');
const output=resolve(args['--output']||resolve(build,'door-exit-interactions.json'));
const {NES}=await import(pathToFileURL(resolve(core)));
const rom=readFileSync(resolve(build,'hangar-ntsc.nes'));
function readLabels(directory){return Object.fromEntries(readFileSync(resolve(directory,'hangar.lbl'),'utf8').split('\n')
 .map(s=>s.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));}
let labels=readLabels(build);
const nes=new NES();nes.loadROM(rom.toString('latin1'));
let cpu=nes.cpu;nes.ppu.updateControlReg1(0);nes.ppu.updateControlReg2(0);
let calls=0;
function put(name,value,offset=0){assert.ok(name in labels,name);cpu.mem[labels[name]+offset]=value&255;}
function get(name){assert.ok(name in labels,name);return cpu.mem[labels[name]];}
function coord(name,value){const q=Math.round(value*256);put(name,q);put(name,q>>8,1);put(name+'_hi',q>>16);}
function call(name){
 assert.ok(name in labels,name);cpu.REG_SP=0x1ff;cpu.push(0x4f);cpu.push(0xff);
 cpu.REG_PC=labels[name]-1;cpu.F_INTERRUPT=1;cpu.irqRequested=false;
 let steps=0;
 while(cpu.REG_PC!==0x4fff){
  assert.ok(++steps<100000,name+' must return');cpu.emulate();
  cpu.irqRequested=false;cpu.nmiPending=false;cpu.nmiRaised=false;
 }
 assert.equal(cpu.REG_SP&255,255,name+' stack');calls++;return Boolean(cpu.F_CARRY);
}
function pose(x,z,angle,musicDisabled=0){
 cpu.mem.fill(0,0,0x800);coord('player_x',x);coord('player_z',z);
 put('pending_angle',angle);put('pistol_health',100);put('music_disabled',musicDisabled);
}
const counts={doorBoundary:0,exitBoundary:0,inputGuards:0,lifecycle:0,collision:0,closeContact:0,baselineCloseContact:0}, checks=[], examples=[];
function check(name,fn){fn();checks.push(name);}
const fraction=1/256;

check('All 256 facings across exact door panel and side boundaries',()=>{
 for(const x of [32,287+255/256,288,288+fraction,290,296,302.5,304-fraction,304,304+fraction,544])
 for(const z of [108-fraction,108,108+fraction,112,118-fraction,118,120,122,122+fraction,124,128,132-fraction,132,132+fraction,380])
 for(let angle=0;angle<256;angle++){
  pose(x,z,angle);
  const expected=x>=288&&x<304&&((z>122&&z<=132&&angle>=75&&angle<=181)||
   (z>=108&&z<118&&(angle>=203||angle<=53)));
  assert.equal(call('door_eligible'),expected,JSON.stringify({kind:'door',x,z,angle,expected}));
  counts.doorBoundary++;
 }
});
const closeContactPoses=[
 {x:301,z:122.25,angle:175,note:'North, near right: centered aim previously outside the 45-degree cone'},
 {x:291,z:122.25,angle:81,note:'North, near left: centered aim previously outside the 45-degree cone'},
 {x:301,z:117.75,angle:209,note:'South, near right: centered aim previously outside the 45-degree cone'},
 {x:291,z:117.75,angle:47,note:'South, near left: centered aim previously outside the 45-degree cone'},
 ...[[290+fraction,122+fraction],[302-fraction,122+fraction],
     [290+fraction,118-fraction],[302-fraction,118-fraction]].map(([x,z])=>({x,z,
  angle:(Math.round(Math.atan2(296-x,120-z)*128/Math.PI)+256)&255,
  note:'Legal fractional contact limit, aimed at panel center'})),
];
check('Legal close-contact poses show the prompt and accept fresh A with music ON/OFF',()=>{
 for(const musicDisabled of [0,1])for(const p of closeContactPoses){
  pose(p.x,p.z,p.angle,musicDisabled);
  coord('move_x',p.x);coord('move_z',p.z);put('player_floor',2);
  assert.equal(call('movement_candidate_blocked'),false,'Fixture must be a legal player pose: '+JSON.stringify(p));
  assert.equal(call('door_eligible'),true,JSON.stringify(p));
  call('door_tick');assert.equal(get('door_near'),1,'Prompt eligibility');
  assert.equal(get('pistol_dirty')&4,4,'Prompt requests a HUD update');
  put('input_buttons',0x80);call('door_tick');
  assert.equal(get('door_state'),0,'Held A without a new edge does not activate');
  for(const input of [0x81,0x82,0x83]){
   put('input_buttons',input);put('button_edges',0x80);call('door_tick');
   assert.equal(get('door_state'),0,'A with lateral input remains strafe');
  }
  put('input_buttons',0x80);put('button_edges',0x80);call('door_tick');
  assert.equal(get('door_state'),1,'Fresh A requests the open door');
  assert.equal(get('scene_version'),1,'One requested geometry change');
  assert.equal(get('door_near'),0,'Requested door clears the prompt');
  counts.closeContact++;
  examples.push({...p,musicDisabled,collisionLegal:true,eligible:true,requested:true});
 }
});
check('All 256 facings across exact exit range, lateral and higher-page boundaries',()=>{
 for(const x of [28,284,286-fraction,286,286+fraction,290,294-fraction,294,294+fraction,542])
 for(const z of [22-fraction,22,22+fraction,28,34-fraction,34,34+fraction,284])
 for(let angle=0;angle<256;angle++){
  pose(x,z,angle);
  const expected=x>=286&&x<294&&z>=22&&z<=34&&angle>=160&&angle<=224;
  assert.equal(call('exit_eligible'),expected,JSON.stringify({kind:'exit',x,z,angle,expected}));
  counts.exitBoundary++;
 }
});
check('Formerly rejected centered diagonal and lateral door approaches are eligible',()=>{
 for(const [kind,x,z,angle,note] of [
  ['door',300,124,160,'North: aimed exactly at door center from a diagonal'],
  ['door',292,124,96,'North: opposite centered diagonal'],
  ['door',300,116,224,'South: aimed exactly at door center from a diagonal'],
  ['door',292,116,32,'South: opposite centered diagonal'],
  ['door',302.5,116,0,'South: eligibility-only sample near right panel edge; not a collision-legality claim'],
  ['door',289.5,116,0,'South: eligibility-only sample near left panel edge; not a collision-legality claim'],
  ['exit',288,32,160,'Aimed exactly at switch center from a diagonal'],
  ['exit',288,24,224,'Opposite centered switch diagonal'],
 ]){
  pose(x,z,angle);assert.equal(call(kind+'_eligible'),true,note);
  examples.push({kind,x,z,angle,note,eligible:true});
 }
});
check('Fresh A required; strafe blocked; A+B and music OFF retain interaction',()=>{
 for(const musicDisabled of [0,1])for(const kind of ['door','exit'])
 for(const input of [0x80,0x81,0x82,0x83,0xc0])for(const edge of [0,0x80,0x90]){
  pose(kind==='door'?300:288,kind==='door'?124:32,160,musicDisabled);
  put('input_buttons',input);put('button_edges',edge);call(kind+'_tick');
  const expected=Boolean(edge&128)&&!(edge&16)&&!(input&3);
  assert.equal(kind==='door'?get('door_state')===1:get('exit_flags')===128,expected,
   JSON.stringify({kind,musicDisabled,input,edge,expected}));
  counts.inputGuards++;
 }
});
check('Dead, completed, outside, behind and side-of-wall states cannot activate',()=>{
 for(const musicDisabled of [0,1])for(const kind of ['door','exit'])
 for(const rejection of ['dead','completed','outside','behind','side']){
  pose(kind==='door'?300:288,kind==='door'?124:32,160,musicDisabled);
  if(rejection==='dead')put('pistol_health',0);
  if(rejection==='completed'){put('exit_flags',128);put('exit_sound_timer',5);}
  if(rejection==='outside')coord('player_x',kind==='door'?304:294);
  if(rejection==='behind')put('pending_angle',kind==='door'?0:64);
  if(rejection==='side')coord(kind==='door'?'player_z':'player_x',kind==='door'?120:282);
  put('input_buttons',128);put('button_edges',128);call(kind+'_tick');
  assert.equal(get('door_state'),0);
  assert.equal(get('exit_flags'),rejection==='completed'?128:0);
  assert.notEqual(get('exit_sound_timer'),32,'No repeated completion chime');
  counts.inputGuards++;
 }
});
check('Door request is once-only; collision remains until matching view publishes',()=>{
 pose(300,124,160);put('button_edges',128);put('input_buttons',128);
 call('door_tick');assert.equal(get('door_state'),1);assert.equal(get('scene_version'),1);
 assert.equal(get('door_near'),0);assert.equal(call('door_eligible'),false);
 coord('move_x',296);coord('move_z',120);assert.equal(call('door_candidate_blocked'),true);
 call('door_request');assert.equal(get('scene_version'),1);
 put('visible_door',0);call('door_publish');assert.equal(get('door_state'),1);
 assert.equal(call('door_candidate_blocked'),true);
 put('visible_door',1);call('door_publish');assert.equal(get('door_state'),2);
 assert.equal(call('door_candidate_blocked'),false);
 call('door_reset');call('door_publish');assert.equal(get('door_state'),0,'Stale open picture cannot reopen reset door');
 counts.lifecycle+=10;
});
check('Closed/requested finite-panel collision remains unchanged; open clears it',()=>{
 for(const state of [0,1,2])for(const x of [286-fraction,286,296,306,306+fraction,552])
 for(const z of [118-fraction,118,120,122,122+fraction,376]){
  pose(296,124,128);put('door_state',state);coord('move_x',x);coord('move_z',z);
  const expected=state<2&&x>=286&&x<=306&&z>=118&&z<=122;
  assert.equal(call('door_candidate_blocked'),expected,JSON.stringify({state,x,z,expected}));counts.collision++;
 }
});
let baselineComparison=null;
if(args['--baseline-build']){
 const baselineBuild=resolve(args['--baseline-build']);
 const baselineRom=readFileSync(resolve(baselineBuild,'hangar-ntsc.nes'));
 nes.loadROM(baselineRom.toString('latin1'));cpu=nes.cpu;labels=readLabels(baselineBuild);
 nes.ppu.updateControlReg1(0);nes.ppu.updateControlReg2(0);
 check('Previous 45-degree cone rejects the same legal close-contact prompt poses',()=>{
  for(const musicDisabled of [0,1])for(const p of closeContactPoses){
   pose(p.x,p.z,p.angle,musicDisabled);
   coord('move_x',p.x);coord('move_z',p.z);put('player_floor',2);
   assert.equal(call('movement_candidate_blocked'),false,'Baseline fixture is physically legal');
   assert.equal(call('door_eligible'),false,'Baseline confirms the old close-contact rejection');
   put('input_buttons',0x80);put('button_edges',0x80);call('door_tick');
   assert.equal(get('door_near'),0,'Baseline does not offer the prompt');
   assert.equal(get('door_state'),0,'Baseline does not accept a fresh A press');
   counts.baselineCloseContact++;
  }
 });
 baselineComparison={romSha256:createHash('sha256').update(baselineRom).digest('hex'),
  closeContactPoses:closeContactPoses.length,musicModes:2,
  result:'All legal close-contact cases reject prompt/use in the previous cone and accept in the candidate.'};
}
mkdirSync(dirname(output),{recursive:true});
const report={passed:true,romSha256:createHash('sha256').update(rom).digest('hex'),checks,counts,calls,examples,
 baselineComparison,
 limitations:'Injected CPU poses execute actual linked 6502 routines; no PPU timing, controller-only route, or physical-console claim.'};
writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:true,checks:checks.length,counts,calls,output}));
