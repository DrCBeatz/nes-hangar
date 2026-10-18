/**
 * Focused execution of linked 6502 helpers in the pinned JSNES CPU.
 * This suite deliberately injects RAM/register fixtures and suppresses automatic
 * interrupts. It is NOT controller-only traversal or a PPU timing proof.
 * Supply the JSNES core pinned by the 8-Bit Pocket project at commit
 * 5b27c4243f1cb2528c54941e13c29c4ced7d5a45. Its CPU and entry-point
 * hashes are checked below. Building Hangar itself needs no npm dependency.
 *
 * node verification/gameplay-fixtures.mjs --core <jsnes>/src/index.js
 * Optional: --baseline <old-build-directory> adds old/new comparisons.
 * The baseline directory must contain ROM, labels and map.json from release
 * 644d047c…; the current-only suite requires only the normal Hangar build.
 */
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { resolve, dirname } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const options = Object.fromEntries(Array.from({ length: (process.argv.length - 2) / 2 }, (_, i) => [process.argv[2 + i * 2], process.argv[3 + i * 2]]));
assert.ok(options["--core"], "Pass --core pointing to the pinned JSNES src/index.js");
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const corePath = resolve(options["--core"]);
const coreCpuSha256 = hash(readFileSync(resolve(dirname(corePath), "cpu.js")));
assert.equal(coreCpuSha256, "17469b310738c4b3092d648289c8537a4584f6b45bc1735adb540968a75308f2", "Use the documented pinned JSNES CPU");
assert.equal(hash(readFileSync(corePath)), "0531f69c4e9e2973bdcdc89bf3ad6e6dfa3257572f8e7eccd405fa158cc3a1a7", "Use the documented pinned JSNES entry point");
const { NES } = await import(pathToFileURL(corePath));
const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

class Machine {
  constructor(directory) {
    this.directory = directory;
    this.rom = readFileSync(resolve(directory, "hangar-ntsc.nes"));
    this.symbolBytes = readFileSync(resolve(directory, "hangar.lbl"));
    this.labels = {};
    for (const line of this.symbolBytes.toString().split("\n")) {
      const match = line.match(/^al ([\da-f]+) \.(.+)$/i);
      if (match && !match[2].includes("::")) this.labels[match[2]] = parseInt(match[1], 16);
    }
    this.scene = readJson(resolve(directory, "map.json"));
    this.calls = {};
    this.maxCycles = {};
  }
  fixture() {
    const nes = new NES();
    nes.loadROM(this.rom.toString("latin1"));
    nes.cpu.mem.fill(0, 0, 0x8000);
    nes.cpu.irqRequested = false;
    nes.cpu.F_INTERRUPT = 1;
    nes.ppu.updateControlReg1(0);
    nes.ppu.updateControlReg2(0);
    const context = { nes, writes: [], mapperWrites: [] };
    const write = nes.mmap.write.bind(nes.mmap);
    nes.mmap.write = (address, value) => {
      if (address >= 0x2000 && address <= 0x4017) context.writes.push([address, value]);
      if (address >= 0x8000) context.mapperWrites.push([address, value]);
      write(address, value);
    };
    for (const name of ["movement_init", "pistol_reset", "zombie_reset", "medkit_reset", "exit_reset", "results_reset", "pause_init"]) this.call(context, name);
    this.put(context, "button_edges", 0);
    this.put(context, "input_buttons", 0);
    return context;
  }
  put(context, name, value, offset = 0) {
    assert.ok(name in this.labels, `Missing symbol ${name}`);
    context.nes.cpu.mem[this.labels[name] + offset] = value & 255;
  }
  get(context, name, offset = 0) {
    assert.ok(name in this.labels, `Missing symbol ${name}`);
    return context.nes.cpu.mem[this.labels[name] + offset];
  }
  word(context, name) { return this.get(context, name) + 256 * this.get(context, name, 1); }
  coordinate(context, name, q8) {
    this.put(context, name, q8);
    this.put(context, name, q8 >> 8, 1);
    this.put(context, name + "_hi", q8 >> 16);
  }
  pose(context, x, z, angle = 192) {
    this.coordinate(context, "player_x", x);
    this.coordinate(context, "player_z", z);
    this.put(context, "pending_angle", angle);
  }
  call(context, name, accumulator) {
    const c = context.nes.cpu;
    assert.ok(name in this.labels, `Missing symbol ${name}`);
    if (accumulator !== undefined) c.REG_ACC = accumulator;
    c.REG_SP = 0x1ff;
    c.push(0x4f); c.push(0xff);
    c.REG_PC = this.labels[name] - 1;
    c.irqRequested = false;
    context.writes = []; context.mapperWrites = [];
    let cycles = 0, instructions = 0;
    while (c.REG_PC !== 0x4fff) {
      assert.ok(instructions++ < 100000, `${name} did not return`);
      cycles += c.emulate();
      c.irqRequested = false;
    }
    assert.equal(c.REG_SP & 255, 255, `${name} balanced stack`);
    assert.deepEqual(context.mapperWrites, [], `${name} must stay in the fixed PRG bank`);
    this.calls[name] = (this.calls[name] || 0) + 1;
    this.maxCycles[name] = Math.max(this.maxCycles[name] || 0, cycles);
    return Boolean(c.F_CARRY);
  }
}

