{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DeriveFunctor              #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE DeriveLift                 #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns             #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TemplateHaskell            #-}

module Playground.Types where

import           Control.Lens                 (makeLenses)
import           Data.Aeson                   (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import qualified Data.Aeson                   as JSON
import           Data.List.NonEmpty           (NonEmpty ((:|)))
import           Data.Map                     (Map)
import           Data.Text                    (Text)
import           GHC.Generics                 (Generic)
import           Language.Haskell.Interpreter (CompilationError, SourceCode)
import qualified Language.Haskell.Interpreter as HI
import qualified Language.Haskell.TH.Syntax   as TH
import           Ledger                       (Address, Blockchain, PubKey, Tx, TxId, TxIn, TxOut,
                                               TxOutOf (TxOutOf, txOutAddress, txOutType),
                                               TxOutType (PayToPubKey, PayToScript), fromSymbol)
import qualified Ledger.Ada                   as Ada
import           Ledger.Scripts               (ValidatorHash)
import           Ledger.Value                 (TokenName)
import qualified Ledger.Value                 as V
import           Schema                       (FormSchema)
import           Wallet.Emulator.Types        (EmulatorEvent, Wallet, walletPubKey)

data KnownCurrency =
    KnownCurrency
        { hash         :: ValidatorHash
        , friendlyName :: String
        , knownTokens  :: NonEmpty TokenName
        }
    deriving (Eq, Show, Generic, ToJSON, FromJSON)

adaCurrency :: KnownCurrency
adaCurrency =
    KnownCurrency
        { hash = fromSymbol Ada.adaSymbol
        , friendlyName = "Ada"
        , knownTokens = Ada.adaToken :| []
        }

--------------------------------------------------------------------------------
newtype Fn =
    Fn Text
    deriving (Eq, Show, Generic, TH.Lift)
    deriving newtype (ToJSON, FromJSON)

data Expression
    = Action
          { function  :: Fn
          , wallet    :: Wallet
          , arguments :: [JSON.Value]
          }
    | Wait
          { blocks :: Int
          }
    deriving (Show, Generic, ToJSON, FromJSON)

type Program = [Expression]

data SimulatorWallet =
    SimulatorWallet
        { simulatorWalletWallet  :: Wallet
        , simulatorWalletBalance :: V.Value
        }
    deriving (Show, Generic, Eq)
    deriving anyclass (ToJSON, FromJSON)

data Evaluation =
    Evaluation
        { wallets    :: [SimulatorWallet]
        , program    :: Program
        , sourceCode :: SourceCode
        , blockchain :: Blockchain
        }
    deriving (Generic, ToJSON, FromJSON)

pubKeys :: Evaluation -> [PubKey]
pubKeys Evaluation {..} = walletPubKey . simulatorWalletWallet <$> wallets

data EvaluationResult =
    EvaluationResult
        { resultBlockchain  :: [[(TxId, Tx)]] -- Blockchain annotated with hashes.
        , resultRollup      :: [[AnnotatedTx]]
        , emulatorLog       :: [EmulatorEvent]
        , fundsDistribution :: [SimulatorWallet]
        , walletKeys        :: [(PubKey, Wallet)]
        }
    deriving (Generic, ToJSON)

data CompilationResult =
    CompilationResult
        { functionSchema  :: [FunctionSchema FormSchema]
        , knownCurrencies :: [KnownCurrency]
        , iotsSpec        :: Text
        }
    deriving (Show, Generic, ToJSON)

data FunctionSchema a =
    FunctionSchema
        { functionName   :: Fn
        , argumentSchema :: [a]
        }
    deriving (Eq, Show, Generic, ToJSON, FromJSON, Functor)

------------------------------------------------------------
data PlaygroundError
    = CompilationErrors [CompilationError]
    | InterpreterError HI.InterpreterError
    | FunctionSchemaError
    | DecodeJsonTypeError String String
    | PlaygroundTimeout
    | RollupError Text
    | OtherError String
    deriving (Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

------------------------------------------------------------
data SequenceId =
    SequenceId
        { slotIndex :: Int
        , txIndex   :: Int
        }
    deriving (Eq, Ord, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

data DereferencedInput =
    DereferencedInput
        { originalInput :: TxIn
        , refersTo      :: TxOut
        }
    deriving (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

data BeneficialOwner
    = OwnedByPubKey PubKey
    | OwnedByScript Address
    deriving (Eq, Show, Ord, Generic)
    deriving anyclass (FromJSON, ToJSON, FromJSONKey, ToJSONKey)

toBeneficialOwner :: TxOut -> BeneficialOwner
toBeneficialOwner TxOutOf {txOutType, txOutAddress} =
    case txOutType of
        PayToPubKey pubKey -> OwnedByPubKey pubKey
        PayToScript _      -> OwnedByScript txOutAddress

data AnnotatedTx =
    AnnotatedTx
        { sequenceId         :: SequenceId
        , txId               :: TxId
        , tx                 :: Tx
        , dereferencedInputs :: [DereferencedInput]
        , balances           :: Map BeneficialOwner V.Value
        }
    deriving (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

makeLenses 'EvaluationResult

makeLenses 'SequenceId

makeLenses 'AnnotatedTx
