{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE RecordWildCards #-}
-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
-- An implementation of the DBPendingTxs which uses Persistent and SQLite.

module Cardano.Wallet.DB.Store.Submissions.New.Layer
    ( mkDbPendingTxs
    )
    where

import Prelude

import Cardano.Wallet
    ( ErrNoSuchWallet (..) )
import Cardano.Wallet.DB
    ( DBPendingTxs (..)
    , ErrNoSuchTransaction (..)
    , ErrPutLocalTxSubmission (..)
    , ErrRemoveTx (..)
    )
import Cardano.Wallet.DB.Sqlite.Types
    ( TxId (..) )
import Cardano.Wallet.DB.Store.Submissions.New.Operations
    ( DeltaTxSubmissions
    , SubmissionMeta (SubmissionMeta, submissionMetaResubmitted)
    , TxSubmissionsStatus
    , submissionMetaFromTxMeta
    )
import Cardano.Wallet.Primitive.Types
    ( WalletId )
import Cardano.Wallet.Primitive.Types.Tx
    ( LocalTxSubmissionStatus (LocalTxSubmissionStatus), SealedTx )
import Cardano.Wallet.Submissions.Operations
    ( Operation (..) )
import Cardano.Wallet.Submissions.Submissions
    ( TxStatusMeta (..), transactions, transactionsL )
import Cardano.Wallet.Submissions.TxStatus
    ( TxStatus (..), getTx, status )
import Control.Lens
    ( to, (^.), (^..) )
import Control.Monad.Except
    ( ExceptT (ExceptT) )
import Data.Bifunctor
    ( second )
import Data.DBVar
    ( DBVar, modifyDBMaybe, readDBVar, updateDBVar )
import Data.DeltaMap
    ( DeltaMap (..) )
import Data.Maybe
    ( fromJust )
import Database.Persist.Sql
    ( SqlPersistT )

import qualified Data.Map.Strict as Map

-- TODO: This implementation is not completed / fully tested yet.
mkDbPendingTxs
    :: DBVar (SqlPersistT IO) (DeltaMap WalletId DeltaTxSubmissions) -- ^
    -> DBPendingTxs (SqlPersistT IO)
mkDbPendingTxs dbvar = DBPendingTxs
    { putLocalTxSubmission_ = \wid txid tx sl -> do
        let errNoSuchWallet = ErrPutLocalTxSubmissionNoSuchWallet $
                ErrNoSuchWallet wid
        ExceptT $ modifyDBMaybe dbvar $ \ws -> do
            case Map.lookup wid ws of
                Nothing -> (Nothing, Left errNoSuchWallet)
                Just _  ->
                    let
                        delta = Just
                            $ Adjust wid
                            $ AddSubmission sl (TxId txid, tx)
                            $ error "pls pass meta to putLocalTxSubmission!"
                    in  (delta, Right ())

    , addTxSubmission_ =  \wid (tx,meta,sealedTx) resubmitted ->
        let expiry = fromJust (meta ^. #expiry)
            -- FIXME ADP-2367: The value 'meta' supplied here is
            -- constructed by 'Cardano.Wallet.mkTxMeta', where this
            -- field is always a 'Just'. In the future, we should
            -- the expiration slot directly from a @tx :: Read.Tx@.
        in  updateDBVar dbvar
                $ Adjust wid
                $ AddSubmission expiry (TxId $ tx ^. #txId, sealedTx)
                $ submissionMetaFromTxMeta meta resubmitted

    , getInSubmissionTransactionInfos_ = \wid -> do
            submissions <- readDBVar dbvar
            pure $ case Map.lookup wid submissions of
                Nothing  -> []
                Just xs -> xs ^.. transactionsL . traverse . to (fmap snd)

    , readLocalTxSubmissionPending_ = \wid -> do
            v <- readDBVar dbvar
            pure $ case Map.lookup wid v of
                Nothing -> []
                Just sub -> do
                    (_k, x) <- Map.assocs $ sub ^. transactionsL
                    mkLocalTxSubmission x

    , rollForwardTxSubmissions_ = \wid tip txs ->
        updateDBVar dbvar
            $ Adjust wid $ RollForward tip (second TxId <$> txs)

    , removePendingOrExpiredTx_ = \wid txId -> do
        let errNoSuchWallet = ErrRemoveTxNoSuchWallet
                $ ErrNoSuchWallet wid
            errNoTx = ErrRemoveTxNoSuchTransaction
                $ ErrNoSuchTransaction wid txId
            errInLedger = ErrRemoveTxAlreadyInLedger txId
        ExceptT $ modifyDBMaybe dbvar $ \ws -> do
            case Map.lookup wid ws of
                Nothing -> (Nothing, Left errNoSuchWallet)
                Just sub ->
                    case status (TxId txId) (transactions sub) of
                        Unknown -> (Nothing, Left errNoTx)
                        InLedger{} -> (Nothing, Left errInLedger)
                        _ -> (Just $ Adjust wid $ Forget (TxId txId), Right ())
    }

mkLocalTxSubmission
    :: TxSubmissionsStatus
    -> [LocalTxSubmissionStatus SealedTx]
mkLocalTxSubmission (TxStatusMeta status' SubmissionMeta{..})
    = maybe
        []
        (\(TxId txId, sealed) -> pure $
            LocalTxSubmissionStatus (txId) sealed submissionMetaResubmitted
        )
        $ getTx status'
