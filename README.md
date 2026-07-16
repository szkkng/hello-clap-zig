# hello-clap-zig

A minimal non-GUI CLAP gain plugin written in Zig.

Setup:

```bash
nix develop
```

Build & Install:

```bash
# Set -p to your CLAP plugin directory.
zig build -Doptimize=ReleaseFast -p ~/Library/Audio/Plug-Ins/CLAP
```
