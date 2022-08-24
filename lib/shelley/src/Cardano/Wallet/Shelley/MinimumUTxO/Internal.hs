{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}

-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
-- Computing minimum UTxO values: internal interface.
--
module Cardano.Wallet.Shelley.MinimumUTxO.Internal
    ( computeMinimumCoinForUTxOLedger
    , computeMinimumCoinForUTxOCardanoApi
    ) where

import Prelude

import Cardano.Ledger.Shelley.API.Wallet
    ( evaluateMinLovelaceOutput )
import Cardano.Wallet.Primitive.Types.Coin
    ( Coin )
import Cardano.Wallet.Primitive.Types.MinimumUTxO
    ( MinimumUTxOForShelleyBasedEra (..) )
import Cardano.Wallet.Primitive.Types.Tx
    ( TxOut )
import Cardano.Wallet.Shelley.Compatibility
    ( toCardanoTxOut, unsafeLovelaceToWalletCoin, unsafeValueToLovelace )
import Cardano.Wallet.Shelley.Compatibility.Ledger
    ( toAllegraTxOut
    , toAlonzoTxOut
    , toBabbageTxOut
    , toMaryTxOut
    , toShelleyTxOut
    , toWalletCoin
    )
import Data.Function
    ( (&) )
import GHC.Stack
    ( HasCallStack )

import qualified Cardano.Api.Shelley as Cardano

-- | Computes a minimum UTxO value with the ledger.
--
computeMinimumCoinForUTxOLedger
    :: MinimumUTxOForShelleyBasedEra
    -> TxOut
    -> Coin
computeMinimumCoinForUTxOLedger minimumUTXO txOut =
    toWalletCoin $ case era of
        Cardano.ShelleyBasedEraShelley ->
            evaluateMinLovelaceOutput pp
                $ toShelleyTxOut txOut
        Cardano.ShelleyBasedEraAllegra ->
            evaluateMinLovelaceOutput pp
                $ toAllegraTxOut txOut
        Cardano.ShelleyBasedEraMary ->
            evaluateMinLovelaceOutput pp
                $ toMaryTxOut txOut
        Cardano.ShelleyBasedEraAlonzo ->
            evaluateMinLovelaceOutput pp
                $ toAlonzoTxOut txOut Nothing
        Cardano.ShelleyBasedEraBabbage ->
            evaluateMinLovelaceOutput pp
                $ toBabbageTxOut txOut Nothing
  where
    MinimumUTxOForShelleyBasedEra era pp = minimumUTxO

-- | Computes a minimum UTxO value with the Cardano API.
--
computeMinimumCoinForUTxOCardanoApi
    :: HasCallStack
    => MinimumUTxOForShelleyBasedEra
    -> TxOut
    -> Coin
computeMinimumCoinForUTxOCardanoApi minimumUTxO txOut =
    unsafeCoinFromResult $
        Cardano.calculateMinimumUTxO era
            (toCardanoTxOut era txOut)
            (Cardano.fromLedgerPParams era pp)
  where
    MinimumUTxOForShelleyBasedEra era pp = minimumUTxO

    unsafeCoinFromResult
        :: Either Cardano.MinimumUTxOError Cardano.Value -> Coin
    unsafeCoinFromResult = \case
        Right value ->
            -- We assume that the returned value is a non-negative ada quantity
            -- with no other assets. If this assumption is violated, we have no
            -- way to continue, and must raise an error:
            value
                & unsafeValueToLovelace
                & unsafeLovelaceToWalletCoin
        Left e ->
            -- The 'Cardano.calculateMinimumUTxO' function should only return
            -- an error if a required protocol parameter is missing.
            --
            -- However, given that values of 'MinimumUTxOForShelleyBasedEra'
            -- can only be constructed by supplying an era-specific protocol
            -- parameters record, it should be impossible to trigger this
            -- condition.
            --
            -- Any violation of this assumption indicates a programming error.
            -- If this condition is triggered, we have no way to continue, and
            -- must raise an error:
            --
            error $ unwords
                [ "computeMinimumCoinForUTxOCardanoApi:"
                , "unexpected error:"
                , show e
                ]
