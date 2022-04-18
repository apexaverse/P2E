{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE NumericUnderscores  #-}

module P2E (mint, policy, policyCode, curSymbol, simulate, writePolicyFile) where

import           Control.Monad          hiding (fmap)
import           Control.Exception      (throwIO)
import           Data.Text              (Text)
import           Data.Void              (Void)
import qualified Data.ByteString.Short  as SBS
import qualified Data.ByteString.Lazy   as LBS
import           Plutus.Contract        as Contract
import           Plutus.Trace.Emulator  as Emulator
import qualified PlutusTx
import           PlutusTx.Prelude       hiding (Semigroup(..), unless)
import           Ledger                 hiding (mint, singleton)
import           Ledger.Constraints     as Constraints
import qualified Ledger.Typed.Scripts   as Scripts
import qualified Ledger.Value           as Value
import           Prelude                (IO, Show (..), String,  userError, FilePath)
import           Text.Printf            (printf)
import           Wallet.Emulator.Wallet
import           Cardano.Api            (PlutusScriptV1, FileError, writeFileTextEnvelope)
import           Cardano.Api.Shelley    (PlutusScript (..))
import           Codec.Serialise        (serialise)

tokenName :: TokenName
tokenName = "APEXAVERSE"

tokenSupply :: Integer
tokenSupply = 10_000_000_000

{-# INLINABLE mkPolicy #-}
mkPolicy :: () -> ScriptContext -> Bool
mkPolicy () _ = True

policyCode :: PlutusTx.CompiledCode Scripts.WrappedMintingPolicyType
policyCode = $$(PlutusTx.compile [|| Scripts.wrapMintingPolicy mkPolicy ||])

policy :: Scripts.MintingPolicy
policy = mkMintingPolicyScript policyCode

curSymbol :: CurrencySymbol
curSymbol = scriptCurrencySymbol policy

mint :: Contract () EmptySchema Text ()
mint = do
    let val     = Value.singleton curSymbol tokenName tokenSupply
        lookups = Constraints.mintingPolicy policy
        tx      = Constraints.mustMintValue val
    ledgerTx <- submitTxConstraintsWith @Void lookups tx
    void $ awaitTxConfirmed $ getCardanoTxId ledgerTx
    Contract.logInfo @String $ printf "forged %s" (show val)

writeMintingPolicy :: FilePath -> Scripts.MintingPolicy -> IO (Either (FileError ()) ())
writeMintingPolicy file = writeFileTextEnvelope @(PlutusScript PlutusScriptV1) file Nothing . PlutusScriptSerialised . SBS.toShort . LBS.toStrict . serialise . getMintingPolicy

writePolicyFile :: IO ()
writePolicyFile = do
    let file  = "policy.plutus"
    e <- writeMintingPolicy file policy
    case e of
      Left err -> throwIO $ userError $ show err
      Right () -> return ()

simulate :: IO ()
simulate = runEmulatorTraceIO $ do
    _ <- activateContractWallet (knownWallet 1) mint
    void $ Emulator.waitNSlots 1
