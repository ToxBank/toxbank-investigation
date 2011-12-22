#!/bin/sh

mkdir -p investigation
mkdir -p java
mkdir -p public
mkdir -p tmp
mkdir -p 4store

BASEDIR=`pwd`

# check dependencies
sudo apt-get -y install build-essential libpcre3-dev librasqal2-dev libtool libraptor1-dev libglib2.0-dev ncurses-dev libreadline-dev curl unzip

cd java
wget https://github.com/downloads/ISA-tools/ISAvalidator-ISAconverter-BIImanager/ISA-validator-1.4.zip
unzip ISA-validator-1.4.zip
cd -

# get, compile, install "raptor" "rasqal"
# raptor
cd tmp
wget http://download.librdf.org/source/raptor2-2.0.4.tar.gz
tar xvzf raptor2-2.0.4.tar.gz
cd raptor2-2.0.4
./configure
make
sudo make install
cd -

# rasqal
wget http://download.librdf.org/source/rasqal-0.9.27.tar.gz
tar xvzf rasqal-0.9.27.tar.gz
cd rasqal-0.9.27
./configure
make
sudo make install
cd -

# 4store
wget http://4store.org/download/4store-v1.1.4.tar.gz
tar xvzf 4store-v1.1.4.tar.gz
cd 4store-v1.1.4
./configure --with-storage-path=$BASEDIR/4store
make
sudo make install
sudo /sbin/ldconfig
cd $BASEDIR
sudo rm -r tmp

# start service
4s-backend-setup ToxBank
4s-backend ToxBank

cd investigation
git init
echo "*/*.zip" > .gitignore
echo "*/tmp" >> .gitignore
git add .gitignore
git commit -am ".gitignore added"
cd -
