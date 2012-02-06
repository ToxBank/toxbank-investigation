#!/bin/sh
#
# Installs 4store 1.14 in toxbank-investigations/services/4store
# Author: Christoph Helma, Andreas Maunz, Denis Gebele.
#



# get, compile, install "raptor" "rasqal" "4store"
# raptor
mkdir -p tmp
cd tmp
wget http://download.librdf.org/source/raptor2-2.0.4.tar.gz
tar xvzf raptor2-2.0.4.tar.gz
cd raptor2-2.0.4 >>$LOG 2>&1
./configure --prefix=/$TB_PREFIX/4store
make
sudo make install
cd -

# rasqal
wget http://download.librdf.org/source/rasqal-0.9.27.tar.gz
tar xvzf rasqal-0.9.27.tar.gz
cd rasqal-0.9.27
./configure --prefix=/$TB_PREFIX/4store >>$LOG 2>&1
make
sudo make install
cd -

# 4store
wget http://4store.org/download/4store-v1.1.4.tar.gz
tar xvzf 4store-v1.1.4.tar.gz
cd 4store-v1.1.4
./configure --prefix=/$TB_PREFIX/4store --with-storage-path=/$TB_PREFIX/database >>$LOG 2>&1
make >>$LOG 2>&1
sudo make install
sudo /sbin/ldconfig
export LD_LIBRARY_PATH="/$TB_PREFIX/4store/lib"
export PATH="$PATH:/$TB_PREFIX/4store/bin"
cd "$DIR"
sudo rm -r tmp

# build database ToxBank
4s-backend-setup ToxBank
# start 4s service
# 4s-backend ToxBank
