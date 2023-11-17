# Rootless Podman Homemanager Module

A Home-manager module to generate systemd services for Rootless Podman Pods from a Nixos `virtualisation.oci-containers` / docker-compose like style.

__Note:__ Currently it is only supported to use containers which are part of a pod.

## Installation
```
{
  inputs.rootless-podman-homeManager.url = "github:FabianKoehnen/rootless-podman-homemanager";

  outputs = { self, nixpkgs, rootless-podman-homeManager }: {
    # change `yourhostname` to your actual hostname
    nixosConfigurations.yourhostname = nixpkgs.lib.nixosSystem {
      # customize to your system
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        home-manager.sharedModules = [
            rootless-podman-homeManager.homeManagerModules.default
        ];
      ];
    };
  };
}
```

## Available Options
__Note:__ `virtualisation.rootless-podman.uid` needs to be set with the uid of the user of the home-manager configuration
### Pods
See [default.nix#L88](default.nix#L88)
### Containers
See [default.nix#L11](default.nix#L11)


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