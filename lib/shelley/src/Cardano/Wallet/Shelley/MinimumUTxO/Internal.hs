{-# LANGUAGE LambdaCase #-}

-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
-- Computing minimum UTxO values: internal interface.
--
module Cardano.Wallet.Shelley.MinimumUTxO.Internal
    ( computeMinimumUTxOCoinOracle
    ) where

import Prelude

import Cardano.Wallet.Primitive.Types.Coin
    ( Coin )
import Cardano.Wallet.Primitive.Types.MinimumUTxO
    ( MinimumUTxOForShelleyBasedEra (..) )
import Cardano.Wallet.Primitive.Types.Tx
    ( TxOut )
import Cardano.Wallet.Shelley.Compatibility
    ( toCardanoTxOut, unsafeLovelaceToWalletCoin, unsafeValueToLovelace )
import Data.Function
    ( (&) )
import GHC.Stack
    ( HasCallStack )

import qualified Cardano.Api.Shelley as Cardano

-- | Provides an oracle for computing minimum UTxO values.
--
-- Our oracle is based on the Cardano API function 'calculateMinimumUTxO',
-- which we treat as a source of truth.
--
computeMinimumUTxOCoinOracle
    :: HasCallStack
    => MinimumUTxOForShelleyBasedEra
    -> TxOut
    -> Coin
computeMinimumUTxOCoinOracle (MinimumUTxOForShelleyBasedEra era pp) txOut =
    unsafeCoinFromResult $
        Cardano.calculateMinimumUTxO era
            (toCardanoTxOut era txOut)
            (Cardano.fromLedgerPParams era pp)
  where
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
                [ "computeMinimumUTxOCoinOracle:"
                , "unexpected error:"
                , show e
                ]
