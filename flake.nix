{
  outputs = _: {
    homeManagerModules.default = import ./default.nix;
  };
}

