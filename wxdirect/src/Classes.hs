-----------------------------------------------------------------------------------------
{-| Module      :  Classes
    Copyright   :  (c) Daan Leijen 2003
    License     :  BSD-style

    Maintainer  :  daan@cs.uu.nl
    Stability   :  provisional
    Portability :  portable

    Defines most of the classes in wxWindows.
-}
-----------------------------------------------------------------------------------------
module Classes( isClassName, isBuiltin, haskellClassDefs
              , objectClassNames, classNames
              , classExtends
              , getWxcDir, setWxcDir
              -- * Class info
              , ClassInfo(..)
              , classInfo
              , classIsManaged
              , findManaged
              , managedClasses
              ) where

import System( getEnv )
import Char( isUpper )
import List( sort, sortBy )
import qualified Set
import qualified Map
import HaskellNames( haskellTypeName, isBuiltin )
import Types

-- to parse a class hierarchy
import Text.ParserCombinators.Parsec
import ParseC( readHeaderFile )

-- unsafe hack :-(
import System.IO.Unsafe( unsafePerformIO )
import Data.IORef



-- urk, ugly hack to make "classes" function pure.
{-# NOINLINE wxcdir #-}
wxcdir :: IORef String
wxcdir
  = unsafePerformIO $
    do newIORef ("../wxc")

getWxcDir :: IO String
getWxcDir
  = readIORef wxcdir

setWxcDir :: String -> IO ()
setWxcDir dir
  = writeIORef wxcdir dir

{-----------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------}
ignoreClasses :: Set.Set String
ignoreClasses
  = Set.fromList ["wxFile", "wxDir", "wxString", "wxManagedPtr"]

classes :: [Class]
classes
  = unsafePerformIO $
    do {-
       xs <- parseClassHierarchy "ClassHierarchy.txt"
       ys <- parseClassHierarchy "ClassHierarchyExtra.txt"
       -}
       -- urk, ugly hack.
       wxcdir <- getWxcDir
       cs <- parseClassDefs (wxcdir ++ "/include/wxc.h")
                           -- ,wxcdir ++ "/include/ewxw/wxc_glue.h"
                           -- ,wxcdir ++ "/include/db.h"
                            
       -- writeFile "wxclasses.def" (showClasses cs)
       return cs
       -- return (mergeClasses xs ys) -- (mergeClasses zs (mergeClasses ys xs))


mergeClasses xs ys
  = foldr (\c cs -> mergeClass c cs) xs ys

mergeClass cls []   = [cls]
mergeClass cls1@(Class name1 subs1)  (cls2@(Class name2 subs2) : cs)
  | name1 == name2  = Class name2 (mergeClasses subs1 subs2) : cs
  | otherwise       = cls2:mergeClass cls1 cs


{-----------------------------------------------------------------------------------------
  Managed classes
-----------------------------------------------------------------------------------------}
data ClassInfo = ClassInfo{ classWxName   :: String
                          , withSelf      :: String -> String
                          , withPtr       :: String
                          , withResult    :: String
                          , withRef       :: String
                          , objDelete     :: String
                          , classTypeName :: String -> String
                          }
                  
classIsManaged :: String -> Bool
classIsManaged name
  = case findManaged name of
      Just info -> True
      Nothing   -> False

classInfo :: String -> ClassInfo
classInfo name
  = case findManaged name of
      Just info -> info
      Nothing   -> standardInfo name

findManaged :: String -> Maybe ClassInfo
findManaged name
  = find managedClasses
  where
    find [] = Nothing
    find (info:rest) | classWxName info == name = Just info
                     | otherwise                = find rest


standardInfo :: String -> ClassInfo
standardInfo name
  = ClassInfo name (\methodName -> "withObjectRef " ++ methodName) "withObjectPtr" "withObjectResult" 
                    "" "objectDelete" (\typevar -> haskellTypeName name ++ " " ++ typevar)

managedClasses :: [ClassInfo]
managedClasses 
  = -- standard reference objects with a distinguished static object. (i.e. wxNullBitmap)
    map standardNull 
    ["Bitmap"
    ,"Cursor"
    ,"Icon"
    ,"Font"
    ,"Pen"
    ,"Brush"
    ] ++

    -- standard reference objects
    map standardRef
    ["Image"
    ,"FontData"
    ,"ListItem"
    ,"PrintData"
    ,"PrintDialogData"
    ,"PageSetupDialogData"] ++

    -- standard reference object, but not a subclass of wxObject
    [ ClassInfo "wxDateTime" (affix "withObjectRef") "withObjectPtr" "withManagedDateTimeResult" 
                    "withRefDateTime" "dateTimeDelete" (affix "DateTime")
    , ClassInfo "wxGridCellCoordsArray" (affix "withObjectRef") "withObjectPtr" 
                    "withManagedGridCellCoordsArrayResult"   
                    "withRefGridCellCoordsArray" "gridCellCoordsArrayDelete" (affix "GridCellCoordsArray")
    ] ++


    -- managed objects (that are not passed by reference)
    map standard
    ["Wave"] ++

    -- translated directly to a Haskell datatype
    [ ClassInfo "wxColour" (affix "withColourRef") "withColourPtr" "withManagedColourResult"
                     "withRefColour" "const (return ())" (const "Color")
    , ClassInfo "wxString" (affix "withStringRef") "withStringPtr" "withManagedStringResult"
                     "withRefString" "const (return ())" (const "String")
    , ClassInfo "wxTreeItemId" (affix "withTreeItemIdRef") "withTreeItemIdPtr" "withManagedTreeItemIdResult"
                     "withRefTreeItemId" "const (return ())" (const "TreeItem")
    ]


  where
    standardNull name
      = (standardRef name){ withResult = "withManaged" ++ name ++ "Result" }

    standardRef name
      = (standard name){ withRef = "withRef" ++ name }

    standard name
      = ClassInfo ("wx" ++ name)  (affix "withObjectRef") "withObjectPtr" "withManagedObjectResult" 
                    "" "objectDelete" (affix name)
        
    affix name arg
      = name ++ " " ++ arg

{-----------------------------------------------------------------------------------------
   Classes
-----------------------------------------------------------------------------------------}
data Class
  = Class String [Class]
  deriving Eq

instance Show Class where
  showsPrec d c
    = showString (showClass 0 c)

showClasses cs
  = unlines (map (showClass 0) cs)

showClass indent (Class name subs)
  = (replicate indent '\t' ++ name ++ concatMap ("\n"++) (map (showClass (indent+1)) subs))

isClassName s
  = Set.member s classNames

objectClassNames :: [String]
objectClassNames
  = case filter isObject classes of
      [classObject] -> -- filter (/="wxColour") $ 
                       flatten classObject
      other         -> []
  where
    flatten (Class name derived)
      = name : concatMap flatten derived

    isObject (Class name derived)
      = (name == "wxObject")


classNames :: Set.Set String
classNames
  = Set.unions (map flatten classes)
  where
    flatten (Class name derived)
      = Set.insert name (Set.unions (map flatten derived))

classExtends :: Map.Map String String
classExtends
  = Map.unions (map (flatten "") classes)
  where
    flatten parent (Class name derived)
      = Map.insert name parent (Map.unions (map (flatten name) derived))


sortClasses :: [Class] -> [Class]
sortClasses cs
  = map sortExtends (sortBy cmp cs)
  where
    cmp (Class name1 _) (Class name2 _) = compare name1 name2

    sortExtends (Class name extends)
      = Class name (sortClasses extends)


haskellClassDefs :: ([(String,[String])],[String])     -- exported, definitions
haskellClassDefs
  = unzip (concatMap (haskellClass []) classes)


haskellClass parents (Class name derived)
--  | isBuiltin name = []   -- handled as a basic type
--  | otherwise
    = ( (tname,[tname,inheritName tname,className tname]) -- ++ (if isBuiltin name then [tname ++ "Object"] else []))
      ,   ({-
           if isBuiltin name
            then ("-- | Pointer to a managed object of type '" ++ tname ++ "'" ++
                  (if null parents then "" else ", derived from '" ++ head parents ++ "'") ++
                  ".\n" ++
                  "type " ++ tname ++ " a  = " ++
                  "Managed " ++ pparens (inheritName tname ++ " a") ++ "\n" ++
                  "-- | Pointer to an (unmanaged) object of type " ++ tname ++ ".\n" ++
                  "type " ++ tname ++ "Object" ++ " a  = " ++ "Object " ++ pparens (inheritName tname ++ " a"))
            else  -}
                  ("-- | Pointer to an object of type '" ++ tname ++ "'" ++
                  (if null parents then "" else ", derived from '" ++ head parents ++ "'") ++
                  ".\n" ++
                  "type " ++ tname ++ " a  = " ++  inheritance)
          ) ++ "\n" ++
        "-- | Inheritance type of the " ++ tname ++ " class.\n" ++
        "type " ++ inheritName tname ++ " a  = " ++ inheritanceType ++ "\n" ++
        "-- | Abstract type of the " ++ tname ++ " class.\n" ++
        "data " ++ className tname ++ " a  = " ++ className tname ++ "\n"
      )
     : concatMap (haskellClass (tname:parents)) derived
  where
    tname         = haskellTypeName name
    className s   = "C" ++ haskellTypeName s
    inheritName s = "T" ++ haskellTypeName s

    explicitInheritance
      = foldl extend (className tname ++ " a") parents
      where
        extend child parent
          = "C"++parent ++ " " ++ pparens child

    inheritanceType
      = (if null parents then id else (\tp -> inheritName (head parents) ++ " " ++ pparens tp))
         (className tname ++ " a")

    inheritance
      = (if null parents then "Object " else (haskellTypeName (head parents) ++ " "))
        ++ pparens (className tname ++ " a")


pparens txt
  = "(" ++ txt ++ ")"


{-----------------------------------------------------------------------------------------
   Read a class hierarchy from file.
   The format consists of all classes on a line,
   with subclassing expressed by putting tabs in front of the class.
   see: http://www.wxwindows.org/classhierarchy.txt
-----------------------------------------------------------------------------------------}
parseClassHierarchy :: FilePath -> IO [Class]
parseClassHierarchy fname
  = do result <- parseFromFile parseClasses (if null fname then "classhierarchy.txt" else fname)
       case result of
         Left err  -> do putStrLn ("parse error in class hierarchy: " ++ show err)
                         return []
         Right cs -> return cs
    `catch` \err ->
     do putStrLn ("exception while parsing: " ++ fname)
        print err
        return []

parseClasses :: Parser [Class]
parseClasses
  = do cs <- pclasses 0
       eof
       return cs

pclasses :: Int -> Parser [Class]
pclasses indent
  = do css <- many (pclass indent)
       return (concat css)
  <?> "classes"

pclass :: Int -> Parser [Class]
pclass indent
  = do try (count indent pindent)
       name <- pclassName
       whiteSpace
       mkClass
            <- (do char '\n'
                   return (\subs -> filterClass (Class name subs))
                <|>
                do name2 <- try $
                             do char '='
                                whiteSpace
                                name2 <- pclassName
                                whiteSpace
                                char '\n'
                                return name2
                   return (\subs -> filterClass (Class name2 subs))
                <|>
                do skipToEndOfLine
                   return (\subs -> []))
       subs <- pclasses (indent+1)
       return (mkClass subs)
  <|>
    do char '\n'
       return []
  <?> "class"


filterClass :: Class -> [Class]
filterClass (Class name subs)
  | not (Set.member name ignoreClasses) = [Class name subs]
filterClass cls
  = []


pindent
  = do{ char '\t'; return ()} <|> do{ count 8 space; return () }
  <?> ""

pclassName
  = many1 alphaNum
  <?> "class name"

skipToEndOfLine
  = do many (noneOf "\n")
       char '\n'

whiteSpace
  = many (oneOf " \t")

{-----------------------------------------------------------------------------------------
  parse class hierarchy from class definitions in a C header files:
  TClassDef(tp)
  TClassDefExtend(tp,parent)
-----------------------------------------------------------------------------------------}
parseClassDefs :: FilePath -> IO [Class]
parseClassDefs fname
  = do putStrLn "reading class definitions:"
       lines  <- readHeaderFile fname
       let defs    = filter (not . null . fst) (map parseClassDef lines)
           extends = Map.fromList defs
           extend name
                   = complete (Class name [])
                   where
                     complete cls@(Class cname ext)
                       = case Map.lookup cname extends of
                           Just ""     -> cls
                           Just parent -> complete (Class parent [cls])
                           Nothing     -> trace ("warning: undefined base class " ++ show cname ++ " in definition of " ++ show name) $
                                          cls
           clss    = map (extend . fst) defs
       return (foldr (\c cs -> mergeClass c cs) [] clss)

parseClassDef :: String -> (String,String)
parseClassDef line
  = case parse pdef "" line of
      Left err  -> ("","")
      Right r   -> r

pdef :: Parser (String,String)
pdef
  = do reserved "TClassDefExtend"
       psymbol "("
       tp <- identifier
       psymbol ","
       ext <- identifier
       psymbol ")"
       return (tp,ext)
  <|>
    do reserved "TClassDef"
       tp <- parens identifier
       return (tp,"")

parens p
  = do{ psymbol "("; x <- p; psymbol ")"; return x }

psymbol s
  = lexeme (string s)

reserved s
  = lexeme (try (string s))

identifier
  = lexeme (many1 alphaNum)

lexeme p
  = do{ x <- p
      ; whiteSpace
      ; return x
      }