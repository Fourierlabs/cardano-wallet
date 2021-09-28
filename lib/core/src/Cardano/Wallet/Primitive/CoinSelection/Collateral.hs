{- HLINT ignore "Evaluate" -}

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

-- |
-- Copyright: © 2021 IOHK
-- License: Apache-2.0
--
-- Provides functions for selecting coins for use as collateral from a UTxO
-- set.
--
-- See the documentation for 'performSelection' for more details.
--
module Cardano.Wallet.Primitive.CoinSelection.Collateral
    (
    -- * Public API

      performSelection
    , PerformSelection
    , SelectionParams (..)
    , SelectionResult (..)
    , SelectionError (..)
    , SearchSpaceLimit (..)

    -- * Internal API

    -- ** Selecting collateral by giving priority to smallest values first
    , selectCollateralSmallest

    -- ** Selecting collateral by giving priority to largest values first
    , selectCollateralLargest

    -- ** Guarding search space size
    , SearchSpaceRequirement (..)
    , guardSearchSpaceSize

    -- ** Generating submaps
    , submaps

    -- ** Generating subsequences
    , subsequencesOfSize
    , numberOfSubsequencesOfSize

    -- ** Control flow
    , firstRight
    , takeUntil
    )
    where

import Cardano.Wallet.Primitive.Types.Coin
    ( Coin )
import Data.Function
    ( (&) )
import Data.List.NonEmpty
    ( NonEmpty )
import Data.Map.Strict
    ( Map )
import Data.Maybe
    ( listToMaybe, mapMaybe )
import Data.Ord
    ( Down (..) )
import Data.Semigroup
    ( sconcat )
import Data.Set
    ( Set )
import GHC.Generics
    ( Generic )

import Prelude

import qualified Data.Foldable as F
import qualified Data.List as L
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Math.Combinatorics.Exact.Binomial as MathExact
import qualified Numeric.SpecFunctions as MathFast

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

type PerformSelection inputId =
    SelectionParams inputId ->
    Either (SelectionError inputId) (SelectionResult inputId)

-- | Specifies the parameters for selecting collateral.
--
data SelectionParams inputId = SelectionParams
    { coinsAvailable
        :: Map inputId Coin
        -- ^ The set of all coins available for selection as collateral.
    , maximumSelectionSize
        :: Int
        -- ^ An upper bound on the number of unique coins that can be selected
        -- as collateral.
    , minimumSelectionAmount
        :: Coin
        -- ^ A lower bound on the sum of coins to be selected as collateral.
    , searchSpaceLimit
        :: SearchSpaceLimit
        -- ^ An upper bound on the search space size, to protect the wallet
        -- against computations that use excessive amounts of time or space.
    }
    deriving (Eq, Generic, Show)

-- | Specifies an upper bound on the search space size.
--
data SearchSpaceLimit
    = SearchSpaceLimit Int
    -- ^ Specifies an upper bound on the number of coin combinations that can
    -- be considered in any single step.
    | UnsafeNoSearchSpaceLimit
    -- ^ Specifies that there is no search space limit. This should only be
    -- used for testing purposes.
    deriving (Eq, Show)

-- | Represents a successful selection of collateral.
--
newtype SelectionResult inputId = SelectionResult
    { coinsSelected :: Map inputId Coin
        -- ^ The coins that were selected for collateral.
    }
    deriving (Eq, Generic, Show)

-- | Represents an unsuccessful attempt to select collateral.
--
newtype SelectionError inputId = SelectionError
    { largestCombinationAvailable :: Map inputId Coin
        -- ^ The largest combination of coins available.
    }
    deriving (Eq, Generic, Show)

-- | Selects coins for collateral.
--
-- This function tries two strategies in the following order, picking the first
-- strategy that succeeds:
--
--    1. Attempt to select an amount of collateral that is as small as possible.
--    2. Attempt to select collateral from the largest coins available.
--
-- The first strategy, given unlimited computation time, will always produce an
-- optimal result: the smallest possible amount of collateral. However, if the
-- required search space is large, and if the 'searchSpaceLimit' parameter is
-- set to a value that's smaller than the required search space size, then this
-- strategy will fail without computing a result.
--
-- The second strategy sacrifices optimality and always produces a result if
-- one is available, by looking only at the very largest coins available. This
-- result can be computed very quickly, without using much search space.
--
-- The combination of these two strategies means that we can satisfy the
-- following properties:
--
-- If the attempt to select collateral succeeds:
--
--    >>> sum  coinsSelected ≥ minimumSelectionAmount
--    >>> size coinsSelected ≤ maximumSelectionSize
--    >>>      coinsSelected ⊆ coinsAvailable
--
-- If the attempt to select collateral fails:
--
--    >>> sum  largestCombinationAvailable < minimumSelectionAmount
--    >>> size largestCombinationAvailable ≤ maximumSelectionSize
--    >>>      largestCombinationAvailable ⊆ coinsAvailable
--
performSelection :: forall inputId. Ord inputId => PerformSelection inputId
performSelection =
    firstRight
        [ selectCollateralSmallest
        , selectCollateralLargest
        ]

