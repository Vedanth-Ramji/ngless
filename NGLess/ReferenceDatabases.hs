{- Copyright 2013-2016 NGLess Authors
 - License: MIT
-}
module ReferenceDatabases
    ( Reference(..)
    , ReferenceFilePaths(..)
    , builtinReferences
    , createReferencePack
    , ensureDataPresent
    , installData
    ) where

import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BL
import qualified Codec.Archive.Tar as Tar
import qualified Codec.Compression.GZip as GZip
import           Control.Monad.Extra (whenJust)

import System.FilePath
import System.Directory
import System.IO.Error
import Data.Foldable
import Data.Maybe

import Control.Monad
import Control.Applicative ((<|>))
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Resource(release)

import qualified StandardModules.Mappers.Bwa as Bwa
import Network (downloadExpandTar, downloadOrCopyFile)
import FileManagement (createTempDir, InstallMode(..))
import NGLess.NGLEnvironment
import Configuration
import Utils.Utils
import Modules
import Output
import NGLess

data ReferenceFilePaths = ReferenceFilePaths
    { rfpFaFile :: Maybe FilePath
    , rfpGffFile :: Maybe FilePath
    , rfpFunctionalMap :: Maybe FilePath
    } deriving (Eq, Show)


dataDirectory Root = nConfGlobalDataDirectory <$> nglConfiguration
dataDirectory User = nConfUserDataDirectory   <$> nglConfiguration

builtinReferences :: [Reference]
builtinReferences = [Reference rn (T.concat [rn, "-0.0.0"]) Nothing True False | rn <-
                [ "hg19" -- Homo_sapiens
                , "mm10" -- Mus_musculus
                , "rn4" --  Rattus_norvegicus
                , "bosTau4" --  Bos_taurus
                , "canFam2" --Canis_familiaris
                , "dm3" --Drosophila_melanogaster
                , "ce10" --Caenorhabditis_elegans
                , "sacCer3" --Saccharomyces_cerevisiae
                ]]

isDefaultReference rn = isJust $ find ((==rn) . refName) builtinReferences

moduleDirectReference :: T.Text -> NGLessIO (Maybe ReferenceFilePaths)
moduleDirectReference rname = do
    mods <- loadedModules
    let refs = concatMap modReferences mods
    findM refs $ \case
        ExternalReference eref fafile gtffile mapfile
            | eref == rname -> return . Just $! ReferenceFilePaths (Just fafile) gtffile mapfile
        _ -> return Nothing

referencePath = "Sequence/BWAIndex/reference.fa.gz"
gffPath = "Annotation/annotation.gtf.gz"
functionalMapPath = "Annotation/functional.map.gz"

buildFaFilePath :: FilePath -> FilePath
buildFaFilePath = (</> referencePath)

buildGFFPath :: FilePath -> FilePath
buildGFFPath = (</> gffPath)

buildFunctionalMapPath :: FilePath -> FilePath
buildFunctionalMapPath = (</> functionalMapPath)


createReferencePack :: FilePath -> FilePath -> Maybe FilePath -> Maybe FilePath -> NGLessIO ()
createReferencePack oname reference mgtf mfunc = do
    (rk,tmpdir) <- createTempDir "ngless_ref_creator_"
    outputListLno' DebugOutput ["Working with temporary directory: ", tmpdir]
    liftIO $ do
        createDirectoryIfMissing True (tmpdir ++ "/Sequence/BWAIndex/")
        createDirectoryIfMissing True (tmpdir ++ "/Annotation/")
    downloadOrCopyFile reference (buildFaFilePath tmpdir)
    whenJust mgtf $ \gtf ->
        downloadOrCopyFile gtf (buildGFFPath tmpdir)
    whenJust mfunc $ \func ->
        downloadOrCopyFile func (buildFunctionalMapPath tmpdir)
    Bwa.createIndex (buildFaFilePath tmpdir)
    let referencefiles = [referencePath ++ ext |
                                    ext <- [""
                                        ,".amb"
                                        ,".ann"
                                        ,".bwt"
                                        ,".pac"
                                        ,".sa"]]
        filelist = referencefiles ++ [gffPath | isJust mgtf] ++ [functionalMapPath | isJust mfunc]
    liftIO $
        BL.writeFile oname . GZip.compress . Tar.write =<< Tar.pack tmpdir filelist
    outputListLno' ResultOutput ["Created reference package in file ", oname]
    release rk



-- | Make sure that the passed reference is present, downloading it if
-- necessary.
-- Returns the base path for the data.
ensureDataPresent :: T.Text -- ^ reference name (unversioned)
                        -> NGLessIO ReferenceFilePaths
ensureDataPresent rname = moduleDirectReference rname >>= \case
        Just r -> return r
        Nothing -> findDataFiles (T.unpack rname) >>= \case
            Just refdir -> wrapRefDir refdir
            Nothing -> wrapRefDir =<< installData Nothing rname
    where
        wrapRefDir refdir = return $! ReferenceFilePaths
                        (Just $ buildFaFilePath refdir)
                        (Just $ buildGFFPath refdir)
                        Nothing

-- | Installs reference data uncondictionally
-- When mode is Nothing, tries to install them in global directory, otherwise
-- installs it in the user directory
installData :: Maybe InstallMode -> T.Text -> NGLessIO FilePath
installData Nothing refname = do
    p' <- nConfGlobalDataDirectory <$> nglConfiguration
    canInstallGlobal <- liftIO $ do
        created <- (createDirectoryIfMissing False p' >> return True) `catchIOError` (\_ -> return False)
        if created
            then writable <$> getPermissions p'
            else return False
    if canInstallGlobal
        then installData (Just Root) refname
        else installData (Just User) refname
installData (Just mode) refname = do
    basedir <- dataDirectory mode
    mods <- loadedModules
    let unpackRef (ExternalPackagedReference r) = Just r
        unpackRef _ = Nothing
        refs = mapMaybe unpackRef $ concatMap modReferences mods
    ref  <- case find ((==refname) . refName) (refs ++ builtinReferences) of
        Just ref -> return ref
        Nothing -> throwScriptError ("Could not find reference '" ++ T.unpack refname ++ "'. It is not builtin nor in one of the loaded modules.")
    url <- case refUrl ref of
        Just u -> return u
        Nothing
            | isDefaultReference (refName ref) -> do
                    baseURL <- nConfDownloadBaseURL <$> nglConfiguration
                    return $ baseURL </> "References" </> T.unpack (refName ref) <.> "tar.gz"
            | otherwise ->
                throwScriptError ("Expected reference data, got "++T.unpack (refName ref))
    outputListLno' InfoOutput ["Starting download from ", url]
    let destdir = basedir </> "References" </> T.unpack refname
    downloadExpandTar url destdir
    outputLno' InfoOutput "Reference download completed!"
    return destdir



-- | checks first user and then global data directories for <ref>.
-- The user directory is checked first to allow the user to override a
-- problematic global installation.
findDataFiles :: FilePath -> NGLessIO (Maybe FilePath)
findDataFiles ref = liftM2 (<|>)
    (findDataFilesIn ref User)
    (findDataFilesIn ref Root)

findDataFilesIn :: FilePath -> InstallMode -> NGLessIO (Maybe FilePath)
findDataFilesIn ref mode = do
    basedir <- dataDirectory mode
    let refdir = basedir </> "References" </> ref
    hasIndex <- Bwa.hasValidIndex (buildFaFilePath refdir)
    outputListLno' TraceOutput ["Looked for ", ref, " in directory ", refdir, if hasIndex then " (and found it)" else " (and did not find it)"]
    return $! (if hasIndex
                then Just refdir
                else Nothing)