const candidate = new Machine(resolve(options["--candidate"] || resolve(root, "build")));
const baseline = options["--baseline"] ? new Machine(resolve(options["--baseline"])) : null;
if (baseline) assert.equal(hash(baseline.rom), "644d047c07fe9ade8c14b87c42faa5720b026e0a13c017c4326be604adebbc87");
assert.equal(candidate.scene.medkit.pickup_radius, 6);
assert.equal(candidate.scene.ammo.pickup_radius, 4);
assert.deepEqual([candidate.scene.exit.x_min, candidate.scene.exit.x_max, candidate.scene.exit.z_min, candidate.scene.exit.z_max, candidate.scene.exit.angle_min, candidate.scene.exit.angle_max], [286, 294, 22, 34, 172, 212]);
const checks = {}, counts = {}, examples = {};

// Full-width fractional circle boundaries: signs, axes, diagonals, quantization
// steps and far points with identical low words all execute assembled helpers.
const offsets = [-65536, -1537, -1536, -1535, -1504, -1088, -1025, -1024, -1023, -992, -769, -768, -767, -736, -33, -32, -31, -1, 0, 1, 31, 32, 33, 736, 767, 768, 769, 992, 1023, 1024, 1025, 1088, 1504, 1535, 1536, 1537, 65536];
let rangeCases = 0;
for (const machine of [baseline, candidate].filter(Boolean)) {
  for (const active of [0, 1]) {
    const c = machine.fixture();
    const item = active ? machine.scene.ammo : machine.scene.medkit;
    machine.put(c, "active_encounter", active);
    for (const dx of offsets) for (const dz of offsets) {
      const x = item.x * 256 + dx, z = item.z * 256 + dz;
      if (x < 0 || z < 0 || x >= 1024 * 256 || z >= 1024 * 256) continue;
      machine.pose(c, x, z);
      const expected = Math.ceil(Math.abs(dx) / 32) ** 2 + Math.ceil(Math.abs(dz) / 32) ** 2 < (item.pickup_radius * 8) ** 2;
      assert.equal(machine.call(c, "medkit_in_range"), expected, `${active ? "ammo" : "medkit"} dx=${dx}/256 dz=${dz}/256 radius=${item.pickup_radius}`);
      rangeCases++;
    }
  }
}
counts.pickupBoundaryCases = rangeCases;
checks.exactFractionalPickupCirclesMatchIndependentOracle = true;
examples.pickupOldVersusNew = [];
for (const [dx, dz] of [[0, 0], [3.5, 0], [0, -3.5], [4, 0], [0, -4], [5, 0], [3, 3], [2.75, 2.75], [3.875, 0.125], [3.875, 1]]) {
  const result = { dx, dz };
  for (const [name, m] of [["old", baseline], ["new", candidate]].filter(([, machine]) => machine)) {
    const c = m.fixture();m.put(c, "active_encounter", 1);
    m.pose(c, (m.scene.ammo.x + dx) * 256, (m.scene.ammo.z + dz) * 256);
    result[name] = m.call(c, "medkit_in_range");
  }
  examples.pickupOldVersusNew.push(result);
}
if (baseline) {
  assert.ok(examples.pickupOldVersusNew.some((e) => e.old && !e.new));
  assert.ok(examples.pickupOldVersusNew.every((e) => !e.new || e.old));
  checks.ammoTightensWithoutChangingMedkit = true;
}

