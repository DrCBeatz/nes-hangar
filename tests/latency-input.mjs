/** Actual linked 6502 latency-policy checks, with explicit NMI-owned mutations.
 * This does not measure input-device, display or PPU timing. The Mesen latency
 * comparison covers those separately. ROM and source inputs remain unchanged.
 */
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
const here=dirname(fileURLToPath(import.meta.url)),args={};
for(let i=2;i<process.argv.length;i++){
 const key=process.argv[i];
 if(key==='--help'){
  console.log('node tests/latency-input.mjs --core JSNES/src/index.js [--build BUILD] [--policy release|all] [--output JSON]');process.exit(0);
 }
 assert.ok(['--core','--build','--policy','--output'].includes(key),'Unknown option '+key);
 assert.ok(process.argv[i+1]&&!process.argv[i+1].startsWith('--'),'Missing value for '+key);args[key]=process.argv[++i];
}
const policy=args['--policy']||'release';assert.ok(['release','all'].includes(policy));
const build=resolve(args['--build']||resolve(here,'../build')),core=resolve(args['--core']||process.env.JSNES_CORE||'');
assert.ok(args['--core']||process.env.JSNES_CORE,'Supply --core or JSNES_CORE');
const hash=b=>createHash('sha256').update(b).digest('hex');
assert.equal(hash(readFileSync(resolve(dirname(core),'cpu.js'))),'17469b310738c4b3092d648289c8537a4584f6b45bc1735adb540968a75308f2','Use pinned JSNES CPU');
const {NES}=await import(pathToFileURL(core));
const rom=readFileSync(resolve(build,'hangar-ntsc.nes'));
assert.equal(rom[4],8,'Eight 16 KiB PRG banks');
const labels=Object.fromEntries(readFileSync(resolve(build,'hangar.lbl'),'utf8').split('\n')
 .map(s=>s.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));
