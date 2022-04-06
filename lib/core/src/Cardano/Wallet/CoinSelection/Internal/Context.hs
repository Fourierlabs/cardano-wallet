{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
-- This module provides the 'SelectionContext' class, which provides a shared
-- context for types used by coin selection.
--
module Cardano.Wallet.CoinSelection.Internal.Context
    (
    -- * Selection contexts
      SelectionContext (..)
    )
    where

import Prelude

import Fmt
    ( Buildable )
import GHC.Generics
    ( Generic )

-- | Provides a shared context for types used by coin selection.
--
class
    ( Buildable (Address c)
    , Buildable (Asset c)
    , Buildable (UTxO c)
    , Generic (Address c)
    , Generic (Asset c)
    , Generic (UTxO c)
    , Ord (Address c)
    , Ord (Asset c)
    , Ord (UTxO c)
    , Show (Address c)
    , Show (Asset c)
    , Show (UTxO c)
    ) =>
    SelectionContext c
  where

    -- | A target address to which payments can be made.
    type Address c

    -- | A unique identifier for an individual asset.
    type Asset c

    -- | A unique identifier for an individual UTxO.
    type UTxO c

    -- | Generates a dummy address value.
    dummyAddress :: Address c
