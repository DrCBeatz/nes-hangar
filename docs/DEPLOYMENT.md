# Browser deployment

[Play Hangar](https://8bitpocket.app/?game=hangar) is live on the maintained
8-Bit Pocket site. Click **Play Hangar**, then press **Start** on the game title
screen. The ordinary hosted picker and local **Open ROM** loader remain available.

## Deployed integration

The initial emulator integration is [commit b2e8312](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/commit/b2e8312ebb59a315d5603ca80d596843cdfd1f8d).
Its [deployment workflow](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/actions/runs/39170142984)
passed on 2026-10-18, including tests, the Vite build, S3 upload and CloudFront
invalidation. This used the existing hosting; no AWS infrastructure or domain
configuration changed.

- A versioned copy of the release is hosted at
  `/roms/hangar-ntsc-fcc47032.nes` with the same SHA-256 as this repository.
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

## Gameplay update

The `prototype-2026-10-18-gameplay` ROM is hosted as
`/roms/hangar-ntsc-fcc47032.nes`. It tightens the ammo pickup, adds an empty-gun
click and widens exit-switch activation. The stable Play link and controls
remain the same.

The updated `test/hangar.test.mjs` runs 7,493 normal NTSC refreshes with only
controller input, including both encounters, both pickups, zero-ammo feedback,
the door, completion from the expanded switch area and restart. All 18 tests
and the production build passed locally. Boundary and timing results for this
exact ROM are linked in [VERIFICATION.md](VERIFICATION.md).

## Initial verification and limits

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
