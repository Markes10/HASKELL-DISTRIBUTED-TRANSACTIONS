{-# LANGUAGE RecordWildCards #-}

-- ============================================================================
-- High-Assurance Distributed Transaction Platform
-- Language: Haskell (GHC 9.x)
-- Domain: Distributed 2-Phase Commit (2PC) & STM Transaction Management
-- ============================================================================

module DistributedTransactions
    ( TxId
    , TxStatus(..)
    , Vote(..)
    , Participant(..)
    , Coordinator(..)
    , executeTwoPhaseCommit
    ) where

import Control.Concurrent.STM
import Control.Monad (forM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

type TxId = String
type AccountId = String
type Balance = Double

data Vote = VoteCommit | VoteAbort String deriving (Show, Eq)
data TxStatus = TxPending | TxCommitted | TxAborted String deriving (Show, Eq)

data Participant = Participant
    { partId      :: String
    , balanceRef  :: TVar Balance
    , prepareTx   :: TxId -> Balance -> STM Vote
    , commitTx    :: TxId -> STM ()
    , abortTx     :: TxId -> STM ()
    }

data Coordinator = Coordinator
    { coordId      :: String
    , participants :: [Participant]
    }

executeTwoPhaseCommit :: Coordinator -> TxId -> [(String, Balance)] -> IO TxStatus
executeTwoPhaseCommit Coordinator{..} txId transfers = do
    -- Phase 1: Prepare & Collect Votes atomically
    votes <- atomically $ forM transfers $ \(pId, amount) -> do
        case filter (\p -> partId p == pId) participants of
            [] -> return (VoteAbort "Participant not registered")
            (p:_) -> prepareTx p txId amount

    let allCommitted = all (== VoteCommit) votes

    -- Phase 2: Decision Broadcast
    if allCommitted
        then do
            atomically $ forM_ participants (\p -> commitTx p txId)
            return TxCommitted
        else do
            let abortReason = head [reason | VoteAbort reason <- votes]
            atomically $ forM_ participants (\p -> abortTx p txId)
            return (TxAborted abortReason)
  where
    forM_ = flip mapM
