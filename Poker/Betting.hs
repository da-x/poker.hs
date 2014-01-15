{-# LANGUAGE FlexibleContexts #-}

module Poker.Betting (
  betting
) where

import Control.Lens
import Control.Monad.State
import Data.Char (toLower)
import Text.Read (readMaybe)

import Poker.Types
import Poker.Hands

betting :: (Functor m, MonadState Game m, MonadIO m) => m ()
betting = unlessM bettingDone $ bettingRound >> betting

unlessM :: Monad m => m Bool -> m () -> m ()
unlessM b s = b >>= (`unless` s)


bettingDone :: MonadState Game m => m Bool
bettingDone = do
  mb <- use maxBet
  ps <- use players
  let bs = map (view bet) ps
      actives = filter (/= Fold) bs
  return ((length actives == 1) || (all $ f mb) bs)
  where f mb b = case b of
                      None -> False
                      Fold -> True
                      _    -> b == mb

bettingRound :: (MonadState Game m, MonadIO m) => m ()
bettingRound = players <~ (get >>= perform (players.traversed.act playerAction))

playerAction :: (MonadState Game m, MonadIO m) => Player -> m [Player]
playerAction p = do
  mb <- use maxBet
  let b = p^.bet
  liftM return $ p & case mb of
    (Bet _) | b == Fold -> return
            | b < mb    -> getAction False
    _       | b == None -> getAction True
            | otherwise -> return

toInt :: Bet -> Int
toInt (Bet x) = x
toInt _       = 0

showState :: (MonadState Game m, MonadIO m) => Player -> m ()
showState p = do
  c <- use community
  mb <- use maxBet
  let state = "Pockets: " ++ show (p^.pockets)
           ++ " Community: " ++ show c
           ++ " Bet: " ++ show (toInt mb)
  liftIO $ putStrLn state

getAction :: (MonadState Game m, MonadIO m) => Bool -> Player -> m Player
getAction canBet p = do
  showState p
  mb <- use maxBet
  b <- if canBet then getCheckOrBet else getBetOrFold mb
  let d = max 0 $ toInt b - toInt (p^.bet)
  if toInt b > p^.chips
  then liftIO (putStrLn "You don't have that many chips.") >> getAction canBet p
  else do maxBet .= max b mb
          pot += d
          return $ chips -~ d $ bet .~ b $ p

getBetOrFold :: MonadIO m => Bet -> m Bet
getBetOrFold mb = do
  liftIO $ putStrLn "Fold, Call, or Raise?"
  input <- liftIO getLine
  case map toLower input of
       "fold"  -> return Fold
       "call"  -> return mb
       "raise" -> getRaise mb
       _       -> getBetOrFold mb

getRaise :: MonadIO m => Bet -> m Bet
getRaise mb = liftIO $ putStrLn "Raise by how much?" >> liftM (\r -> fmap (+r) mb) getBet

getCheckOrBet :: MonadIO m => m Bet
getCheckOrBet = do
  liftIO $ putStrLn "Check or Bet?"
  input <- liftIO getLine
  case map toLower input of
       "check" -> return Check
       "bet"   -> liftIO $ putStrLn "Bet how much?" >> fmap Bet getBet
       _       -> getCheckOrBet

getBet :: MonadIO m => m Int
getBet = liftIO getLine >>= maybe (liftIO $ putStrLn "Invalid bet" >> getBet) return . readMaybe
