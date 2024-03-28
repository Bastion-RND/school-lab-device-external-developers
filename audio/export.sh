#!/bin/bash

SOURCE=$1
TARGET=$2

echo $SOURCE
echo $TARGET

IFS=$'\n' 

if [ -e $TARGET ]; then
    rm -rf $TARGET
fi

mkdir -p $TARGET

for f in $(ls -1 $SOURCE | grep mp3)
do
    echo $SOURCE/$f '->' $TARGET/'0'$f
    lame --silent -mm $SOURCE/$f $TARGET/'0'$f
done

unset IFS
