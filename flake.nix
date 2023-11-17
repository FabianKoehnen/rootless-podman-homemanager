{
  outputs = _: {
    nixosModules.default = import "./default.nix";
  };
}

