{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Data.DeltaSpec
    ( spec
    ) where

import Prelude

import Data.DBVar
    ( Store (..), newCachedStore, newStore )
import Data.Delta
    ( Delta (..) )
import Fmt
    ( Buildable (..) )
import Test.DBVar
    ( prop_StoreUpdates )
import Test.Hspec
    ( Spec, describe, it, parallel )
import Test.QuickCheck
    ( elements, generate, (===) )
import Test.QuickCheck.Gen
    ( Gen, listOf )
import Test.QuickCheck.Monadic
    ( monadicIO, run )

spec :: Spec
spec = do
    parallel $ describe "Data.Delta" $ do
        it "Dummy test, to be expanded"
            True
    describe "CachedStore" $ do
        it "respects store laws" $ monadicIO $ do
            cachedStore <- run $ do
                testStore <- newStore @TestStoreDelta
                resetTestStoreBase testStore
                newCachedStore testStore
            prop_StoreUpdates run
                cachedStore
                (pure emptyTestStore)
                $ const genTestStoreDeltas
        it "behaves like the cached one" $ monadicIO $ run $ do

            das <- generate $ listOf genTestStoreDeltas

            testStore <- newStore @TestStoreDelta

            cachedStore <- newCachedStore testStore

            resetTestStoreBase testStore
            updateStore cachedStore das
            Right cachedFinal <- loadS cachedStore

            resetTestStoreBase testStore
            updateStore testStore das
            Right originalFinal <- loadS testStore

            pure $ cachedFinal === originalFinal

updateStore :: Monad m => Store m da -> [da] -> m ()
updateStore store = mapM_ (updateS store Nothing)

genTestStoreDeltas :: Gen TestStoreDelta
genTestStoreDeltas = elements [AddOne, AddTwo, RemoveOne]

resetTestStoreBase :: (Base da ~ TestStoreBase) => Store m da -> m ()
resetTestStoreBase store = writeS store emptyTestStore

emptyTestStore :: TestStoreBase
emptyTestStore = TestStoreBase []

newtype TestStoreBase = TestStoreBase [Int]
    deriving (Show, Eq)

data TestStoreDelta
    = AddOne
    | AddTwo
    | RemoveOne

    deriving (Show, Eq)
instance Buildable TestStoreDelta where
    build = build . show

instance Delta TestStoreDelta where
    type Base TestStoreDelta = TestStoreBase
    apply AddOne = overTestStoreBase (1:)
    apply AddTwo = overTestStoreBase (2:)
    apply RemoveOne = overTestStoreBase (drop 1)

overTestStoreBase :: ([Int] -> [Int]) -> TestStoreBase -> TestStoreBase
overTestStoreBase f (TestStoreBase xs) = TestStoreBase (f xs)
