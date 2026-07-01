self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude-desktop;
in
{
  options.programs.claude-desktop = {
    enable = lib.mkEnableOption "the official Claude desktop app";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "claude-desktop.packages.\${system}.default";
      description = "The claude-desktop package to use.";
    };

    cowork = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Wire up what Cowork's micro-VM sandbox needs on NixOS. The app's
          capability check probes hard-coded FHS paths (no env overrides), so
          these have to exist on the real filesystem:

          - UEFI firmware at `/usr/share/OVMF/OVMF_CODE_4M.fd` (and the
            `_VARS_4M.fd` template derived from it).
          - `virtiofsd` at `/usr/libexec/virtiofsd`. The app ships a virtiofsd
            of its own but does *not* accept it for the check — it wants the
            distro one (`apt install virtiofsd` lands here), so we symlink
            nixpkgs' `virtiofsd`.
          - the `vhost_vsock` kernel module.

          qemu is already on the app's PATH via the package wrapper. Cowork
          also needs `/dev/kvm` access; see
          {option}`programs.claude-desktop.cowork.kvmUsers`.
        '';
      };

      kvmUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "alice" ];
        description = ''
          Users to add to the `kvm` group so Cowork's VM can open `/dev/kvm`.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { environment.systemPackages = [ cfg.package ]; }

      (lib.mkIf cfg.cowork.enable {
        # The app probes these absolute paths at startup (no env overrides):
        #  - OVMF: reads *_CODE_4M.fd, derives *_VARS_4M.fd from it, then copies
        #    VARS to a writable per-VM file, so read-only store firmware is fine.
        #  - virtiofsd: only /usr/libexec/virtiofsd and /usr/bin/virtiofsd are
        #    accepted (the bundled copy is ignored by the capability check).
        systemd.tmpfiles.rules = [
          "L+ /usr/share/OVMF/OVMF_CODE_4M.fd - - - - ${pkgs.OVMF.firmware}"
          "L+ /usr/share/OVMF/OVMF_VARS_4M.fd - - - - ${pkgs.OVMF.variables}"
          "L+ /usr/libexec/virtiofsd - - - - ${pkgs.virtiofsd}/bin/virtiofsd"
        ];

        # Cowork's micro-VM needs the vhost-vsock transport.
        boot.kernelModules = [ "vhost_vsock" ];

        # /dev/kvm access for the listed users.
        users.users = lib.genAttrs cfg.cowork.kvmUsers (_: {
          extraGroups = [ "kvm" ];
        });
      })
    ]
  );
}
