{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}

-- | This module provides facilities for patching incoming 'Requests' to
-- correct the value of 'rqClientAddr' if the snap server is running behind a
-- proxy.
--
-- Example usage:
--
-- @
-- m :: Snap ()
-- m = undefined  -- code goes here
--
-- applicationHandler :: Snap ()
-- applicationHandler = behindProxy X_Forwarded_For m
-- @
--
module Snap.Util.Proxy
  ( ProxyType(..)
  , behindProxy
  ) where

------------------------------------------------------------------------------
import           Control.Applicative   (Alternative ((<|>)))
import           Control.Arrow         (second)
import qualified Data.ByteString.Char8 as S (break, breakEnd, drop, dropWhile, readInt, spanEnd)
import           Data.Char             (isSpace)
import           Data.Maybe            (fromJust)
import           Snap.Core             (MonadSnap, Request (rqClientAddr, rqClientPort), getHeader, modifyRequest)
#if !MIN_VERSION_base(4,8,0)
import           Control.Applicative   ((<$>))
#endif
------------------------------------------------------------------------------


------------------------------------------------------------------------------
-- | What kind of proxy is this? Affects which headers 'behindProxy' pulls the
-- original remote address from.
--
-- Currently only proxy servers that send @X-Forwarded-For@ or @Forwarded-For@
-- are supported.
data ProxyType = NoProxy          -- ^ no proxy, leave the request alone
               | X_Forwarded_For  -- ^ Use the @Forwarded-For@ or
                                  --   @X-Forwarded-For@ header
  deriving (Read, Show, Eq, Ord)


------------------------------------------------------------------------------
-- | Rewrite 'rqClientAddr' if we're behind a proxy.
--
-- Example:
--
-- @
-- ghci> :set -XOverloadedStrings
-- ghci> import qualified "Data.Map" as M
-- ghci> import qualified "Snap.Test" as T
-- ghci> let r = T.get \"\/foo\" M.empty >> T.addHeader \"X-Forwarded-For\" \"1.2.3.4\"
-- ghci> let h = 'Snap.Core.getsRequest' 'rqClientAddr' >>= 'Snap.Core.writeBS')
-- ghci> T.runHandler r h
-- HTTP\/1.1 200 OK
-- server: Snap\/test
-- date: Fri, 08 Aug 2014 14:32:29 GMT
--
-- 127.0.0.1
-- ghci> T.runHandler r ('behindProxy' 'X_Forwarded_For' h)
-- HTTP\/1.1 200 OK
-- server: Snap\/test
-- date: Fri, 08 Aug 2014 14:33:02 GMT
--
-- 1.2.3.4
-- @
behindProxy :: MonadSnap m => ProxyType -> m a -> m a
behindProxy NoProxy         = id
behindProxy X_Forwarded_For = ((modifyRequest xForwardedFor) >>)
{-# INLINE behindProxy #-}


------------------------------------------------------------------------------
xForwardedFor :: Request -> Request
xForwardedFor req = req { rqClientAddr = ip
                        , rqClientPort = port
                        }
  where
    proxyString  = getHeader "Forwarded-For"   req <|>
                   getHeader "X-Forwarded-For" req <|>
                   Just (rqClientAddr req)

    proxyAddr    = trim . snd . S.breakEnd (== ',') . fromJust $ proxyString

    trim         = fst . S.spanEnd isSpace . S.dropWhile isSpace

    (ip,portStr) = second (S.drop 1) . S.break (== ':') $ proxyAddr

    port         = fromJust (fst <$> S.readInt portStr <|>
                             Just (rqClientPort req))
{-# INLINE xForwardedFor #-}
