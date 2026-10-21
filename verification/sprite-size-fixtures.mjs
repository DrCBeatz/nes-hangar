/**
 * Execute linked 6502 size selection and encounter epoch fixtures.
 * Requires a completed build (python3 tools/build.py).
 *
 * node verification/sprite-size-fixtures.mjs --core <jsnes>/src/index.js
 * Optional: --output <report.json>; defaults to build/sprite-size-fixtures.json.
 * The core is pinned to JSNES commit 5b27c4243f1cb2528c54941e13c29c4ced7d5a45;
 * CPU and entry-point hashes are checked before executing it.
 * These injected RAM/register tests suppress interrupts. They supplement the
 * separate controller-only and stock-timing PPU tests; they do not replace them.
 */
// Execute the actual linked 6502 chooser and epoch allocator. RAM fixtures,
// interrupts disabled: supplements the separate stock-timing Mesen tests.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const options={};
for(let i=2;i<process.argv.length;i+=2){
 const key=process.argv[i],value=process.argv[i+1];
 assert.ok(['--core','--output'].includes(key)&&value&&!value.startsWith('--'),
  'Usage: node verification/sprite-size-fixtures.mjs --core <jsnes>/src/index.js [--output <report.json>]');
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
const labels=Object.fromEntries(readFileSync(resolve(root,'build/hangar.lbl'),'utf8')
  .split('\n').map(l=>l.match(/^al ([\da-f]+) \.(.+)$/i)).filter(Boolean).map(m=>[m[2],parseInt(m[1],16)]));
const n=new NES();n.loadROM(rom.toString('latin1'));
n.cpu.mem.fill(0,0,0x8000);n.ppu.updateControlReg1(0);n.ppu.updateControlReg2(0);
const put=(name,value,offset=0)=>{assert.ok(name in labels,name);n.cpu.mem[labels[name]+offset]=value&255;};
const get=name=>n.cpu.mem[labels[name]];
const coord=(name,q)=>{put(name,q);put(name,q>>8,1);put(name+'_hi',q>>16);};
function call(name){
  const c=n.cpu;c.REG_SP=0x1ff;c.push(0x4f);c.push(0xff);c.REG_PC=labels[name]-1;
  c.irqRequested=false;c.F_INTERRUPT=1;
  let cycles=0,steps=0;
  while(c.REG_PC!==0x4fff){assert.ok(++steps<20000,name);cycles+=c.emulate();c.irqRequested=false;}
  assert.equal(c.REG_SP&255,255,name);return {carry:!!c.F_CARRY,cycles};
}
const widths=[4,6,8,12,16,20,24,26,28,30,32];
const nearest=r=>{
  let i=0;
  while(i<widths.length-1 && r<512/(widths[i]+widths[i+1]))i++;
  return i;
};
const stable=(r,old,same)=>{
  let i=nearest(r);
  if(!same || old<6 || old>=widths.length || i<6)return i;
  if(i>old && r>=512/(widths[old]+widths[old+1])-.125)return old;
  if(i<old && r<512/(widths[old-1]+widths[old])+.125)return old;
  return i;
};
let cases=0,maxCycles=0;
for(const [zx,zz] of [[176,312],[294,218],[296,84]]){
  coord('render_zombie_x',zx*256);coord('render_zombie_z',zz*256);
  put('render_zombie_hp',3);put('actor_kind',0);put('render_zombie_epoch',17);
  for(let q=8*256;q<=12*256;q+=7)for(const old of [-1,5,6,7,8,9,10,254]){
    const dx=q%2 ? q : 0, dz=q%2 ? 0 : q;
    coord('render_x',zx*256+dx);coord('render_z',zz*256+dz);
    put('zombie_size_history',old+1);put('zombie_size_epoch',17);
    const out=call('choose_radial_size'),expected=stable(q/256,old,true);
    assert.equal(out.carry,false);assert.equal(get('z_size'),expected,`${zx},${zz} q${q} old${old}`);
    assert.equal(get('zombie_size_history'),expected+1);assert.equal(get('zombie_size_epoch'),17);
    maxCycles=Math.max(maxCycles,out.cycles);cases++;
  }
  // Different encounter identity must discard a near-size history immediately.
  coord('render_x',zx*256);coord('render_z',(zz+9)*256);
  put('zombie_size_history',11);put('zombie_size_epoch',16);
  call('choose_radial_size');assert.equal(get('z_size'),nearest(9));cases++;
  // Corpse and pickup paths cannot poison history for the next living picture.
  for(const [kind,hp] of [[0,128],[1,1]]){
    put('actor_kind',kind);put('render_zombie_hp',hp);
    put('zombie_size_history',9);put('zombie_size_epoch',17);
    call('choose_radial_size');assert.equal(get('zombie_size_history'),9);assert.equal(get('zombie_size_epoch'),17);cases++;
  }
}
// Every initial epoch and several wraparound collision sets, including a
// history tag no longer present in any published/in-flight picture.
let epochCases=0,maxEpochCycles=0;
for(let start=0;start<256;start++)for(const shift of [1,2,17,255]){
  const occupied=[1,2,3,4,shift].map(x=>(start+x)&255);
  put('zombie_epoch',start);put('render_zombie_epoch',occupied[0]);
  put('visible_zombie_epoch',occupied[1]);put('buffer_zombie_epoch',occupied[2]);
  put('buffer_zombie_epoch',occupied[3],1);put('zombie_size_epoch',occupied[4]);
  const oldA=n.cpu.REG_ACC=73,oldX=n.cpu.REG_X=91,oldY=n.cpu.REG_Y=109;
  const out=call('encounter_next_epoch');
  let expected=(start+1)&255;while(occupied.includes(expected))expected=(expected+1)&255;
  assert.equal(get('zombie_epoch'),expected);assert.equal(n.cpu.REG_ACC,oldA);
  assert.equal(n.cpu.REG_X,oldX);assert.equal(n.cpu.REG_Y,oldY);
  maxEpochCycles=Math.max(maxEpochCycles,out.cycles);epochCases++;
}
const result={passed:true,romSha256:createHash('sha256').update(rom).digest('hex'),
  sizeCases:cases,epochCases,maxChooserCycles:maxCycles,maxEpochCycles,
  scope:'Linked 6502 helpers with injected RAM/register fixtures; independent real-distance oracle. Not a PPU timing or controller-route test.'};
Object.assign(result,{coreCommit:'5b27c4243f1cb2528c54941e13c29c4ced7d5a45',coreCpuSha256,coreEntrySha256,driverSha256:hash(readFileSync(fileURLToPath(import.meta.url)))});
const output=resolve(options['--output']||resolve(root,'build/sprite-size-fixtures.json'));
writeFileSync(output,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));
