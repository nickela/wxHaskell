{-# OPTIONS -fglasgow-exts -#include "wxc.h" #-}
-----------------------------------------------------------------------------------------
{-| Module      :  Types
    Copyright   :  (c) Daan Leijen 2003
    License     :  BSD-style

    Maintainer  :  daan@cs.uu.nl
    Stability   :  provisional
    Portability :  portable

    Basic types and operations.
-}
-----------------------------------------------------------------------------------------
module Graphics.UI.WXH.Types(
            -- * Objects
              ( # )
            , Object, objectNull, objectIsNull, objectCast
            , Managed, managedNull, managedIsNull, managedCast, createManaged, withManaged, managedTouch

            -- * Identifiers
            , Id, idAny, idCreate

            -- * Bits
            , (.+.), (.-.)
            , bits
            , bitsSet

            -- * Control
            , unitIO, bracket, bracket_, finally, finalize, when

            -- * Variables
            , Var, varCreate, varGet, varSet, varUpdate, varSwap

            -- * Misc.
            , Style
            , EventId

            -- * Basic types

            -- ** Booleans
            , boolFromInt, intFromBool

            -- ** Colors
            , Color, colorRGB, colorRed, colorGreen, colorBlue
            , black, darkgrey, dimgrey, mediumgrey, grey, lightgrey, white
            , red, green, blue
            , cyan, magenta, yellow

            -- ** Points
            , Point(..), pt, pointFromVec, pointFromSize, pointZero, pointNull
            , pointMove, pointMoveBySize, pointAdd, pointSub, pointScale

            -- ** Sizes
            , Size(..), sz, sizeFromPoint, sizeFromVec, sizeZero, sizeNull, sizeEncloses
            , sizeMin, sizeMax

            -- ** Vectors
            , Vector(..), vec, vecFromPoint, vecFromSize, vecZero, vecNull
            , vecNegate, vecOrtogonal, vecAdd, vecSub, vecScale, vecDistance

            -- ** Rectangles
            , Rect(..)
            , topLeft, topRight, bottomLeft, bottomRight, bottom, right
            , rect, rectBetween, rectFromSize, rectZero, rectNull, rectSize, rectIsEmpty
            , rectContains, rectMoveTo, rectFromPoint, rectCentralPoint, rectCentralRect, rectStretchTo
            , rectMove, rectOverlaps, rectsDiff, rectUnion, rectOverlap, rectUnions

            ) where

import List( (\\) )
import Graphics.UI.WXH.WxcTypes
import Graphics.UI.WXH.WxcDefs
import System.IO.Unsafe( unsafePerformIO )

-- utility
import Data.Bits
import Data.IORef
import qualified Control.Exception as CE
import qualified Monad as M


infixl 5 .+.
infixl 5 .-.
infix 5 #

-- | Reverse application. Useful for an object oriented style of programming.
--
-- > (frame # frameSetTitle) "hi"
--
( # ) :: obj -> (obj -> a) -> a
object # method   = method object


{--------------------------------------------------------------------------------
  Bitmasks
--------------------------------------------------------------------------------}
-- | Bitwise /or/ of two bit masks.
(.+.) :: Int -> Int -> Int
(.+.) i j
  = i .|. j

-- | Unset certain bits in a bitmask.
(.-.) :: Int -> BitFlag -> Int
(.-.) i j
  = i .&. complement j

-- | Bitwise /or/ of a list of bit masks.
bits :: [Int] -> Int
bits xs
  = foldr (.+.) 0 xs

-- | (@bitsSet mask i@) tests if all bits in @mask@ are also set in @i@.
bitsSet :: Int -> Int -> Bool
bitsSet mask i
  = (i .&. mask == mask)


{--------------------------------------------------------------------------------
  Id
--------------------------------------------------------------------------------}
{-# NOINLINE varTopId #-}
varTopId :: Var Id
varTopId
  = unsafePerformIO (varCreate (wxID_HIGHEST+1))

-- | When creating a new window you may specify 'idAny' to let wxWindows
-- assign an unused identifier to it automatically. Furthermore, it can be
-- used in an event connection to handle events for any identifier.
idAny :: Id
idAny
  = -1

-- | Create a new unique identifier.
idCreate :: IO Id
idCreate
  = varUpdate varTopId (+1)



{--------------------------------------------------------------------------------
  Control
--------------------------------------------------------------------------------}
-- | Ignore the result of an 'IO' action.
unitIO :: IO a -> IO ()
unitIO io
  = do io; return ()

-- | Perform an action when a test succeeds.
when :: Bool -> IO () -> IO ()
when = M.when

-- | Properly release resources, even in the event of an exception.
bracket :: IO a           -- ^ computation to run first (acquire resource)
           -> (a -> IO b) -- ^ computation to run last (release resource)
           -> (a -> IO c) -- ^ computation to run in-between (use resource)
           -> IO c
bracket = CE.bracket

-- | Specialized variant of 'bracket' where the return value is not required.
bracket_ :: IO a     -- ^ computation to run first (acquire resource)
           -> IO b   -- ^ computation to run last (release resource)
           -> IO c   -- ^ computation to run in-between (use resource)
           -> IO c
bracket_ = CE.bracket_

-- | Run some computation afterwards, even if an exception occurs.
finally :: IO a -- ^ computation to run first
        -> IO b -- ^ computation to run last (release resource)
        -> IO a
finally = CE.finally

-- | Run some computation afterwards, even if an exception occurs. Equals 'finally' but
-- with the arguments swapped.
finalize ::  IO b -- ^ computation to run last (release resource)
          -> IO a -- ^ computation to run first
          -> IO a
finalize last first
  = finally first last

{--------------------------------------------------------------------------------
  Variables
--------------------------------------------------------------------------------}

-- | A mutable variable. Use this instead of 'MVar's or 'IORef's to accomodate for
-- future expansions with possible concurrency.
type Var a  = IORef a

-- | Create a fresh mutable variable.
varCreate :: a -> IO (Var a)
varCreate x    = newIORef x

-- | Get the value of a mutable variable.
varGet :: Var a -> IO a
varGet v    = readIORef v

-- | Set the value of a mutable variable.
varSet :: Var a -> a -> IO ()
varSet v x = writeIORef v x

-- | Swap the value of a mutable variable.
varSwap :: Var a -> a -> IO a
varSwap v x = do prev <- varGet v; varSet v x; return prev

-- | Update the value of a mutable variable and return the old value.
varUpdate :: Var a -> (a -> a) -> IO a
varUpdate v f = do x <- varGet v
                   varSet v (f x)
                   return x



{-----------------------------------------------------------------------------------------
  Point
-----------------------------------------------------------------------------------------}
pointMove :: Vector -> Point -> Point
pointMove (Vector dx dy) (Point x y)
  = Point (x+dx) (y+dy)

pointMoveBySize :: Size -> Point -> Point
pointMoveBySize (Size w h) (Point x y) = Point (x + w) (y + h)

pointAdd :: Point -> Point -> Point
pointAdd (Point x1 y1) (Point x2 y2) = Point (x1+x2) (y1+y2)

pointSub :: Point -> Point -> Point
pointSub (Point x1 y1) (Point x2 y2) = Point (x1-x2) (y1-y2)

pointScale :: Int -> Point -> Point
pointScale v (Point x y) = Point (v*x) (v*y)


{-----------------------------------------------------------------------------------------
  Size
-----------------------------------------------------------------------------------------}
-- | Returns 'True' if the first size totally encloses the second argument.
sizeEncloses :: Size -> Size -> Bool
sizeEncloses (Size w0 h0) (Size w1 h1)
  = (w0 >= w1) && (h0 >= h1)

-- | The minimum of two sizes.
sizeMin :: Size -> Size -> Size
sizeMin (Size w0 h0) (Size w1 h1)
  = Size (min w0 w1) (min h0 h1)

-- | The maximum of two sizes.
sizeMax :: Size -> Size -> Size
sizeMax (Size w0 h0) (Size w1 h1)
  = Size (max w0 w1) (max h0 h1)

{-----------------------------------------------------------------------------------------
  Vector
-----------------------------------------------------------------------------------------}
vecNegate :: Vector -> Vector
vecNegate (Vector x y)
  = Vector (-x) (-y)

vecOrtogonal :: Vector -> Vector
vecOrtogonal (Vector x y) = (Vector y (-x))

vecAdd :: Vector -> Vector -> Vector
vecAdd (Vector x1 y1) (Vector x2 y2) = Vector (x1+x2) (y1+y2)

vecSub :: Vector -> Vector -> Vector
vecSub (Vector x1 y1) (Vector x2 y2) = Vector (x1-x2) (y1-y2)

vecScale :: Int -> Vector -> Vector
vecScale v (Vector x y) = Vector (v*x) (v*y)

vecDistance :: Point -> Point -> Vector
vecDistance (Point x1 y1) (Point x2 y2) = Vector (x2-x1) (y2-y1)

{-----------------------------------------------------------------------------------------
  Rectangle
-----------------------------------------------------------------------------------------}
rectContains :: Point -> Rect -> Bool
rectContains (Point x y) (Rect l t w h)
  = (x >= l && x <= (l+w) && y >= t && y <= (t+h))

rectMoveTo :: Point -> Rect -> Rect
rectMoveTo p r
  = rect p (rectSize r)

rectFromPoint :: Point -> Rect
rectFromPoint (Point x y)
  = Rect x y x y

rectCentralPoint :: Rect -> Point
rectCentralPoint (Rect l t w h)
  = Point (l + div w 2) (t + div h 2)

rectCentralRect :: Rect -> Size -> Rect
rectCentralRect r@(Rect l t rw rh) (Size w h)
  = let c = rectCentralPoint r
    in Rect (px c - (w - div w 2)) (py c - (h - div h 2)) w h


rectStretchTo :: Size -> Rect -> Rect
rectStretchTo (Size w h) (Rect l t _ _)
  = Rect l t w h

rectMove :: Vector -> Rect -> Rect
rectMove (Vector dx dy) (Rect x y w h)
  = Rect (x+dx) (y+dy) w h

rectOverlaps :: Rect -> Rect -> Bool
rectOverlaps (Rect x1 y1 w1 h1) (Rect x2 y2 w2 h2)
  = (x1+w1 >= x2 && x1 <= x2+w2) && (y1+h1 >= y2 && y1 <= y2+h2)

rectsDiff :: Rect -> Rect -> [Rect]
rectsDiff rect1 rect2
  = subtractFittingRect rect1 (rectOverlap rect1 rect2)
  where
    -- subtractFittingRect r1 r2 subtracts r2 from r1 assuming that r2 fits inside r1
    subtractFittingRect :: Rect -> Rect -> [Rect]
    subtractFittingRect r1 r2 =
            filter (not . rectIsEmpty)
                    [ rectBetween (topLeft r1) (topRight r2)
                    , rectBetween (pt (left r1) (top r2)) (bottomLeft r2)
                    , rectBetween (pt (left r1) (bottom r2)) (pt (right r2) (bottom r1))
                    , rectBetween (topRight r2) (bottomRight r1)
                    ]

rectUnion :: Rect -> Rect -> Rect
rectUnion r1 r2
  = rectBetween (pt (min (left r1) (left r2)) (min (top r1) (top r2)))
         (pt (max (right r1) (right r2)) (max (bottom r1) (bottom r2)))

rectUnions :: [Rect] -> Rect
rectUnions []
  = rectZero
rectUnions (r:rs)
  = foldr rectUnion r rs

rectOverlap :: Rect -> Rect -> Rect
rectOverlap r1 r2
  | rectOverlaps r1 r2  = rectBetween (pt (max (left r1) (left r2)) (max (top r1) (top r2)))
                               (pt (min (right r1) (right r2)) (min (bottom r1) (bottom r2)))
  | otherwise           = rectZero


{-----------------------------------------------------------------------------------------
 Default colors.
-----------------------------------------------------------------------------------------}
black, darkgrey, dimgrey, mediumgrey, grey, lightgrey, white :: Color
red, green, blue :: Color
cyan, magenta, yellow :: Color

black     = colorRGB 0x00 0x00 0x00
darkgrey  = colorRGB 0x2F 0x2F 0x2F
dimgrey   = colorRGB 0x54 0x54 0x54
mediumgrey= colorRGB 0x64 0x64 0x64
grey      = colorRGB 0x80 0x80 0x80
lightgrey = colorRGB 0xC0 0xC0 0xC0
white     = colorRGB 0xFF 0xFF 0xFF

red       = colorRGB 0xFF 0x00 0x00
green     = colorRGB 0x00 0xFF 0x00
blue      = colorRGB 0x00 0x00 0xFF

yellow    = colorRGB 0xFF 0xFF 0x00
magenta   = colorRGB 0xFF 0x00 0xFF
cyan      = colorRGB 0x00 0xFF 0xFF