let exitCases = 0;
const xs = [286, 292, 294].flatMap((v) => [v * 256 - 1, v * 256, v * 256 + 1]);
const zs = [22, 24, 32, 34].flatMap((v) => [v * 256 - 1, v * 256, v * 256 + 1]);
for (const m of [baseline, candidate].filter(Boolean)) {
  const c = m.fixture(), e = m.scene.exit;
  for (const x of xs) for (const z of zs) for (const angle of [0, 171, 172, 173, 175, 176, 192, 208, 209, 211, 212, 213, 255]) for (const health of [0, 100]) {
    m.pose(c, x, z, angle);m.put(c, "pistol_health", health);
    const expected = Boolean(health && x >= e.x_min * 256 && x < e.x_max * 256 && z >= e.z_min * 256 && z <= e.z_max * 256 && angle >= e.angle_min && angle <= e.angle_max);
    assert.equal(m.call(c, "exit_eligible"), expected, `exit ${x}/256 ${z}/256 angle=${angle} health=${health}`);
    exitCases++;
  }
}
counts.exitBoundaryCases = exitCases;
checks.exitRectangleAndAngleEdgesAreExact = true;
examples.exitOldVersusNew = [];
for (const [x, z, angle] of [[289, 28, 192], [293.5, 28, 192], [289, 22, 192], [289, 34, 192], [289, 28, 172], [289, 28, 212], [294, 28, 192], [289, 34 + 1 / 256, 192], [289, 28, 213]]) {
  const result = { x, z, angle };
  for (const [name, m] of [["old", baseline], ["new", candidate]].filter(([, machine]) => machine)) { const c = m.fixture();m.pose(c, x * 256, z * 256, angle);result[name] = m.call(c, "exit_eligible"); }
  examples.exitOldVersusNew.push(result);
}
for (const [edges, buttons, completes] of [[0, 0x80, false], [0x80, 0x80, true], [0x80, 0x81, false], [0x80, 0x82, false], [0x80, 0x83, false]]) {
  const c = candidate.fixture();candidate.pose(c, 293 * 256, 33 * 256, 174);
  candidate.put(c, "button_edges", edges);candidate.put(c, "input_buttons", buttons);
  candidate.call(c, "exit_tick");
  assert.equal(Boolean(candidate.get(c, "exit_flags") & 128), completes);
  assert.equal(candidate.get(c, "results_screen_state"), completes ? 1 : 0);
}
checks.exitStillRequiresFreshAAndRejectsBothStrafeDirections = true;

function dryFixture() {
  const c = candidate.fixture();
  candidate.put(c, "pistol_ammo", 0);candidate.put(c, "input_buttons", 0x40);candidate.put(c, "button_edges", 0x40);
  candidate.put(c, "pistol_dirty", 0);
  return c;
}
const protectedState = (c) => ["pistol_ammo", "pistol_pose", "pistol_dirty", "zombie_hp", "zombie_hits", "zombie_kills", "zombie_hit_flash"].map((n) => candidate.get(c, n)).concat(candidate.word(c, "pistol_shot_count"), Array.from({ length: 6 }, (_, i) => candidate.get(c, "pistol_digits", i)));
const c = dryFixture(), unchanged = protectedState(c);
candidate.call(c, "pistol_tick");
assert.deepEqual(protectedState(c), unchanged);
assert.equal(candidate.get(c, "pistol_flash_timer"), 0x82);
assert.equal(candidate.get(c, "pistol_cooldown"), 15);
assert.deepEqual(c.writes, [[0x4015, 15], [0x400c, 0x18], [0x400e, 0x84], [0x400f, 0xf8]]);
assert.equal(candidate.get(c, "pause_sound_noise"), 0x18);
checks.emptyClickHasExactShortNoiseCueWithoutShotOrHudMutation = true;
const clickWrites = [{ tick: 0, writes: c.writes }];
candidate.put(c, "button_edges", 0);
for (let tick = 1; tick <= 40; tick++) {
  candidate.call(c, "pistol_tick");
  assert.deepEqual(protectedState(c), unchanged);
  if (c.writes.length) clickWrites.push({ tick, writes: c.writes });
  if (tick === 1) assert.equal(candidate.get(c, "pistol_flash_timer"), 0x81);
  if (tick >= 2) assert.equal(candidate.get(c, "pistol_flash_timer"), 0);
}
assert.deepEqual(clickWrites, [{ tick: 0, writes: [[0x4015, 15], [0x400c, 0x18], [0x400e, 0x84], [0x400f, 0xf8]] }, { tick: 2, writes: [[0x400c, 0x30], [0x4015, 7]] }]);
examples.dryFireWrites = clickWrites;
checks.emptyClickStopsAfterTwoActiveTicksAndHeldBDoesNotRepeat = true;
candidate.put(c, "button_edges", 0x40);candidate.call(c, "pistol_tick");
assert.equal(candidate.get(c, "pistol_flash_timer"), 0x82);
candidate.put(c, "button_edges", 0x40);candidate.call(c, "pistol_tick");
assert.equal(candidate.get(c, "pistol_flash_timer"), 0x81);
assert.deepEqual(c.writes, []);
checks.freshBRearmsOnlyAfterCooldown = true;

