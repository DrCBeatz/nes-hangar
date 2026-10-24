/** Verify the raster's specialized dirty-name marking against the previous
 * generic linked routine, then compare complete ordinary render products.
 * These injected, interrupt-free CPU fixtures are not gameplay FPS tests.
 */
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const args={};for(let i=2;i<process.argv.length;i+=2){assert.ok(['--baseline','--build','--core','--output'].includes(process.argv[i]));args[process.argv[i]]=process.argv[i+1];}
for(const arg of ['--baseline','--build','--core','--output'])assert.ok(args[arg],arg+' required');
const sha=b=>createHash('sha256').update(b).digest('hex'),core=resolve(args['--core']);
assert.equal(sha(readFileSync(resolve(dirname(core),'cpu.js'))),'17469b310738c4b3092d648289c8537a4584f6b45bc1735adb540968a75308f2');
const {NES}=await import(pathToFileURL(core));
class Machine{
 constructor(build){this.build=resolve(build);this.rom=readFileSync(resolve(this.build,'hangar-ntsc.nes'));this.labels=Object.fromEntries(readFileSync(resolve(this.build,'hangar.lbl'),'utf8').split('\n').map(s=>s.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));this.fixed=readFileSync(resolve(this.build,'fixed-patterns.bin'));this.names=readFileSync(resolve(this.build,'nametable.bin'));}
 fixture(){const nes=new NES();nes.loadROM(this.rom.toString('latin1'));nes.cpu.mem.fill(0,0,0x8000);nes.ppu.updateControlReg1(0);nes.ppu.updateControlReg2(0);nes.mmap.loadRomBank(0,0x8000);nes.mmap.loadRomBank(7,0xc000);return {nes};}
 put(c,n,v,o=0){assert.ok(n in this.labels,n);c.nes.cpu.mem[this.labels[n]+o]=v&255;}
 get(c,n,o=0){assert.ok(n in this.labels,n);return c.nes.cpu.mem[this.labels[n]+o];}
 coordinate(c,n,v){this.put(c,n,v);this.put(c,n,v>>8,1);this.put(c,n+'_hi',v>>16);}
 run(c,start,end){const cpu=c.nes.cpu;cpu.REG_PC=start-1;cpu.F_INTERRUPT=1;cpu.irqRequested=false;let cycles=0,steps=0;while(cpu.REG_PC!==end-1){assert.ok(++steps<3000000,'CPU fixture returns');cycles+=cpu.emulate();cpu.irqRequested=false;cpu.nmiPending=false;cpu.nmiRaised=false;}return cycles;}
 call(c,n){const cpu=c.nes.cpu;cpu.REG_SP=0x1ff;cpu.push(0x4f);cpu.push(0xff);const cycles=this.run(c,this.labels[n],0x5000);assert.equal(cpu.REG_SP&255,255,n+' stack');return cycles;}
 raster(c,bank){const mem=c.nes.cpu.mem,origin=0x6000+bank*0x1000,pixels=Buffer.alloc(256*144);for(let y=24;y<168;y++)for(let x=0;x<256;x++){const tile=mem[origin+0xc00+(y>>3)*32+(x>>3)],a=tile<64?tile*16:origin+(tile-64)*16,bytes=tile<64?this.fixed:mem,b=7-(x&7);pixels[(y-24)*256+x]=((bytes[a+(y&7)]>>b)&1)|(((bytes[a+8+(y&7)]>>b)&1)<<1);}return pixels;}
 initRender(c){for(const origin of [0x6000,0x7000]){for(let i=0;i<1024;i++)c.nes.cpu.mem[origin+0xc00+i]=this.names[i];c.nes.cpu.mem.fill(255,origin+0xf40,origin+0x1000);}for(const n of ['music_init','movement_init','pistol_reset','zombie_reset','medkit_reset','exit_reset','encounters_reset'])this.call(c,n);}
 pose(c,p,bank){this.put(c,'active_encounter',p.actor||0);c.nes.cpu.REG_X=p.actor||0;this.call(c,'encounters_load');this.coordinate(c,'player_x',Math.round(p.x*256));this.coordinate(c,'player_z',Math.round(p.z*256));for(const [n,v]of Object.entries({door_state:p.door??2,pending_angle:p.angle,player_floor:p.floor??2,player_eye:(p.floor??2)+4,render_buffer:bank,visible_buffer:bank^1,requested_mode:p.mode||0,pistol_dirty:0,zombie_dirty:0,medkit_dirty:0,quick_pending:0,upload_busy:0,input_buttons:0,button_edges:0,corpse_state:0}))this.put(c,n,v);if(!p.live){this.put(c,'zombie_hp',0);this.put(c,'medkit_state',0xc0);}}
}
const old=new Machine(args['--baseline']),candidate=new Machine(args['--build']);
for(const n of ['nt_dirty_flags','cell_row','cell_col','name_ptr'])assert.equal(old.labels[n],candidate.labels[n],n+' RAM unchanged');
const oldCtx=old.fixture(),newCtx=candidate.fixture();newCtx.nes.mmap.loadRomBank(3,0x8000);
const counts={tileRegisterCases:0,wholeRenderCases:0,viewportPixelsCompared:0},cycles={old:new Set(),candidate:new Set()};
// Every tile ID, every viewport tile and both destination banks. Vary initial
// X and carry; the fast path must preserve A/Y/stack and write one exact flag.
for(let bank=0;bank<2;bank++)for(let row=0;row<18;row++)for(let col=0;col<32;col++)for(let tile=0;tile<256;tile++){
 const expected=6+row*2+(col>>4),name=0x6c00+bank*0x1000+(row+3)*32+col;
 for(const [m,c]of [[old,oldCtx],[candidate,newCtx]]){const cpu=c.nes.cpu;cpu.mem.fill(0xa5,m.labels.nt_dirty_flags,m.labels.nt_dirty_flags+48);m.put(c,'cell_row',row);m.put(c,'cell_col',col);m.put(c,'name_ptr',name);m.put(c,'name_ptr',name>>8,1);cpu.REG_ACC=tile;cpu.REG_X=(tile+row)&255;cpu.REG_Y=0;cpu.F_CARRY=(tile+col)&1;cpu.REG_SP=0x1ff;}
 cycles.old.add(old.call(oldCtx,'nt_dirty_name')+6);
 cycles.candidate.add(candidate.run(newCtx,candidate.labels.raster_dirty_begin,candidate.labels.raster_dirty_end));
 for(const [m,c]of [[old,oldCtx],[candidate,newCtx]]){const cpu=c.nes.cpu;assert.equal(cpu.REG_ACC,tile);assert.equal(cpu.REG_Y,0);assert.equal(cpu.REG_SP&255,255);for(let i=0;i<48;i++)assert.equal(cpu.mem[m.labels.nt_dirty_flags+i],i===expected?1:0xa5);}
 counts.tileRegisterCases++;
}
assert.deepEqual([...cycles.candidate],[26]);
const poses=[
 {id:'opening',x:52,z:172,angle:0},{id:'recess',x:52,z:220,angle:224,floor:0},
 {id:'opening-near-edge',x:35.875,z:220,angle:192},{id:'square-live',x:136,z:312,angle:64,actor:0,live:true},
 {id:'inner-corner',x:181,z:297,angle:32},{id:'slime-back',x:276,z:256,angle:224,actor:1,live:true},
 {id:'slime-entry',x:292,z:256,angle:128,actor:1,live:true},{id:'slime-middle',x:310,z:216,angle:224,actor:1,live:true},
 {id:'slime-exit',x:296,z:180,angle:128,actor:1,live:true},{id:'door-closed',x:296,z:124,angle:128,actor:2,live:true,door:0},
 {id:'door-open',x:296,z:124,angle:128,actor:2,live:true},{id:'third-close',x:296,z:94,angle:128,actor:2,live:true},
 {id:'third-oblique',x:274,z:100,angle:96,actor:2,live:true},{id:'exit',x:288,z:28,angle:192,actor:2},
 {id:'coarse-slime',x:292,z:256,angle:128,actor:1,live:true,mode:1},
 {id:'coarse-opening',x:52,z:172,angle:0,mode:1},
];
const comparisons=[];
for(let i=0;i<poses.length;i++){
 const pose=poses[i],bank=i&1,contexts=[old.fixture(),candidate.fixture()];[old,candidate].forEach((m,j)=>{m.initRender(contexts[j]);m.pose(contexts[j],pose,bank);});
 for(let pass=0;pass<2;pass++){
  const records=[old,candidate].map((m,j)=>{const c=contexts[j],cycles=m.call(c,'render_begin');assert.equal(m.get(c,'overflow_flag'),0);assert.equal(m.get(c,'buffer_state',bank),2);return {cycles,pixels:m.raster(c,bank),staging:Buffer.from(c.nes.cpu.mem.slice(0x6000+bank*4096,0x7000+bank*4096)),dirty:Buffer.from(c.nes.cpu.mem.slice(m.labels.nt_dirty_flags,m.labels.nt_dirty_flags+48)),list:Buffer.from(c.nes.cpu.mem.slice(m.labels.nt_dirty_list+bank*64,m.labels.nt_dirty_list+bank*64+m.get(c,'nt_dirty_count',bank)))};});
  assert.deepEqual(records[1].pixels,records[0].pixels,pose.id+' pixels');assert.deepEqual(records[1].staging,records[0].staging,pose.id+' complete staging bytes');assert.deepEqual(records[1].dirty,records[0].dirty,pose.id+' dirtyflags');assert.deepEqual(records[1].list,records[0].list,pose.id+' uploadlist');
  comparisons.push({pose,bank,pass,baselineCycles:records[0].cycles,candidateCycles:records[1].cycles,savedCycles:records[0].cycles-records[1].cycles,percentChange:100*(records[1].cycles/records[0].cycles-1),rasterSha256:sha(records[1].pixels),stagingSha256:sha(records[1].staging),dirtyBlocks:records[1].list.length});counts.wholeRenderCases++;counts.viewportPixelsCompared+=256*144;
 }
}
const report={passed:true,scope:'Interrupt-free linked6502 fixtures with injected legal camera state. Every viewport tile and tile ID are checked; complete world/actor/OAM/palette staging and dirty upload lists match baseline at diagnostic poses. Not a controller/PPU timing or gameplay FPS test.',sha256:{baseline:sha(old.rom),candidate:sha(candidate.rom),test:sha(readFileSync(fileURLToPath(import.meta.url))),core:sha(readFileSync(core))},counts,cycles:{baselineCallIncludingJsr:[...cycles.old],inline:[...cycles.candidate]},comparisons};
const out=resolve(args['--output']);mkdirSync(dirname(out),{recursive:true});writeFileSync(out,JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({passed:true,counts,cycles:report.cycles,comparisons:comparisons.map(x=>({id:x.pose.id,pass:x.pass,saved:x.savedCycles,percent:x.percentChange}))},null,2));