--------------------------------------------------------------------------------
-- Internal API
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Selecting collateral by giving priority to smallest values first
--------------------------------------------------------------------------------

-- | Attempts to select an amount of collateral that is as small as possible.
--
-- This function, given unlimited computation time, will always produce an
-- optimal result: the smallest possible amount of collateral. However, if the
-- required search space is large, and if the 'searchSpaceLimit' parameter is
-- set to a value that's smaller than the required search space size, then this
-- function will return without computing a result.
--
selectCollateralSmallest
    :: forall inputId. Ord inputId => PerformSelection inputId
selectCollateralSmallest params =
    case smallestValidCombination of
        Just coinsSelected ->
            Right SelectionResult {coinsSelected}
        Nothing ->
            Left (SelectionError mempty)
  where
    coinsToConsider :: [(inputId, Coin)]
    coinsToConsider = coinsAvailable
        & Map.toList
        & L.sortOn snd
        & takeUntil ((>= minimumSelectionAmount) . snd)

    numberOfCoinsToConsider :: Int
    numberOfCoinsToConsider = length coinsToConsider

    smallestValidCombination :: Maybe (Map inputId Coin)
    smallestValidCombination =
        listToMaybe $ L.sortOn F.fold validCombinations
      where
        validCombinations :: [Map inputId Coin]
        validCombinations =
            mapMaybe smallestValidCombinationOfSize
            [1 .. maximumSelectionSize]

    smallestValidCombinationOfSize :: Int -> Maybe (Map inputId Coin)
    smallestValidCombinationOfSize size =
        guardSearchSpaceSize searchSpaceRequirement searchSpaceLimit result
      where
        result :: Maybe (Map inputId Coin)
        result = coinsToConsider
            & (`subsequencesOfSize` size)
            & fmap (\ics -> (ics, F.foldMap snd ics))
            & L.sortOn snd
            & L.dropWhile ((< minimumSelectionAmount) . snd)
            & listToMaybe
            & fmap (Map.fromList . fst)

        searchSpaceRequirement :: SearchSpaceRequirement
        searchSpaceRequirement = maybe
            SearchSpaceRequirementUnknown
            SearchSpaceRequirement
            (numberOfCoinsToConsider `numberOfSubsequencesOfSize` size)

    SelectionParams
        { coinsAvailable
        , maximumSelectionSize
        , minimumSelectionAmount
        , searchSpaceLimit
        } = params

--------------------------------------------------------------------------------
-- Selecting collateral by giving priority to largest values first
--------------------------------------------------------------------------------

-- | Selects collateral from the largest coins available.
--
-- This function sacrifices optimality and always produces a result if one is
-- available, by looking only at the very largest coins available.
--
-- This result can be computed very quickly, without using much search space.
--
selectCollateralLargest
    :: forall inputId. Ord inputId => PerformSelection inputId
selectCollateralLargest params =
    case smallestValidSubmapOfLargestCombinationAvailable of
        Just coinsSelected ->
            Right SelectionResult {coinsSelected}
        Nothing ->
            Left SelectionError {largestCombinationAvailable}
  where
    largestCombinationAvailable :: Map inputId Coin
    largestCombinationAvailable =
        coinsAvailable
            & Map.toList
            & L.sortOn (Down . snd)
            & L.take maximumSelectionSize
            & Map.fromList

    smallestValidSubmapOfLargestCombinationAvailable :: Maybe (Map inputId Coin)
    smallestValidSubmapOfLargestCombinationAvailable =
        largestCombinationAvailable
            & submaps
            & Set.toList
            & fmap (\ics -> (ics, F.fold ics))
            & L.sortOn snd
            & L.dropWhile ((< minimumSelectionAmount) . snd)
            & fmap fst
            & listToMaybe

    SelectionParams
        { coinsAvailable
        , maximumSelectionSize
        , minimumSelectionAmount
        } = params

--------------------------------------------------------------------------------
-- Generating submaps
--------------------------------------------------------------------------------

-- | Generates all submaps of a given map.
--
-- This function is analogous to 'Set.powerSet'.
--
-- For a map 'm' of size 'n', this function will generate all possible submaps,
-- including the empty map and the original map 'm'.
--
submaps :: forall a b. (Ord a, Ord b) => Map a b -> Set (Map a b)
submaps m = Set.map (Map.restrictKeys m) (Set.powerSet (Map.keysSet m))

