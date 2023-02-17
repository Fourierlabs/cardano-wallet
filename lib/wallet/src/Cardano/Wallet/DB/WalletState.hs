{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeFamilies #-}

-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
-- Pure data type which represents the entire wallet state,
-- including all checkpoints.
--
-- FIXME during ADP-1043: Actually include everything,
-- e.g. TxHistory, Pending transactions, …

module Cardano.Wallet.DB.WalletState
    ( -- * Wallet state
      WalletState (..)
    , fromGenesis
    , getLatest
    , findNearestPoint

    -- * WalletCheckpoint (internal use mostly)
    , WalletCheckpoint (..)
    , toWallet
    , fromWallet
    , getBlockHeight
    , getSlot

    -- * Delta types
    , DeltaWalletState1 (..)
    , DeltaWalletState

    -- * Multiple wallets
    , DeltaMap (..)
    , ErrNoSuchWallet (..)
    , adjustNoSuchWallet
    ) where

import Prelude

import Cardano.Wallet.Address.Book
    ( AddressBookIso (..), Discoveries, Prologue )
import Cardano.Wallet.Checkpoints
    ( Checkpoints )
import Cardano.Wallet.DB.Errors
    ( ErrNoSuchWallet (..) )
import Cardano.Wallet.DB.Store.Submissions.Operations
    ( DeltaTxSubmissions, TxSubmissions )
import Cardano.Wallet.Primitive.Types
    ( BlockHeader, WalletId )
import Cardano.Wallet.Primitive.Types.UTxO
    ( UTxO )
import Data.Delta
    ( Delta (..) )
import Data.DeltaMap
    ( DeltaMap (..) )
import Data.Generics.Internal.VL
    ( withIso )
import Data.Generics.Internal.VL.Lens
    ( over, view, (^.) )
import Data.Map.Strict
    ( Map )
import Data.Word
    ( Word32 )
import Fmt
    ( Buildable (..), pretty )
import GHC.Generics
    ( Generic )

import qualified Cardano.Wallet.Checkpoints as CPS
import qualified Cardano.Wallet.Primitive.Model as W
import qualified Cardano.Wallet.Primitive.Types as W
import qualified Cardano.Wallet.Submissions.Submissions as Submissions
import qualified Data.Map.Strict as Map

{-------------------------------------------------------------------------------
    Wallet Checkpoint
-------------------------------------------------------------------------------}
-- | Data stored in a single checkpoint.
-- Only includes the 'UTxO' and the 'Discoveries', but not the 'Prologue'.
data WalletCheckpoint s = WalletCheckpoint
    { currentTip :: !BlockHeader
    , utxo :: !UTxO
    , discoveries :: !(Discoveries s)
    } deriving (Generic)

deriving instance AddressBookIso s => Eq (WalletCheckpoint s)

-- | Helper function: Get the block height of a wallet checkpoint.
getBlockHeight :: WalletCheckpoint s -> Word32
getBlockHeight (WalletCheckpoint currentTip _ _) =
    currentTip ^. (#blockHeight . #getQuantity)

-- | Helper function: Get the 'Slot' of a wallet checkpoint.
getSlot :: WalletCheckpoint s -> W.Slot
getSlot (WalletCheckpoint currentTip _ _) =
    W.toSlot . W.chainPointFromBlockHeader $ currentTip

-- | Convert a stored 'WalletCheckpoint' to the legacy 'W.Wallet' state.
toWallet :: AddressBookIso s => Prologue s -> WalletCheckpoint s -> W.Wallet s
toWallet pro (WalletCheckpoint pt utxo dis) =
    W.unsafeInitWallet utxo pt $ withIso addressIso $ \_ from -> from (pro,dis)

-- | Convert a legacy 'W.Wallet' state to a 'Prologue' and a 'WalletCheckpoint'
fromWallet :: AddressBookIso s => W.Wallet s -> (Prologue s, WalletCheckpoint s)
fromWallet w = (pro, WalletCheckpoint (W.currentTip w) (W.utxo w) dis)
  where
    (pro, dis) = withIso addressIso $ \to _ -> to (w ^. #getState)

{-------------------------------------------------------------------------------
    Wallet State
-------------------------------------------------------------------------------}
-- | Wallet state. Currently includes:
--
-- * Prologue of the address discovery state
-- * Checkpoints of UTxO and of discoveries of the address discovery state.
--
-- FIXME during ADP-1043: Include also TxHistory, pending transactions, …,
-- everything.
data WalletState s = WalletState
    { prologue    :: !(Prologue s)
    , checkpoints :: !(Checkpoints (WalletCheckpoint s))
    , submissions :: !TxSubmissions
    } deriving (Generic)

deriving instance AddressBookIso s => Eq (WalletState s)

-- | Create a wallet from the genesis block.
fromGenesis :: AddressBookIso s => W.Wallet s -> Maybe (WalletState s)
fromGenesis cp
    | W.isGenesisBlockHeader header = Just $
        WalletState{ prologue
            , checkpoints = CPS.fromGenesis checkpoint
            , submissions = Submissions.mkEmpty 0
            }
    | otherwise = Nothing
  where
    header = cp ^. #currentTip
    (prologue, checkpoint) = fromWallet cp

-- | Get the wallet checkpoint with the largest slot number
getLatest :: AddressBookIso s => WalletState s -> W.Wallet s
getLatest w =
    toWallet (w ^. #prologue) . snd $ CPS.getLatest (w ^. #checkpoints)

-- | Find the nearest 'Checkpoint' that is either at the given point or before.
findNearestPoint :: WalletState s -> W.Slot -> Maybe W.Slot
findNearestPoint = CPS.findNearestPoint . view #checkpoints

{-------------------------------------------------------------------------------
    Delta type for the wallet state
-------------------------------------------------------------------------------}
type DeltaWalletState s = [DeltaWalletState1 s]

data DeltaWalletState1 s
    = ReplacePrologue (Prologue s)
    -- ^ Replace the prologue of the address discovery state
    | UpdateCheckpoints (CPS.DeltasCheckpoints (WalletCheckpoint s))
    -- ^ Update the wallet checkpoints.
    | UpdateSubmissions DeltaTxSubmissions

instance Delta (DeltaWalletState1 s) where
    type Base (DeltaWalletState1 s) = WalletState s
    apply (ReplacePrologue p) = over #prologue $ const p
    apply (UpdateCheckpoints d) = over #checkpoints $ apply d
    apply (UpdateSubmissions d) = over #submissions $ apply d

instance Buildable (DeltaWalletState1 s) where
    build (ReplacePrologue _) = "ReplacePrologue …"
    build (UpdateCheckpoints d) = "UpdateCheckpoints (" <> build d <> ")"
    build (UpdateSubmissions d) = "UpdateSubmissions (" <> build d <> ")"

instance Show (DeltaWalletState1 s) where
    show = pretty

{-------------------------------------------------------------------------------
    Multiple wallets.
-------------------------------------------------------------------------------}
-- | Adjust a specific wallet if it exists or return 'ErrNoSuchWallet'.
adjustNoSuchWallet
    :: WalletId
    -> (ErrNoSuchWallet -> e)
    -> (w -> Either e (dw, b))
    -> (Map WalletId w -> (Maybe (DeltaMap WalletId dw), Either e b))
adjustNoSuchWallet wid err update wallets = case Map.lookup wid wallets of
    Nothing -> (Nothing, Left $ err $ ErrNoSuchWallet wid)
    Just wal -> case update wal of
        Left e -> (Nothing, Left e)
        Right (dw, b) -> (Just $ Adjust wid dw, Right b)

