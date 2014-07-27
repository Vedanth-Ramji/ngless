{-# LANGUAGE TemplateHaskell, OverloadedStrings, TupleSections #-}
-- Unit tests are their own programme.

module Main where

-- Import basic functionality and our own modules


import Test.Framework.TH
import Test.HUnit
import Test.Framework.Providers.HUnit
import Test.Framework.Providers.QuickCheck2
import Control.Applicative
import Text.Parsec (parse)
import Text.Parsec.Combinator (eof)
import Text.ParserCombinators.Parsec.Prim (GenParser)
import Text.Parsec (SourcePos)
import Text.Parsec.Pos (newPos)

import System.Directory(removeFile)

import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy.Char8 as L

import qualified Data.Text as T
import Data.Aeson

import qualified Data.IntervalMap.Strict as IM
import qualified Data.IntervalMap.Interval as IM

import Language
import Interpret
import Parse
import Tokens
import Types
import PrintFastqBasicStats
import PerBaseQualityScores
import Substrim
import FastQFileData
import FileManagement
import Validation
import CountOperation
import Annotation

import Data.Sam
import Data.Json
import Data.AnnotRes
import qualified Data.GFF as GFF


-- The main test driver is automatically generated
main = $(defaultMainGenerator)

-- Test Parsing Module
parseText :: GenParser (SourcePos,Token) () a -> T.Text -> a
parseText p t = fromRight . parse p "test" . _cleanupindents . fromRight . tokenize "test" $ t
fromRight (Right r) = r
fromRight (Left e) = error (concat ["Unexpected Left: ",show e])
parseBody = map snd . parseText _nglbody
parsetest = parsengless "test"

case_parse_symbol = parseBody "{symbol}" @?= [ConstSymbol "symbol"]
case_parse_fastq = parseBody fastqcalls @?= fastqcall
    where
        fastqcalls = "fastq(\"input.fq\")"
        fastqcall  = [FunctionCall Ffastq (ConstStr "input.fq") [] Nothing]

case_parse_count = parseBody countcalls @?= countcall
    where
        countcalls = "count(annotated, count={gene})"
        countcall  = [FunctionCall Fcount (Lookup (Variable "annotated")) [(Variable "count",ConstSymbol "gene")] Nothing]

case_parse_count_mult_counts = parseBody countcalls @?= countcall
    where
        countcalls = "count(annotated, count=[{gene},{cds}])"
        countcall  = [FunctionCall Fcount (Lookup (Variable "annotated")) [(Variable "count", ListExpression [ConstSymbol "gene", ConstSymbol "cds"])] Nothing]

case_parse_assignment =  parseBody "reads = \"something\"" @?=
        [Assignment (Variable "reads") (ConstStr "something")]

case_parse_sequence = parseBody seqs @?= seqr
    where
        seqs = "reads = 'something'\nreads = 'something'"
        seqr = [a,a]
        a    = Assignment (Variable "reads") (ConstStr "something")

case_parse_num = parseBody nums @?= num
    where
        nums = "a = 0x10"
        num  = [Assignment (Variable "a") (ConstNum 16)]

case_parse_bool = parseBody bools @?= bool
    where
        bools = "a = true"
        bool  = [Assignment (Variable "a") (ConstBool True)]

case_parse_if_else = parseBody blocks @?= block
    where
        blocks = "if true:\n 0\n 1\nelse:\n 2\n"
        block  = [Condition (ConstBool True) (Sequence [ConstNum 0,ConstNum 1]) (Sequence [ConstNum 2])]

case_parse_if = parseBody blocks @?= block
    where
        blocks = "if true:\n 0\n 1\n"
        block  = [Condition (ConstBool True) (Sequence [ConstNum 0,ConstNum 1]) (Sequence [])]

case_parse_if_end = parseBody blocks @?= block
    where
        blocks = "if true:\n 0\n 1\n2\n"
        block  = [Condition (ConstBool True) (Sequence [ConstNum 0,ConstNum 1]) (Sequence []),ConstNum 2]

case_parse_ngless = parsengless "test" ngs @?= Right ng
    where
        ngs = "ngless '0.0'\n"
        ng  = Script "0.0" []

case_parse_list = parseText _listexpr "[a,b]" @?= ListExpression [Lookup (Variable "a"), Lookup (Variable "b")]

case_parse_indexexpr_11 = parseText _indexexpr "read[1:1]" @?= IndexExpression (Lookup (Variable "read")) (IndexTwo j1 j1)
case_parse_indexexpr_10 = parseText _indexexpr "read[1:]"  @?= IndexExpression (Lookup (Variable "read")) (IndexTwo j1 Nothing)
case_parse_indexexpr_01 = parseText _indexexpr "read[:1]"  @?= IndexExpression (Lookup (Variable "read")) (IndexTwo Nothing j1)
case_parse_indexexpr_00 = parseText _indexexpr "read[:]"   @?= IndexExpression (Lookup (Variable "read")) (IndexTwo Nothing Nothing)

case_parse_indexexprone_1 = parseText _indexexpr "read[1]" @?= IndexExpression (Lookup (Variable "read")) (IndexOne (ConstNum 1))
case_parse_indexexprone_2 = parseText _indexexpr "read[2]" @?= IndexExpression (Lookup (Variable "read")) (IndexOne (ConstNum 2))
case_parse_indexexprone_var = parseText _indexexpr "read[var]" @?= IndexExpression (Lookup (Variable "read")) (IndexOne (Lookup (Variable "var")))

case_parse_cleanupindents_0 = tokcleanupindents [TIndent 1] @?= []
case_parse_cleanupindents_1 = tokcleanupindents [TNewLine] @?= [TNewLine]
case_parse_cleanupindents_2 = tokcleanupindents [TIndent 1,TNewLine] @?= [TNewLine]
case_parse_cleanupindents_3 = tokcleanupindents [TOperator '(',TNewLine,TIndent 2,TOperator ')'] @?= [TOperator '(',TOperator ')']

case_parse_cleanupindents_4 = tokcleanupindents toks @?= toks'
    where
        toks  = [TWord "write",TOperator '(',TWord "A",TOperator ',',TNewLine,TIndent 16,TNewLine,TIndent 16,TWord "format",TOperator '=',TExpr (ConstSymbol "csv"),TOperator ')',TNewLine]
        toks' = [TWord "write",TOperator '(',TWord "A",TOperator ','                                        ,TWord "format",TOperator '=',TExpr (ConstSymbol "csv"),TOperator ')',TNewLine]
case_parse_cleanupindents_4' = tokcleanupindents toks @?= toks'
    where
        toks  = [TOperator '(',TOperator ',',TNewLine,TIndent 16,TNewLine,TIndent 16,TOperator ')',TNewLine]
        toks' = [TOperator '(',TOperator ','                                        ,TOperator ')',TNewLine]
case_parse_cleanupindents_4'' = tokcleanupindents toks @?= toks'
    where
        toks  = [TOperator '(',TNewLine,TIndent 16,TNewLine,TIndent 16,TOperator ')',TNewLine]
        toks' = [TOperator '('                                        ,TOperator ')',TNewLine]

j1 = Just (ConstNum 1)
tokcleanupindents = map snd . _cleanupindents . map (newPos "test" 0 0,)

case_parse_kwargs = parseBody "unique(reads,maxCopies=2)\n" @?= [FunctionCall Funique (Lookup (Variable "reads")) [(Variable "maxCopies", ConstNum 2)] Nothing]

-- Test Tokens module
tokenize' fn t = map snd <$> (tokenize fn t)

case_tok_cr = TNewLine @=? (case parse (_eol <* eof) "test" "\r\n" of { Right t -> t; Left _ -> error "Parse failed"; })
case_tok_single_line_comment = tokenize' "test" with_comment @?= Right expected
    where
        with_comment = "a=0# comment\nb=1\n"
        expected = [TWord "a",TOperator '=',TExpr (ConstNum 0),TNewLine,TWord "b",TOperator '=',TExpr (ConstNum 1),TNewLine]

case_tok_single_line_comment_cstyle = tokenize' "test" with_comment @?= Right expected
    where
        with_comment = "a=0// comment\nb=1\n"
        expected = [TWord "a",TOperator '=',TExpr (ConstNum 0),TNewLine,TWord "b",TOperator '=',TExpr (ConstNum 1),TNewLine]

case_tok_multi_line_comment = tokenize' "test" with_comment @?= Right expected
    where
        with_comment = "a=0/* This\n\nwith\nlines*/\nb=1\n"
        expected = [TWord "a",TOperator '=',TExpr (ConstNum 0),TIndent 0,TNewLine,TWord "b",TOperator '=',TExpr (ConstNum 1),TNewLine]

case_tok_word_ = tokenize' "test" "word_with_underscore" @?= Right expected
    where
        expected = [TWord "word_with_underscore"]



-- Test Encoding
case_calculateEncoding_sanger = calculateEncoding 55 @?= Encoding "Sanger / Illumina 1.9" sanger_encoding_offset
case_calculateEncoding_illumina_1 = calculateEncoding 65 @?= Encoding "Illumina 1.3" illumina_encoding_offset
case_calculateEncoding_illumina_1_5 = calculateEncoding 100 @?= Encoding "Illumina 1.5" illumina_encoding_offset

--Test the calculation of the Mean
case_calc_simple_mean = calcMean (500 :: Int) (10 :: Int) @?= (50 :: Double) 

--- SETUP to reduce imports.
-- test array: "\n\v\f{zo\n\v\NUL" -> [10,11,12,123,122,111,10,11,0]
-- test cutoff: chr 20 -> '\DC4'

--Property 1: For every s, the size must be allways smaller than the input
prop_substrim_maxsize s = st >= 0 && e <= B.length (B.pack s)
    where (st,e) = calculateSubStrim (B.pack s) '\DC4'

-- Property 2: substrim should be idempotent
prop_substrim_idempotent s = st == 0 && e == B.length s1
    where
        s1 = removeBps (B.pack s) (calculateSubStrim (B.pack s) '\DC4')
        (st,e) = calculateSubStrim s1 '\DC4'
                        
case_substrim_normal_exec =  calculateSubStrim "\n\v\f{zo\n\v\NUL" '\DC4' @?= (3,3)
case_substrim_empty_quals = calculateSubStrim "" '\DC4' @?= (0,0)

-- Test Types
isError (Right _) = assertFailure "error not caught"
isError (Left _) = return ()

isOk m (Left _) = assertFailure m
isOk _ (Right _) = return ()
isOkTypes = isOk "Type error on good code"

case_bad_type_fastq = isError $ checktypes (Script "0.0" [(0,FunctionCall Ffastq (ConstNum 3) [] Nothing)])
case_good_type_fastq = isOkTypes $ checktypes (Script "0.0" [(0,FunctionCall Ffastq (ConstStr "fastq.fq") [] Nothing)])

case_type_complete = isOkTypes $ (parsetest complete) >>= checktypes

complete = "ngless '0.0'\n\
    \reads = fastq('input1.fq')\n\
    \reads = unique(reads,maxCopies=2)\n\
    \preprocess(reads) using |read|:\n\
    \    read = read[5:]\n\
    \    read = substrim(read, minQuality=24)\n\
    \    if len(read) < 30:\n\
    \        discard\n"

case_indent_comment = isOk "ParseFailed" $ parsetest indent_comment
case_indent_space = isOk "ParseFailed" $ parsetest indent_space

indent_comment = "ngless '0.0'\n\
    \reads = fastq('input1.fq')\n\
    \preprocess(reads) using |read|:\n\
    \    read = read[5:]\n\
    \    # comment \n"

indent_space  = "ngless '0.0'\n\
    \reads = fastq('input1.fq')\n\
    \preprocess(reads) using |read|:\n\
    \    read = read[5:]\n\
    \    \n"

case_indent_empty_line = isOkTypes $ parsetest indent_empty_line >>= checktypes
    where indent_empty_line  = "ngless '0.0'\n\
            \reads = fastq('input1.fq')\n\
            \preprocess(reads) using |read|:\n\
            \    read = read[5:]\n\
            \    \n\
            \    if len(read) < 24:\n\
            \        discard\n"

-----
--- Validation pure functions

case_bad_function_attr_count = isError $ parsetest function_attr >>= validate
    where function_attr = "ngless '0.0'\n\
            \count(annotated, count={gene})\n"

case_good_function_attr_count_1 = isOkTypes $ parsetest good_function_attr >>= validate
    where good_function_attr = "ngless '0.0'\n\
            \write(count(annotated, count={gene}),ofile='gene_counts.csv',format={csv})"

case_good_function_attr_count_2 = isOkTypes $ parsetest good_function_attr >>= validate
    where good_function_attr = "ngless '0.0'\n\
            \counts = count(annotated, count={gene})"

case_bad_function_attr_map = isError $ parsetest function_attr >>= validate
    where function_attr = "ngless '0.0'\n\
            \map(input,reference='sacCer3')\n"

case_good_function_attr_map_1 = isOkTypes $ parsetest good_function_attr >>= validate
    where good_function_attr = "ngless '0.0'\n\
            \write(map(input,reference='sacCer3'),ofile='result.sam',format={sam})"

case_good_function_attr_map_2 = isOkTypes $ parsetest good_function_attr >>= validate
    where good_function_attr = "ngless '0.0'\n\
            \counts = map(input,reference='sacCer3')"


-- Type Validate pre process operations

case_pre_process_indexation_1 = evalIndex (NGOShortRead "@IRIS" "AGTACCAA" "aa`aaaaa") [Just (NGOInteger 5), Nothing] @?= (NGOShortRead "@IRIS" "CAA" "aaa")
case_pre_process_indexation_2 = evalIndex (NGOShortRead "@IRIS" "AGTACCAA" "aa`aaaaa") [Nothing, Just (NGOInteger 3)] @?= (NGOShortRead "@IRIS" "AGT" "aa`")
case_pre_process_indexation_3 = evalIndex (NGOShortRead "@IRIS" "AGTACCAA" "aa`aaaaa") [Just (NGOInteger 2), Just (NGOInteger 5)] @?= (NGOShortRead "@IRIS" "TAC" "`aa")

case_pre_process_length_1 = evalLen (NGOShortRead "@IRIS" "AGTACCAA" "aa`aaaaa") @?= (NGOInteger 8)

case_bop_gte_1 = evalBinary BOpGTE (NGOInteger 10) (NGOInteger 10) @?= (NGOBool True)
case_bop_gte_2 = evalBinary BOpGTE (NGOInteger 11) (NGOInteger 10) @?= (NGOBool True)
case_bop_gte_3 = evalBinary BOpGTE (NGOInteger 10) (NGOInteger 11) @?= (NGOBool False)

case_bop_gt_1 = evalBinary BOpGT (NGOInteger 10) (NGOInteger 10) @?= (NGOBool False)
case_bop_gt_2 = evalBinary BOpGT (NGOInteger 11) (NGOInteger 10) @?= (NGOBool True)
case_bop_gt_3 = evalBinary BOpGT (NGOInteger 10) (NGOInteger 11) @?= (NGOBool False)

case_bop_lt_1 = evalBinary BOpLT (NGOInteger 10) (NGOInteger 10) @?= (NGOBool False)
case_bop_lt_2 = evalBinary BOpLT (NGOInteger 11) (NGOInteger 10) @?= (NGOBool False)
case_bop_lt_3 = evalBinary BOpLT (NGOInteger 10) (NGOInteger 11) @?= (NGOBool True)

case_bop_lte_1 = evalBinary BOpLTE (NGOInteger 10) (NGOInteger 10) @?= (NGOBool True)
case_bop_lte_2 = evalBinary BOpLTE (NGOInteger 11) (NGOInteger 10) @?= (NGOBool False)
case_bop_lte_3 = evalBinary BOpLTE (NGOInteger 10) (NGOInteger 11) @?= (NGOBool True)

case_bop_eq_1 = evalBinary BOpEQ (NGOInteger 10) (NGOInteger 10) @?= (NGOBool True)
case_bop_eq_2 = evalBinary BOpEQ (NGOInteger 10) (NGOInteger 0) @?= (NGOBool False)

case_bop_neq_1 = evalBinary BOpNEQ (NGOInteger 0) (NGOInteger 10) @?= (NGOBool True)
case_bop_neq_2 = evalBinary BOpNEQ (NGOInteger 10) (NGOInteger 10) @?= (NGOBool False)

case_bop_add_1 = evalBinary BOpAdd (NGOInteger 0) (NGOInteger 10) @?= (NGOInteger 10)
case_bop_add_2 = evalBinary BOpAdd (NGOInteger 10) (NGOInteger 0) @?= (NGOInteger 10)
case_bop_add_3 = evalBinary BOpAdd (NGOInteger 10) (NGOInteger 10) @?= (NGOInteger 20)

case_bop_mul_1 = evalBinary BOpMul (NGOInteger 0) (NGOInteger 10) @?= (NGOInteger 0)
case_bop_mul_2 = evalBinary BOpMul (NGOInteger 10) (NGOInteger 0) @?= (NGOInteger 0)
case_bop_mul_3 = evalBinary BOpMul (NGOInteger 10) (NGOInteger 10) @?= (NGOInteger 100)

case_uop_minus_1 = evalMinus (NGOInteger 10) @?= (NGOInteger (-10))
case_uop_minus_2 = evalMinus (NGOInteger (-10)) @?= (NGOInteger 10)

--

case_files_in_dir = do
    x <- getFilesInDir "docs"
    length x @?= 5

case_template_id = template "a/B/c/d/xpto_1.fq" @?= template "a/B/c/d/xpto_1.fq"
case_template    = template "a/B/c/d/xpto_1.fq" @?= "xpto_1"

case_parse_filename = parseFileName "/var/folders/sample_1.9168$afterQC" @?= ("/var/folders/","sample_1")

case_temp_fp      = assertNotEqual (getTempFilePath "xpto") (getTempFilePath "xpto")
case_temp_fp_comp = assertNotEqual (getTFilePathComp "xpto") (getTFilePathComp "xpto")

assertNotEqual a b = do
    a' <- a 
    b' <- b
    mapM_ removeFile [a', b'] -- a' and b' creates a file, this line removes it.
    assertBool "a' and b' should be different" (a' /= b')

case_dir_contain_formats = doesDirContainFormats "NGLess/Tests" [".hs"] >>= assertBool "doesDirContainFormats \"NGLess/Tests\" [\".hs\"]" 

-- Json Operations

case_basicInfoJson = basicInfoToJson "x1" 1.0 "x2" 2 (3,4) @?= (encode $ BasicInfo "x1" 1.0 "x2" 2 (3,4))


-- should be the same
case_createFileProcessed = do
    x <- createFilesProcessed "test" "script"
    y <- createFilesProcessed "test" "script"
    x @?= y

-- Sam operations

case_isAligned_sam = isAligned (SamLine ud 16 ud 0 0 ud ud 0 0 ud ud) @? "Should be aligned"
case_isAligned_raw = isAligned (head . readAlignments $ r) @? "Should be aligned"
    where
        r = "SRR070372.3\t16\tV\t7198336\t21\t26M3D9M3D6M6D8M2D21M\t*\t0\t0\tCCCTTATGCAGGTCTTAACACAATTCTTGTATGTTCCATCGTTCTCCAGAATGAATATCAATGATACCAA\t014<<BBBBDDFFFDDDDFHHFFD?@??DBBBB5555::?=BBBBDDF@BBFHHHHHHHFFFFFD@@@@@\tNM:i:14\tMD:Z:26^TTT9^TTC6^TTTTTT8^AA21\tAS:i:3\tXS:i:0"

case_isNotAligned = (not $ isAligned (SamLine ud 4 ud 0 0 ud ud 0 0 ud ud)) @? "Should not be aligned"

case_isUnique = isUnique (SamLine ud 16 ud 0 10 ud ud 0 0 ud ud) @? "Should be unique"
case_isNotUnique = (not $ isUnique (SamLine ud 4 ud 0 0 ud ud 0 0 ud ud)) @? "Should not be unique"
ud = undefined

case_read_one_Sam_Line = readAlignments samLineFlat @?= [samLine]
case_read_mul_Sam_Line = readAlignments (L.unlines $ replicate 10 samLineFlat) @?= replicate 10 samLine

samLineFlat = "IRIS:7:3:1046:1723#0\t4\t*\t0\t0\t*\t*\t0\t0\tAAAAAAAAAAAAAAAAAAAAAAA\taaaaaaaaaaaaaaaaaa`aa`^\tAS:i:0  XS:i:0"
samLine = SamLine {samQName = "IRIS:7:3:1046:1723#0", samFlag = 4, samRName = "*", samPos = 0, samMapq = 0, samCigar = "*", samRNext = "*", samPNext = 0, samTLen = 0, samSeq = "AAAAAAAAAAAAAAAAAAAAAAA", samQual = "aaaaaaaaaaaaaaaaaa`aa`^"}   


-- Tests with scripts (This will pass to a shell script)

--preprocess_s = "ngless '0.0'\n\
--    \input = fastq('samples/sample.fq')\n\
--    \preprocess(input) using |read|:\n\
--    \   read = read[3:]\n\
--    \   read = read[: len(read) ]\n\
--    \   read = substrim(read, min_quality=5)\n\
--    \   if len(read) > 20:\n\
--    \       continue\n\
--    \   if len(read) <= 20:\n\
--    \       discard\n\
--    \write(input, ofile='samples/resultSampleFiltered.txt')\n"


--map_s = "ngless '0.0'\n\
--    \input = fastq('samples/sample.fq')\n\
--    \preprocess(input) using |read|:\n\
--    \    if len(read) < 20:\n\
--    \        discard\n\
--    \mapped = map(input,reference='sacCer3')\n\
--    \write(mapped, ofile='samples/resultSampleSam.sam',format={sam})\n"

--case_preprocess_script = case parsetest preprocess_s >>= checktypes of
--        Left err -> T.putStrLn err
--        Right expr -> do
--            _ <- defaultDir >>= createDirIfExists  -- this is the dir where everything will be kept.
--            (interpret preprocess_s) . nglBody $ expr
--            res' <- B.readFile "samples/resultSampleFiltered.txt"
--            (length $ B.lines res') @?= (16 :: Int)

--case_map_script = case parsetest map_s >>= checktypes of
--        Left err -> T.putStrLn err
--        Right expr -> do
--            _ <- defaultDir >>= createDirIfExists  -- this is the dir where everything will be kept.
--            (interpret map_s) . nglBody $ expr
--            res' <- unCompress "samples/resultSampleSam.sam"
--            calcSamStats res' @?= [5,0,0,0]

-- Test compute stats

case_compute_stats_lc = do
    contents <- unCompress "samples/resultSampleFiltered.txt"
    (lc $ computeStats contents) @?= 'X'

-- Parse GFF lines

gff_line = "chrI\tunknown\texon\t4124\t4358\t.\t-\t.\tgene_id \"Y74C9A.3\"; transcript_id \"NM_058260\"; gene_name \"Y74C9A.3\"; p_id \"P23728\"; tss_id \"TSS14501\";"
gff_structure = GFF.GffLine "chrI" "unknown" GFF.GffExon 4124 4358 Nothing GFF.GffNegStrand (-1) "gene_id \"Y74C9A.3\"; transcript_id \"NM_058260\"; gene_name \"Y74C9A.3\"; p_id \"P23728\"; tss_id \"TSS14501\";"

case_check_attr_tag_1 = GFF.checkAttrTag "id = 10;" @?= '='
case_check_attr_tag_2 = GFF.checkAttrTag "id 10;" @?= ' '

case_trim_attrs_1  = GFF.trimString " x = 10" @?= "x = 10"
case_trim_attrs_2  = GFF.trimString " x = 10 " @?= "x = 10"
case_trim_attrs_3  = GFF.trimString "x = 10 " @?= "x = 10"
case_trim_attrs_4  = GFF.trimString "x = 10" @?= "x = 10"


case_parse_gff_line = GFF.readLine gff_line @?= gff_structure
case_parse_gff_atributes = (GFF.parseGffAttributes (GFF.gffAttributes gff_structure)) @?= [("gene_id","Y74C9A.3"), ("transcript_id" ,"NM_058260"), ("gene_name", "Y74C9A.3"), ("p_id", "P23728"), ("tss_id", "TSS14501")]

-- teste parseGffAttributes
case_parse_gff_atributes_normal_1 = GFF.parseGffAttributes "ID=chrI;dbxref=NCBI:NC_001133;Name=chrI" @?= [("ID","chrI"),("dbxref","NCBI:NC_001133"),("Name","chrI")]
case_parse_gff_atributes_normal_2 = GFF.parseGffAttributes "gene_id=chrI;dbxref=NCBI:NC_001133;Name=chrI" @?= [("gene_id","chrI"),("dbxref","NCBI:NC_001133"),("Name","chrI")]
case_parse_gff_atributes_trail_del = GFF.parseGffAttributes "gene_id=chrI;dbxref=NCBI:NC_001133;Name=chrI;" @?= [("gene_id","chrI"),("dbxref","NCBI:NC_001133"),("Name","chrI")]
case_parse_gff_atributes_trail_del_space = GFF.parseGffAttributes "gene_id=chrI;dbxref=NCBI:NC_001133;Name=chrI; " @?= [("gene_id","chrI"),("dbxref","NCBI:NC_001133"),("Name","chrI")]

-- Setup

gff_structure_Exon = GFF.GffLine "chrI" "unknown" GFF.GffExon 4124 4358 Nothing GFF.GffNegStrand (-1) "gene_id \"Y74C9A.3\"; transcript_id \"NM_058260\"; gene_name \"Y74C9A.3\"; p_id \"P23728\"; tss_id \"TSS14501\";"
gff_structure_CDS = GFF.GffLine "chrI" "unknown" GFF.GffCDS 4124 4358 Nothing GFF.GffNegStrand (-1) "gene_id \"Y74C9A.3\"; transcript_id \"NM_058260\"; gene_name \"Y74C9A.3\"; p_id \"P23728\"; tss_id \"TSS14501\";"
gff_structure_Gene = GFF.GffLine "chrI" "unknown" GFF.GffGene 4124 4358 Nothing GFF.GffNegStrand (-1) "gene_id \"Y74C9A.3\"; transcript_id \"NM_058260\"; gene_name \"Y74C9A.3\"; p_id \"P23728\"; tss_id \"TSS14501\";"


gff_features_all = Just (NGOList  [ NGOSymbol "gene", NGOSymbol "cds", NGOSymbol "exon"])
gff_features_gene = Just (NGOList [ NGOSymbol "gene"])
gff_features_cds = Just (NGOList  [ NGOSymbol "cds" ])

gff_lines_ex = [gff_structure_Exon,gff_structure_CDS,gff_structure_Gene]

----

case_filter_features_1 = filter (GFF.filterFeatures gff_features_all) gff_lines_ex @?= gff_lines_ex
case_filter_features_2 = filter (GFF.filterFeatures Nothing) gff_lines_ex @?= gff_lines_ex
case_filter_features_3 = filter (GFF.filterFeatures gff_features_gene) gff_lines_ex @?= [gff_structure_Gene]
case_filter_features_4 = filter (GFF.filterFeatures gff_features_cds) gff_lines_ex @?= [gff_structure_CDS]
case_filter_features_5 = filter (GFF.filterFeatures gff_features_cds) [gff_structure_Exon,gff_structure_Exon,gff_structure_Gene] @?= []


case_cigar_to_length_1 = cigarTLen "18M2D19M" @?= 39
case_cigar_to_length_2 = cigarTLen "37M" @?= 37
case_cigar_to_length_3 = cigarTLen "3M1I3M1D5M" @?= 12

--- Count operation

ds_annot_gene = "x\tgene\t10\t+\n"
ds_annot_cds = "x\tCDS\t11\t+\n"
ds_annot_exon = "x\texon\t12\t+\n"
ds_annot_counts = L.concat [ds_annot_gene, ds_annot_cds, ds_annot_exon]

annot_features_gene = Just (NGOList  [ NGOSymbol "gene" ])
annot_features_cds =  Just (NGOList  [ NGOSymbol "cds"  ])
annot_features_exon = Just (NGOList  [ NGOSymbol "exon" ])

annot_features_gene_cds = Just (NGOList  [ NGOSymbol "gene", NGOSymbol "cds" ])
annot_features_cds_exon = Just (NGOList  [ NGOSymbol "exon", NGOSymbol "cds" ])

annot_features_all =  Just (NGOList  [ NGOSymbol "gene", NGOSymbol "cds", NGOSymbol "exon" ])


case_annot_count_none = filterAnnot ds_annot_counts Nothing (NGOInteger 0) @?= readAnnotCounts ds_annot_counts
case_annot_count_all = filterAnnot ds_annot_counts annot_features_all (NGOInteger 0) @?= readAnnotCounts ds_annot_counts

-- simple case. Filter all but one element
case_annot_count_gene = filterAnnot ds_annot_counts annot_features_gene (NGOInteger 0) @?= readAnnotCounts ds_annot_gene
case_annot_count_cds = filterAnnot ds_annot_counts annot_features_cds (NGOInteger 0) @?= readAnnotCounts ds_annot_cds
case_annot_count_exon = filterAnnot ds_annot_counts annot_features_exon (NGOInteger 0) @?= readAnnotCounts ds_annot_exon

-- empty case
case_annot_count_other_empty = filterAnnot ds_annot_counts (Just (NGOList  [ NGOSymbol "other" ])) (NGOInteger 0) @?= []

-- Filter all but one element
case_annot_count_gene_cds = filterAnnot ds_annot_counts annot_features_gene_cds (NGOInteger 0) @?= (readAnnotCounts $ L.concat [ds_annot_gene, ds_annot_cds])
case_annot_count_cds_exon = filterAnnot ds_annot_counts annot_features_cds_exon (NGOInteger 0) @?= (readAnnotCounts $ L.concat [ds_annot_cds, ds_annot_exon])


-- Min value of occurrences to count operation
case_annot_count_lim_no_feat = filterAnnot ds_annot_counts Nothing (NGOInteger 30) @?= []
case_annot_count_lim_feat = filterAnnot ds_annot_counts annot_features_all (NGOInteger 30) @?= []


-- interval mode 
--case_annot_interval_none = getIntervalQuery Nothing == IM.intersecting
case_interval_map_subsumes_1 = IM.subsumes (IM.ClosedInterval (1 :: Integer) 5) (IM.ClosedInterval 3 6) @?= False
case_interval_map_subsumes_2 = IM.subsumes (IM.ClosedInterval (1 :: Integer) 5) (IM.ClosedInterval 3 5) @?= True
case_interval_map_subsumes_4 = IM.subsumes (IM.ClosedInterval (3 :: Integer) 5) (IM.ClosedInterval 1 500) @?= False
case_interval_map_subsumes_3 = IM.subsumes (IM.ClosedInterval (1 :: Integer) 500) (IM.ClosedInterval 3 5) @?= True


case_interval_map_overlaps_1 = IM.overlaps  (IM.ClosedInterval (1 :: Integer) 5) (IM.ClosedInterval 6 7) @?= False
case_interval_map_overlaps_2 = IM.overlaps  (IM.ClosedInterval (3 :: Integer) 6) (IM.ClosedInterval 1 5) @?= True
case_interval_map_overlaps_3 = IM.overlaps  (IM.ClosedInterval (300 :: Integer) 400) (IM.ClosedInterval 200 300) @?= True


--case_interval_query_Nothing_true = (getIntervalQuery Nothing) (IM.ClosedInterval 1 5) (IM.ClosedInterval 3 6)
--                                    @?= IM.overlaps (IM.ClosedInterval (1 :: Integer) 5) (IM.ClosedInterval 3 6)

--case_interval_query_intersect_true = (getIntervalQuery (Just $ NGOString "intersect")) (IM.ClosedInterval 1 5) (IM.ClosedInterval 3 6)
--                                    @?= IM.overlaps (IM.ClosedInterval (1 :: Integer) 5) (IM.ClosedInterval 3 6)

--case_interval_query_within_false = (getIntervalQuery (Just $ NGOString "within")) (IM.ClosedInterval 1 5) (IM.ClosedInterval 3 6)
--                                    @?= IM.subsumes (IM.ClosedInterval (1 :: Integer) 5) (IM.ClosedInterval 3 6)


--case_interval_query_within_true = (getIntervalQuery (Just $ NGOString "within")) (IM.ClosedInterval 1 500) (IM.ClosedInterval 200 300)
--                                    @?= IM.subsumes (IM.ClosedInterval (1 :: Integer) 500) (IM.ClosedInterval 200 300)



case_not_InsideInterval_1 = isInsideInterval 0 (IM.ClosedInterval 1 5) @?= False
case_not_InsideInterval_2 = isInsideInterval 6 (IM.ClosedInterval 1 5) @?= False

case_isInsideInterval_1 = isInsideInterval 3 (IM.ClosedInterval 1 5) @?= True
case_isInsideInterval_2 = isInsideInterval 1 (IM.ClosedInterval 1 5) @?= True
case_isInsideInterval_3 = isInsideInterval 5 (IM.ClosedInterval 3 5) @?= True


k1 = (IM.ClosedInterval 10 20, head $ readAnnotCounts "x\tgene\t10\t+\n")
k2 = (IM.ClosedInterval 1 5,   head $ readAnnotCounts "y\tgene\t10\t+\n")
k3 = (IM.ClosedInterval 30 30, head $ readAnnotCounts "x\tgene\t20\t+\n")

imap1   = IM.fromList [k1]
imap2   = IM.fromList [k2]
imapAll = IM.fromList [k1, k2]

imap1Dup   = IM.fromList [k2, k2] -- same pair
imap2Dup   = IM.fromList [k1, k3] -- same pair
imap3Dup   = IM.fromList [k1, k3, k1] -- same id

-- union
case_union_empty       = union [IM.empty, IM.empty] @?= IM.empty
case_union_one_empty_1 = union [imapAll, IM.empty]   @?= imapAll
case_union_one_empty_2 = union [IM.empty, imapAll]   @?= imapAll

case_union_same  = union [imapAll, imapAll] @?= imapAll
case_union_dif   = union [imap1, imap2]     @?= imapAll

-- intersection_strict
case_intersection_strict_empty       = intersection_strict [IM.empty, IM.empty] @?= IM.empty
case_intersection_strict_one_empty_1 = intersection_strict [imapAll, IM.empty]   @?= IM.empty
case_intersection_strict_one_empty_2 = intersection_strict [IM.empty, imapAll]   @?= IM.empty

case_intersection_strict_dif      = intersection_strict [imap1, imap2] @?= IM.empty
case_intersection_strict_normal_1 = intersection_strict [imap1, imapAll] @?= imap1
case_intersection_strict_normal_2 = intersection_strict [imapAll, imap1] @?= imap1
case_intersection_strict_same     = intersection_strict [imapAll, imapAll] @?= imapAll

-- intersection_non_empty
case_intersection_nonempty_empty   = intersection_non_empty [IM.empty, IM.empty] @?= IM.empty
case_intersection_nonempty_empty_1 = intersection_non_empty [imapAll, IM.empty]   @?= imapAll
case_intersection_nonempty_empty_2 = intersection_non_empty [IM.empty, imapAll]   @?= imapAll

case_intersection_nonempty_dif      = intersection_non_empty [imap1, imap2] @?= IM.empty
case_intersection_nonempty_normal_1 = intersection_non_empty [imap1, imapAll] @?= imap1
case_intersection_nonempty_normal_2 = intersection_non_empty [imapAll, imap1] @?= imap1
case_intersection_nonempty_same     = intersection_non_empty [imapAll, imapAll] @?= imapAll


case_size_no_dup_normal = sizeNoDup imapAll @?= 2
case_size_no_dup_empty  = sizeNoDup IM.empty @?= 0

case_size_no_dup_duplicate_1 = sizeNoDup imap1Dup @?= 1
case_size_no_dup_duplicate_2 = sizeNoDup imap2Dup @?= 1
case_size_no_dup_duplicate_3 = sizeNoDup imap3Dup @?= 1


-----


