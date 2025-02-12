{-# LANGUAGE TypeFamilies #-}

module Cardano.Wallet.Read.Primitive.Tx.Features.Outputs
    ( getOutputs
    , fromShelleyTxOut
    , fromMaryTxOut
    , fromAllegraTxOut
    , fromAlonzoTxOut
    , fromBabbageTxOut
    , fromCardanoValue
    , fromShelleyAddress
    , fromByronTxOut
    )
    where

import Prelude

import Cardano.Binary
    ( serialize' )
import Cardano.Chain.Common
    ( unsafeGetLovelace )
import Cardano.Wallet.Read.Eras
    ( EraFun (..), K (..) )
import Cardano.Wallet.Read.Primitive.Tx.Features.Fee
    ( fromShelleyCoin )
import Cardano.Wallet.Read.Tx.Outputs
    ( Outputs (..) )
import Cardano.Wallet.Util
    ( internalError )
import Data.Foldable
    ( toList )
import GHC.Stack
    ( HasCallStack )
import Ouroboros.Consensus.Shelley.Eras
    ( StandardAllegra
    , StandardAlonzo
    , StandardBabbage
    , StandardMary
    , StandardShelley
    )

import qualified Cardano.Api.Shelley as Cardano
import qualified Cardano.Chain.UTxO as Byron
import qualified Cardano.Ledger.Address as SL
import qualified Cardano.Ledger.Alonzo as Alonzo
import qualified Cardano.Ledger.Alonzo.TxBody as Alonzo
import qualified Cardano.Ledger.Babbage as Babbage
import qualified Cardano.Ledger.Babbage.TxBody as Babbage
import qualified Cardano.Ledger.Shelley.API as SL
import qualified Cardano.Wallet.Primitive.Types.Address as W
import qualified Cardano.Wallet.Primitive.Types.Coin as W
import qualified Cardano.Wallet.Primitive.Types.Coin as Coin
import qualified Cardano.Wallet.Primitive.Types.Hash as W
import qualified Cardano.Wallet.Primitive.Types.TokenBundle as TokenBundle
import qualified Cardano.Wallet.Primitive.Types.TokenPolicy as W
import qualified Cardano.Wallet.Primitive.Types.TokenQuantity as W
import qualified Cardano.Wallet.Primitive.Types.Tx.TxOut as W

getOutputs :: EraFun Outputs (K [W.TxOut])
getOutputs = EraFun
    { byronFun = \(Outputs os) -> K . fmap fromByronTxOut $ toList os
    , shelleyFun = \(Outputs os) -> K . fmap fromShelleyTxOut $ toList os
    , allegraFun = \(Outputs os) -> K . fmap fromAllegraTxOut $ toList os
    , maryFun = \(Outputs os) -> K . fmap fromMaryTxOut $ toList os
    , alonzoFun = \(Outputs os) -> K . fmap fromAlonzoTxOut $ toList os
    , babbageFun = \(Outputs os) -> K . fmap fromBabbageTxOut $ toList os
    }

fromShelleyAddress :: SL.Addr crypto -> W.Address
fromShelleyAddress = W.Address . SL.serialiseAddr

fromShelleyTxOut :: SL.TxOut StandardShelley -> W.TxOut
fromShelleyTxOut (SL.TxOut addr amount) = W.TxOut
    (fromShelleyAddress addr)
    (TokenBundle.fromCoin $ fromShelleyCoin amount)

fromAllegraTxOut :: SL.TxOut StandardAllegra -> W.TxOut
fromAllegraTxOut (SL.TxOut addr amount) = W.TxOut
    (fromShelleyAddress addr)
    (TokenBundle.fromCoin $ fromShelleyCoin amount)

fromMaryTxOut :: SL.TxOut StandardMary -> W.TxOut
fromMaryTxOut (SL.TxOut addr value) =
    W.TxOut (fromShelleyAddress addr) $
    fromCardanoValue $ Cardano.fromMaryValue value

fromAlonzoTxOut
    :: Alonzo.TxOut StandardAlonzo
    -> W.TxOut
fromAlonzoTxOut (Alonzo.TxOut addr value _) =
    W.TxOut (fromShelleyAddress addr) $
    fromCardanoValue $ Cardano.fromMaryValue value

fromBabbageTxOut
    :: Babbage.TxOut StandardBabbage
    -> W.TxOut
fromBabbageTxOut (Babbage.TxOut addr value _datum _refScript) =
    W.TxOut (fromShelleyAddress addr) $
    fromCardanoValue $ Cardano.fromMaryValue value

-- Lovelace to coin. Quantities from ledger should always fit in Word64.
fromCardanoLovelace :: HasCallStack => Cardano.Lovelace -> W.Coin
fromCardanoLovelace =
    Coin.unsafeFromIntegral . unQuantity . Cardano.lovelaceToQuantity
  where
    unQuantity (Cardano.Quantity q) = q

fromCardanoValue :: HasCallStack => Cardano.Value -> TokenBundle.TokenBundle
fromCardanoValue = uncurry TokenBundle.fromFlatList . extract
  where
    extract value =
        ( fromCardanoLovelace $ Cardano.selectLovelace value
        , mkBundle $ Cardano.valueToList value
        )

    -- Do Integer to Natural conversion. Quantities from ledger TxOuts can
    -- never be negative (but unminted values could be negative).
    mkQuantity :: Integer -> W.TokenQuantity
    mkQuantity = W.TokenQuantity . checkBounds
      where
        checkBounds n
          | n >= 0 = fromIntegral n
          | otherwise = internalError "negative token quantity"

    mkBundle assets =
        [ (TokenBundle.AssetId (mkPolicyId p) (mkTokenName n) , mkQuantity q)
        | (Cardano.AssetId p n, Cardano.Quantity q) <- assets
        ]

    mkPolicyId = W.UnsafeTokenPolicyId . W.Hash . Cardano.serialiseToRawBytes
    mkTokenName = W.UnsafeTokenName . Cardano.serialiseToRawBytes

fromByronTxOut :: Byron.TxOut -> W.TxOut
fromByronTxOut (Byron.TxOut addr coin) = W.TxOut
    { W.address = W.Address (serialize' addr)
    , W.tokens = TokenBundle.fromCoin $ Coin.fromWord64 $ unsafeGetLovelace coin
    }
