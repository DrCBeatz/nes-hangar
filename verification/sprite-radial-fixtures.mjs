/**
 * Execute linked 6502 radial floor-anchor fixtures.
 * Requires a completed build (python3 tools/build.py).
 *
 * node verification/sprite-radial-fixtures.mjs --core <jsnes>/src/index.js
 * Optional: --output <report.json>; defaults to build/sprite-radial-fixtures.json.
 * The core is pinned to JSNES commit 5b27c4243f1cb2528c54941e13c29c4ced7d5a45;
 * CPU and entry-point hashes are checked before executing it.
 * These injected RAM/register tests suppress interrupts. They supplement the
 * separate controller-only and stock-timing PPU tests; they do not replace them.
 */
// Execute linked 6502 sqrt32 + rounded division, independently checked against
// Math.sqrt. Injected RAM fixtures complement stock-timing Mesen render tests.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const options={};
for(let i=2;i<process.argv.length;i+=2){
 const key=process.argv[i],value=process.argv[i+1];
 assert.ok(['--core','--output'].includes(key)&&value&&!value.startsWith('--'),
  'Usage: node verification/sprite-radial-fixtures.mjs --core <jsnes>/src/index.js [--output <report.json>]');
 assert.ok(!(key in options),`Duplicate option ${key}`);options[key]=value;
}
assert.ok(options['--core'],'Pass --core pointing to the pinned JSNES src/index.js');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const core=resolve(options['--core']);
const coreCpuSha256=hash(readFileSync(resolve(dirname(core),'cpu.js')));
const coreEntrySha256=hash(readFileSync(core));
assert.equal(coreCpuSha256,'17469b310738c4b3092d648289c8537a4584f6b45bc1735adb540968a75308f2','Use the documented pinned JSNES CPU');
assert.equal(coreEntrySha256,'0531f69c4e9e2973bdcdc89bf3ad6e6dfa3257572f8e7eccd405fa158cc3a1a7','Use the documented pinned JSNES entry point');
const {NES}=await import(pathToFileURL(core));
const rom=readFileSync(resolve(root,'build/hangar-ntsc.nes'));
const labels=Object.fromEntries(readFileSync(resolve(root,'build/hangar.lbl'),'utf8').split('\n')
 .map(l=>l.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));
