# Browser deployment

[Play Hangar](https://8bitpocket.app/?game=hangar) is live on the maintained
8-Bit Pocket site. Click **Play Hangar**, then press **Start** on the game title
screen. The ordinary hosted picker and local **Open ROM** loader remain available.

The current hosted ROM is `prototype-2026-10-24-door-reach`, the previously
published release identified below. The repository's `release/hangar-ntsc.nes`
is now `prototype-2026-10-26-performance-rc1`, awaiting the user's playtest
before a separate browser deployment. Updating this repository does not deploy
8-Bit Pocket. See the [candidate notes](PERFORMANCE-UPDATE-20261026.md).

The hosted October 24 release includes the bronze logo, optional
Dr C Beatz soundtrack, revised interactions and ammo placement, credits and
HUD polish. The public author credit is **Dr C Beatz**.

## Current hosted release: 2026-10-24

The game source and ROM were published in
[eba6c06](https://github.com/DrCBeatz/nes-hangar/commit/eba6c0604989c7313ae3575e1968a81562df9329).
Its [clean GitHub build](https://github.com/DrCBeatz/nes-hangar/actions/runs/40144651000)
reproduced the checked-in ROM. The browser integration is
[b0dedb0](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/commit/b0dedb04137656cc004e755a8e4ba189c04ca7fc).
Its [deployment workflow](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/actions/runs/40144651509)
passed, including tests, the production build, S3 synchronization and
CloudFront invalidation. Existing hosting and the stable Play link are unchanged.

- The versioned ROM is `/roms/hangar-ntsc-db258e4c.nes`, 131,088 bytes.
- SHA-256: `db258e4c9c57ff3ef9f4bc8eb732f31b65eec85a1a639e7a9787a90dde1722a9`.
- All 19 emulator tests passed. Controller-only JSNES routes completed the
  level with music ON (7,953 refreshes) and OFF (7,837 refreshes), including
  credits, pickups, all three encounters, door/exit, pause and restart.
- Live HTTP checks returned 200 for the page, manifest, ROM and application
  bundles. The served HTML, manifest, ROM, JavaScript and CSS match the local
  production build exactly.
- This publication did not add a new interactive browser/device check:
  computer-use browser access was unavailable. The controller routes test the
  emulator core; they do not certify audible playback or mobile performance.
  Physical-console testing also remains outstanding.

See the [deployment record](../verification/release-browser-deployment.json),
[ROM verification](VERIFICATION.md), and [itch.io page draft](itch-page-copy.txt).
The five [itch.io screenshots](itch-assets/) are actual captures of this release.

## Historical integrations

The previous sprite-stability ROM (`f342c5b8…`) passed all 18 isolated
core/loading tests, including a 7,529-refresh controller-only route. That
historical evidence is preserved in
[sprite-stability-browser.json](../verification/sprite-stability-browser.json).

### Initial deployed integration

The initial emulator integration is [commit b2e8312](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/commit/b2e8312ebb59a315d5603ca80d596843cdfd1f8d).
Its [deployment workflow](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/actions/runs/39170142984)
passed on 2026-10-18, including tests, the Vite build, S3 upload and CloudFront
invalidation. This used the existing hosting; no AWS infrastructure or domain
configuration changed.

- Releases use hash-based ROM filenames; the current filename is listed above.
- The hosted manifest has stable ID `hangar`. Query strings resolve only
  known manifest IDs; an unknown ID leaves the picker and file loader usable.
- The page waits for a Play gesture before fetching/starting the game. Audio
  startup is preserved across the asynchronous fetch and rapid pause/switch actions.
- The manifest and attribution file link back to this repository and its
  separate code/content license scope.

The [keyboard-guide update](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/commit/0ba0347)
shows Hangar’s default keyboard bindings before Play, from both the direct
link and hosted picker. Controls reopens the guide during gameplay and pauses
the emulator while it covers the view; closing it preserves the prior pause
state. This does not alter the ROM or replace saved custom keyboard bindings.

### Enclosure and third-encounter update

The earlier release was `prototype-2026-10-19-third-encounter`, served as
`/roms/hangar-ntsc-277422aa.nes`. It includes the inner enclosure, tighter ammo
pickup, conservative visibility optimization and third soldier encounter.
The stable `?game=hangar` link, emulator controls and infrastructure are unchanged.

All 18 emulator tests and the production build pass for this ROM. The updated
controller-only JSNES test runs 7,555 normal NTSC refreshes through all three
encounters, both pickups, the door, completion and restart. It deliberately
wastes three rounds to test empty-gun feedback, then finishes with 12 shots,
nine hits, three kills and four rounds. All 46 read-only test symbols were
checked against this release's linker output. The built site's ROM is
byte-identical to that release at [source commit 0f31a394](https://github.com/DrCBeatz/nes-hangar/tree/0f31a3947b7d8a2bed63c64acc53ce8812ce3470).
The evidence is in [third-encounter-browser.json](../verification/third-encounter-browser.json).

Publication uses the existing GitHub Actions workflow: tests, production
build, S3 synchronization and CloudFront invalidation. The ROM's hash-based
filename prevents an older cached ROM from being substituted for this release.

### Previous gameplay update

The `prototype-2026-10-18-empty-buzz` ROM was hosted as
`/roms/hangar-ntsc-08ba1092.nes`. It tightens the ammo pickup, adds an empty-gun
cue and widens exit-switch activation. The latest revision uses a deep buzz
lasting about 133 ms, with slightly more volume. The stable Play link and
controls remain the same.

The updated `test/hangar.test.mjs` runs 7,500 normal NTSC refreshes with only
controller input, including both encounters, both pickups, zero-ammo feedback,
the door, completion from the expanded switch area and restart. All 18 tests
and the production build passed locally. Boundary and timing results for this
exact ROM are linked in [VERIFICATION.md](VERIFICATION.md).

### Initial verification and limits

The initial `npm test` run in the emulator repository passed 18 tests: 17 loading/audio/guide
cases and one real-core gameplay test. The latter runs 2,427 normal NTSC
frames through the pinned JSNES core with controller input, covering title,
loading, pause/resume, movement, soldier attacks, a three-hit kill and corpse
state. It generates frame buffers and finite audio samples without injecting
game RAM or save states. The tests run before production deployment.

Desktop Safari checks covered the direct Play link, title/start, movement,
firing, game pause, emulator pause/resume, switching to Melo-Jellos 2, local
ROM selection and an unknown game ID. The deployed link was also opened and
started, and the live ROM checksum and JavaScript bundle matched the local
production build. These are targeted checks, not a complete browser playthrough
or a certification of mobile Safari/Chrome, audible sound quality, rendering
accuracy or device performance. Phone testing remains a useful next step.

## Display, palette and speed

The app pins [JSNES commit `5b27c42`](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/package.json). Its [screen implementation](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/browser/screen.js) creates a 256×240 canvas and fits it at a 16:15 ratio. The app also applies independent maximum width/height constraints in [`.screen canvas`](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/src/styles.css), so verify the final displayed ratio at each viewport size. For a future 4:3 presentation option, keep the 256×240 drawing buffer and change one coordinated display-sizing calculation; CSS alone would compete with the explicit dimensions written by `fitInParent()`.

There is no palette selector in the application. The pinned [PPU initialization](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/ppu/index.js) uses its [built-in NTSC RGB palette](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/ppu/palette-table.js). Compare actual Hangar captures before proposing a selectable palette; matching NES color indices does not guarantee identical displayed colors between emulators.

The browser [frame timer](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/browser/frame-timer.js) targets about 60.098 emulated frames per second. The app's `papu.setFrameRate(60)` synchronizes audio calculations; it is not a Mesen-style extra-scanline overclock. There is no exposed speed/overclock setting. Measure browser emulation speed separately from Hangar's world-rendering rate: a browser sustaining full emulation speed can still show the ROM's normal hardware-limited redraw cadence. Keep the first comparison at normal speed.

## Landing page and custom domain

A dedicated project page can add screenshots, a ROM download and the existing
Play link. Maintain one emulator implementation initially. A separate branded
emulator build is optional and adds another deployment to maintain.

The current [CloudFormation template](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/b2e8312ebb59a315d5603ca80d596843cdfd1f8d/infrastructure/cloudformation.yml)
uses a private S3 origin, CloudFront, ACM HTTPS and Route 53. Use CloudFormation
and a reviewed [change set](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-cfn-updating-stacks-changesets.html)
for later infrastructure changes. If creating a separate site, define its
bucket, distribution and policy together. There is no need to enable public
S3 website hosting when using a private S3 origin behind CloudFront.

Test the game at the existing URL before configuring a separate domain. A
preferred domain can be registered earlier if desired, but registration is
independent of deployment. Connecting it later needs CloudFront aliases, a
covering ACM certificate in us-east-1 and DNS records. The existing template’s
DomainName parameter replaces its current apex/www aliases; do not change it
just to add a separate Hangar brand. See [AWS certificate requirements](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html)
and [Route 53 routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-cloudfront-distribution.html).

The emulator deploy runs `aws s3 sync dist ... --delete`. If the landing page
shares that bucket, include it and its downloads in the maintained Vite build;
manual bucket uploads absent from dist can be deleted at the next deployment.
Alternatively, use a separate stack/bucket for the landing page and link to
8-Bit Pocket. A page at the existing site can use `/hangar/index.html` without
adding new domain infrastructure.
