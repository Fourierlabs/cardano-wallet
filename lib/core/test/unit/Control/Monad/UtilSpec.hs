{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}

-- |
-- Copyright: © 2022 IOHK
-- License: Apache-2.0
--
module Control.Monad.UtilSpec
    ( spec
    )
    where

import Prelude

import Control.Monad
    ( (<=<) )
import Control.Monad.Identity
    ( Identity (..) )
import Control.Monad.Util
    ( applyNM )
import Data.Function
    ( (&) )
import Data.Function.Utils
    ( applyN )
import Test.Hspec
    ( Spec, describe, it )
import Test.QuickCheck
    ( Fun (..), Property, applyFun, conjoin, property, (===) )

spec :: Spec
spec = describe "Control.Monad.UtilSpec" $ do

    describe "applyNM" $ do
        it "prop_applyNM_applyN" $
            prop_applyNM_applyN @Int & property
        it "prop_applyNM_unit @Identity" $
            prop_applyNM_unit @Identity @Int & property
        it "prop_applyNM_unit @Maybe" $
            prop_applyNM_unit @Maybe @Int & property
        it "prop_applyNM_unit @[]" $
            prop_applyNM_unit @[] @Int & property

--------------------------------------------------------------------------------
-- applyNM
--------------------------------------------------------------------------------

prop_applyNM_applyN
    :: (Eq a, Show a) => Int -> Fun a a -> a -> Property
prop_applyNM_applyN n (applyFun -> f) a =
    applyNM n (Identity <$> f) a === Identity (applyN n f a)

prop_applyNM_unit
    :: (Monad m, Eq (m a), Show (m a)) => Fun a (m a) -> a -> Property
prop_applyNM_unit (applyFun -> f) a = conjoin
    [ applyNM 0 f a === pure a
    , applyNM 1 f a === f a
    , applyNM 2 f a === (f <=< f) a
    , applyNM 3 f a === (f <=< f <=< f) a
    ]
