{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTSyntax #-}

{- |
Copyright: © 2022 IOHK
License: Apache-2.0

Define the high level operations admitted on the 'Submissions' store.

This operations are intended to leave the state of the store valid as to
invariants found in the specifications.

-}
module Cardano.Wallet.Submissions.Operations
    ( applyOperations
    , Operation (..)
    ) where

import Prelude

import Cardano.Wallet.Submissions.Primitives
    ( Primitive (MoveFinality, MoveTip), applyPrimitive )
import Cardano.Wallet.Submissions.Submissions
    ( Submissions )
import Cardano.Wallet.Submissions.TxStatus
    ( HasTxId (..) )
import Data.Foldable
    ( Foldable (..) )

import qualified Cardano.Wallet.Submissions.Primitives as DP

-- High Level, invariant respectful operations over the 'Submissions' store.
data Operation meta slot tx where
    -- | Insert tx new transaction in the local submission store.
    AddSubmission :: slot -> tx -> meta -> Operation meta slot tx
    -- | Move transactions in the in-ledger state, removing them from
    -- in-submission.
    RollForward
      :: slot -- ^ New tip.
      -> [(slot, tx)] -- ^ Transactions that were found in the ledder.
      -> Operation meta slot tx
    -- | Move transactions from the in-ledger state to in-submission state,
    -- when their acceptance slot falls after the new tip.
    RollBack
      :: slot -- ^ new tip
      -> Operation meta slot tx
    -- | Remove transactions that cannot be rolled back in the ledger
    -- and transaction that cannot make it to the ledger due to expiration
    -- and max rollback time.
    Prune :: slot -> Operation meta slot tx
    -- | Remove a transaction from the tracked set.
    Forget :: tx -> Operation meta slot tx
    deriving (Show)


-- | Apply a high level operation to the submission store.
applyOperations
    :: (Ord slot, Ord (TxId tx), HasTxId tx)
    => Operation meta slot tx
    -> Submissions meta slot tx
    -> Submissions meta slot tx
applyOperations (AddSubmission expiring tx meta)
    = applyPrimitive (DP.AddSubmission expiring tx meta)
applyOperations (RollForward newtip txs) = \x ->
    applyPrimitive (MoveTip newtip)
        . foldl'
            ( \x' (s, tx) ->
                    applyPrimitive (DP.MoveToLedger s tx) x'
            )
            x
        $ txs
applyOperations (RollBack t) = applyPrimitive (MoveTip t)
applyOperations (Prune t) = applyPrimitive (MoveFinality t)
applyOperations (Forget tx) = applyPrimitive (DP.Forget tx)
