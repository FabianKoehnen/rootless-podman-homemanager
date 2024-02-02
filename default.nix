{ config, options, lib, pkgs, ... }:

with lib;
let
    cfg = config.virtualisation.rootless-podman;
    
    sopsSecretType = 
        { ... }: {
            options = {
                type = lib.mkOption {
                    type = lib.types.enum [ "mount" "env"];
                    default = "env";
                    description = ''
                        How the secret is exposed to the container. 
                        mount mounts the secret into the container as a file. 
                        env exposes the secret as an environment variable. 
                        Defaults to env.
                    '';
                };
                target = lib.mkOption {
                    type = with types; nullOr str;
                    default = null;
                    description = ''

                        Target of secret. For mounted secrets, this is the path to the secret inside the container. 
                        If a fully qualified path is provided, the secret is mounted at that location. 
                        Otherwise, the secret is mounted to /run/secrets/target for linux containers or /var/run/secrets/target for freebsd containers. 
                        If the target is not set, the secret is mounted to /run/secrets/secretname by default. 
                        For env secrets, this is the environment variable key. Defaults to secretname.
                    '';
                };
                uid = lib.mkOption {
                    type = with types; nullOr str;
                    default = null;
                    description = ''
                        UID of secret. Defaults to 0. Mount secret type only.
                    '';
                };
                gid = lib.mkOption {
                    type = with types; nullOr str;
                    default = null;
                    description = ''
                        GID of secret. Defaults to 0. Mount secret type only.
                    '';
                };
                mode = lib.mkOption {
                    type = with types; nullOr str;
                    default = null;
                    description = ''
                        Mode of secret. Defaults to 0444. Mount secret type only.
                    '';
                };
            };
    };
    
    containerOptions =
        { ... }: {
            
            options = {
                image = mkOption {
                    type = with types; str;
                    description = lib.mdDoc "OCI image to run.";
                    example = "library/hello-world";
                };

                cmd = mkOption {
                    type =  with types; listOf str;
                    default = [];
                    description = lib.mdDoc "Commandline arguments to pass to the image's entrypoint.";
                    example = literalExpression ''
                        ["--port=9000"]
                    '';
                };

                environment = mkOption {
                    type = with types; attrsOf str;
                    default = {};
                    description = lib.mdDoc "Environment variables to set for this container.";
                    example = literalExpression ''
                        {
                        DATABASE_HOST = "db.example.com";
                        DATABASE_PORT = "3306";
                        }
                    '';
                };

                environmentFiles = mkOption {
                    type = with types; listOf (nullOr path);
                    default = [];
                    description = lib.mdDoc "Environment files for this container.";
                    example = literalExpression ''
                        [
                        /path/to/.env
                        /path/to/.env.secret
                        ]
                    '';
                };

                volumes = mkOption {
                    type = with types; listOf (nullOr str);
                    default = [];
                    description = lib.mdDoc ''
                        List of volumes to attach to this container.

                        Note that this is a list of `"src:dst"` strings to
                        allow for `src` to refer to `/nix/store` paths, which
                        would be difficult with an attribute set.  There are
                        also a variety of mount options available as a third
                        field; please refer to the
                        [docker engine documentation](https://docs.docker.com/engine/reference/run/#volume-shared-filesystems) for details.
                    '';
                    example = literalExpression ''
                        [
                        "volume_name:/path/inside/container"
                        "/path/on/host:/path/inside/container"
                        ]
                    '';
                };

                sopsSecrets = mkOption {
                    type = with types; attrsOf (types.submodule sopsSecretType);
                    default = {};
                    description = lib.mdDoc "sops secret names to set as env var via podman secrets";
                    example = literalExpression ''
                        {
                            "container/database/MARIADB_ROOT_PASSWORD" = {

                            };
                        }
                    '';
                };

                extraArgs = mkOption {
                    type = with types; listOf (nullOr str);
                    default = [];
                };
            };
        };

    podOptions =
        { ... }: {
            options = {
                ports = mkOption {
                    type = with types; listOf str;
                    default = [];
                    description = lib.mdDoc ''
                        Network ports to publish from the container to the outer host.

                        Valid formats:
                        - `<ip>:<hostPort>:<containerPort>`
                        - `<ip>::<containerPort>`
                        - `<hostPort>:<containerPort>`
                        - `<containerPort>`

                        Both `hostPort` and `containerPort` can be specified as a range of
                        ports.  When specifying ranges for both, the number of container
                        ports in the range must match the number of host ports in the
                        range.  Example: `1234-1236:1234-1236/tcp`

                        When specifying a range for `hostPort` only, the `containerPort`
                        must *not* be a range.  In this case, the container port is published
                        somewhere within the specified `hostPort` range.
                        Example: `1234-1236:1234/tcp`

                        Refer to the
                        [Docker engine documentation](https://docs.docker.com/engine/reference/run/#expose-incoming-ports) for full details.
                    '';
                    example = literalExpression ''
                        [
                        "8080:9000"
                        ]
                    '';
                };
                network = mkOption {
                    type = with types; nullOr str;
                    default = "slirp4netns";
                    description = lib.mdDoc ''
                        see https://docs.podman.io/en/latest/markdown/podman-pod-create.1.html#network-mode-net
                    '';
                    example = literalExpression ''
                        slirp4netns
                    '';
                    
                };
                containers = mkOption {
                    type = with types; attrsOf (types.submodule containerOptions);
                    default = {};
                    description = lib.mdDoc ''
                        Rootless containers to run as systemd services.
                    '';
                };

                extraArgs = mkOption {
                    type = with types; listOf (nullOr str);
                    default = [];
                };
            };
        };

    podTemplate = name: value: mappedName:(
        let
            inherit name;
            inherit value;
            inherit mappedName;

            containers = map (containerName: "container-"+name+"-"+containerName+".service") ((attrNames value.containers));

            portsString = foldl (entry: acc: entry+" -p"+acc) "" value.ports;

            podStartOptionsList = lib.lists.optional (0 < builtins.length(value.ports)) "${portsString}" ++ 
                lib.lists.optional (isString (value.network)) "--net=${value.network}" ++ 
                value.extraArgs
            ;

            podStartOptions = concatMapStrings (x: " " + x) podStartOptionsList;
        in
            {
                Unit = {
                    Description="Podman ${mappedName}.service";
                    Documentation="man:podman-generate-systemd(1)";
                    RequiresMountsFor="/tmp/containers-user-${cfg.uid}/containers";
                    Wants=["network-online.target" "podman.socket"] ++ containers;
                    Before=containers;
                    After=["network-online.target" "podman.socket" "sops-nix.service"];
                };
                Service = {
                    Environment=[
                        "PATH=/bin:/sbin:/nix/var/nix/profiles/default/bin:/run/wrappers/bin"
                        "PODMAN_SYSTEMD_UNIT=%n"
                    ];
                    Restart="on-failure";
                    TimeoutStopSec="70";
                    ExecStartPre=''
                        ${pkgs.podman}/bin/podman pod create \
                            --infra-conmon-pidfile=%t/${mappedName}.pid \
                            --pod-id-file=%t/${mappedName}.pod-id \
                            --exit-policy=stop \
                            ${podStartOptions} ${mappedName}
                    '';
                    ExecStart=''
                        ${pkgs.podman}/bin/podman pod start \
                            --pod-id-file %t/${mappedName}.pod-id
                    '';
                    ExecStop=''
                        ${pkgs.podman}/bin/podman pod stop \
                            --ignore \
                            --pod-id-file %t/${mappedName}.pod-id  \
                            -t 10
                    '';
                    ExecStopPost=''
                        ${pkgs.podman}/bin/podman pod rm \
                            --ignore \
                            -f \
                            --pod-id-file %t/${mappedName}.pod-id
                    '';
                    PIDFile="%t/${mappedName}.pid";
                    Type="forking";
                };
                Install = {
                    WantedBy=["default.target"];
                };
            }
        );

    containerTemplate = name: value: mappedName: podName:(
        let
            inherit name;
            inherit value;

            mappedPodName = "podman_pod_${podName}";
            PodServiceName = "${mappedPodName}.service";

            volumesOptionString = foldl (entry: acc: entry+" -v"+acc) "" value.volumes;

            containerStartOptionsList = lib.lists.optional (0 < builtins.length(value.volumes)) "${volumesOptionString}" ++
                value.extraArgs
            ;
            containerStartOptions = concatMapStrings (x: " " + x) containerStartOptionsList;
            


            secretsSet =  foldl (acc: entry: acc++[{name=lib.last (builtins.split "/" entry); path=entry;}]) [] (builtins.attrNames value.sopsSecrets);
            ServiceExecStartPre = concatStringsSep "\\\n"
                (
                    concatMap (
                        x: [ "${pkgs.podman}/bin/podman secret exists ${x.name} || ${pkgs.podman}/bin/podman secret create ${x.name} ${config.sops.secrets.${x.path}.path};" ]
                    ) secretsSet
                );

            ServiceExecStartSecrets = concatStringsSep "\\\n" 
                (
                    attrsets.mapAttrsToList (
                        name: value: (
                            let
                                shortendName = lib.last (builtins.split "/" name);
                            in
                            assert !(value.type != "mount" && value.gid != null) || throw  "you can only use gid with the mount type. error in secret ${name}";
                            assert !(value.type != "mount" && value.uid != null) || throw  "you can only use uid with the mount type. error in secret ${name}";
                            assert !(value.type != "mount" && value.mode != null) || throw  "you can only use mode with the mount type. error in secret ${name}";

                            if (builtins.length (builtins.attrNames (lib.attrsets.filterAttrs (name: value: name != "type" && value != null) value))) == 0 then 
                                "--secret ${shortendName},type=env,target=${shortendName}"
                            else 
                                "--secret ${shortendName},type=${(value.type or ''env'')},target=${(value.target or shortendName)}"+
                                lib.strings.optionalString (value.gid != null) ",uid=${value.uid}"+
                                lib.strings.optionalString (value.gid != null) ",gid=${value.gid}"+
                                lib.strings.optionalString (value.gid != null) ",uid=${value.mode}"
                        )
                    ) value.sopsSecrets
                );

            ServiceExecStartEnvs = concatStringsSep "\\\n"
                (
                    attrValues (
                        lib.attrsets.concatMapAttrs (name: value: {${name}="--env ${name}=${value}";}) value.environment
                    )
                );

            ExecStopPostSecrets = concatStringsSep "\\\n"
                (
                    concatMap (
                        x: [ "${pkgs.podman}/bin/podman secret exists ${x.name} && ${pkgs.podman}/bin/podman secret rm ${x.name};" ]
                    ) secretsSet
                );
        in
        {
            Unit= {
                Description="Podman ${mappedName}.service";
                Documentation="man:podman-generate-systemd(1)";
                Wants=["network-online.target"];
                RequiresMountsFor="%t/containers";
                BindsTo=PodServiceName;
                After=["network-online.target" PodServiceName];
            };
            Service = {
                ExecStart=''
                    ${pkgs.podman}/bin/podman run \
                        --cidfile=%t/%n.ctr-id \
                        --cgroups=no-conmon \
                        --rm \
                        --pod-id-file %t/${mappedPodName}.pod-id \
                        --sdnotify=conmon \
                        --replace \
                        --detach \
                        ${containerStartOptions} \
                        ${ServiceExecStartSecrets} \
                        ${ServiceExecStartEnvs} \
                        --name ${podName}_${name} ${value.image}
                '';
                ExecStop=''
                    ${pkgs.podman}/bin/podman stop \
                        --ignore -t 10 \
                        --cidfile=%t/%n.ctr-id
                '';
                ExecStopPost=''
                    ${pkgs.bash}/bin/bash -c "${pkgs.podman}/bin/podman rm \
                        -f \
                        --ignore -t 10 \
                        --cidfile=%t/%n.ctr-id; \
                        ${ExecStopPostSecrets}"
                '';
                Environment=[
                    "PATH=/bin:/sbin:/nix/var/nix/profiles/default/bin:/run/wrappers/bin"
                    "PODMAN_SYSTEMD_UNIT=%n"
                ];
                Restart="on-failure";
                TimeoutStopSec="70";
                ExecStartPre=''${pkgs.bash}/bin/bash -c "''+ServiceExecStartPre+''"'';
                Type="notify";
                NotifyAccess="all";
            };
            Install = {
                WantedBy=["default.target"];
            };
        });
in
{
    options = {
        virtualisation.rootless-podman.uid = mkOption {
            type = with types; str;
        };
        virtualisation.rootless-podman.pods = mkOption {
            type = with types; attrsOf (types.submodule podOptions);
            default = {};
        };   
    };
    
    config = 
        let
            pods = mapAttrs' 
                (
                    name: value: 
                    let mappedName="podman_pod_${name}"; 
                    in nameValuePair mappedName (podTemplate name value mappedName)
                ) cfg.pods;

            podsContainers = mapAttrs
                (
                    podName: podValue:
                    (
                        mapAttrs'
                        (
                            containerName: containerValue:
                            let mappedName="podman_container_${podName}_${containerName}"; 
                            in nameValuePair mappedName (containerTemplate containerName containerValue mappedName podName)
                        ) podValue.containers
                    )
                ) cfg.pods;
            
            containers = builtins.zipAttrsWith (name: values: (lib.elemAt values 0)) (builtins.attrValues podsContainers);
        in
        {
            systemd.user.services = pods // containers;
        }
    ;
}