--------------------------------------------------------------------------------
-- Guarding search space size
--------------------------------------------------------------------------------

data SearchSpaceRequirement
    = SearchSpaceRequirement Int
      -- ^ Indicates a known search space requirement.
    | SearchSpaceRequirementUnknown
      -- ^ Indicates that the search space requirement is unknown.

guardSearchSpaceSize
    :: SearchSpaceRequirement
    -- ^ The search space requirement
    -> SearchSpaceLimit
    -- ^ The search space limit
    -> Maybe a
    -- ^ A computation that potentially yields a value
    -> Maybe a
    -- ^ The guarded computation
guardSearchSpaceSize requirement limit =
    case requirement of
        -- When the search space requirement is unknown, err on the side of
        -- caution and avoid evaluating the computation, unless the caller
        -- has explicitly specified that there is no limit:
        SearchSpaceRequirementUnknown ->
            case limit of
                SearchSpaceLimit _       -> const Nothing
                UnsafeNoSearchSpaceLimit -> id
        -- When the search space requirement is known, only evaluate the
        -- computation if the requirement is not greater than the limit:
        SearchSpaceRequirement r ->
            case limit of
                SearchSpaceLimit l | l < r -> const Nothing
                SearchSpaceLimit _         -> id
                UnsafeNoSearchSpaceLimit   -> id

--------------------------------------------------------------------------------
-- Generating subsequences
--------------------------------------------------------------------------------

-- | Computes the number of subsequences generated by 'subsequencesOfSize'.
--
-- This function can be used to determine whether calling 'subsequencesOfSize'
-- would use an excessive amount of time and space, and if so, avoid calling
-- it.
--
-- Returns 'Nothing' if the result is larger than 'maxBound :: Int'.
--
numberOfSubsequencesOfSize
    :: Int
    -- ^ Indicates the size of the sequence.
    -> Int
    -- ^ Indicates the size of subsequences.
    -> Maybe Int
numberOfSubsequencesOfSize n k
    | k <  0 || n <   0      = Nothing
    | k == 0 || k ==  n      = Just 1
    | k == 1 || k == (n - 1) = Just n
    | resultOutOfBounds      = Nothing
    | otherwise              = Just (fromIntegral resultExact)
  where
    resultExact :: Integer
    resultExact = MathExact.choose
        (fromIntegral @Int @Integer n)
        (fromIntegral @Int @Integer k)

    resultFast :: Integer
    resultFast = floor (MathFast.choose n k)

    resultOutOfBounds :: Bool
    resultOutOfBounds = False
        || resultFast  < 0
        || resultFast  > fromIntegral @Int @Integer (maxBound @Int)
        || resultExact < 0
        || resultExact > fromIntegral @Int @Integer (maxBound @Int)

-- | Generates all subsequences of size 'k' from a particular sequence.
--
-- Warning: this function can use an excessive amount of time and space.
--
-- To check how many results would be returned without actually generating
-- them, use the 'numberOfSubsequencesOfSize' function.
--
-- Properties:
--
--    >>> all (== k) (length <$> xs `subsequencesOfSize` k)
--
--    >>> length (xs `subsequencesOfSize` k) ==
--    >>>     length xs `numberOfSubsequencesOfSize` k
--
subsequencesOfSize
    :: [a]
    -- ^ The sequence from which to generate subsequences.
    -> Int
    -- ^ The size 'k' of subsequences to generate.
    -> [[a]]
    -- ^ All subsequences of size 'k'.
subsequencesOfSize xs k
    | k <= 0 =
        []
    | k > length xs =
        []
    | otherwise =
        case drop k (subsequencesBySize xs) of
            result : _ -> result
            [] -> []
  where
    subsequencesBySize [] = [[[]]]
    subsequencesBySize (y : ys) =
        zipWith
            (++)
            ([] : map (map (y :)) next)
            (next ++ [[]])
      where
        next = subsequencesBySize ys

--------------------------------------------------------------------------------
-- Control flow
--------------------------------------------------------------------------------

-- | Applies a sequence of functions to an argument until one succeeds.
--
-- This function iterates through the specified sequence from left to right,
-- applying each function to the given argument, and returning the very first
-- 'Right' result encountered, without evaluating the subsequent functions.
--
-- If none of the given functions produces a 'Right' result, then this function
-- returns the 'Left' result produced by the last function in the sequence.
--
firstRight :: NonEmpty (a -> Either e r) -> (a -> Either e r)
firstRight = sconcat

-- | Takes items from a list until a predicate becomes true.
--
-- The returned list is a prefix of the original list, and includes the very
-- first item that satisfies the predicate.
--
takeUntil :: (a -> Bool) -> [a] -> [a]
takeUntil p = foldr (\x ys -> x : if p x then [] else ys) []
