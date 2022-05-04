let
 release = import ./release.nix;
 pkgs = release.pkgs;

in pkgs.mkShell {

  name = "nglessEnv";

  nativeBuildInputs = [
    release.NGLess.components.exes.ngless
    pkgs.prodigal
    pkgs.samtools
    pkgs.megahit
    pkgs.python3 # required for megahit (dependency should be upstreamed)
    pkgs.minimap2
    pkgs.bwa

    pkgs.xz
    pkgs.which
    pkgs.zstd
  ];

}
