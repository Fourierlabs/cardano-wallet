{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE DeriveAnyClass      #-}
{-# LANGUAGE DeriveGeneric       #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE DerivingStrategies  #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TemplateHaskell     #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeOperators       #-}
{-# LANGUAGE ViewPatterns        #-}
{-# OPTIONS_GHC -fno-ignore-interface-pragmas #-}
{-# OPTIONS_GHC -fno-omit-interface-pragmas #-}
{-# OPTIONS_GHC -fno-specialise #-}
{-# OPTIONS_GHC -fplugin-opt PlutusTx.Plugin:debug-context #-}

module Test.PlutusE2E.Base where

import Data.Aeson
    ( (.=) )
import Data.Generics.Internal.VL.Lens
    ( view, (^.) )
import Ledger
    ( POSIXTime, PaymentPubKeyHash
    )
import Ledger.Constraints.OffChain
    ( tx )
import Data.Proxy (Proxy(..))
import Cardano.Wallet.Unsafe
    ( unsafeMkMnemonic )
import Cardano.Mnemonic
    ( SomeMnemonic (..))
import Plutus.Contracts.Crowdfunding
import PlutusTx.Prelude hiding (Applicative (..), Semigroup (..), return, (<$>), (>>), (>>=), error)
import Prelude (Semigroup (..))
import Control.Arrow
    ( second )
import Cardano.Wallet.Primitive.AddressDerivation
    (HardDerivation (..), Role(..), getRawKey, publicKey)

import qualified Test.Integration.Framework.DSL as DSL
import qualified Data.Vector as Vector
import qualified Codec.CBOR.Write as CBORWrite
import qualified Codec.Serialise.Class as Serialise
import qualified Cardano.Wallet.Primitive.AddressDerivation.Shelley as Shelley
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base16 as Base16
import qualified Data.HashMap.Strict as HM
import qualified Data.Text.Encoding as T
import qualified Ledger.Constraints as Constraints
import qualified Ledger.Interval as Interval
import qualified Ledger.Typed.Scripts as Scripts hiding
    ( validatorHash )
import qualified Plutus.V1.Ledger.Value as Plutus
import qualified PlutusTx
import qualified Prelude as Haskell
import qualified Ledger as Plutus
import qualified Cardano.Crypto.Wallet

data Crowdfunding
instance Scripts.ValidatorTypes Crowdfunding where
    type instance RedeemerType Crowdfunding = CampaignAction
    type instance DatumType Crowdfunding = PaymentPubKeyHash

typedValidator :: Campaign -> Scripts.TypedValidator Crowdfunding
typedValidator = Scripts.mkTypedValidatorParam @Crowdfunding
    $$(PlutusTx.compile [|| mkValidator ||])
    $$(PlutusTx.compile [|| wrap ||])
    where
        wrap = Scripts.wrapValidator

-- | A sample campaign
theCampaign :: POSIXTime -> Campaign
theCampaign startTime = Campaign
    { campaignDeadline = startTime + 20000
    , campaignCollectionDeadline = startTime + 30000
    , campaignOwner = Haskell.undefined -- Emulator.mockWalletPaymentPubKeyHash (knownWallet 1)
    }

-- newActor :: Context -> Actor
-- actorWallet :: Actor -> Wallet
-- actorWalletMnemonics :: Actor -> Mnemonic 15
-- actorWalletRootKey :: Actor -> k 'RootK XPrv
-- actorPaymentPublicKey :: Actor -> Plutus.PaymentPublicKey
-- actorPaymentPublicKeyHash :: Actor -> Plutus.PaymentPublicKeyHash
-- actorPaymentPrivateKey :: Actor -> Plutus.PaymentPrivateKey

walletToPubKeyHash ctx = do
    (w, mw) <- second (unsafeMkMnemonic @15) Haskell.<$> DSL.fixtureWalletWithMnemonics (Proxy @"shelley") ctx

    -- Generate a public key for contributor
    let
        pw = Haskell.mempty
        rootSk = Shelley.generateKeyFromSeed (SomeMnemonic mw, Nothing) pw
        acctSk = deriveAccountPrivateKey pw rootSk Haskell.minBound
        addrSk = getRawKey $ deriveAddressPrivateKey pw acctSk UtxoExternal Haskell.minBound

    Haskell.pure $ fromWalletToPlutus addrSk

fromWalletToPlutus :: Cardano.Crypto.Wallet.XPrv -> Plutus.PaymentPubKeyHash
fromWalletToPlutus =
    Plutus.PaymentPubKeyHash . Plutus.pubKeyHash . Plutus.toPublicKey

-- contribute' :: _ -> Campaign -> PaymentPubKeyHash -> Plutus.Value -> Aeson.Value
contribute' input cmp contributor value =
    let
        inst = typedValidator cmp

        constraints
            = Constraints.mustPayToTheScript contributor value
            <> Constraints.mustValidateIn (Interval.to (campaignDeadline cmp))

        unbalancedTx =
            either (Haskell.error "Failed to create Tx from constraints") id
            $ Constraints.mkTx
                (Constraints.typedValidatorLookups inst)
                constraints

        -- import Codec.CBOR.Write qualified as Write
        -- import Codec.Serialise.Class (Serialise, encode)
        unbalancedTxHex =
            T.decodeUtf8
            . Base16.encode
            . CBORWrite.toStrictByteString
            . Serialise.encode
            $ unbalancedTx ^. tx
    in
        Aeson.Null
        -- Aeson.Object $ HM.fromList
        --   [ "transaction" .= Aeson.String unbalancedTxHex
        --   , "inputs" .= Aeson.toJSON [ Aeson.object
        --       [ "id" .= view #id input
        --       , "index" .= view #index input
        --       , "address" .= view #address input
        --       , "amount" .= view #amount input
        --       , "assets" .= Aeson.Array Vector.empty
        --       ] ]
        --  -- The contribution action does not try to spend a UTxO at a script
        --  -- address, it only puts funds to the script address, so datum and
        --  -- redeemer are not required.
        --  , "redeemers" .= (Aeson.toJSON ([] :: [()]))
        --  ]

    -- Tx in UnbalancedTx has no extra required signatories.
    -- But is available in UnbalancedTx
    -- So BalanceTx first, get sealed Tx back, then add required signatories
    -- before calling signTransaction.

    -- TODO: Add reqSignerHashes to TxUpdate
    -- TODO: Change test DSL to take UnBalancedTxs to handle this natively?


            -- w <- fixtureWallet ctx
