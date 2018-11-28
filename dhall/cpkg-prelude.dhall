let concatMapSep = https://raw.githubusercontent.com/dhall-lang/dhall-lang/master/Prelude/Text/concatMapSep
in

let types = https://raw.githubusercontent.com/vmchale/cpkg/master/dhall/cpkg-types.dhall
in

let showVersion =
  λ(x : List Natural) → concatMapSep "." Natural Natural/show x
in

let mkTarget =
  λ(x : Optional Text) →
    Optional/fold Text x Text (λ(tgt : Text) → " --target=${tgt}") ""
in

let makeExe =
  λ(os : types.OS) →

    let gmake = λ(_ : {}) → "gmake"
    in
    let make  = λ(_ : {}) → "make"
    in

    merge
      { FreeBSD   = gmake
      , OpenBSD   = gmake
      , NetBSD    = gmake
      , Solaris   = gmake
      , Dragonfly = gmake
      , Linux     = make
      , Darwin    = make
      , Windows   = make
      }
      os
in

let defaultConfigure =
  λ(cfg : types.ConfigureVars) →
    [ "./configure --prefix=${cfg.installDir}" ++ mkTarget cfg.targetTriple ]
in

let defaultBuild =
  λ(cfg : types.BuildVars) →
    [ "${makeExe cfg.buildOS} -j${Natural/show cfg.cpus}"]
in

let defaultInstall =
  λ(os : types.OS) →
    [ "${makeExe os} install" ]
in

let unbounded =
  λ(x : Text) →
    { name = x
    , bound = types.VersionBound.NoBound
    }
in

let defaultPackage =
  { configureCommand = defaultConfigure
  , executableFiles  = [ "configure" ]
  , buildCommand     = defaultBuild
  , installCommand   = defaultInstall
  , pkgBuildDeps     = [] : List types.Dep
  , pkgDeps          = [] : List types.Dep
  }
in

let makeGnuPackage =
  λ(pkg : { name : Text, version : List Natural}) →
    defaultPackage ⫽
      { pkgName = pkg.name
      , pkgVersion = pkg.version
      , pkgUrl = "https://mirrors.ocf.berkeley.edu/gnu/lib${pkg.name}/lib${pkg.name}-${showVersion pkg.version}.tar.xz"
      , pkgSubdir = "lib${pkg.name}-${showVersion pkg.version}"
      }
in

{ showVersion    = showVersion
, makeGnuPackage = makeGnuPackage
, defaultPackage = defaultPackage
, unbounded      = unbounded
, makeExe        = makeExe
}
