/** Linked ammo interaction checks, including every legal lower MMC1 PRG selection.
 * Runs the actual 6502 routines with injected state and compares their range
 * decisions to an independent integer oracle. Mesen movement tests are separate.
 * No ROM file or map source is modified.
 */
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve, dirname} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),args={};
for(let i=2;i<process.argv.length;i+=2){
 const key=process.argv[i];
 if(key==='--help'){console.log('node tests/ammo-interactions.mjs --core JSNES/src/index.js --baseline BUILD [--build BUILD] [--output JSON]');process.exit(0);}
 assert.ok(['--core','--baseline','--build','--output'].includes(key),'Unknown option '+key);
 assert.ok(process.argv[i+1]&&!process.argv[i+1].startsWith('--'),'Missing value for '+key);args[key]=process.argv[i+1];
}
assert.ok(args['--core']&&args['--baseline'],'Supply --core and --baseline');
const core=resolve(args['--core']),hash=b=>createHash('sha256').update(b).digest('hex');
assert.equal(hash(readFileSync(resolve(dirname(core),'cpu.js'))),'17469b310738c4b3092d648289c8537a4584f6b45bc1735adb540968a75308f2','Use pinned JSNES CPU');
const {NES}=await import(pathToFileURL(core));
class Machine{
 constructor(build){
  this.build=build;this.rom=readFileSync(resolve(build,'hangar-ntsc.nes'));
  this.labels=Object.fromEntries(readFileSync(resolve(build,'hangar.lbl'),'utf8').split('\n').map(s=>s.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));
  this.scene=JSON.parse(readFileSync(resolve(build,'map.json')));this.calls={};this.maxCycles={};
  assert.equal(this.rom[4],8,'Eight 16 KiB PRG banks');
 }
 fixture(){
  const nes=new NES();nes.loadROM(this.rom.toString('latin1'));nes.cpu.mem.fill(0,0,0x8000);nes.ppu.updateControlReg1(0);nes.ppu.updateControlReg2(0);
  const c={nes,writes:[]},raw=nes.cpu.write.bind(nes.cpu);nes.cpu.write=(a,v)=>{c.writes.push([a,v]);raw(a,v);};
  this.call(c,'music_init',0,true);for(const n of ['pistol_reset','medkit_reset','results_reset'])this.call(c,n);
  this.put(c,'pistol_health',100);return c;
 }
 put(c,n,v,o=0){assert.ok(n in this.labels,n);c.nes.cpu.mem[this.labels[n]+o]=v&255;}
 get(c,n,o=0){assert.ok(n in this.labels,n);return c.nes.cpu.mem[this.labels[n]+o];}
 pose(c,x,z){for(const[n,q]of[['player_x',x],['player_z',z]]){this.put(c,n,q);this.put(c,n,q>>8,1);this.put(c,n+'_hi',q>>16);}}
 bank(c,b){c.nes.mmap.loadRomBank(b,0x8000);c.nes.mmap.loadRomBank(7,0xc000);assert.deepEqual(Buffer.from(c.nes.cpu.mem.slice(0x8000,0xc000)),this.rom.subarray(16+b*16384,16+(b+1)*16384));}
 call(c,n,a=0,allowMapper=false){
  assert.ok(n in this.labels,n);const cpu=c.nes.cpu;cpu.REG_ACC=a;cpu.REG_SP=0x1ff;cpu.push(0x4f);cpu.push(0xff);cpu.REG_PC=this.labels[n]-1;cpu.F_INTERRUPT=1;cpu.irqRequested=false;c.writes=[];
  let cycles=0,steps=0;while(cpu.REG_PC!==0x4fff){assert.ok(++steps<100000,n+' returns');cycles+=cpu.emulate();cpu.irqRequested=false;cpu.nmiPending=false;cpu.nmiRaised=false;}
  assert.equal(cpu.REG_SP&255,255,n+' balanced stack');if(!allowMapper)assert.ok(c.writes.every(([a])=>a<0x8000),n+' must not bank switch');
  this.calls[n]=(this.calls[n]||0)+1;this.maxCycles[n]=Math.max(this.maxCycles[n]||0,cycles);this.lastCycles=cycles;return Boolean(cpu.F_CARRY);
 }
 shadows(c){return c.writes.filter(([a])=>a>=this.labels.audio_sfx_regs&&a<this.labels.audio_sfx_regs+24).map(([a,v])=>[0x4000+a-this.labels.audio_sfx_regs,v]);}
}
const baseline=new Machine(resolve(args['--baseline'])),candidate=new Machine(resolve(args['--build']||resolve(root,'build')));
assert.equal(baseline.scene.ammo.pickup_radius,3);assert.equal(candidate.scene.ammo.pickup_radius,3.5);assert.equal(candidate.scene.medkit.pickup_radius,6);
assert.deepEqual(candidate.scene.medkit,baseline.scene.medkit,'Medkit metadata unchanged');
const a={...baseline.scene.ammo},b={...candidate.scene.ammo};delete a.pickup_radius;delete b.pickup_radius;assert.deepEqual(a,b,'Ammo position/art/amount unchanged');
const oracle=(dx,dz,r)=>Math.ceil(Math.abs(dx)/32)**2+Math.ceil(Math.abs(dz)/32)**2<(r*8)**2;
const counts={nativeRangeCalls:0,translatedRangeCalls:0,medkitUnchanged:0,newlyAccepted:0,scratchCases:0,lifecycleCases:0};
const machines=[baseline,candidate],contexts=machines.map(m=>m.fixture());
const offsets=Array.from(new Set([0,-1,1,-65536,65536,-131072,131072,
 ...Array.from({length:25},(_,i)=>(i-12)*128).flatMap(v=>[v-1,v,v+1]),
 ...[544,576,704,736,768,800,832,864,896,928].flatMap(v=>[v-1,v,v+1,-v-1,-v,-v+1])])).sort((a,b)=>a-b);
