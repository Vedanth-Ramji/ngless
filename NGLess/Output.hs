{- Copyright 2013-2021 NGLess Authors
 - License: MIT
 -}
{-# LANGUAGE TemplateHaskell, RecordWildCards, CPP, FlexibleContexts #-}

module Output
    ( OutputType(..)
    , MappingInfo(..)
    , AutoComment(..)
    , buildComment
    , commentC
    , outputListLno
    , outputListLno'
    , outputFQStatistics
    , outputMappedSetStatistics
    , writeOutputJSImages
    , writeOutputTSV
    , outputConfiguration
    ) where

import           Text.Printf (printf)
import           System.IO (hIsTerminalDevice, stdout)
import           System.IO.Unsafe (unsafePerformIO)
import           System.IO.SafeWrite (withOutputFile)
import           Data.Maybe (maybeToList, fromMaybe, isJust)
import           Data.IORef (IORef, newIORef, modifyIORef, readIORef)
import           Data.List (sort)
import           Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import           System.FilePath ((</>))
import           Data.Aeson.TH (deriveToJSON, defaultOptions, Options(..))
import           Data.Time (getZonedTime, ZonedTime(..))
import           Data.Time.Format (formatTime, defaultTimeLocale)
import qualified System.Console.ANSI as ANSI
import           Control.Monad
import           Control.Monad.IO.Class (liftIO)
import           Control.Monad.Extra (whenJust)
import           Numeric (showFFloat)
import           Control.Arrow (first)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Conduit as C
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.ByteString.Lazy as BL

import qualified Diagrams.Backend.SVG as D
import qualified Diagrams.TwoD.Size as D
import qualified Diagrams.Prelude as D
import           Diagrams.Prelude ((#), (^&), (|||))

import           System.Environment (lookupEnv)


import           Data.FastQ (FastQEncoding(..), encodingName)
import qualified Data.FastQ as FQ
import Configuration
import CmdArgs (Verbosity(..))
import NGLess.NGLEnvironment
import NGLess.NGError

data AutoComment = AutoScript | AutoDate | AutoResultHash
                        deriving (Eq, Show)


buildComment :: Maybe T.Text -> [AutoComment] -> T.Text -> NGLessIO [T.Text]
buildComment c ac rh = do
        ac' <- mapM buildAutoComment ac
        return $ maybeToList c ++ concat ac'
    where
        buildAutoComment :: AutoComment -> NGLessIO [T.Text]
        buildAutoComment AutoDate = liftIO $ do
            t <- formatTime defaultTimeLocale "%a %d-%m-%Y %R" <$> getZonedTime
            return . (:[]) $ T.concat ["Script run on ", T.pack t]
        buildAutoComment AutoScript = (("Output generated by:":) . map addInitialIndent . T.lines . ngleScriptText) <$> nglEnvironment
        buildAutoComment AutoResultHash = return [T.concat ["Output hash: ", rh]]
        addInitialIndent t = T.concat ["    ", t]

-- Output a comment as a conduit
commentC :: Monad m => B.ByteString -> [T.Text] -> C.ConduitT () B.ByteString m ()
commentC cmarker cs = forM_ cs $ \c -> do
                                C.yield cmarker
                                C.yield (TE.encodeUtf8 c)
                                C.yield "\n"


data OutputType = TraceOutput | DebugOutput | InfoOutput | ResultOutput | WarningOutput | ErrorOutput
    deriving (Eq, Ord)

instance Show OutputType where
    show TraceOutput = "trace"
    show DebugOutput = "debug"
    show InfoOutput = "info"
    show ResultOutput = "result"
    show WarningOutput = "warning"
    show ErrorOutput = "error"

data OutputLine = OutputLine !Int !OutputType !ZonedTime !String

instance Aeson.ToJSON OutputLine where
    toJSON (OutputLine lno ot t m) = Aeson.object
                                        ["lno" .= lno
                                        , "time" .=  formatTime defaultTimeLocale "%a %d-%m-%Y %T" t
                                        , "otype" .= show ot
                                        , "message" .= m
                                        ]


data BPosInfo = BPosInfo
                    { _mean :: !Int
                    , _median :: !Int
                    , _lowerQuartile :: !Int
                    , _upperQuartile :: !Int
                    } deriving (Show)
$(deriveToJSON defaultOptions{fieldLabelModifier = drop 1} ''BPosInfo)

data FQInfo = FQInfo
                { fileName :: String
                , scriptLno :: !Int
                , gcContent :: !Double
                , nonATCGFrac :: !Double
                , encoding :: !String
                , numSeqs :: !Int
                , numBasepairs :: !Integer
                , seqLength :: !(Int,Int)
                , perBaseQ :: [BPosInfo]
                } deriving (Show)

$(deriveToJSON defaultOptions ''FQInfo)

data MappingInfo = MappingInfo
                { mi_lno :: Int
                , mi_inputFile :: FilePath
                , mi_reference :: String
                , mi_totalReads :: !Int
                , mi_totalAligned :: !Int
                , mi_totalUnique :: !Int
                } deriving (Show)

$(deriveToJSON defaultOptions{fieldLabelModifier = drop 3} ''MappingInfo)

data SavedOutput = SavedOutput
        { outOutput :: [OutputLine]
        , fqOutput :: [FQInfo]
        , mapOutput :: [MappingInfo]
        }

savedOutput :: IORef SavedOutput
{-# NOINLINE savedOutput #-}
savedOutput = unsafePerformIO (newIORef (SavedOutput [] [] []))

addOutputLine :: OutputLine -> SavedOutput -> SavedOutput
addOutputLine !oline so@(SavedOutput ells _ _) = so { outOutput = oline:ells }

addFQOutput !fq so@(SavedOutput _ fqs _) = so { fqOutput = fq:fqs }
addMapOutput !mp so@(SavedOutput _ _ maps) = so { mapOutput = mp:maps }

outputReverse (SavedOutput a b c) = SavedOutput (reverse a) (reverse b) (reverse c)

-- | See `outputListLno'`, which is often the right function to use
outputListLno :: OutputType      -- ^ Level at which to output
                    -> Maybe Int -- ^ Line number (in script). Use 'Nothing' for global messages
                    -> [String]
                    -> NGLessIO ()
outputListLno ot lno ms = output ot (fromMaybe 0 lno) (concat ms)

-- | Output a message using the global line number.
-- This function takes a list as it is often a more convenient interface
outputListLno' :: OutputType      -- ^ Level at which to output
                    -> [String]   -- ^ output. Will be 'concat' together (without any spaces or similar in between)
                    -> NGLessIO ()
outputListLno' !ot ms = do
    lno <- ngleLno <$> nglEnvironment
    outputListLno ot lno ms

shouldPrint :: Bool -- ^ is terminal
                -> OutputType
                -> Verbosity
                -> Bool
shouldPrint _ TraceOutput _ = False
shouldPrint _      _ Loud = True
shouldPrint False ot Quiet = ot == ErrorOutput
shouldPrint False ot Normal = ot > InfoOutput
shouldPrint True  ot Quiet = ot >= WarningOutput
shouldPrint True  ot Normal = ot >= InfoOutput

output :: OutputType -> Int -> String -> NGLessIO ()
output !ot !lno !msg = do
    isTerm <- liftIO $ hIsTerminalDevice stdout
    hasNOCOLOR <- isJust <$> liftIO (lookupEnv "NO_COLOR")
    verb <- nConfVerbosity <$> nglConfiguration
    traceSet <- nConfTrace <$> nglConfiguration
    colorOpt <- nConfColor <$> nglConfiguration
    let sp = traceSet || shouldPrint isTerm ot verb
        doColor = case colorOpt of
            ForceColor -> True
            NoColor -> False
            AutoColor -> isTerm && not hasNOCOLOR
    c <- colorFor ot
    liftIO $ do
        t <- getZonedTime
        modifyIORef savedOutput (addOutputLine $ OutputLine lno ot t msg)
        when sp $ do
            let st = if doColor
                        then ANSI.setSGRCode [ANSI.SetColor ANSI.Foreground ANSI.Dull c]
                        else ""
                rst = if doColor
                        then ANSI.setSGRCode [ANSI.Reset]
                        else ""
                tformat = if traceSet -- when trace is set, output seconds
                                then "%a %d-%m-%Y %T"
                                else "%a %d-%m-%Y %R"
                tstr = formatTime defaultTimeLocale tformat t
                lineStr = if lno > 0
                                then printf " Line %s" (show lno)
                                else "" :: String
            putStrLn $ printf "%s[%s]%s: %s%s" st tstr lineStr msg rst

colorFor :: OutputType -> NGLessIO ANSI.Color
colorFor = return . colorFor'
    where
        colorFor' TraceOutput   = ANSI.White
        colorFor' DebugOutput   = ANSI.White
        colorFor' InfoOutput    = ANSI.Blue
        colorFor' ResultOutput  = ANSI.Black
        colorFor' WarningOutput = ANSI.Yellow
        colorFor' ErrorOutput   = ANSI.Red


encodeBPStats :: FQ.FQStatistics -> [BPosInfo]
encodeBPStats res = map encode1 (FQ.qualityPercentiles res)
    where encode1 (mean, median, lq, uq) = BPosInfo mean median lq uq

outputFQStatistics :: FilePath -> FQ.FQStatistics -> FastQEncoding -> NGLessIO ()
outputFQStatistics fname stats enc = do
    lno' <- ngleLno <$> nglEnvironment
    let enc'    = encodingName enc
        sSize'  = FQ.seqSize stats
        nSeq'   = FQ.nSeq stats
        gc'     = FQ.gcFraction stats
        nATGC   = FQ.nonATCGFrac stats
        st      = encodeBPStats stats
        lno     = fromMaybe 0 lno'
        nbps    = FQ.nBasepairs stats
        binfo   = FQInfo fname lno gc' nATGC enc' nSeq' nbps sSize' st
    let p s0 s1  = outputListLno' DebugOutput [s0, s1]
    p "Simple Statistics completed for: " fname
    p "Number of base pairs: "      (show $ length (FQ.qualCounts stats))
    p "Encoding is: "               (show enc)
    p "Number of sequences: "   (show $ FQ.nSeq stats)
    liftIO $ modifyIORef savedOutput (addFQOutput binfo)

outputMappedSetStatistics :: MappingInfo -> NGLessIO ()
outputMappedSetStatistics mi@(MappingInfo _ _ ref total aligned unique) = do
        lno <- ngleLno <$> nglEnvironment
        let out = outputListLno' ResultOutput
        out ["Mapped readset stats (", ref, "):"]
        out ["Total reads: ", show total]
        out ["Total reads aligned: ", showNumAndPercentage aligned]
        out ["Total reads Unique map: ", showNumAndPercentage unique]
        out ["Total reads Non-Unique map: ", showNumAndPercentage (aligned - unique)]
        liftIO $ modifyIORef savedOutput (addMapOutput $ mi { mi_lno = fromMaybe 0 lno })
    where
        showNumAndPercentage :: Int -> String
        showNumAndPercentage v = concat [show v, " [", showFFloat (Just 2) ((fromIntegral (100*v) / fromIntegral total') :: Double) "", "%]"]
        total' = if total /= 0 then total else 1


data InfoLink = HasQCInfo !Int
                | HasStatsInfo !Int
    deriving (Eq, Show)
instance Aeson.ToJSON InfoLink where
    toJSON (HasQCInfo lno) = Aeson.object
                                [ "info_type" .= ("has_QCInfo" :: String)
                                , "lno" .= show lno
                                ]
    toJSON (HasStatsInfo lno) = Aeson.object
                                [ "info_type" .= ("has_StatsInfo" :: String)
                                , "lno" .= show lno
                                ]

data ScriptInfo = ScriptInfo String String [(Maybe InfoLink,T.Text)] deriving (Show, Eq)
instance Aeson.ToJSON ScriptInfo where
   toJSON (ScriptInfo a b c) = Aeson.object [ "name" .= a,
                                            "time" .= b,
                                            "script" .= Aeson.toJSON c ]

wrapScript :: [(Int, T.Text)] -> [FQInfo] -> [Int] -> [(Maybe InfoLink, T.Text)]
wrapScript script tags stats = first annotate <$> script
    where
        annotate i
            | i `elem` (scriptLno <$> tags) = Just (HasQCInfo i)
            | i `elem` stats = Just (HasStatsInfo i)
            | otherwise =  Nothing

writeOutputJSImages :: FilePath -> FilePath -> T.Text -> NGLessIO ()
writeOutputJSImages odir scriptName script = liftIO $ do
    SavedOutput fullOutput fqStats mapStats <- outputReverse <$> readIORef savedOutput
    fqfiles <- forM (zip [(0::Int)..] fqStats) $ \(ix, q) -> do
        let oname = "output"++show ix++".svg"
            bpos = perBaseQ q
        drawBaseQs (odir </> oname) bpos
        return oname
    t <- getZonedTime
    let script' = zip [1..] (T.lines script)
        sInfo = ScriptInfo (odir </> "output.js") (show t) (wrapScript script' fqStats (mi_lno <$> mapStats))
    withOutputFile (odir </> "output.js") $ \hout ->
        BL.hPutStr hout (BL.concat
                    ["var output = "
                    , Aeson.encode $ Aeson.object
                        [ "output" .= fullOutput
                        , "processed" .= sInfo
                        , "fqStats" .= fqStats
                        , "mapStats" .= mapStats
                        , "scriptName" .= scriptName
                        , "plots" .= fqfiles
                        ]
                    ,";\n"])


-- | Writes QC stats to the given filepaths.
writeOutputTSV :: Bool -- ^ whether to transpose matrix
                -> Maybe FilePath -- ^ FastQ statistics
                -> Maybe FilePath -- ^ Mapping statistics
                -> NGLessIO ()
writeOutputTSV transpose fqStatsFp mapStatsFp = liftIO $ do
        SavedOutput _ fqStats mapStats <- outputReverse <$> readIORef savedOutput
        whenJust fqStatsFp $ \fp ->
            withOutputFile fp $ \hout ->
                BL.hPut hout  . formatTSV $ encodeFQStats <$> fqStats
        whenJust mapStatsFp $ \fp ->
            withOutputFile fp $ \hout ->
                BL.hPutStr hout . formatTSV $ encodeMapStats <$> mapStats
    where
        formatTSV :: [[(BL.ByteString, String)]] -> BL.ByteString
        formatTSV [] = BL.empty
        formatTSV contents@(h:_)
            | transpose = BL.concat ("\tstats\n":(formatTSV1 <$> zip [0..] contents))
            | otherwise = BL.concat [BL8.intercalate "\t" (fst <$> h), "\n",
                                    BL8.intercalate "\n" (asTSVline . fmap snd <$> contents), "\n"]
        formatTSV1 :: (Int, [(BL.ByteString, String)]) -> BL.ByteString
        formatTSV1 (i, contents) = BL.concat [BL8.concat [BL8.concat [BL8.pack . show $ i, ":", h], "\t", BL8.pack c, "\n"]
                                                                        | (h, c) <- contents]
        asTSVline = BL8.intercalate "\t" . map BL8.pack

        encodeFQStats FQInfo{..} = sort
                            [ ("file", fileName)
                            , ("encoding", encoding)
                            , ("numSeqs", show numSeqs)
                            , ("numBasepairs", show numBasepairs)
                            , ("minSeqLen", show (fst seqLength))
                            , ("maxSeqLen", show (snd seqLength))
                            , ("gcContent", show gcContent)
                            , ("nonATCGFraction", show nonATCGFrac)
                            ]
        encodeMapStats MappingInfo{..} = sort
                [ ("inputFile", mi_inputFile)
                , ("lineNumber", show mi_lno)
                , ("reference", mi_reference)
                , ("total", show mi_totalReads)
                , ("aligned", show mi_totalAligned)
                , ("unique", show mi_totalUnique)
                ]

outputConfiguration :: NGLessIO ()
outputConfiguration = do
    cfg <- ngleConfiguration <$> nglEnvironment
    outputListLno' DebugOutput ["# Configuration"]
    outputListLno' DebugOutput ["\tdownload base URL: ", nConfDownloadBaseURL cfg]
    outputListLno' DebugOutput ["\tglobal data directory: ", nConfGlobalDataDirectory cfg]
    outputListLno' DebugOutput ["\tuser directory: ", nConfUserDirectory cfg]
    outputListLno' DebugOutput ["\tuser data directory: ", nConfUserDataDirectory cfg]
    outputListLno' DebugOutput ["\ttemporary directory: ", nConfTemporaryDirectory cfg]
    outputListLno' DebugOutput ["\tkeep temporary files: ", show $ nConfKeepTemporaryFiles cfg]
    outputListLno' DebugOutput ["\tcreate report: ", show $ nConfCreateReportDirectory cfg]
    outputListLno' DebugOutput ["\treport directory: ", nConfReportDirectory cfg]
    outputListLno' DebugOutput ["\tcolor setting: ", show $ nConfColor cfg]
    outputListLno' DebugOutput ["\tprint header: ",  show $ nConfPrintHeader cfg]
    outputListLno' DebugOutput ["\tsubsample: ", show $ nConfSubsample cfg]
    outputListLno' DebugOutput ["\tverbosity: ", show $ nConfVerbosity cfg]
    forM_ (nConfIndexStorePath cfg) $ \p ->
        outputListLno' DebugOutput ["\tindex storage path: ", p]
    outputListLno' DebugOutput ["\tsearch path:"]
    forM_ (nConfSearchPath cfg) $ \p ->
        outputListLno' DebugOutput ["\t\t", p]


type Diagram = D.QDiagram D.SVG D.V2 Double D.Any
-- Draw a chart of the base qualities
--
-- The code is very empirical in magic numbers
drawBaseQs :: FilePath -> [BPosInfo] -> IO ()
drawBaseQs oname bpos = D.renderSVG oname (D.mkSizeSpec2D (Just (1200.0 :: Double)) (Just 800.0)) $
        D.padX 1.2 $ D.padY 1.1 $ D.centerXY $
        chart ||| D.strutX 0.04 ||| legend
    where
        datalines = [
            ("Mean" ,  style1, meanValues),
            ("Median", style2, medianValues),
            ("Upper Quartile", style3, uqValues),
            ("Lower Quartile", style4, lqValues)
            ]

        lenBP = length bpos
        chart = mconcat [plot st d | (_, st, d) <- datalines]
                    <> horizticks <> vertticks
                    <> text' "Basepair position" # D.moveTo (0.5 ^& (-0.07))
                    <> text' "Quality score" # D.rotate (90 D.@@ D.deg) # D.moveTo ((-0.1) ^& (0.5))

        plot :: (D.Path D.V2 Double, Diagram -> Diagram) -> [(Double, Double)] -> Diagram
        plot (shape, style) ps = let
                        ps' = D.p2 <$> ps
                     in style (D.strokeP $ D.fromVertices ps') `D.atop` D.strokeP (mconcat [ shape D.# D.moveTo p | p <- ps' ])
        horizticks :: Diagram
        horizticks =
            let
                ticks = (takeWhile (< lenBP) [0, 25..]) ++ [lenBP]
                pairs = [(fromIntegral tk * tickspace, show tk) | tk <- ticks]
                tickspace :: Double
                tickspace = 1.0 / fromIntegral lenBP

                textBits = mconcat     [ text' t # D.moveTo ((x)^&(-0.04)) | (x,t) <- pairs ]
                tickBits =    mconcat  [ D.fromVertices [ (x) ^& 0, (x) ^& 0.1     ] | (x,_) <- pairs ]
                            <> mconcat [ D.fromVertices [ (x) ^& h, (x) ^& (h-0.1) ] | (x,_) <- pairs ]
                            <> mconcat [ D.fromVertices [ (x) ^& 0, (x) ^& h       ] # dashedLine | (x,_) <- pairs ]
            in textBits <> tickBits

        h = 1.0
        w = 1.0

        dashedLine = D.lc D.gray . D.dashing [ 0.3, 0.3] 0
        vertticks :: Diagram
        vertticks =
            let
                pairs = [(0.0,  "0"),
                         (0.25, "10"),
                         (0.50, "20"),
                         (0.75, "30"),
                         (1.00, "40")]
                textBits = mconcat [ text' t # D.alignR # D.moveTo   ((-0.04) ^&  y) | (y,t) <- pairs ]
                tickBits = mconcat     [ D.fromVertices [ 0 ^& y,     0.1 ^& y ] | (y,_) <- pairs ]
                            <> mconcat [ D.fromVertices [ w ^& y, (w-0.1) ^& y ] | (y,_) <- pairs ]
                            <> mconcat [ D.fromVertices [ 0 ^& y,       w ^& y ] # dashedLine | (y,_) <- pairs ]
            in textBits <> tickBits


        legend = D.translateY 0.8 $
                    D.vcat' D.with {D._sep=0.1} $
                        [littleLine s ||| D.strutX 0.2 ||| text' label # D.alignL
                            | (label, s, _) <- datalines]
            where
                littleLine :: (D.Path D.V2 Double, Diagram -> Diagram) -> Diagram
                littleLine (shape, st) = st (D.strokeP $ D.fromVertices [ D.p2 (0, 0), D.p2 (0.2, 0) ]) <> (D.strokeP shape # D.moveTo (D.p2 (0.1, 0)))
        text' :: String -> Diagram
        text' s = D.text s # D.fc D.black # D.lw D.none # D.fontSizeL 0.03


        [meanValues, medianValues, uqValues, lqValues] = map rescale [_mean, _median, _upperQuartile, _lowerQuartile]

        rescale :: (BPosInfo -> Int) -> [(Double, Double)]
        rescale sel = [(rescale1 1 (toInteger lenBP) x, rescale1 0 40 y) | (x,y) <- zip [1..] values]
            where
                values = map (toInteger . sel) bpos
                rescale1 :: Integer -> Integer -> Integer -> Double
                rescale1 m0 m1 x = let
                                   m0' = fromInteger m0
                                   s = fromInteger (m1 - m0)
                                   x' = fromInteger x
                               in (x'-m0')/s

        style1 = (D.circle   0.01, D.lc D.red)
        style2 = (D.square   0.01, D.lc D.green)
        style3 = (D.pentagon 0.01, D.lc D.blue)
        style4 = (D.star (D.StarSkip 2) (D.pentagon 0.01), D.lc D.brown)

