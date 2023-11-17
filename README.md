# Rootless Podman Homemanager Module

A Home-manager module to generate systemd services for Rootless Podman Pods from a Nixos `virtualisation.oci-containers` / docker-compose like style.

## Installation
```
{
  inputs.rootless-podman.url = "github:FabianKoehnen/rootless-podman-homemanager";

  outputs = { self, nixpkgs, sops-nix }: {
    # change `yourhostname` to your actual hostname
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      # customize to your system
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        home-manager.sharedModules = [
            inputs.rootless-podman.homeManagerModules.default
        ];
      ];
    };
  };
}
```

## Example
```
virtualisation.rootless-podman = {
    uid = "1001";
    pods = {
        homeassistent = {
            ports = [
                "6052:6052"
                "5353:5353/udp"
            ];

            containers = {
                esphome = {
                    image = "docker.io/esphome/esphome";
                    environment = {
                        ESPHOME_DASHBOARD_USE_PING="true";
                    };
                    volumes = [
                        "/var/run/dbus:/var/run/dbus"
                        "/var/run/avahi-daemon/socket:/var/run/avahi-daemon/socket"
                    ];
                };

                busybox = {
                    image = "docker.io/busybox";
                    cmd = "sleep 1000";
                };
            };
        };
    };
};
```