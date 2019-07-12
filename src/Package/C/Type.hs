{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}

module Package.C.Type ( CPkg (..)
                      , BuildVars (..)
                      , Verbosity (..)
                      , EnvVar (..)
                      , Command (..)
                      , Dep (..)
                      , Version (..)
                      , OS (..)
                      , TargetTriple (..)
                      -- * Helper functions
                      , cPkgDhallToCPkg
                      , showVersion
                      ) where

import           CPkgPrelude
import qualified Data.Text                as T
import           GHC.Generics             (Generic)
import qualified Package.C.Dhall.Type     as Dhall
import           Package.C.Triple.Type
import           Package.C.Type.Shared
import           Package.C.Type.Vars
import           Package.C.Type.Verbosity
import           Package.C.Type.Version

data EnvVar = EnvVar { var :: String, value :: String }
            deriving (Eq, Ord, Generic, Binary, Hashable)

data Command = CreateDirectory { dir :: String }
             | MakeExecutable { file :: String }
             | Call { program     :: String
                    , arguments   :: [String]
                    , environment :: Maybe [EnvVar]
                    , procDir     :: Maybe String
                    }
             | SymlinkBinary { file :: String }
             | SymlinkManpage { file :: String, section :: Int }
             | Symlink { tgt :: String, linkName :: String }
             | Write { contents :: T.Text, file :: FilePath }
             | CopyFile { src :: FilePath, dest :: FilePath }
             | Patch { patchContents :: T.Text }
             deriving (Eq, Ord, Generic, Binary, Hashable)

-- TODO: build script should take OS as an argument?
-- That way we can use make/gmake where we want it
data CPkg = CPkg { pkgName          :: String
                 , pkgVersion       :: Version
                 , pkgUrl           :: String
                 , pkgSubdir        :: String
                 , pkgStream        :: Bool -- ^ Use @tar@ package to stream
                 , pkgBuildDeps     :: [ Dep ]
                 , pkgDeps          :: [ Dep ]
                 , configureCommand :: BuildVars -> [ Command ]
                 , buildCommand     :: BuildVars -> [ Command ]
                 , installCommand   :: BuildVars -> [ Command ]
                 }

envVarDhallToEnvVar :: Dhall.EnvVar -> EnvVar
envVarDhallToEnvVar (Dhall.EnvVar ev x) = EnvVar (T.unpack ev) (T.unpack x)

commandDhallToCommand :: Dhall.Command -> Command
commandDhallToCommand (Dhall.CreateDirectory d)   = CreateDirectory (T.unpack d)
commandDhallToCommand (Dhall.MakeExecutable exe)  = MakeExecutable (T.unpack exe)
commandDhallToCommand (Dhall.Call p as env proc)  = Call (T.unpack p) (T.unpack <$> as) (fmap envVarDhallToEnvVar <$> env) (T.unpack <$> proc)
commandDhallToCommand (Dhall.SymlinkBinary b)     = SymlinkBinary (T.unpack b)
commandDhallToCommand (Dhall.SymlinkManpage b s)  = SymlinkManpage (T.unpack b) (fromIntegral s)
commandDhallToCommand (Dhall.Write out fp)        = Write out (T.unpack fp)
commandDhallToCommand (Dhall.CopyFile src' dest') = CopyFile (T.unpack src') (T.unpack dest')
commandDhallToCommand (Dhall.Symlink t l)         = Symlink (T.unpack t) (T.unpack l)
commandDhallToCommand (Dhall.Patch c)             = Patch c

buildVarsToDhallBuildVars :: BuildVars -> Dhall.BuildVars
buildVarsToDhallBuildVars (BuildVars dir' cd tgt' cross incls prelds shr lds bins os' arch' sta nproc) = Dhall.BuildVars (T.pack dir') (T.pack cd) tgt' cross (T.pack <$> incls) (T.pack <$> prelds) (T.pack <$> shr) (T.pack <$> lds) (T.pack <$> bins) os' arch' sta (fromIntegral nproc)

cPkgDhallToCPkg :: Dhall.CPkg -> CPkg
cPkgDhallToCPkg (Dhall.CPkg n v url subdir stream bldDeps deps cfgCmd buildCmd installCmd) =
    CPkg (T.unpack n) (Version v) (T.unpack url) (T.unpack subdir) stream bldDeps deps configure build install

    where configure cfg = commandDhallToCommand <$> cfgCmd (buildVarsToDhallBuildVars cfg)
          build cfg = commandDhallToCommand <$> buildCmd (buildVarsToDhallBuildVars cfg)
          install cfg = commandDhallToCommand <$> installCmd (buildVarsToDhallBuildVars cfg)
