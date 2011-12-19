#!/bin/sh

mkdir -p investigation
mkdir -p java
mkdir -p public

cd java
wget https://github.com/downloads/ISA-tools/ISAvalidator-ISAconverter-BIImanager/ISA-validator-1.4.zip
unzip ISA-validator-1.4.zip
cd -

cd investigation
git init
echo "*/*.zip" > .gitignore
cd -