const template=readFileSync(resolve(build,'nametable.bin'));
const machine=new NES();machine.loadROM(rom.toString('latin1'));const cpu=machine.cpu;
machine.ppu.updateControlReg1(0);machine.ppu.updateControlReg2(0);
const counts={},checks=[],timings={};let writes=[],calls=0;
const rawWrite=cpu.write.bind(cpu);cpu.write=(a,v)=>{writes.push(a);rawWrite(a,v);};
function put(n,v,o=0){assert.ok(n in labels,n);cpu.mem[labels[n]+o]=v&255;}
function get(n,o=0){assert.ok(n in labels,n);return cpu.mem[labels[n]+o];}
function word(n,v){if(v!==undefined){put(n,v);put(n,v>>8,1);}return get(n)|(get(n,1)<<8);}
function coord(n,v){const q=Math.round(v*256);put(n,q);put(n,q>>8,1);put(n+'_hi',q>>16);}
function allowed(fields){const set=new Set();for(const[n,size]of fields)for(let i=0;i<size;i++)set.add(labels[n]+i);return set;}
const isStack=a=>a>=0x100&&a<0x200;
function ownership(set,name){assert.ok(writes.every(a=>isStack(a)||set.has(a)),name+' writes only owned RAM; unexpected '+writes.filter(a=>!isStack(a)&&!set.has(a)).map(a=>a.toString(16)));}
function begin(n){cpu.REG_ACC=0;cpu.REG_X=0x71;cpu.REG_Y=0xa3;cpu.REG_SP=0x1ff;cpu.push(0x4f);cpu.push(0xff);cpu.REG_PC=labels[n]-1;writes=[];cpu.F_INTERRUPT=1;cpu.irqRequested=false;}
function step(){const cycles=cpu.emulate();cpu.irqRequested=false;cpu.nmiPending=false;cpu.nmiRaised=false;return cycles;}
function run(n,hook=()=>{},stop=0x5000,max=3000000){
 begin(n);let steps=0,cycles=0;
 while(cpu.REG_PC!==stop-1){assert.ok(steps<max,n+' must return');hook(cpu.REG_PC+1,steps);cycles+=step();steps++;}
 if(stop===0x5000)assert.equal(cpu.REG_SP&255,255,n+' balanced stack');calls++;
 const t=timings[n]??={calls:0,min:Infinity,max:0,total:0};t.calls++;t.min=Math.min(t.min,cycles);t.max=Math.max(t.max,cycles);t.total+=cycles;
 return {carry:Boolean(cpu.F_CARRY),steps,cycles};
}
function clear(){cpu.mem.fill(0,0,0x8000);machine.mmap.loadRomBank(0,0x8000);machine.mmap.loadRomBank(7,0xc000);}
function check(n,fn){fn();checks.push(n);}
function normalized(buttons){
 // Express intent independently as signed axes, not the assembly's masks.
 const x=Number(Boolean(buttons&1))-Number(Boolean(buttons&2));
 const z=Number(Boolean(buttons&8))-Number(Boolean(buttons&4));
 return (x>0?1:x<0?2:0)|(z>0?8:z<0?4:0)|(x&&buttons&128?128:0);
}
function invalidates(old,next){
 const a=normalized(old),b=normalized(next);
 const directions=policy==='all'?Boolean((a^b)&15):Boolean((a&15)&~b);
 return directions||Boolean(a&3)&&Boolean((a^b)&128)||Boolean((next&~old)&0x30);
}
const observerOwned=allowed([['latency_epoch',2],['latency_hard_epoch',2],['latency_intent',1],['latency_new_intent',1]]);
const checkpointOwned=allowed([['latency_check_version',1],['latency_check_epoch',2],['latency_height_decision',1]]);
function observer(old,next,epoch=0x12ff,hard=0x34ff){
 put('input_buttons',next);put('button_edges',next&~old);put('latency_intent',normalized(old));word('latency_epoch',epoch);word('latency_hard_epoch',hard);
 run('latency_observe_input');ownership(observerOwned,'input observer');
 assert.equal(word('latency_epoch'),(epoch+Number(invalidates(old,next)))&65535,JSON.stringify({old,next,policy}));
 assert.equal(word('latency_hard_epoch'),(hard+Number(Boolean((next&~old)&0x30)))&65535);
 assert.equal(get('latency_intent'),normalized(next));
}
check('Every raw controller transition follows normalized direction and hard-control policy',()=>{
 clear();let events=0;
 for(let old=0;old<256;old++)for(let next=0;next<256;next++){observer(old,next);events+=invalidates(old,next);}
 counts.controllerTransitions=65536;counts.invalidatingTransitions=events;
 for(const epoch of [0,1,254,255,256,65534,65535])for(const[old,next]of [[8,0],[0,8],[1,129],[0,0x30],[8,0x30]])observer(old,next,epoch,epoch);
 counts.epochWrapCases=35;
});
function snapshotFixture(){
 clear();
 for(const[n,v]of [['player_x',513.25],['player_z',767.75],['zombie_x',510.125],['zombie_z',770.5]]){
  coord(n,v);coord(n.replace('player','render').replace(/^zombie/,'render_zombie'),v);
 }
 for(const[live,captured,v]of [['pending_angle','render_angle',43],['player_floor','render_floor',2],['player_eye','render_eye',6],
  ['requested_mode','render_mode',0],['scene_version','render_scene_version',75],['zombie_epoch','render_zombie_epoch',19]]){put(live,v);put(captured,v);}
 put('zombie_walk_counter',0x20);put('render_zombie_pose',0x20);put('zombie_hp',3);put('render_zombie_hp',3);
 put('active_encounter',0);put('medkit_state',0);put('render_medkit_state',0);put('door_state',0);put('render_door',0);
 put('visible_floor',2);put('visible_eye',6);put('latency_budget',1);
 word('latency_render_epoch',65535);word('latency_epoch',0);word('latency_render_hard_epoch',65535);word('latency_hard_epoch',65535);word('nmi_count',255);
}
check('Current-snapshot guard checks all Q16.8 coordinates, actors, selected items and door geometry',()=>{
 snapshotFixture();assert.equal(run('latency_snapshot_current').carry,true);ownership(new Set(),'snapshot guard');
 const fields=[['player_x',2],['player_x_hi',1],['player_z',2],['player_z_hi',1],['pending_angle',1],['player_floor',1],['player_eye',1],
  ['requested_mode',1],['scene_version',1],['zombie_epoch',1],['zombie_x',2],['zombie_x_hi',1],['zombie_z',2],['zombie_z_hi',1],
  ['zombie_walk_counter',1],['zombie_hp',1],['medkit_state',1],['active_encounter',1],['door_state',1]];
 let cases=0;
 for(const[n,size]of fields)for(let i=0;i<size;i++){
  snapshotFixture();put(n,get(n,i)^(n==='zombie_walk_counter'?0x20:n==='medkit_state'?0x80:1),i);
  assert.equal(run('latency_snapshot_current').carry,false,n+' byte '+i);ownership(new Set(),'snapshot guard');cases++;
 }
 for(const hp of[0,1,3])for(const corpse of[0,1,128])for(const captured of[0,1,3,128]){
  snapshotFixture();put('zombie_hp',hp);put('corpse_state',corpse);put('render_zombie_hp',captured);
  assert.equal(run('latency_snapshot_current').carry,captured===(hp|| (corpse?128:0)));cases++;
 }
 for(const encounter of[0,1,2])for(const state of[0,31,64,128,192,255])for(const captured of[0,64,128,192]){
  snapshotFixture();put('active_encounter',encounter);put('medkit_state',state);put('render_medkit_state',captured);
  const expected=encounter===0?state&128:encounter===1?((state&64)?192:64):128;
  assert.equal(run('latency_snapshot_current').carry,captured===expected);cases++;
 }
 for(const state of[0,1,2])for(const captured of[0,1]){
  snapshotFixture();put('door_state',state);put('render_door',captured);assert.equal(run('latency_snapshot_current').carry,captured===Number(state!==0));cases++;
 }
 // Weapon/HUD/audio timers and collection of the OTHER room's item do not
 // invalidate an otherwise current world snapshot.
 for(const[n,v]of [['pistol_flash_timer',8],['pistol_dirty',3],['music_disabled',1],['medkit_state',64],['zombie_walk_counter',63]]){
  snapshotFixture();put(n,v);assert.equal(run('latency_snapshot_current').carry,true,n+' is not a world change');cases++;
 }
 counts.snapshotCases=cases;
});
check('One retry per acquired bank, including epoch wrap and repeated new events',()=>{
 snapshotFixture();word('latency_abort_count',65535);put('latency_budget',0);run('latency_job_begin');assert.equal(get('latency_budget'),1);
 coord('player_x',514);assert.equal(run('latency_checkpoint').carry,true);
 run('latency_record_abort');assert.equal(get('latency_budget'),0);assert.equal(word('latency_abort_count'),0);
 for(const epoch of[0,1,65535])for(const hard of[0,1,65535]){
  word('latency_epoch',epoch);word('latency_hard_epoch',hard);assert.equal(run('latency_checkpoint').carry,false);ownership(checkpointOwned,'budget-exhausted guard');
 }
 run('latency_job_begin');assert.equal(get('latency_budget'),1);word('latency_epoch',0);word('latency_hard_epoch',0);assert.equal(run('latency_checkpoint').carry,true);
 counts.budgetCases=12;
});
function heightSetup(render,current,visible,{budget=1,stale=true,hard=false,sameCamera=false}={}){
 snapshotFixture();if(!sameCamera)coord('player_x',514);
 for(const[p,v]of [['render',render],['player',current],['visible',visible]]){put(p+'_floor',v[0]);put(p+'_eye',v[1]);}
 put('latency_budget',budget);word('latency_epoch',stale?0:65535);word('latency_hard_epoch',hard?0:65535);
}
const pairEq=(a,b)=>a[0]===b[0]&&a[1]===b[1];
function heightDecision(render,current,visible,{budget=1,stale=true,hard=false,sameCamera=false}={}){
 const sameHeight=pairEq(render,current);
 const preserve=!hard&&sameHeight&&(sameCamera||visible[1]!==0&&!pairEq(render,visible));
 return Boolean(budget&&stale&&!preserve);
}
check('Floor-transition priority, current-view reuse and hard-control override truth table',()=>{
 const pairs=[[0,0],[0,4],[2,6],[4,8]];let cases=0;
 for(const render of pairs)for(const current of pairs)for(const visible of pairs)
 for(const budget of[0,1])for(const stale of[false,true])for(const hard of[false,true])for(const sameCamera of[false,true]){
  const options={budget,stale,hard,sameCamera};heightSetup(render,current,visible,options);
  assert.equal(run('latency_checkpoint').carry,heightDecision(render,current,visible,options),JSON.stringify({render,current,visible,...options}));
  assert.equal(cpu.REG_X,0x71);assert.equal(cpu.REG_Y,0xa3);ownership(checkpointOwned,'height/current guard');
  assert.equal(word('latency_render_epoch'),65535);assert.equal(word('latency_render_hard_epoch'),65535);assert.equal(get('latency_budget'),budget);cases++;
 }
 // A soft edge after snapshot is safe while all inputs match. The decision
 // must be reconsidered after motion resumes, even without a second edge.
 snapshotFixture();assert.equal(run('latency_checkpoint').carry,false);assert.equal(word('latency_render_epoch'),65535);
 coord('player_x',514);assert.equal(run('latency_checkpoint').carry,true);counts.heightAndCurrentCases=cases+2;
});
const races=[];
function guardedRace(name,entry,setup,mutate,expectedBefore,expectedAfter){
 setup();const trace=[];run(entry,pc=>trace.push(pc));
 const reads=trace.flatMap((pc,i)=>cpu.mem[pc]===0xa5&&cpu.mem[pc+1]===labels.nmi_count?[i]:[]);
 assert.equal(reads.length,2,name+' two version reads');const finalRead=reads.at(-1);let late=0;
 for(let at=0;at<=trace.length;at++){
  setup();let injected=false;const inject=()=>{word('nmi_count',256);mutate();injected=true;};
  const result=run(entry,(pc,i)=>{if(i===at)inject();});if(!injected)inject();
  assert.equal(result.carry,at<=finalRead?expectedAfter:expectedBefore,JSON.stringify({name,at,finalRead}));
  assert.equal(cpu.REG_X,0x71);assert.equal(cpu.REG_Y,0xa3);ownership(checkpointOwned,'interrupted guard');late+=at>finalRead;
 }
 races.push({name,instructionBoundaryInjections:trace.length+1,finalVersionReadInstruction:finalRead,documentedLateCoherentDecisions:late});
}
check('NMI guard interleavings never accept torn epochs or mixed height/current decisions',()=>{
 guardedRace('epoch wraps during ordinary check','latency_checkpoint',()=>{snapshotFixture();coord('player_x',514);word('latency_epoch',65535);},()=>word('latency_epoch',0),false,true);
 guardedRace('published height catches up','latency_height_check',()=>heightSetup([0,4],[0,4],[2,6]),()=>{put('visible_floor',0);put('visible_eye',4);},false,true);
 guardedRace('player steps back to old height','latency_height_check',()=>heightSetup([0,4],[0,4],[2,6]),()=>{put('player_floor',2);put('player_eye',6);},false,true);
 guardedRace('hard event overrides step priority','latency_height_check',()=>heightSetup([0,4],[0,4],[2,6]),()=>word('latency_hard_epoch',0),false,true);
 guardedRace('current snapshot becomes stale without another intent edge','latency_height_check',()=>snapshotFixture(),()=>coord('player_x',514),false,true);
 counts.instructionBoundaryInjections=races.reduce((s,r)=>s+r.instructionBoundaryInjections,0);
});
function producerFixture(bank=0){
 clear();for(const base of[0x6000,0x7000])for(let i=0;i<1024;i++)cpu.mem[base+0xc00+i]=template[i];
 for(const base of[0x6000,0x7000])cpu.mem.fill(0,base+0xea0,base+0x1000);
 coord('player_x',52);coord('player_z',172);put('player_floor',2);put('player_eye',6);put('visible_floor',2);put('visible_eye',6);
 put('pistol_health',100);put('medkit_state',0xc0);put('render_buffer',bank);put('visible_buffer',bank^1);word('nmi_count',255);
}
const captureNames=['render_x','render_z','render_x_hi','render_z_hi','render_angle','render_floor','render_eye','render_mode','render_scene_version',
 'render_zombie_x','render_zombie_z','render_zombie_x_hi','render_zombie_z_hi','render_zombie_epoch','render_zombie_pose','render_zombie_hp','render_medkit_state','render_door','latency_render_epoch','latency_render_hard_epoch'];
