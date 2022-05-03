{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -fno-warn-partial-type-signatures #-}

module Cardano.Wallet.Primitive.Types.Tx.Gen
    ( coarbitraryTxIn
    , genTx
    , genTxHash
    , genTxIndex
    , genTxIn
    , genTxInFunction
    , genTxInLargeRange
    , genTxOut
    , genTxOutCoin
    , genTxOutTokenBundle
    , genTxMint
    , genTxBurn
    , genTxWith
    , shrinkTxWith
    , genTxScriptValidity
    , shrinkTx
    , shrinkTxHash
    , shrinkTxIndex
    , shrinkTxIn
    , shrinkTxInLargeRange
    , shrinkTxOut
    , shrinkTxOutCoin
    , shrinkTxMint
    , shrinkTxBurn
    , shrinkTxScriptValidity
    )
    where

import Prelude

import Cardano.Wallet.Gen
    ( genNestedTxMetadata, shrinkTxMetadata )
import Cardano.Wallet.Primitive.Types.Address.Gen
    ( genAddress, shrinkAddress )
import Cardano.Wallet.Primitive.Types.Coin
    ( Coin (..) )
import Cardano.Wallet.Primitive.Types.Coin.Gen
    ( genCoinPositive, shrinkCoinPositive )
import Cardano.Wallet.Primitive.Types.Hash
    ( Hash (..), mockHash )
import Cardano.Wallet.Primitive.Types.RewardAccount
    ( RewardAccount (..) )
import Cardano.Wallet.Primitive.Types.RewardAccount.Gen
    ( genRewardAccount, shrinkRewardAccount )
import Cardano.Wallet.Primitive.Types.TokenBundle
    ( TokenBundle )
import Cardano.Wallet.Primitive.Types.TokenBundle.Gen
    ( genTokenBundleSmallRange, shrinkTokenBundleSmallRange )
import Cardano.Wallet.Primitive.Types.TokenMap.Gen
    ( genAssetIdLargeRange, genTokenMap, shrinkTokenMap )
import Cardano.Wallet.Primitive.Types.TokenQuantity
    ( TokenQuantity (..) )
import Cardano.Wallet.Primitive.Types.Tx
    ( Tx (..)
    , TxBurn (..)
    , TxIn (..)
    , TxMetadata (..)
    , TxMint (..)
    , TxOut (..)
    , TxScriptValidity (..)
    , coinIsValidForTxOut
    , txOutMaxCoin
    , txOutMaxTokenQuantity
    , txOutMinCoin
    , txOutMinTokenQuantity
    )
import Control.Monad
    ( replicateM )
import Data.ByteArray.Encoding
    ( Base (Base16), convertToBase )
import Data.Either
    ( fromRight )
import Data.List.Extra
    ( nubOrdOn )
import Data.Map.Strict
    ( Map )
import Data.Text.Class
    ( FromText (..) )
import Data.Word
    ( Word8, Word32 )
import Generics.SOP
    ( NP (..) )
import GHC.Generics
    ( Generic )
import Test.QuickCheck
    ( Gen
    , arbitrary
    , choose
    , coarbitrary
    , elements
    , frequency
    , liftArbitrary
    , liftArbitrary2
    , liftShrink
    , liftShrink2
    , listOf
    , oneof
    , scale
    , shrinkList
    , shrinkMapBy
    , sized
    , suchThat
    )
import Test.QuickCheck.Arbitrary.Generic
    ( genericArbitrary, genericShrink )
import Test.QuickCheck.Extra
    ( chooseNatural
    , genFunction
    , genMapWith
    , genSized2With
    , genericRoundRobinShrink
    , shrinkInterleaved
    , shrinkMapWith
    , shrinkNatural
    , (<:>)
    , (<@>)
    )

import qualified Cardano.Wallet.Primitive.Types.Coin as Coin
import qualified Cardano.Wallet.Primitive.Types.TokenBundle as TokenBundle
import qualified Data.ByteString.Char8 as B8
import qualified Data.List as L
import qualified Data.Text as T

--------------------------------------------------------------------------------
-- Transactions generated according to the size parameter
--------------------------------------------------------------------------------

genTx :: Gen Tx
genTx = genTxWith genTxIn

shrinkTx :: Shrink Tx
shrinkTx = shrinkTxWith shrinkTxIn

genTxWith :: Gen TxIn -> Gen Tx
genTxWith genTxInFn = txWithoutIdToTx <$> genTxWithoutId genTxInFn

shrinkTxWith :: Shrink TxIn -> Shrink Tx
shrinkTxWith shrinkTxInFn =
    shrinkMapBy txWithoutIdToTx txToTxWithoutId (shrinkTxWithoutId shrinkTxInFn)

type Shrink a = a -> [a]

data TxWithoutId = TxWithoutId
    { fee :: !(Maybe Coin)
    , resolvedInputs :: ![(TxIn, Coin)]
    , resolvedCollateralInputs :: ![(TxIn, Coin)]
    , outputs :: ![TxOut]
    , collateralOutput :: !(Maybe TxOut)
    , mint :: !TxMint
    , burn :: !TxBurn
    , metadata :: !(Maybe TxMetadata)
    , withdrawals :: !(Map RewardAccount Coin)
    , scriptValidity :: !(Maybe TxScriptValidity)
    }
    deriving (Eq, Generic, Ord, Show)

genTxWithoutId :: Gen TxIn -> Gen TxWithoutId
genTxWithoutId genTxInFn = TxWithoutId
    <$> liftArbitrary genCoinPositive
    <*> fmap (nubOrdOn fst) (scale (`div` 4) (listOf genResolvedInput))
    <*> fmap (nubOrdOn fst) (scale (`div` 4) (listOf genResolvedInput))
    <*> scale (`div` 4) (listOf genTxOut)
    <*> scale (`div` 4) (liftArbitrary genTxOut)
    <*> scale (`div` 4) genTxMint
    <*> scale (`div` 4) genTxBurn
    <*> liftArbitrary genNestedTxMetadata
    <*> genMapWith genRewardAccount genCoinPositive
    <*> liftArbitrary genTxScriptValidity
  where
    genResolvedInput = liftArbitrary2 genTxInFn genCoinPositive

shrinkTxWithoutId :: Shrink TxIn -> Shrink TxWithoutId
shrinkTxWithoutId shrinkTxInFn = genericRoundRobinShrink
    <@> liftShrink shrinkCoinPositive
    <:> fmap (fmap (nubOrdOn fst)) (shrinkList shrinkResolvedInput)
    <:> fmap (fmap (nubOrdOn fst)) (shrinkList shrinkResolvedInput)
    <:> shrinkList shrinkTxOut
    <:> liftShrink shrinkTxOut
    <:> shrinkTxMint
    <:> shrinkTxBurn
    <:> liftShrink shrinkTxMetadata
    <:> shrinkMapWith shrinkRewardAccount shrinkCoinPositive
    <:> liftShrink shrinkTxScriptValidity
    <:> Nil
  where
    shrinkResolvedInput = liftShrink2 shrinkTxInFn shrinkCoinPositive

txWithoutIdToTx :: TxWithoutId -> Tx
txWithoutIdToTx tx@TxWithoutId {..} = Tx {txId = mockHash tx, ..}

txToTxWithoutId :: Tx -> TxWithoutId
txToTxWithoutId Tx {..} = TxWithoutId {..}

--------------------------------------------------------------------------------
-- Transaction script validity
--------------------------------------------------------------------------------

genTxScriptValidity :: Gen TxScriptValidity
genTxScriptValidity = genericArbitrary

shrinkTxScriptValidity :: TxScriptValidity -> [TxScriptValidity]
shrinkTxScriptValidity = genericShrink

--------------------------------------------------------------------------------
-- Transaction hashes
--------------------------------------------------------------------------------

genTxHash :: Gen (Hash "Tx")
genTxHash = sized $ \size -> elements $ take (max 1 size) txHashes

shrinkTxHash :: Hash "Tx" -> [Hash "Tx"]
shrinkTxHash = const []

txHashes :: [Hash "Tx"]
txHashes = mkTxHash <$> ['0' .. '9'] <> ['A' .. 'F']

--------------------------------------------------------------------------------
-- Transaction hashes chosen from a large range (to minimize collisions)
--------------------------------------------------------------------------------

genTxHashLargeRange :: Gen (Hash "Tx")
genTxHashLargeRange = Hash . B8.pack <$> replicateM 32 arbitrary

--------------------------------------------------------------------------------
-- Transaction indices generated according to the size parameter
--------------------------------------------------------------------------------

genTxIndex :: Gen Word32
genTxIndex = sized $ \size -> elements $ take (max 1 size) txIndices

shrinkTxIndex :: Word32 -> [Word32]
shrinkTxIndex 0 = []
shrinkTxIndex _ = [0]

txIndices :: [Word32]
txIndices = [0 ..]

--------------------------------------------------------------------------------
-- Transaction inputs generated according to the size parameter
--------------------------------------------------------------------------------

genTxIn :: Gen TxIn
genTxIn = genSized2With TxIn genTxHash genTxIndex

shrinkTxIn :: TxIn -> [TxIn]
shrinkTxIn (TxIn h i) = uncurry TxIn <$> shrinkInterleaved
    (h, shrinkTxHash)
    (i, shrinkTxIndex)

--------------------------------------------------------------------------------
-- Transaction input functions
--------------------------------------------------------------------------------

coarbitraryTxIn :: TxIn -> Gen a -> Gen a
coarbitraryTxIn = coarbitrary . show

genTxInFunction :: Gen a -> Gen (TxIn -> a)
genTxInFunction = genFunction coarbitraryTxIn

--------------------------------------------------------------------------------
-- Transaction inputs chosen from a large range (to minimize collisions)
--------------------------------------------------------------------------------

genTxInLargeRange :: Gen TxIn
genTxInLargeRange = TxIn
    <$> genTxHashLargeRange
    -- Note that we don't need to choose indices from a large range, as hashes
    -- are already chosen from a large range:
    <*> genTxIndex

shrinkTxInLargeRange :: TxIn -> [TxIn]
shrinkTxInLargeRange = const []

--------------------------------------------------------------------------------
-- Transaction outputs generated according to the size parameter
--------------------------------------------------------------------------------

genTxOut :: Gen TxOut
genTxOut = TxOut
    <$> genAddress
    <*> genTokenBundleSmallRange `suchThat` tokenBundleHasNonZeroCoin

shrinkTxOut :: TxOut -> [TxOut]
shrinkTxOut (TxOut a b) = uncurry TxOut <$> shrinkInterleaved
    (a, shrinkAddress)
    (b, filter tokenBundleHasNonZeroCoin . shrinkTokenBundleSmallRange)

tokenBundleHasNonZeroCoin :: TokenBundle -> Bool
tokenBundleHasNonZeroCoin b = TokenBundle.getCoin b /= Coin 0

--------------------------------------------------------------------------------
-- Coins chosen from the full range allowed in a transaction output
--------------------------------------------------------------------------------

-- | Generates coins across the full range allowed in a transaction output.
--
-- This generator has a slight bias towards the limits of the range, but
-- otherwise generates values uniformly across the whole range.
--
-- This can be useful when testing roundtrip conversions between different
-- types.
--
genTxOutCoin :: Gen Coin
genTxOutCoin = frequency
    [ (1, pure txOutMinCoin)
    , (1, pure txOutMaxCoin)
    , (8, Coin.fromNatural <$> chooseNatural
        ( Coin.toNatural txOutMinCoin + 1
        , Coin.toNatural txOutMaxCoin - 1
        )
      )
    ]

shrinkTxOutCoin :: Coin -> [Coin]
shrinkTxOutCoin
    = L.filter coinIsValidForTxOut
    . shrinkMapBy Coin.fromNatural Coin.toNatural shrinkNatural

--------------------------------------------------------------------------------
-- Token bundles with fixed numbers of assets.
--
-- Values are chosen from across the full range of values permitted within
-- transaction outputs.
--
-- Policy identifiers, asset names, token quantities are all allowed to vary.
--------------------------------------------------------------------------------

genTxOutTokenBundle :: Int -> Gen TokenBundle
genTxOutTokenBundle fixedAssetCount
    = TokenBundle.fromFlatList
        <$> genTxOutCoin
        <*> replicateM fixedAssetCount genAssetQuantity
  where
    genAssetQuantity = (,)
        <$> genAssetIdLargeRange
        <*> genTokenQuantity
    genTokenQuantity = integerToTokenQuantity <$> oneof
        [ pure $ tokenQuantityToInteger txOutMinTokenQuantity
        , pure $ tokenQuantityToInteger txOutMaxTokenQuantity
        , choose
            ( tokenQuantityToInteger txOutMinTokenQuantity + 1
            , tokenQuantityToInteger txOutMaxTokenQuantity - 1
            )
        ]
      where
        tokenQuantityToInteger :: TokenQuantity -> Integer
        tokenQuantityToInteger = fromIntegral . unTokenQuantity

        integerToTokenQuantity :: Integer -> TokenQuantity
        integerToTokenQuantity = TokenQuantity . fromIntegral

--------------------------------------------------------------------------------
-- Minting and burning
--------------------------------------------------------------------------------

genTxMint :: Gen TxMint
genTxMint = TxMint <$> genTokenMap

genTxBurn :: Gen TxBurn
genTxBurn = TxBurn <$> genTokenMap

shrinkTxMint :: TxMint -> [TxMint]
shrinkTxMint = shrinkMapBy TxMint unTxMint shrinkTokenMap

shrinkTxBurn :: TxBurn -> [TxBurn]
shrinkTxBurn = shrinkMapBy TxBurn unTxBurn shrinkTokenMap

--------------------------------------------------------------------------------
-- Internal utilities
--------------------------------------------------------------------------------

-- The input must be a character in the range [0-9] or [A-F].
--
mkTxHash :: Char -> Hash "Tx"
mkTxHash c
    = fromRight reportError
    $ fromText
    $ T.pack
    $ replicate txHashHexStringLength c
  where
    reportError = error $
        "Unable to generate transaction hash from character: " <> show c

txHashHexStringLength :: Int
txHashHexStringLength = 64
