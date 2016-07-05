{- |
    Wuss is a library that lets you easily create secure WebSocket clients over
    the WSS protocol. It is a small addition to
    <https://hackage.haskell.org/package/websockets the websockets package>
    and is adapted from existing solutions by
    <https://gist.github.com/jaspervdj/7198388 @jaspervdj>,
    <https://gist.github.com/mpickering/f1b7ba3190a4bb5884f3 @mpickering>, and
    <https://gist.github.com/elfenlaid/7b5c28065e67e4cf0767 @elfenlaid>.

    == Example

    > import Wuss
    >
    > import Control.Concurrent (forkIO)
    > import Control.Monad (forever, unless, void)
    > import Data.Text (Text, pack)
    > import Network.WebSockets (ClientApp, receiveData, sendClose, sendTextData)
    >
    > main :: IO ()
    > main = runSecureClient "echo.websocket.org" 443 "/" ws
    >
    > ws :: ClientApp ()
    > ws connection = do
    >     putStrLn "Connected!"
    >
    >     void . forkIO . forever $ do
    >         message <- receiveData connection
    >         print (message :: Text)
    >
    >     let loop = do
    >             line <- getLine
    >             unless (null line) $ do
    >                 sendTextData connection (pack line)
    >                 loop
    >     loop
    >
    >     sendClose connection (pack "Bye!")
-}
module Wuss
    ( runSecureClient
    , runSecureClientWith
    ) where

import qualified Data.ByteString as StrictBytes
import qualified Data.ByteString.Lazy as LazyBytes
import qualified Network.Connection as Connection
import qualified Network.Socket as Socket
import qualified Network.WebSockets as WebSockets
import qualified Network.WebSockets.Stream as Stream

{- |
    A secure replacement for 'Network.WebSockets.runClient'.

    >>> let app _connection = return ()
    >>> runSecureClient "echo.websocket.org" 443 "/" app
-}
runSecureClient
    :: Socket.HostName -- ^ Host
    -> Socket.PortNumber -- ^ Port
    -> String -- ^ Path
    -> WebSockets.ClientApp a -- ^ Application
    -> IO a
runSecureClient host port path app =
    let options = WebSockets.defaultConnectionOptions
        headers = []
    in  runSecureClientWith host port path options headers app

{- |
    A secure replacement for 'Network.WebSockets.runClientWith'.

    >>> let options = defaultConnectionOptions
    >>> let headers = []
    >>> let app _connection = return ()
    >>> runSecureClientWith "echo.websocket.org" 443 "/" options headers app

    If you want to run a secure client without certificate validation, use
    'Network.WebSockets.runClientWithStream'. For example:

    > let host = "echo.websocket.org"
    > let port = 443
    > let path = "/"
    > let options = defaultConnectionOptions
    > let headers = []
    > let tlsSettings = TLSSettingsSimple
    >     -- This is the important setting.
    >     { settingDisableCertificateValidation = True
    >     , settingDisableSession = False
    >     , settingUseServerName = False
    >     }
    > let connectionParams = ConnectionParams
    >     { connectionHostname = host
    >     , connectionPort = port
    >     , connectionUseSecure = Just tlsSettings
    >     , connectionUseSocks = Nothing
    >     }
    >
    > context <- initConnectionContext
    > connection <- connectTo context connectionParams
    > stream <- makeStream
    >     (fmap Just (connectionGetChunk connection))
    >     (maybe (return ()) (connectionPut connection . toStrict))
    > runClientWithStream stream host path options headers $ \ connection -> do
    >     -- Do something with the connection.
    >     return ()
-}
runSecureClientWith
    :: Socket.HostName -- ^ Host
    -> Socket.PortNumber -- ^ Port
    -> String -- ^ Path
    -> WebSockets.ConnectionOptions -- ^ Options
    -> WebSockets.Headers -- ^ Headers
    -> WebSockets.ClientApp a -- ^ Application
    -> IO a
runSecureClientWith host port path options headers app = do
    context <- Connection.initConnectionContext
    connection <- Connection.connectTo context (connectionParams host port)
    stream <- Stream.makeStream (reader connection) (writer connection)
    WebSockets.runClientWithStream stream host path options headers app

connectionParams :: Socket.HostName -> Socket.PortNumber -> Connection.ConnectionParams
connectionParams host port = Connection.ConnectionParams
    { Connection.connectionHostname = host
    , Connection.connectionPort = port
    , Connection.connectionUseSecure = Just tlsSettings
    , Connection.connectionUseSocks = Nothing
    }

tlsSettings :: Connection.TLSSettings
tlsSettings = Connection.TLSSettingsSimple
    { Connection.settingDisableCertificateValidation = False
    , Connection.settingDisableSession = False
    , Connection.settingUseServerName = False
    }

reader :: Connection.Connection -> IO (Maybe StrictBytes.ByteString)
reader connection = fmap Just (Connection.connectionGetChunk connection)

writer :: Connection.Connection -> Maybe LazyBytes.ByteString -> IO ()
writer connection = maybe (return ()) (Connection.connectionPut connection . LazyBytes.toStrict)
