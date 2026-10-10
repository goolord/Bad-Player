{
  description = "Bad Player: a Discord bot that only allows YouTube video links in text channels";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # Oracle Cloud's Ampere A1 shapes are aarch64; the E2 micro shapes are x86_64.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      src = lib.fileset.toSource {
        root = ./.;
        fileset = lib.fileset.unions [
          ./bad-player.cabal
          ./app
          ./src
          ./test
        ];
      };

      # GHC 9.10, the same compiler cabal.project pins.
      haskellPackagesFor =
        pkgs:
        pkgs.haskell.packages.ghc910.override {
          overrides = hself: hsuper: {
            # nixpkgs marks calamity broken only because its upper bounds
            # exclude data-default-class 0.2 and typerep-map 0.7; it builds fine
            # against both.
            calamity = lib.pipe hsuper.calamity [
              pkgs.haskell.lib.compose.doJailbreak
              pkgs.haskell.lib.compose.markUnbroken
            ];
            bad-player = hself.callCabal2nix "bad-player" src { };
          };
        };

      badPlayerFor =
        pkgs:
        let
          # Only the executable, so the runtime closure doesn't pull in GHC.
          exe = pkgs.haskell.lib.compose.justStaticExecutables (haskellPackagesFor pkgs).bad-player;
        in
        exe.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
          # TLS needs CA certificates. Ship nixpkgs' bundle so the binary works
          # on any distro, while still letting SYSTEM_CERTIFICATE_PATH override it.
          postFixup = (old.postFixup or "") + ''
            wrapProgram $out/bin/bad-player \
              --set-default SYSTEM_CERTIFICATE_PATH ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '';
          meta = (old.meta or { }) // {
            mainProgram = "bad-player";
          };
        });
    in
    {
      packages = forAllSystems (pkgs: rec {
        bad-player = badPlayerFor pkgs;
        default = bad-player;
      });

      checks = forAllSystems (pkgs: {
        # Building runs the link-matcher test suite.
        bad-player = badPlayerFor pkgs;
      });

      devShells = forAllSystems (
        pkgs:
        let
          hp = haskellPackagesFor pkgs;
        in
        {
          default = hp.shellFor {
            packages = p: [ p.bad-player ];
            nativeBuildInputs = [ pkgs.cabal-install ];
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.bad-player;
        in
        {
          options.services.bad-player = {
            enable = lib.mkEnableOption "the Bad Player Discord bot";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = lib.literalExpression "bad-player.packages.\${system}.default";
              description = "The Bad Player package to run.";
            };

            tokenFile = lib.mkOption {
              # A string rather than a path so the secret is never copied into
              # the world-readable Nix store.
              type = lib.types.str;
              example = "/etc/bad-player/token";
              description = ''
                File containing the Discord bot token. It is passed to the
                service as a systemd credential, so it can stay readable by
                root only.
              '';
            };

            playlistChannel = lib.mkOption {
              type = lib.types.str;
              default = "bad-playlist";
              description = "Name of the text channel that only allows YouTube video links.";
            };

            catchUpHours = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 24;
              description = ''
                On every fresh connection, re-check messages in the playlist channel
                posted within this many hours, to moderate anything sent while
                the bot was down. 0 disables this.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.services.bad-player = {
              description = "Bad Player Discord bot";
              wantedBy = [ "multi-user.target" ];
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              # Never give up restarting; Discord or network outages can last
              # longer than systemd's default burst limit.
              startLimitIntervalSec = 0;

              environment = {
                BOT_TOKEN_FILE = "%d/bot-token";
                PLAYLIST_CHANNEL = cfg.playlistChannel;
                CATCHUP_HOURS = toString cfg.catchUpHours;
              };

              serviceConfig = {
                ExecStart = lib.getExe cfg.package;
                LoadCredential = "bot-token:${cfg.tokenFile}";
                Restart = "always";
                RestartSec = "10s";

                # The bot uses tens of MB; this only guards small VMs against
                # a runaway process.
                MemoryMax = "512M";

                DynamicUser = true;
                CapabilityBoundingSet = "";
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectProc = "invisible";
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                  "AF_UNIX"
                  "AF_NETLINK"
                ];
                RestrictNamespaces = true;
                RestrictRealtime = true;
                LockPersonality = true;
                SystemCallArchitectures = "native";
                SystemCallFilter = [ "@system-service" ];
              };
            };
          };
        };
    };
}
