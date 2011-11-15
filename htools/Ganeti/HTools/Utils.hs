{-| Utility functions. -}

{-

Copyright (C) 2009, 2010, 2011 Google Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301, USA.

-}

module Ganeti.HTools.Utils
    (
      debug
    , debugFn
    , debugXy
    , sepSplit
    , stdDev
    , if'
    , select
    , applyIf
    , commaJoin
    , readEitherString
    , JSRecord
    , loadJSArray
    , fromObj
    , fromObjWithDefault
    , maybeFromObj
    , tryFromObj
    , fromJVal
    , asJSObject
    , asObjectList
    , fromJResult
    , tryRead
    , formatTable
    , annotateResult
    , defaultGroupID
    , parseUnit
    ) where

import Data.Char (toUpper)
import Data.List
import qualified Text.JSON as J

import Debug.Trace

import Ganeti.HTools.Types
-- we will re-export these for our existing users
import Ganeti.HTools.JSON

-- * Debug functions

-- | To be used only for debugging, breaks referential integrity.
debug :: Show a => a -> a
debug x = trace (show x) x

-- | Displays a modified form of the second parameter before returning
-- it.
debugFn :: Show b => (a -> b) -> a -> a
debugFn fn x = debug (fn x) `seq` x

-- | Show the first parameter before returning the second one.
debugXy :: Show a => a -> b -> b
debugXy = seq . debug

-- * Miscellaneous

-- | Apply the function if condition holds, otherwise use default value.
applyIf :: Bool -> (a -> a) -> a -> a
applyIf b f x = if b then f x else x

-- | Comma-join a string list.
commaJoin :: [String] -> String
commaJoin = intercalate ","

-- | Split a list on a separator and return an array.
sepSplit :: Eq a => a -> [a] -> [[a]]
sepSplit sep s
    | null s    = []
    | null xs   = [x]
    | null ys   = [x,[]]
    | otherwise = x:sepSplit sep ys
    where (x, xs) = break (== sep) s
          ys = drop 1 xs

-- * Mathematical functions

-- Simple and slow statistical functions, please replace with better
-- versions

-- | Standard deviation function.
stdDev :: [Double] -> Double
stdDev lst =
  -- first, calculate the list length and sum lst in a single step,
  -- for performance reasons
  let (ll', sx) = foldl' (\(rl, rs) e ->
                           let rl' = rl + 1
                               rs' = rs + e
                           in rl' `seq` rs' `seq` (rl', rs')) (0::Int, 0) lst
      ll = fromIntegral ll'::Double
      mv = sx / ll
      av = foldl' (\accu em -> let d = em - mv in accu + d * d) 0.0 lst
  in sqrt (av / ll) -- stddev

-- *  Logical functions

-- Avoid syntactic sugar and enhance readability. These functions are proposed
-- by some for inclusion in the Prelude, and at the moment they are present
-- (with various definitions) in the utility-ht package. Some rationale and
-- discussion is available at <http://www.haskell.org/haskellwiki/If-then-else>

-- | \"if\" as a function, rather than as syntactic sugar.
if' :: Bool -- ^ condition
    -> a    -- ^ \"then\" result
    -> a    -- ^ \"else\" result
    -> a    -- ^ \"then\" or "else" result depending on the condition
if' True x _ = x
if' _    _ y = y

-- | Return the first result with a True condition, or the default otherwise.
select :: a            -- ^ default result
       -> [(Bool, a)]  -- ^ list of \"condition, result\"
       -> a            -- ^ first result which has a True condition, or default
select def = maybe def snd . find fst


-- | Annotate a Result with an ownership information.
annotateResult :: String -> Result a -> Result a
annotateResult owner (Bad s) = Bad $ owner ++ ": " ++ s
annotateResult _ v = v

-- | Try to extract a key from a object with better error reporting
-- than fromObj.
tryFromObj :: (J.JSON a) =>
              String     -- ^ Textual "owner" in error messages
           -> JSRecord   -- ^ The object array
           -> String     -- ^ The desired key from the object
           -> Result a
tryFromObj t o = annotateResult t . fromObj o


-- * Parsing utility functions

-- | Parse results from readsPrec.
parseChoices :: (Monad m, Read a) => String -> String -> [(a, String)] -> m a
parseChoices _ _ ((v, ""):[]) = return v
parseChoices name s ((_, e):[]) =
    fail $ name ++ ": leftover characters when parsing '"
           ++ s ++ "': '" ++ e ++ "'"
parseChoices name s _ = fail $ name ++ ": cannot parse string '" ++ s ++ "'"

-- | Safe 'read' function returning data encapsulated in a Result.
tryRead :: (Monad m, Read a) => String -> String -> m a
tryRead name s = parseChoices name s $ reads s

-- | Format a table of strings to maintain consistent length.
formatTable :: [[String]] -> [Bool] -> [[String]]
formatTable vals numpos =
    let vtrans = transpose vals  -- transpose, so that we work on rows
                                 -- rather than columns
        mlens = map (maximum . map length) vtrans
        expnd = map (\(flds, isnum, ml) ->
                         map (\val ->
                                  let delta = ml - length val
                                      filler = replicate delta ' '
                                  in if delta > 0
                                     then if isnum
                                          then filler ++ val
                                          else val ++ filler
                                     else val
                             ) flds
                    ) (zip3 vtrans numpos mlens)
   in transpose expnd

-- | Default group UUID (just a string, not a real UUID).
defaultGroupID :: GroupID
defaultGroupID = "00000000-0000-0000-0000-000000000000"

-- | Tries to extract number and scale from the given string.
--
-- Input must be in the format NUMBER+ SPACE* [UNIT]. If no unit is
-- specified, it defaults to MiB. Return value is always an integral
-- value in MiB.
parseUnit :: (Monad m, Integral a, Read a) => String -> m a
parseUnit str =
    -- TODO: enhance this by splitting the unit parsing code out and
    -- accepting floating-point numbers
    case reads str of
      [(v, suffix)] ->
          let unit = dropWhile (== ' ') suffix
              upper = map toUpper unit
              siConvert x = x * 1000000 `div` 1048576
          in case () of
               _ | null unit -> return v
                 | unit == "m" || upper == "MIB" -> return v
                 | unit == "M" || upper == "MB"  -> return $ siConvert v
                 | unit == "g" || upper == "GIB" -> return $ v * 1024
                 | unit == "G" || upper == "GB"  -> return $ siConvert
                                                    (v * 1000)
                 | unit == "t" || upper == "TIB" -> return $ v * 1048576
                 | unit == "T" || upper == "TB"  -> return $
                                                    siConvert (v * 1000000)
                 | otherwise -> fail $ "Unknown unit '" ++ unit ++ "'"
      _ -> fail $ "Can't parse string '" ++ str ++ "'"
