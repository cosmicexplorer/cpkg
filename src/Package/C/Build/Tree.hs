module Package.C.Build.Tree ( buildByName
                            ) where

import           Control.Recursion
import           CPkgPrelude
import           Data.Containers.ListUtils (nubOrd)
import           Data.List                 (isInfixOf)
import           Package.C.Build
import           Package.C.Monad
import           Package.C.PackageSet
import           Package.C.Type
import           Package.C.Type.Tree
import           System.Directory          (doesDirectoryExist)
import           System.FilePath           ((</>))

data BuildDirs = BuildDirs { libraries :: [FilePath]
                           , share     :: [FilePath]
                           , include   :: [FilePath]
                           , binaries  :: [FilePath]
                           }

getAll :: [BuildDirs] -> BuildDirs
getAll bds =
    let go f = concat (f <$> bds)
    in BuildDirs (go libraries) (go share) (go include) (go binaries)

-- in order to prevent the "vanilla" libffi from preceding the *cross* libffi,
-- we filter out any directory that doesn't contain the target triple. this
-- causes further bugs and it's slow
--
-- Really we should allow *all* libdirs for Python/Perl here, since they won't
-- (hopefully) pollute the pkg-config path...
immoralFilter :: Maybe TargetTriple -> [FilePath] -> [FilePath]
immoralFilter Nothing fps = fps
immoralFilter (Just tgt') fps =
    let infixDir = show tgt'
    in filter (\fp -> infixDir `isInfixOf` fp || "meson" `isInfixOf` fp || "XML-Parser" `isInfixOf` fp || "python3" `isInfixOf` fp) fps -- FIXME: more principled approach

-- filter out stuff from the path
filterCross :: Maybe TargetTriple -> [FilePath] -> [FilePath]
filterCross Nothing = id
filterCross (Just tgt') =
    let infixDir = show tgt'
    in filter (\fp -> not (infixDir `isInfixOf` fp) || "ncurses" `isInfixOf` fp)

buildWithContext :: DepTree CPkg
                 -> Maybe TargetTriple
                 -> Bool -- ^ Should we build static libraries?
                 -> Bool -- ^ Install globally
                 -> PkgM ()
buildWithContext cTree host sta glob = zygoM' dirAlg buildAlg cTree

    where buildAlg :: DepTreeF CPkg (BuildDirs, ()) -> PkgM ()
          buildAlg (DepNodeF c usr preBds) =
            buildCPkg c host sta glob usr ds (immoralFilter host ls) is (filterCross host bs)
                where (BuildDirs ls ds is bs) = getAll (fst <$> preBds)
          buildAlg (BldDepNodeF c preBds) =
            buildCPkg c Nothing False False False ds ls is bs -- don't use static libraries for build dependencies
            -- also don't install them globally
            -- build dependencies are not manual!
                where (BuildDirs ls ds is bs) = getAll (fst <$> preBds)

          mkBuildDirs :: MonadIO m => FilePath -> BuildDirs -> m BuildDirs
          mkBuildDirs pkgDir (BuildDirs ls ds is bs) = do
            let linkDir = pkgDir </> "lib"
                linkDir64 = pkgDir </> "lib64"
                includeDir = pkgDir </> "include"
                dataDir = pkgDir </> "share"
                binDir = pkgDir </> "bin"
                links = linkDir64 : linkDir : ls
                bins = binDir : bs
                shares = dataDir : ds

            -- TODO: do this for all of them?
            includeExists <- liftIO (doesDirectoryExist includeDir)
            let includes = if includeExists
                then includeDir : is
                else is

            pure (BuildDirs (nubOrd links) (nubOrd shares) (nubOrd includes) (nubOrd bins))

          dirAlg :: DepTreeF CPkg BuildDirs -> PkgM BuildDirs
          dirAlg (DepNodeF c _ bds) = do

            let bldDirs@(BuildDirs ls ds is bs) = getAll bds

            buildVars <- getVars host sta ds (immoralFilter host ls) is (filterCross host bs)

            pkgDir <- cPkgToDir c host glob buildVars

            mkBuildDirs pkgDir bldDirs

          dirAlg (BldDepNodeF c bds) = do

            let bldDirs@(BuildDirs ls ds is bs) = getAll bds

            buildVars <- getVars Nothing False ds ls is bs

            pkgDir <- cPkgToDir c Nothing False buildVars

            mkBuildDirs pkgDir bldDirs

-- TODO: should this parse a string into a TargetTriple instead?
buildByName :: PackId -> Maybe TargetTriple -> Maybe String -> Bool -> Bool -> PkgM ()
buildByName pkId host pkSet sta glob = do
    allPkgs <- liftIO (pkgsM pkId pkSet)
    buildWithContext allPkgs host sta glob
