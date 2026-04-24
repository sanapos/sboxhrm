#!/bin/sh
for f in /tmp/ref_*.jpg; do
  name=$(basename $f)
  echo "Downloading $name"
done
