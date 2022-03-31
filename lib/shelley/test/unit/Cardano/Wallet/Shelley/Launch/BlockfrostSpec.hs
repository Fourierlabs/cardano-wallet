module Cardano.Wallet.Shelley.Launch.BlockfrostSpec
  ( spec,
  )
where

import qualified Blockfrost.Client.Types as Blockfrost
import Blockfrost.Env
  ( Env (Testnet),
  )
import Cardano.Wallet.Shelley.Launch
  ( Mode (Light, Normal),
    modeOption,
  )
import Cardano.Wallet.Shelley.Launch.Blockfrost
  ( readToken,
  )
import qualified Data.Text as T
import Options.Applicative
  ( ParserFailure (execFailure),
    ParserResult (CompletionInvoked, Failure, Success),
    defaultPrefs,
    execParserPure,
    fullDesc,
    info,
  )
import Test.Hspec
  ( Spec,
    describe,
    expectationFailure,
    it,
    shouldBe,
    shouldReturn,
  )
import Test.Utils.Platform
  ( isWindows,
  )
import UnliftIO
  ( withSystemTempFile,
  )
import UnliftIO.IO
  ( hClose,
  )
import Prelude

spec :: Spec
spec = describe "Blockfrost CLI options" $ do
  it "modeOption --node-socket" $ do
    let parserInfo = info modeOption fullDesc
        args = ["--node-socket", mockSocketOrPipe]
    case execParserPure defaultPrefs parserInfo args of
      Failure pf -> expectationFailure $ show pf
      CompletionInvoked cr -> expectationFailure $ show cr
      Success (Light _) -> expectationFailure "Normal mode expected"
      Success (Normal _conn) -> pure ()

  it "modeOption --light" $
    withSystemTempFile "blockfrost.token" $ \f h -> do
      let parserInfo = info modeOption fullDesc
          args = ["--light", "--blockfrost-token-file", f]
          net = "testnet"
          projectId = "jlUej4vcMt3nKPRAiNpLUEeKBIEPqgH2"
      case execParserPure defaultPrefs parserInfo args of
        Failure pf -> expectationFailure $ show pf
        CompletionInvoked cr -> expectationFailure $ show cr
        Success (Normal _conn) -> expectationFailure "Light mode expected"
        Success (Light tf) -> do
          hClose h *> writeFile f (net <> projectId)
          readToken tf
            `shouldReturn` Blockfrost.Project Testnet (T.pack projectId)

  it "modeOption requires --light flag" $ do
    let parserInfo = info modeOption fullDesc
        args = ["--blockfrost-token-file", mockSocketOrPipe]
    case execParserPure defaultPrefs parserInfo args of
      Failure pf
        | (help, _code, _int) <- execFailure pf "" ->
          show help
            `shouldBe` "Missing: --light\n\n\
                       \Usage:  (--node-socket "
              <> nodeSocketMetavar
              <> " | \
                 \--light --blockfrost-token-file FILE)"
      result -> expectationFailure $ show result

nodeSocketMetavar :: String
nodeSocketMetavar = if isWindows then "PIPENAME" else "FILE"

mockSocketOrPipe :: String
mockSocketOrPipe = if isWindows then "\\\\.\\pipe\\test" else "/tmp/pipe"
