{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.podman;

  podman-lib = import ./podman-lib.nix { inherit pkgs lib config; };

  createQuadletSource = name: networkDef:
    let
      quadlet = (podman-lib.deepMerge {
        Install = {
          WantedBy = (if networkDef.autoStart then [
            "default.target"
            "multi-user.target"
          ] else
            [ ]);
        };
        Network = {
          Driver = networkDef.driver;
          Gateway = networkDef.gateway;
          Internal = networkDef.internal;
          NetworkName = name;
          Label = networkDef.labels // { "nix.home-manager.managed" = true; };
          PodmanArgs = networkDef.extraPodmanArgs;
          Subnet = networkDef.subnet;
        };
        Service = {
          Environment = {
            PATH = (builtins.concatStringsSep ":" [
              "${podman-lib.newuidmapPaths}"
              "${makeBinPath [ pkgs.su pkgs.coreutils ]}"
            ]);
          };
          ExecStartPre = [ "${podman-lib.awaitPodmanUnshare}" ];
          TimeoutStartSec = 15;
          RemainAfterExit = "yes";
        };
        Unit = {
          After = [ "network.target" ];
          Description = (if (builtins.isString networkDef.description) then
            networkDef.description
          else
            "Service for network ${name}");
        };
      } networkDef.extraConfig);
    in ''
      # Automatically generated by home-manager for podman network configuration
      # DO NOT EDIT THIS FILE DIRECTLY
      #
      # ${name}.network
      ${podman-lib.toQuadletIni quadlet}
    '';

  toQuadletInternal = name: networkDef: {
    assertions = podman-lib.buildConfigAsserts name networkDef.extraConfig;
    serviceName =
      "podman-${name}"; # generated service name: 'podman-<name>-network.service'
    source = podman-lib.removeBlankLines (createQuadletSource name networkDef);
    resourceType = "network";
  };

in let
  networkDefinitionType = types.submodule {
    options = {

      autoStart = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to start the network on boot (requires user lingering).
        '';
      };

      description = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "My Network";
        description = "The description of the network.";
      };

      driver = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "bridge";
        description = "The network driver to use.";
      };

      extraConfig = mkOption {
        type = podman-lib.extraConfigType;
        default = { };
        example = literalExpression ''
          {
            Network = {
              ContainerConfModule = "/etc/nvd.conf";
            };
            Service = {
              TimeoutStartSec = 30;
            };
          }
        '';
        description = "INI sections and values to populate the Network Quadlet";
      };

      extraPodmanArgs = mkOption {
        type = with types; listOf str;
        default = [ ];
        example = [ "--dns=192.168.55.1" "--ipam-driver" ];
        description = ''
          Extra arguments to pass to the podman network create command.
        '';
      };

      gateway = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "192.168.20.1";
        description = "The gateway IP to use for the network.";
      };

      internal = mkOption {
        type = with types; nullOr bool;
        default = null;
        description = "Whether the network should be internal";
      };

      labels = mkOption {
        type = with types; attrsOf str;
        default = { };
        example = {
          app = "myapp";
          some-label = "somelabel";
        };
        description = "The labels to apply to the network.";
      };

      subnet = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "192.168.20.0/24";
        description = "The subnet to use for the network.";
      };

    };
  };
in {
  options.services.podman.networks = mkOption {
    type = types.attrsOf networkDefinitionType;
    default = { };
    description = "Defines Podman network quadlet configurations.";
  };

  config = let networkQuadlets = mapAttrsToList toQuadletInternal cfg.networks;
  in mkIf cfg.enable {
    services.podman.internal.quadletDefinitions = networkQuadlets;
    assertions = flatten (map (network: network.assertions) networkQuadlets);

    xdg.configFile."podman/networks.manifest".text =
      podman-lib.generateManifestText networkQuadlets;
  };
}