const multiByte=new Set(['render_x','render_z','render_zombie_x','render_zombie_z','latency_render_epoch','latency_render_hard_epoch']);
function captured(){return captureNames.map(n=>multiByte.has(n)?word(n):get(n));}
function liveChange(){
 word('nmi_count',256);coord('player_x',514.5);coord('player_z',768.25);put('pending_angle',160);put('player_floor',0);put('player_eye',4);
 put('requested_mode',1);put('scene_version',1);coord('zombie_x',530.25);coord('zombie_z',775.75);put('zombie_epoch',1);put('zombie_walk_counter',0x20);
 put('zombie_hp',0);put('corpse_state',1);put('active_encounter',1);put('medkit_state',0x40);put('door_state',1);word('latency_epoch',0);word('latency_hard_epoch',0);
}
check('Producer snapshots remain coherent across every NMI boundary, including high coordinates and actor handoff',()=>{
 const setup=()=>{producerFixture();word('latency_epoch',65535);word('latency_hard_epoch',65535);put('zombie_hp',3);};
 setup();const trace=[];run('render_begin',pc=>trace.push(pc),labels.opening_render);const old=captured();
 setup();liveChange();run('render_begin',()=>{},labels.opening_render);const next=captured();let oldCount=0,nextCount=0;
 for(let at=0;at<=trace.length;at++){
  setup();let injected=false;run('render_begin',(pc,i)=>{if(i===at){liveChange();injected=true;}},labels.opening_render);if(!injected)liveChange();
  const actual=captured();assert.ok(JSON.stringify(actual)===JSON.stringify(old)||JSON.stringify(actual)===JSON.stringify(next),'Coherent producer capture at '+at);
  oldCount+=JSON.stringify(actual)===JSON.stringify(old);nextCount+=JSON.stringify(actual)===JSON.stringify(next);
  for(const n of['angle','floor','eye','mode','door','zombie_epoch','zombie_hp'])assert.equal(get('buffer_'+n),get('render_'+n));
  for(const n of['x','z','zombie_x','zombie_z']){assert.equal(word('buffer_'+n),word('render_'+n));assert.equal(get('buffer_'+n+'_hi'),get('render_'+n+'_hi'));}
 }
 assert.ok(oldCount&&nextCount);counts.producerSnapshotInjections=trace.length+1;counts.oldCoherentSnapshots=oldCount;counts.newCoherentSnapshots=nextCount;
});
const renderCases=[];
check('Actual renderer restarts at most once, preserves dirty union and completes unchanged pixels',()=>{
 for(const[name,initial,first,second,expected]of[
  ['release and reverse during second attempt',8,0,4,1],
  ['start during active production',0,8,null,policy==='all'?1:0],
  ['add turn while walking',8,9,null,policy==='all'?1:0],
 ]){
  producerFixture();put('latency_intent',normalized(initial));put('input_buttons',initial);
  // The other staging bank and its active metadata belong to the uploader.
  put('buffer_state',3,1);put('buffer_tile_count',47,1);put('nt_dirty_count',7,1);
  const other=Buffer.from(cpu.mem.slice(0x7000,0x7c00));const beforeNames=Buffer.from(cpu.mem.slice(0x6c60,0x6ea0));
  let attempts=0,aborts=0,firstDone=false,secondDone=false,dirtyAtAbort=[];
  const mutate=buttons=>{
   const prior=get('input_buttons');put('input_buttons',buttons);put('button_edges',buttons&~prior);put('latency_intent',normalized(buttons));
   word('latency_epoch',word('latency_epoch')+Number(invalidates(prior,buttons)));word('nmi_count',word('nmi_count')+1);
   // A complete synthetic NMI movement: no staging or producer scratch writes.
   coord('player_z',secondDone?171:173);
  };
  const result=run('render_begin',pc=>{
   if(pc===labels.latency_attempt_begin){attempts++;assert.ok(attempts<=2,name+' bounded attempts');if(attempts===2)for(const i of dirtyAtAbort)assert.ok(get('nt_dirty_flags',i),'Dirty union retained');}
   if(pc===labels.latency_abort){aborts++;dirtyAtAbort=Array.from({length:48},(_,i)=>i).filter(i=>get('nt_dirty_flags',i));}
   if(pc===labels.latency_strip_checkpoint&&get('cell_col')===8&&!firstDone){firstDone=true;mutate(first);}
   if(pc===labels.latency_strip_checkpoint&&attempts===2&&get('cell_col')===12&&second!==null&&!secondDone){secondDone=true;mutate(second);}
  });
  assert.ok(firstDone);assert.equal(aborts,expected);assert.equal(attempts,expected+1);assert.equal(word('latency_abort_count'),expected);assert.equal(get('buffer_state'),2);
  assert.equal(get('buffer_state',1),3);assert.equal(get('buffer_tile_count',1),47);assert.equal(get('nt_dirty_count',1),7);assert.deepEqual(Buffer.from(cpu.mem.slice(0x7000,0x7c00)),other);
  const count=get('buffer_tile_count'),patterns=Buffer.from(cpu.mem.slice(0x6000,0x6000+count*16)),names=Buffer.from(cpu.mem.slice(0x6c60,0x6ea0));
  const dirty=Array.from({length:get('nt_dirty_count')},(_,i)=>get('nt_dirty_list',i));
  assert.equal(new Set(dirty).size,dirty.length);for(let i=0;i<names.length;i++)if(names[i]!==beforeNames[i])assert.ok(dirty.includes((i>>4)+6),'Every changed name scheduled for upload');
  const pose={x:(word('render_x')+get('render_x_hi')*65536)/256,z:(word('render_z')+get('render_z_hi')*65536)/256,angle:get('render_angle')};
  producerFixture();coord('player_x',pose.x);coord('player_z',pose.z);put('pending_angle',pose.angle);run('render_begin');
  assert.equal(get('buffer_tile_count'),count);assert.deepEqual(Buffer.from(cpu.mem.slice(0x6000,0x6000+count*16)),patterns);assert.deepEqual(Buffer.from(cpu.mem.slice(0x6c60,0x6ea0)),names);
  renderCases.push({name,attempts,aborts,finalPose:pose,patternCount:count,dirtyBlocks:dirty.length,dirtyAtAbort:dirtyAtAbort.length,cycles:result.cycles,sha256:hash(Buffer.concat([patterns,names]))});
 }
});
const report={passed:true,policy,romSha256:hash(rom),testSha256:hash(readFileSync(fileURLToPath(import.meta.url))),coreSha256:hash(readFileSync(core)),checks,counts,calls,timings,races,renderCases,
 limitations:'Linked 6502 execution with synthetic NMI-owned mutations and seeded camera poses. Pixel preservation compares a retried frame with a clean linked render of the same snapshot, not an independent geometric oracle. No input-device latency, PPU deadline, controller-only route or physical-console claim.'};
const output=resolve(args['--output']||resolve(build,'latency-input.json'));mkdirSync(dirname(output),{recursive:true});writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({passed:true,policy,checks:checks.length,counts,calls,renderCases,output},null,2));