assert.ok('radial_floor_anchor' in labels,'Fresh linked radial_floor_anchor is required');
const n=new NES();n.loadROM(rom.toString('latin1'));
n.cpu.mem.fill(0,0,0x8000);n.ppu.updateControlReg1(0);n.ppu.updateControlReg2(0);
const put32=(address,value)=>{for(let i=0;i<4;i++)n.cpu.mem[address+i]=Math.floor(value/2**(i*8))&255;};
const allowed=new Set();
for(const [name,size] of [['g_ray_z',4],['g_value',3],['g_rem',4],['g_den',3],['g_acc',4],['g_num',4],['g_sign',1],['coordinate_producer_scratch',2]]){
 assert.ok(name in labels,name);for(let i=0;i<size;i++)allowed.add(labels[name]+i);
}
for(let i=0x100;i<0x200;i++)allowed.add(i);
const specimens=new Map();
function add(square,category){assert.ok(Number.isInteger(square)&&square>=0&&square<=0xffffffff);if(!specimens.has(square))specimens.set(square,category);}
for(let q=8*256;q<=12*256;q++)add(q*q,'dense-close-axis');
for(const q of [0,1,2,16,31,32,63,64,65,127,128,255,256,257,511,512,1023,1024,2047,3073,4095,4096,8191,16383,32767,32768,46340,65534,65535])add(q*q,'axis-global');
for(const x of [0,1,31,63,64,127,255,256,512,1023,1448,1536,2048,2172,2560,3072,4096,8192,16384,32768,46340])for(const y of [x,Math.floor(x/2),x+1])if(x*x+y*y<=0xffffffff)add(x*x+y*y,'diagonal-global');
for(const q of [0,1,63,64,255,256,2048,2304,2560,2816,3072,32767,46340,65535])for(const delta of [-1,0,1])if(q*q+delta>=0&&q*q+delta<=0xffffffff)add(q*q+delta,'square-root-boundary');
for(const square of [0,1,4095,4096,4097,0x7fffffff,0x80000000,0xfffffffd,0xfffffffe,0xffffffff])add(square,'32-bit-boundary');
let rng=0x139513f1;for(let i=0;i<512;i++){rng=(Math.imul(rng,1664525)+1013904223)>>>0;add(rng,'deterministic-global');}
let cases=0,minCycles=Infinity,maxCycles=0,totalCycles=0,fullSentinelCases=0;
const failures=[],byCategory={};
const call=(routine='radial_floor_anchor')=>{
 const c=n.cpu;c.REG_SP=0x1ff;c.push(0x4f);c.push(0xff);c.REG_PC=labels[routine]-1;
 c.irqRequested=false;c.F_INTERRUPT=1;let cycles=0,steps=0;
 while(c.REG_PC!==0x4fff){assert.ok(++steps<20000,'Routine must return');cycles+=c.emulate();c.irqRequested=false;}
 assert.equal(c.REG_SP&255,255,'Balanced return stack');return cycles;
};
for(const [square,category] of specimens)for(const height of [2,4,6]){
 n.cpu.mem.fill(0x5a,0,0x8000);
 put32(labels.g_ray_z,square);n.cpu.mem[labels.render_eye]=2+height;
 n.cpu.mem[labels.z_size]=10;
 // Everything except documented scratch and stack must remain unchanged.
 const full=cases%37===0,before=n.cpu.mem.slice(0,full?0x8000:0x100);
 const cycles=call();
 const radiusQ8=Math.max(64,Math.floor(Math.sqrt(square)));
 const expected=96+Math.round(32768*height/radiusQ8);
 const actual=n.cpu.mem[labels.coordinate_producer_scratch]+256*n.cpu.mem[labels.coordinate_producer_scratch+1];
 const actualRoot=n.cpu.mem[labels.g_den]+256*n.cpu.mem[labels.g_den+1]+65536*n.cpu.mem[labels.g_den+2];
 if(actual!==expected||actualRoot!==radiusQ8)failures.push({square,height,category,expected,actual,radiusQ8,actualRoot});
 assert.equal(n.cpu.mem[labels.z_size],10,'z_size / g_endpoint preserved');
 for(let a=0;a<before.length;a++)if((a<0x800||a>=0x6000)&&!allowed.has(a))assert.equal(n.cpu.mem[a],before[a],`Unexpected RAM write $${a.toString(16)} at square ${square}`);
 cases++;if(full)fullSentinelCases++;minCycles=Math.min(minCycles,cycles);maxCycles=Math.max(maxCycles,cycles);totalCycles+=cycles;
 byCategory[category]=(byCategory[category]||0)+1;
}
// Global-coordinate rejection protects the helper's 32-bit input limit.
const coord=(name,q)=>{n.cpu.mem[labels[name]]=q&255;n.cpu.mem[labels[name]+1]=(q>>>8)&255;n.cpu.mem[labels[name+'_hi']]=(q>>>16)&255;};
const radiusLimitCases=[];
for(const [dx,dz] of [[65535,0],[65536,0],[-65536,0],[0,65536],[46340,46340],[46341,46341],[65000,10000],[512*256,0],[-512*256,0],[65535,1],[65535,362],[65535,363]]){
 n.cpu.mem.fill(0,0,0x8000);coord('render_zombie_x',512*256);coord('render_zombie_z',512*256);
 coord('render_x',512*256+dx);coord('render_z',512*256+dz);
 n.cpu.mem[labels.render_zombie_hp]=3;n.cpu.mem[labels.render_eye]=6;
 call('choose_radial_size');const rejected=!!n.cpu.F_CARRY;
 const square=dx*dx+dz*dz,expectedReject=square>=2**32;
 assert.equal(rejected,expectedReject,`Radius limit ${dx},${dz}`);
 if(!rejected){call();const actual=n.cpu.mem[labels.coordinate_producer_scratch]+256*n.cpu.mem[labels.coordinate_producer_scratch+1];assert.equal(actual,96+Math.round(32768*4/Math.max(64,Math.floor(Math.sqrt(square)))));}
 radiusLimitCases.push({deltaQ8:[dx,dz],square,rejected});
}
const report={passed:failures.length===0,romSha256:createHash('sha256').update(rom).digest('hex'),cases,uniqueSquares:specimens.size,eyeHeights:[2,4,6],byCategory,radiusLimitCases,fullMemorySentinelCases:fullSentinelCases,zeroPageSentinelsEveryCase:true,cycles:{min:minCycles,max:maxCycles,mean:totalCycles/cases},failures:failures.slice(0,30),failureCount:failures.length,
 scope:'Linked 6502 radial_floor_anchor with injected RAM, interrupts disabled. Tests sqrt32 and rounded division against an independent JS Math.sqrt oracle. Not PPU timing or controller gameplay.',
 inputLimit:'Largest input is 0xffffffff (radius just below 256). Exactly radius 256 squares to 0x100000000 and cannot be represented; 12 linked chooser boundary fixtures verify rejection at/above that radius and acceptance below it.',
 clamp:'floor(sqrt(radiusSquaredQ16)), clamped to at least 64 Q8.8; foot = 96 + round(32768 * (render_eye - floor2) / radiusQ8).'};
Object.assign(report,{coreCommit:'5b27c4243f1cb2528c54941e13c29c4ced7d5a45',coreCpuSha256,coreEntrySha256,driverSha256:hash(readFileSync(fileURLToPath(import.meta.url)))});
const output=resolve(options['--output']||resolve(root,'build/sprite-radial-fixtures.json'));
writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));assert.equal(failures.length,0,'All independent radial-anchor fixtures must pass');
