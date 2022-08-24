{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}

-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
-- Computing minimum UTxO values.
--
module Cardano.Wallet.Shelley.MinimumUTxO
    ( computeMinimumCoinForUTxO
    , isBelowMinimumCoinForUTxO
    ) where

import Prelude

import Cardano.Ledger.Babbage.Rules.Utxo
    ( babbageMinUTxOValue )
import Cardano.Ledger.Serialization
    ( mkSized )
import Cardano.Wallet.Primitive.Types.Address
    ( Address (..) )
import Cardano.Wallet.Primitive.Types.Coin
    ( Coin (..) )
import Cardano.Wallet.Primitive.Types.MinimumUTxO
    ( MinimumUTxO (..) )
import Cardano.Wallet.Primitive.Types.TokenBundle
    ( TokenBundle (..) )
import Cardano.Wallet.Primitive.Types.TokenMap
    ( TokenMap )
import Cardano.Wallet.Primitive.Types.Tx
    ( TxOut (..), txOutMaxCoin )
import Cardano.Wallet.Shelley.Compatibility
    ( toCardanoTxOut )
import Cardano.Wallet.Shelley.Compatibility.Ledger
    ( toBabbageTxOut, toWalletCoin )
import Ouroboros.Consensus.Cardano.Block
    ( StandardBabbage )

import qualified Cardano.Api.Shelley as Cardano
import qualified Cardano.Ledger.Babbage.PParams as Babbage
import qualified Cardano.Wallet.Primitive.Types.TokenBundle as TokenBundle
import qualified Cardano.Wallet.Shelley.MinimumUTxO.Internal as Internal

-- | Computes a minimum 'Coin' value for a 'TokenMap' that is destined for
--   inclusion in a transaction output.
--
computeMinimumCoinForUTxO
    :: MinimumUTxO
    -> Address
    -> TokenMap
    -> Coin
computeMinimumCoinForUTxO minimumUTxO addr tokenMap =
    case minimumUTxO of
        MinimumUTxONone ->
            Coin 0
        MinimumUTxOConstant c ->
            c
        MinimumUTxOForShelleyBasedEraOf minimumUTxOShelley ->
            Internal.computeMinimumUTxOCoin minimumUTxOShelley
                (TxOut addr $ TokenBundle txOutMaxCoin tokenMap)

-- | Returns 'True' if and only if the given 'TokenBundle' has a 'Coin' value
--   that is below the minimum acceptable 'Coin' value.
--
isBelowMinimumCoinForUTxO
    :: MinimumUTxO
    -> Address
    -> TokenBundle
    -> Bool
isBelowMinimumCoinForUTxO minimumUTxO addr tokenBundle =
    case minimumUTxO of
        MinimumUTxONone ->
            False
        MinimumUTxOConstant c ->
            TokenBundle.getCoin tokenBundle < c
        MinimumUTxOForShelleyBasedEraOf minimumUTxOShelley ->
            TokenBundle.getCoin tokenBundle <
                Internal.computeMinimumUTxOCoin minimumUTxOShelley
                    (TxOut addr tokenBundle)

-- | Embeds a 'TokenMap' within a padded 'Cardano.TxOut' value.
--
-- When computing the minimum UTxO quantity for a given 'TokenMap', we do not
-- have access to an address or to an ada quantity.
--
-- However, in order to compute a minimum UTxO quantity through the Cardano
-- API, we must supply a 'TxOut' value with a valid address and ada quantity.
--
-- It's imperative that we do not underestimate minimum UTxO quantities, as
-- this may result in the creation of transactions that are unacceptable to
-- the ledger. In the case of change generation, this would be particularly
-- problematic, as change outputs are generated automatically, and users do
-- not have direct control over the ada quantities generated.
--
-- However, while we cannot underestimate minimum UTxO quantities, we are at
-- liberty to moderately overestimate them.
--
-- Since the minimum UTxO quantity function is monotonically increasing w.r.t.
-- the size of the address and ada quantity, if we supply a 'TxOut' with an
-- address and ada quantity whose serialized lengths are the maximum possible
-- lengths, we can be confident that the resultant value will not be an
-- underestimate.
--
_embedTokenMapWithinPaddedTxOut
    :: Cardano.ShelleyBasedEra era
    -> Address
    -> TokenMap
    -> Cardano.TxOut Cardano.CtxTx era
_embedTokenMapWithinPaddedTxOut era addr m =
    toCardanoTxOut era $ TxOut addr $ TokenBundle txOutMaxCoin m

-- | Uses the ledger to compute a minimum ada quantity for the Babbage era.
--
_computeLedgerMinimumCoinForBabbage
    :: Babbage.PParams StandardBabbage
    -> Address
    -> TokenBundle
    -> Coin
_computeLedgerMinimumCoinForBabbage pp addr tokenBundle =
    toWalletCoin
        $ babbageMinUTxOValue pp
        $ mkSized
        $ toBabbageTxOut (TxOut addr tokenBundle) Nothing
