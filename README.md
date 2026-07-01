# claude-desktop (Nix flake)

A Nix flake packaging the **official** Anthropic Claude desktop app for Linux
(beta) — the native `.deb` published at
<https://code.claude.com/docs/en/desktop-linux>, repackaged for NixOS.

Unlike the older community flakes (which unpack the Windows/macOS build and
stub out the native modules), this uses Anthropic's real Linux build: its
bundled Electron 42 runtime, the native `@ant/claude-native` and `node-pty`
modules, and the Cowork micro-VM helpers are all shipped as-is and just
patched for the Nix store.

- Version: **1.17377.0**
- Platforms: `x86_64-linux`, `aarch64-linux`
- License: unfree (Anthropic Consumer Terms). The flake scopes an
  `allowUnfreePredicate` to just this package, so no global unfree opt-in is
  needed.

## Try it

```bash
nix run github:nmcbride/claude-desktop-nix   # or  nix run .
```

## Install

### NixOS (recommended — also enables Cowork)

```nix
# flake.nix
{
  inputs.claude-desktop.url = "github:nmcbride/claude-desktop-nix";

  outputs = { nixpkgs, claude-desktop, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        claude-desktop.nixosModules.default
        {
          programs.claude-desktop.enable = true;
          # For Cowork's VM sandbox (see below):
          programs.claude-desktop.cowork.kvmUsers = [ "youruser" ];
        }
      ];
    };
  };
}
```

### Just the package (profile / `environment.systemPackages` / home-manager)

```nix
environment.systemPackages = [ claude-desktop.packages.${system}.default ];
```

or via the overlay:

```nix
nixpkgs.overlays = [ claude-desktop.overlays.default ];
environment.systemPackages = [ pkgs.claude-desktop ];
```

## Cowork (the VM sandbox)

Chat and Claude Code work from the package alone. **Cowork** runs agent work
inside a QEMU micro-VM, and the app checks several host prerequisites at
startup. It shows "Cowork unsupported on Linux because …" when any are
missing. The requirements (and how they're satisfied here):

| Requirement | Provided by |
| --- | --- |
| `qemu-system-x86_64` on `PATH` | package wrapper (bundles `qemu`) |
| VM helper (`cowork-linux-helper`) + VM image | shipped inside the app, patched |
| UEFI firmware at `/usr/share/OVMF/OVMF_CODE_4M.fd` | **NixOS module** — the app hardcodes this FHS path with no env override |
| `virtiofsd` at `/usr/libexec/virtiofsd` | **NixOS module** — the app checks only `/usr/libexec/virtiofsd` and `/usr/bin/virtiofsd`; it does *not* accept its own bundled copy for the capability check, so we symlink nixpkgs' `virtiofsd` |
| `vhost_vsock` kernel module | **NixOS module** (`boot.kernelModules`) — often already builtin |
| `/dev/kvm` access | **NixOS module** — add users via `cowork.kvmUsers` |

So on NixOS, Cowork works once you enable the module and list your user in
`programs.claude-desktop.cowork.kvmUsers`, then `nixos-rebuild switch` and
re-log (for the `kvm` group) or reboot (if `vhost_vsock` isn't builtin).

`programs.claude-desktop.cowork.enable` defaults to `true`; set it to `false`
if you don't want the `/usr/share/OVMF` + `/usr/libexec/virtiofsd` symlinks or
the kernel module.

### Quick manual test without a rebuild

```bash
sudo modprobe vhost_vsock   # no-op if builtin
OVMF=$(nix build --no-link --print-out-paths nixpkgs#OVMF.fd)/FV
VIRTIOFSD=$(nix build --no-link --print-out-paths nixpkgs#virtiofsd)/bin/virtiofsd
sudo mkdir -p /usr/share/OVMF /usr/libexec
sudo ln -sf "$OVMF/OVMF_CODE.fd" /usr/share/OVMF/OVMF_CODE_4M.fd
sudo ln -sf "$OVMF/OVMF_VARS.fd" /usr/share/OVMF/OVMF_VARS_4M.fd
sudo ln -sf "$VIRTIOFSD" /usr/libexec/virtiofsd
# ensure your user is in the kvm group, then launch claude-desktop
```

> Note: these hand-made symlinks point at store paths with no GC root, so a
> `nix-collect-garbage` can break them. The NixOS module is the durable
> version — it pins the same paths as part of the system closure.

## Sandbox

Chromium's setuid `chrome-sandbox` can't be setuid in the Nix store, so the
app relies on NixOS's unprivileged-user-namespace sandbox (enabled by
default). If your host disables user namespaces and the app won't start, build
with the sandbox off:

```nix
claude-desktop.packages.${system}.default.override { disableSandbox = true; }
```

## Wayland

Native Wayland is opt-in via the usual nixpkgs switch:

```bash
NIXOS_OZONE_WL=1 claude-desktop
```

## Updating to a new release

1. Find the latest version + hashes in the apt index:
   `https://downloads.claude.ai/claude-desktop/apt/stable/dists/stable/main/binary-amd64/Packages`
2. Bump `version` in `package.nix` and update both `hash`es (convert the
   `SHA256` from the index with `nix hash convert --hash-algo sha256 --to sri <hex>`).
