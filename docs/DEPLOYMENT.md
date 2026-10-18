# Browser release plan

Keep Hangar's source and versioned ROM releases in this repository. For the next web iteration, use a small landing page with **Download ROM** and **Play in browser** buttons, backed by the existing [8-Bit Pocket emulator](https://8bitpocket.app/). Maintain one emulator implementation initially; a separate branded build can come later if it needs different behavior.

This is a plan, not a deployed integration. No website, emulator source, AWS resource or public release was changed during this review.

## What is verified

Reviewed on 2026-10-18 against emulator commit [`222b086`](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/tree/222b0865e4494906527f8192619866e6170aa4bb). The local checkout's relevant application, CSS, manifest, package and deployment files matched that public commit. Direct HTTPS requests returned the live site's HTML and ROM manifest; the manifest listed only Melo-Jellos 2. **Hangar gameplay was not tested in the live browser emulator.** Mesen validation does not establish JSNES compatibility or mobile performance.

| Existing capability | Concrete hook |
| --- | --- |
| Load a local `.nes` without uploading it | `src/main.js`: `loadRomFromFile()` reads `file.arrayBuffer()`, then calls `loadRomData()`. |
| List and fetch hosted ROMs | `loadHostedRomManifest()` fetches `/roms/manifest.json`; the picker calls `loadRomFromUrl()`, which uses `Browser.loadROMFromURL()`. |
| Start either kind of ROM | `loadRomData()` initializes the emulator, starts the ROM, applies mono audio and fits the screen. |
| Select a game through its URL | **Not implemented.** There is no query-string game resolver in the reviewed application. |

These hooks are in the pinned [application source](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/src/main.js); the current [manifest](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/public/roms/manifest.json) contains title, URL and attribution fields.

The immediate manual option is to download [release/hangar-ntsc.nes](../release/hangar-ntsc.nes), open 8-Bit Pocket, choose **Open ROM**, and select that file. This uses an existing loading feature; it is not a claim that this ROM has passed browser testing.

## Proposed integration

1. Test that exact release ROM locally with the existing emulator. Check title/Start, movement and strafing, combat, pickups, slime, the exit door, pause/resume and results/restart. Compare with stock NTSC Mesen, then check desktop browsers and mobile Safari/Chrome, including landscape controls and audio after a user gesture.
2. Add a versioned ROM under the emulator's `public/roms/`, a narrow `.gitignore` exception, and an attributed manifest entry. Add an explicit stable `id: "hangar"`; IDs are a proposed extension, not a current feature. Keep the release checksum alongside the download.
3. Extend `loadHostedRomManifest()` to retain entries by ID. Read `new URLSearchParams(location.search).get("game")`, resolve only a known manifest entry, and route it through the existing loader. Show a **Play Hangar** confirmation button so loading/audio startup can begin from a user gesture; show a useful message for an unknown ID. Preserve the ordinary hosted picker and local file loader.
4. After that implementation is tested and deployed, link the landing page's play button to `https://8bitpocket.app/?game=hangar`. **That address does not currently select Hangar.** Until then, label the link **Open emulator** and explain the local-file step.

Use a same-origin hosted ROM URL for the first integration. This fits the existing loader and avoids making cross-origin ROM hosting part of the initial change. A separately hosted landing page can still link to the maintained emulator.

## Display, palette and speed

The app pins [JSNES commit `5b27c42`](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/package.json). Its [screen implementation](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/browser/screen.js) creates a 256×240 canvas and fits it at a 16:15 ratio. The app also applies independent maximum width/height constraints in [`.screen canvas`](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/src/styles.css), so verify the final displayed ratio at each viewport size. For a future 4:3 presentation option, keep the 256×240 drawing buffer and change one coordinated display-sizing calculation; CSS alone would compete with the explicit dimensions written by `fitInParent()`.

There is no palette selector in the application. The pinned [PPU initialization](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/ppu/index.js) uses its [built-in NTSC RGB palette](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/ppu/palette-table.js). Compare actual Hangar captures before proposing a selectable palette; matching NES color indices does not guarantee identical displayed colors between emulators.

The browser [frame timer](https://github.com/taiyuuki/jsnes/blob/5b27c4243f1cb2528c54941e13c29c4ced7d5a45/src/browser/frame-timer.js) targets about 60.098 emulated frames per second. The app's `papu.setFrameRate(60)` synchronizes audio calculations; it is not a Mesen-style extra-scanline overclock. There is no exposed speed/overclock setting. Measure browser emulation speed separately from Hangar's world-rendering rate: a browser sustaining full emulation speed can still show the ROM's normal hardware-limited redraw cadence. Keep the first comparison at normal speed.

## Hosting and release boundary

The existing [infrastructure template](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/infrastructure/cloudformation.yml) describes a private S3 origin behind CloudFront, HTTPS and Route 53. Query strings are not forwarded to the origin, which is compatible with the proposed client-side game resolver: the same HTML can read `?game=hangar` in the browser.

The [deployment workflow](https://github.com/DrCBeatz/nes-emulator-mobile-web-app/blob/222b0865e4494906527f8192619866e6170aa4bb/.github/workflows/deploy.yml) builds Vite's `dist/`, synchronizes it to S3 **with deletion**, then invalidates CloudFront. If the landing page lives at the same site, include it and its downloads in that maintained build output; manually copied files can disappear on the next deploy. Alternatively, host the landing page separately and link to the emulator. A subdirectory page should use an explicit static URL such as `/hangar/index.html` unless routing is deliberately configured.

The next implementation can prepare these changes for review. This repository preparation does not publish them or change the emulator's deployment workflow.
