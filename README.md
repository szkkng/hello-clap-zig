# hello-clap-zig

A minimal CLAP gain plugin written in Zig.

Setup:

```bash
nix develop
```

Build & Install:

```bash
# Set -p to your CLAP plugin directory.
zig build --release=fast -p ~/Library/Audio/Plug-Ins/CLAP
```
