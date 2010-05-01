{-# LANGUAGE FlexibleInstances, TypeSynonymInstances, OverloadedStrings #-}
-- | Core exposed functions.
module Text.Blaze
    ( 
      -- * Important types.
      Html
    , Attribute

      -- * Creating custom tags and attributes.
    , parent
    , leaf
    , attribute

      -- * Converting values to HTML.
    , text
    , rawByteString
    , showHtml

      -- * Setting attributes
    , (!)

      -- * Rendering HTML.
    , renderHtml
    ) where

import Data.Monoid (Monoid, mappend, mempty, mconcat)

import Data.Binary.Builder (Builder, toLazyByteString)
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import Data.Text (Text)

import Text.Blaze.Internal.Utf8Builder

-- | The core HTML datatype.
--
newtype HtmlM a = HtmlM
    { -- | Function to extract the 'Builder'.
      --
      runHtml :: Builder -> Builder
    }

-- | Simplification of the 'HtmlM' type.
--
type Html = HtmlM ()

newtype Attribute = Attribute (Html -> Html)

instance Monoid (HtmlM a) where
    mempty = HtmlM $ \_ -> mempty
    {-# INLINE mempty #-}
    (HtmlM h1) `mappend` (HtmlM h2) = HtmlM $
        \attrs -> h1 attrs `mappend` h2 attrs
    {-# INLINE mappend #-}
    mconcat hs = HtmlM $ \attrs ->
        foldr (\h k -> runHtml h attrs `mappend` k) mempty hs
    {-# INLINE mconcat #-}

instance Monad HtmlM where
    return a = mempty
    {-# INLINE return #-}
    (HtmlM h1) >> (HtmlM h2) = HtmlM $
        \attrs -> h1 attrs `mappend` h2 attrs
    {-# INLINE (>>) #-}
    h1 >>= f = h1 >> f (error "_|_")
    {-# INLINE (>>=) #-}

-- | Create an HTML parent element.
--
parent :: S.ByteString -> S.ByteString -> Html -> Html
parent begin end = \inner -> HtmlM $ \attrs ->
    fromEscapedByteString begin
      `mappend` attrs
      `mappend` fromEscapedAscii7Char '>'
      `mappend` runHtml inner mempty
      `mappend` fromEscapedByteString end
{-# INLINE parent #-}

-- | Create an HTML leaf element.
--
leaf :: S.ByteString -> Html
leaf begin = HtmlM $ \attrs ->
    fromEscapedByteString begin
      `mappend` attrs
      `mappend` fromEscapedByteString " />"
{-# INLINE leaf #-}

-- | Add an attribute to the current element.
--
attribute :: S.ByteString -> Text -> Attribute
attribute key value = Attribute $ \(HtmlM h) -> HtmlM $ \attrs ->
    h $ attrs `mappend` (fromEscapedAscii7Char ' '
              `mappend` (fromEscapedByteString key
              `mappend` (fromEscapedByteString "=\""
              `mappend` (fromText value
              `mappend` (fromEscapedAscii7Char '"')))))
{-# INLINE attribute #-}

class Attributable h where
    -- | Apply an attribute on an element.
    --
    (!) :: h -> Attribute -> h

instance Attributable Html where
    h ! (Attribute a) = a h
    {-# INLINE (!) #-}
    {-# SPECIALIZE (!) :: Html -> Attribute -> Html #-}

instance Attributable (Html -> Html) where
    f ! (Attribute a) = \h -> a (f h)
    {-# INLINE (!) #-}
    {-# SPECIALIZE (!) :: (Html -> Html) -> Attribute -> (Html -> Html) #-}

-- | Render escaped text.
--
text :: Text -- ^ Text to render.
     -> Html -- ^ Resulting HTML fragment.
text = HtmlM . const . fromText
{-# INLINE text #-}

-- | Render a raw 'S.ByteString'. This function will not do any HTML escaping,
-- so be careful with it.
--
rawByteString :: S.ByteString -- ^ Raw 'S.ByteString' to render.
              -> Html       -- ^ Resulting HTML fragment.
rawByteString = HtmlM . const . fromEscapedByteString
{-# INLINE rawByteString #-}

-- | Create a HTML snippet from a 'Show'able type.
--
showHtml :: Show a => a -> Html
showHtml = HtmlM . const . fromString . show
{-# INLINE showHtml #-}

-- | /O(n)./ Render the HTML fragment to lazy 'L.ByteString'.
--
renderHtml :: Html -> L.ByteString
renderHtml = toLazyByteString . flip runHtml mempty