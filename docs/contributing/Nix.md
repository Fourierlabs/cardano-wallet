# Nix

[Nix](https://nixos.org) is a package manager and build tool. It is used in `cardano-wallet` for:
 - [[Hydra]]
 - Provisioning dependencies in [GitHub Actions CI](https://github.com/input-output-hk/cardano-wallet/blob/master/.github/workflows/build.yml#L1).
 - Reproducible development environments ([nix develop][flake.nix]).
 - Distribution of release builds ([[NixOS]]).

Nix is not required for `cardano-wallet` development, but it can help you a lot if you try it.

[flake.nix]: https://github.com/input-output-hk/cardano-wallet/blob/master/flake.nix

## Installing/Upgrading Nix

The minimum required version of Nix is 2.6.0.

- [Nix Package Manager Guide: Installation](https://nixos.org/manual/nix/stable/#ch-installing-binary)
- [Nix Package Manager Guide: Upgrading Nix](https://nixos.org/manual/nix/stable/#ch-upgrading-nix)

## Required settings

The following option _must_ be enabled in your [`nix.conf`](https://nixos.org/manual/nix/stable/command-ref/conf-file.html):

```
experimental-features = nix-command flakes
```

## Binary cache

To improve build speed, it is **highly recommended** (but not mandatory) to configure the **binary cache maintained by IOHK**.

See [iohk-nix/docs/nix.md](https://github.com/input-output-hk/iohk-nix/blob/8b1d65ba294708b12d7b15103ac35431d9b60819/docs/nix.md) or [cardano-node/doc/getting-started/building-the-node-using-nix.md](https://github.com/input-output-hk/cardano-node/blob/468f52e5a6a2f18a2a89218a849d702481819f0b/doc/getting-started/building-the-node-using-nix.md#building-under-nix)
for instructions on how to configure the Hydra binary cache on your system.

## Building with Nix

See the [[Building#Nix]] page.

## Reproducible Development Environment

Run [`nix develop`][nix-develop] to get a build environment which includes all
necessary compilers, libraries, and development tools.

This uses the `devShell` attribute of [`flake.nix`][flake.nix].

Full instructions are on the [[Building#cabalnix-build]] page.

[nix-develop]: https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop.html

## Development tips

### Code generation

- [ ] TODO: Update for cabal `plan-to-nix`

The Nix build depends on code which is generated from `stack.yaml` and
the Cabal files. If you change these files, then you will probably
need to update the generated files.

To do this, run:

```
./nix/regenerate.sh
```

Then add and commit the files that it creates.

Alternatively, wait for Buildkite to run this same command. It will
produce a patch, and also push a commit with updates back to your
branch.

### Haskell.nix pin

The Nix build also depends on the [Haskell.nix](https://github.com/input-output-hk/haskell.nix) build infrastructure.
It may be necessary to update `haskell.nix` when moving to a
new Haskell LTS version or adding Hackage dependencies.

To update to the latest version, run the following command:

```console
$ nix flake lock --update-input haskellNix
warning: updating lock file '/home/rodney/iohk/cw/flake/flake.lock':
• Updated input 'haskellNix':
    'github:input-output-hk/haskell.nix/f05b4ce7337cfa833a377a4f7a889cdbc6581103' (2022-01-11)
  → 'github:input-output-hk/haskell.nix/a3c9d33f301715b162b12afe926b4968f2fe573d' (2022-01-17)
• Updated input 'haskellNix/hackage':
    'github:input-output-hk/hackage.nix/d3e03042af2d0c71773965051d29b1e50fbb128e' (2022-01-11)
  → 'github:input-output-hk/hackage.nix/3e64c7f692490cb403a258209e90fd589f2434a0' (2022-01-17)
• Updated input 'haskellNix/stackage':
    'github:input-output-hk/stackage.nix/308844000fafade0754e8c6641d0277768050413' (2022-01-11)
  → 'github:input-output-hk/stackage.nix/3c20ae33c6e59db9ba49b918d69caefb0187a2c5' (2022-01-15)
warning: Git tree '/home/rodney/iohk/cw/flake' is dirty
```

Then commit the updated
[flake.lock](https://github.com/input-output-hk/cardano-wallet/blob/master/flake.lock)
file.

When updating Haskell.nix, consult the [ChangeLog](https://github.com/input-output-hk/haskell.nix/blob/master/changelog.md#L1) file. There may have been API changes which need corresponding updates in `cardano-wallet`.

### iohk-nix pin

The procedure for updating the [`iohk-nix`](https://github.com/input-output-hk/iohk-nix) library of common code is much the same as for Haskell.nix. Run this command and commit the updated `flake.lock` file:

```console
$ nix flake lock --update-input iohkNix
```

It is not often necessary to update `iohk-nix`. Before updating, ask devops whether there may be changes which affect our build.

## Common problems

### Warning: dumping very large path

```
warning: dumping very large path (> 256 MiB); this may run out of memory
```

Make sure you don't have large files or directories in your git worktree.

When building, Nix will copy the project sources into
`/nix/store`. Standard folders such as `.stack-work` will be filtered
out, but everything else will be copied.
