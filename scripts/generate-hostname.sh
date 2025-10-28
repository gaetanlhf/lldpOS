#!/bin/bash

ADJECTIVES=(
    "able" "brave" "calm" "dear" "eager" "fair" "gentle" "happy" "ideal" "jolly"
    "keen" "lively" "mighty" "noble" "proud" "quiet" "rapid" "smart" "tender" "unique"
    "vital" "wise" "young" "zippy" "bold" "clear" "crisp" "divine" "epic" "fluent"
)

NOUNS=(
    "aardvark" "badger" "cougar" "dolphin" "eagle" "falcon" "gazelle" "heron" "impala" "jaguar"
    "koala" "leopard" "meerkat" "narwhal" "osprey" "panther" "quail" "raven" "shark" "tiger"
    "urchin" "viper" "walrus" "xerus" "yak" "zebra" "bear" "crane" "drake" "elk"
)

ADJ=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
NOUN=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
NUM=$(printf "%04d" $((RANDOM % 10000)))

echo "${ADJ}-${NOUN}-${NUM}"