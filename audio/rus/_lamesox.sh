#!/bin/bash
for f in $(ls -1 | grep -e mp3 -e 'mp3')
do
	lame -mm --decode $f $f.wav
	sox $f.wav --norm=-0.1 _$f.wav silence 1 0.05 0.1% reverse silence 1 0.05 0.1% reverse
	lame -mm _$f.wav $f
	rm *.mp3.wav
done