// Bank7 is the fixed code bank. Banks0–6 contain the mirrored COMMON tables
// required by pickup math when selected in the lower CPU window.
for(let bank=0;bank<7;bank++){
 machines.forEach((m,i)=>m.bank(contexts[i],bank));
 for(const active of[0,1]){
  machines.forEach((m,i)=>m.put(contexts[i],'active_encounter',active));
  for(const dx of offsets)for(const dz of offsets){
   const outcomes=[];for(let i=0;i<2;i++){
    const m=machines[i],c=contexts[i],item=active?m.scene.ammo:m.scene.medkit,x=item.x*256+dx,z=item.z*256+dz;
    if(x<0||z<0||x>=1024*256||z>=1024*256){outcomes.push(null);continue;}
    m.pose(c,x,z);const accepted=m.call(c,'medkit_in_range');assert.equal(accepted,oracle(dx,dz,item.pickup_radius),JSON.stringify({bank,active,dx,dz,radius:item.pickup_radius}));
    assert.ok(c.writes.every(([a])=>a<0x2000||a>0x4017),'Range has no PPU/APU side effects');outcomes.push(accepted);counts.nativeRangeCalls++;
   }
   if(outcomes.every(v=>v!==null)){
    if(active===0){assert.equal(outcomes[0],outcomes[1]);counts.medkitUnchanged++;}
    else{assert.ok(!outcomes[0]||outcomes[1],'Expansion preserves old accepted points');if(!outcomes[0]&&outcomes[1])counts.newlyAccepted++;}
   }
  }
 }
}
const critical=[];
// Fractional edge, conservative rounding, strict3.5 boundary and old wall-side
// complaint. Mixed-axis pairs exercise the full $0310 squared threshold.
for(const[dx,dz]of[[742,0],[863,0],[864,0],[865,0],[895,0],[896,0],[960,0],[608,640],[640,640],[864,224],[864,256],[1,-1]]){
 const m=candidate,c=contexts[1];m.bank(c,0);m.put(c,'active_encounter',1);m.pose(c,m.scene.ammo.x*256+dx,m.scene.ammo.z*256+dz);
 const accepted=m.call(c,'medkit_in_range');assert.equal(accepted,oracle(dx,dz,3.5));critical.push({dxQ8:dx,dzQ8:dz,accepted,squaredEighths:Math.ceil(Math.abs(dx)/32)**2+Math.ceil(Math.abs(dz)/32)**2});
}
const translations=[[1,1],[255,255],[256,256],[257,511],[511,512],[512,513],[767,768],[1022,1022]];
const translatedOffsets=[-961,-960,-959,-897,-896,-895,-865,-864,-863,-641,-640,-639,-33,-32,-31,-1,0,1,31,32,33,639,640,641,863,864,865,895,896,897,959,960,961,-65536,65536];
for(const[x,z]of translations){
 const m=candidate,c=m.fixture();m.put(c,'active_encounter',1);
 for(const[axis,v]of[['x',x],['z',z]]){m.put(c,'pickup_'+axis+'_lo',v,1);m.put(c,'pickup_'+axis+'_hi',v>>8,1);}
 for(const dx of translatedOffsets)for(const dz of translatedOffsets){const px=x*256+dx,pz=z*256+dz;if(px<0||pz<0||px>=1024*256||pz>=1024*256)continue;m.pose(c,px,pz);assert.equal(m.call(c,'medkit_in_range'),oracle(dx,dz,3.5),JSON.stringify({x,z,dx,dz}));counts.translatedRangeCalls++;}
}
{
 const m=candidate,c=m.fixture(),allowed=new Set();for(const[n,len]of[['zombie_delta',2],['zombie_square',2],['zombie_coord',1],['coordinate_nmi_scratch',4]])for(let i=0;i<len;i++)allowed.add(m.labels[n]+i);
 for(const active of[0,1,2])for(const[dx,dz]of[[0,0],[742,0],[864,224],[864,256],[896,0],[65536,0],[0,-65536]]){
  const item=active===0?m.scene.medkit:m.scene.ammo;m.put(c,'active_encounter',active);m.pose(c,item.x*256+dx,item.z*256+dz);const before=c.nes.cpu.mem.slice(0,0x8000);m.call(c,'medkit_in_range');
  for(let a=0;a<0x8000;a++)if((a<0x800||a>=0x6000)&&!(a>=0x100&&a<0x200)&&!allowed.has(a))assert.equal(c.nes.cpu.mem[a],before[a],'Unowned scratch write '+a.toString(16));counts.scratchCases++;
 }
}
function setup(m,active=1,ammo=6,health=75,state=0,dx=0,dz=0){const c=m.fixture(),item=active===0?m.scene.medkit:m.scene.ammo;for(const[n,v]of[['active_encounter',active],['pistol_ammo',ammo],['pistol_health',health],['medkit_state',state],['medkit_dirty',0],['pistol_dirty',0],['scene_version',10],['button_edges',0],['exit_flags',0]])m.put(c,n,v);m.pose(c,item.x*256+dx,item.z*256+dz);return c;}
const lifecycle=[];
for(const musicOff of[0,1])for(const active of[0,1])for(const prior of[0,active?0x80:0x40]){
 const m=candidate,c=setup(m,active,active?95:6,active?75:90,prior);m.put(c,'music_disabled',musicOff);m.call(c,'medkit_tick');
 const field=active?'pistol_ammo':'pistol_health',expected=active?99:100,collected=active?0x40:0x80;
 assert.equal(m.get(c,field),expected);assert.equal(m.get(c,'scene_version'),11);assert.equal(m.get(c,'medkit_dirty'),1);assert.ok(m.get(c,'pistol_dirty')&2);assert.equal(m.get(c,'medkit_state')&0xc0,(prior&0xc0)|collected);
 assert.deepEqual(m.shadows(c),[[0x4006,active?0x54:0xa9],[0x4015,15],[0x4004,0xb8],[0x4005,8],[0x4007,0xf8]],'Same pickup sound request');assert.ok(c.writes.every(([a])=>a<0x4000||a>0x4017),'Effect writes shadows only');
 m.call(c,'music_tick');assert.equal(m.get(c,'audio_owner',1),2,'Pickup owns pulse2 in either music mode');assert.ok(c.writes.some(([a,v])=>a===0x4006&&v===(active?0x54:0xa9)));
 const sound=[];for(let i=0;i<20;i++){m.call(c,'medkit_tick');sound.push(...m.shadows(c));assert.equal(m.get(c,field),expected);assert.equal(m.get(c,'scene_version'),11);}
 assert.equal(sound.filter(([a])=>a===0x4006).length,1,'One second note, no collection retrigger');assert.ok(sound.some(([a,v])=>a===0x4006&&v===(active?0x8e:0x70)));assert.equal(m.get(c,'medkit_state'),(prior&0xc0)|collected);
 m.call(c,'results_capture');assert.equal(m.get(c,'results_items'),prior?2:1);lifecycle.push({musicOff,active,prior,itemCount:m.get(c,'results_items')});counts.lifecycleCases++;
}
for(const active of[0,1]){const m=candidate,c=setup(m,active,active?99:6,active?75:100);m.call(c,'medkit_tick');assert.equal(m.get(c,'medkit_state'),0);assert.equal(m.get(c,'scene_version'),10);assert.deepEqual(m.shadows(c),[]);m.call(c,'results_capture');assert.equal(m.get(c,'results_items'),0);m.put(c,active?'pistol_ammo':'pistol_health',active?98:99);m.call(c,'medkit_tick');assert.ok(m.get(c,'medkit_state')&(active?0x40:0x80));counts.lifecycleCases++;}
for(const reason of['dead','complete','no-item-zone']){const m=candidate,c=setup(m,reason==='no-item-zone'?2:1,6,reason==='dead'?0:75);if(reason==='complete')m.put(c,'exit_flags',0x80);m.call(c,'medkit_tick');assert.equal(m.get(c,'pistol_ammo'),6);assert.equal(m.get(c,'medkit_state')&0xc0,0);assert.equal(m.get(c,'scene_version'),10);counts.lifecycleCases++;}
for(const[dx,dz]of[[742,0],[896,0],[960,0],[864,224],[864,256]]){const m=candidate,c=setup(m,1,6,75,0,dx,dz);m.call(c,'medkit_tick');assert.equal(Boolean(m.get(c,'medkit_state')&0x40),oracle(dx,dz,3.5));counts.lifecycleCases++;}
assert.ok(counts.newlyAccepted>0);
const report={passed:true,radiusBefore:3,radiusAfter:3.5,medkitRadius:6,allSevenLegalLowerPrgBanks:true,fixedPrgBank:7,counts,critical,translations,lifecycle,maximumRoutineCycles:{baseline:baseline.maxCycles,candidate:candidate.maxCycles},sha256:{baseline:hash(baseline.rom),candidate:hash(candidate.rom),test:hash(readFileSync(fileURLToPath(import.meta.url))),core:hash(readFileSync(core))},scope:'Linked6502 fixtures with injected state; translated item tables only in emulated memory. No ROM changes. Controller movement/PPU deadlines are tested separately in Mesen.'};
const output=resolve(args['--output']||resolve(candidate.build,'ammo-interactions-verification.json'));mkdirSync(dirname(output),{recursive:true});writeFileSync(output,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({passed:true,counts,critical,maximumRoutineCycles:report.maximumRoutineCycles,rom:report.sha256.candidate},null,2));
