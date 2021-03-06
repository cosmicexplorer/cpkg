{-# LANGUAGE FlexibleContexts #-}

module Package.C.Db.GarbageCollect ( cleanSymlinks
                                   , cleanCache
                                   , garbageCollect
                                   ) where

import           Control.Monad.Reader  (MonadReader)
import           CPkgPrelude
import qualified Data.Set              as S
import qualified Data.Text             as T
import           Package.C.Db.Memory   (globalPkgDir)
import           Package.C.Db.Monad    (MonadDb)
import           Package.C.Db.Register
import           Package.C.Db.Type
import           Package.C.Logging     (putDiagnostic)
import           Package.C.Type        (TargetTriple, Verbosity)
import           System.Directory      (doesDirectoryExist, doesFileExist, getSymbolicLinkTarget, listDirectory, removeDirectoryRecursive, removeFile)
import           System.FilePath       ((</>))

getTransitiveDepsByName :: (MonadIO m, MonadDb m) => String -> Maybe TargetTriple -> m (S.Set BuildCfg)
getTransitiveDepsByName = getTransitiveDeps <=*< lookupOrFail

garbageCollect :: (MonadIO m, MonadDb m, MonadReader Verbosity m)
               => m ()
garbageCollect = garbageCollectPkgs *> cleanSymlinks

-- TODO: garbage collect old packages as well, and things which are broken b/c
-- their dependencies are gone
--
-- | @since 0.2.3.0
garbageCollectPkgs :: (MonadIO m, MonadDb m, MonadReader Verbosity m)
                   => m ()
garbageCollectPkgs = do
    allPkgs <- installedDb
    let manuals = (toList . S.filter manual) allPkgs
    putDiagnostic ("Manually installed packages: " ++ show (buildName <$> manuals))
    allDeps <- S.unions <$> traverse getTransitiveDeps manuals
    let redundant = allPkgs S.\\ allDeps
    putDiagnostic ("Redundant packages: " ++ show (buildName <$> toList redundant))
    traverse_ uninstallPkg redundant

getTransitiveDeps :: (MonadIO m, MonadDb m) => BuildCfg -> m (S.Set BuildCfg)
getTransitiveDeps cfg = do
    let names = fst <$> pinnedDeps cfg
        host = targetArch cfg
    next <- traverse (\n -> getTransitiveDepsByName n host) (T.unpack <$> names)
    pure $ S.insert cfg (S.unions next)

-- | @since 0.2.3.0
cleanCache :: MonadIO m => m ()
cleanCache = liftIO $ do
    ccDir <- (</> "cache") <$> globalPkgDir
    exists <- doesDirectoryExist ccDir
    when exists $
        removeDirectoryRecursive ccDir

cleanSymlinks :: (MonadReader Verbosity m, MonadIO m) => m ()
cleanSymlinks = do
    pkDir <- liftIO globalPkgDir
    let binDir = pkDir </> "bin"
        manDir = pkDir </> "share" </> "man"
        man1Dir = manDir </> "man1"
        man3Dir = manDir </> "man3"
    traverse_ cleanDir
        [binDir, man1Dir, man3Dir]


cleanDir :: (MonadReader Verbosity m, MonadIO m) => FilePath -> m ()
cleanDir dir = do
    exists <- liftIO $ doesDirectoryExist dir
    when exists $ do
        links <- liftIO $ listDirectory dir
        forM_ links $ \link -> do
            let linkAbs = dir </> link
            brk <- liftIO $ isBroken linkAbs
            when brk $
                putDiagnostic ("Removing link " ++ linkAbs ++ "...") *>
                liftIO (removeFile linkAbs)

isBroken :: FilePath -> IO Bool
isBroken = (fmap not . doesFileExist) <=< getSymbolicLinkTarget

-- getSymbolicLinkTarget
