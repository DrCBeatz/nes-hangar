# Publishing this repository

Repository: [DrCBeatz/nes-hangar](https://github.com/DrCBeatz/nes-hangar).

Suggested description:

> A playable NTSC NES FPS prototype with solid-surface 3D rendering, dynamic
> boundary tiles, sprite enemies and a simplified E1M1-inspired level.

Suggested topics: `nes`, `homebrew`, `6502`, `assembly`, `fps`, `3d-rendering`,
`cc65`, `chr-ram`.

The local repository root is this folder. Publish it independently of the
surrounding research workspace. Git ignores generated build output and local
ROMs, with an explicit exception for `release/hangar-ntsc.nes`.

## Review and build

From the repository root:

```sh
git status
python3 tools/build.py --verify
```

Review README, LICENSE-SCOPE.md and docs/PROVENANCE.md alongside the source.
The MIT license covers original code; the content provenance is separate.

## Update the existing repository

The repository already has its own history and remote. Before publishing a
new prototype, inspect the local changes and confirm the intended destination:

```sh
git status --short
git diff --stat
git remote -v
```

Commit the reviewed source, documentation, reference ROM, checksum and matching
verification records together. Keep unrelated research files and emulator
settings outside the commit. Then push the intended branch to the existing
remote using your configured authentication. Repository preparation and local
verification do not themselves publish or deploy the changes.

If starting from a fresh checkout, clone this repository rather than creating
another empty remote. GitHub's
[existing-project guide](https://docs.github.com/en/get-started/start-your-journey/creating-a-repository-for-your-project-on-github)
describes setup and authentication.

## Release download

The ROM is directly available in `release/`. For a clearer public download,
create a GitHub Release after reviewing the repository and attach
`hangar-ntsc.nes` and `SHA256SUMS`. Use a prototype tag such as
`v0.1.0-prototype`; include the NTSC target, controls, known performance limits
and physical-hardware test status in the release notes.

The included Actions workflow builds/verifies the ROM and uploads a workflow
artifact. It does not create a tag, publish a Release, or deploy the website.

## Later changes

Develop with `python3 tools/build.py`. Test deliberate gameplay or art changes
before replacing the file in `release/`. Refresh SHA256SUMS and release.json
with the new ROM's checksum and version, then run verification again. The
checked-in ROM and reproducible source should describe the same release.

Updating the hosted browser ROM is an independent step; see [DEPLOYMENT.md](DEPLOYMENT.md).