// Execute real pause helpers, including all PPU message work, then tick the
// cue while deliberately following pause_poll's carry gate. Controller-only
// coverage separately proves the complete NMI uses that gate.
const p = dryFixture();candidate.call(p, "pistol_tick");
const timer = candidate.get(p, "pistol_flash_timer"), cooldown = candidate.get(p, "pistol_cooldown");
candidate.put(p, "button_edges", 0x10);candidate.put(p, "input_buttons", 0x50);
assert.equal(candidate.call(p, "pause_poll"), true);
assert.ok(p.writes.some(([a, v]) => a === 0x400c && v === 0x30));
for (let i = 0; i < 30; i++) {
  candidate.put(p, "button_edges", 0);
  assert.equal(candidate.call(p, "pause_poll"), true);
  candidate.call(p, "pause_cue_tick");
}
assert.equal(candidate.get(p, "pistol_flash_timer"), timer);
assert.equal(candidate.get(p, "pistol_cooldown"), cooldown);
candidate.put(p, "button_edges", 0x10);assert.equal(candidate.call(p, "pause_poll"), true);
assert.ok(p.writes.some(([a, v]) => a === 0x400c && v === 0x18));
assert.ok(!p.writes.some(([a]) => a === 0x4015));
candidate.put(p, "button_edges", 0);candidate.put(p, "input_buttons", 0);
candidate.call(p, "pistol_tick");candidate.call(p, "pistol_tick");
assert.equal(candidate.get(p, "pistol_flash_timer"), 0);
checks.pausePreservesAndRestoresTheClickWithoutDisablingOtherChannels = true;

for (const stop of ["pistol_reset", "exit_complete", "player_damage"]) {
  const s = dryFixture();candidate.call(s, "pistol_tick");candidate.call(s, stop, stop === "player_damage" ? 100 : undefined);
  assert.equal(candidate.get(s, "pistol_flash_timer"), 0);
  assert.equal(candidate.get(s, "pistol_cooldown"), 0);
  const channelWrites = s.writes.filter(([a]) => a === 0x4015);
  assert.ok(channelWrites.length && channelWrites.every(([, v]) => !(v & 8) && (v & 4)));
}
checks.resetDeathAndCompletionCancelClickAndPreserveTriangleEnable = true;
for (const [field, value] of [["pistol_health", 0], ["exit_flags", 128], ["pistol_cooldown", 2]]) {
  const s = dryFixture();candidate.put(s, field, value);candidate.call(s, "pistol_tick");
  assert.ok(!s.writes.some(([a]) => a === 0x400f));
  assert.equal(candidate.get(s, "pistol_flash_timer"), 0);
}
checks.deadCompletedAndCoolingDownPlayersCannotStartClick = true;

// Use the actual competing sound owners, not just their condition flags.
// An interrupted tail must stay cancelled when the dry click finishes; a new
// door/guard sound can take ownership normally after that point.
for (const [routine, timerName, timerValue] of [["door_sound_tick", "door_sound_timer", 12], ["zombie_attack_tick", "zombie_audio_timer", 5]]) {
  const s = dryFixture();
  candidate.put(s, "zombie_attack_state", 3);
  candidate.put(s, "zombie_attack_timer", 90);
  candidate.put(s, timerName, timerValue);
  candidate.call(s, "pistol_tick");
  candidate.call(s, routine);
  assert.equal(candidate.get(s, timerName), 0, `${routine} permanently drops its preempted tail`);
  assert.deepEqual(s.writes, [], `${routine} cannot alter the player's live click`);
  assert.equal(candidate.get(s, "pause_sound_noise"), 0x18);
  candidate.put(s, "button_edges", 0);candidate.put(s, "input_buttons", 0);
  candidate.call(s, "pistol_tick");candidate.call(s, "pistol_tick");
  candidate.call(s, routine);
  assert.deepEqual(s.writes, [], `${routine} cannot revive its stale tail`);
  assert.equal(candidate.get(s, "pause_sound_noise"), 0x30);
  candidate.put(s, timerName, timerValue);
  candidate.call(s, routine);
  assert.ok(s.writes.some(([a]) => a === 0x400c), `${routine} may play a subsequent new effect`);
}
checks.doorAndGuardNoiseOwnersYieldWithoutRevivingTheirTails = true;

const report = { passed: Object.values(checks).every(Boolean), scope: "Injected CPU/RAM boundary fixtures execute assembled ROM routines with automatic interrupts suppressed. This is distinct from controller-only traversal and does not certify PPU/VBlank timing.",
  candidateRomSha256: hash(candidate.rom), candidateLabelsSha256: hash(candidate.symbolBytes), baselineRomSha256: baseline ? hash(baseline.rom) : null, coreCpuSha256, coreCommit: "5b27c4243f1cb2528c54941e13c29c4ced7d5a45",
  driverSha256: hash(readFileSync(fileURLToPath(import.meta.url))), checks, counts, examples,
  candidateCalls: candidate.calls, candidateMaximumHelperCycles: candidate.maxCycles, baselineMaximumHelperCycles: baseline ? baseline.maxCycles : null };
const output = resolve(options["--output"] || resolve(root, "verification/gameplay-tweaks.json"));
writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify({ passed: report.passed, checks: Object.keys(checks).length, counts, output }, null, 2));
