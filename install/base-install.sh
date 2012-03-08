#!/bin/sh
#
# Installs base packages for Ubuntu
# Author: Andreas Maunz, Denis Gebele
#
# Your installed packages are safe and will not be updated.

. "`pwd`/utils.sh"
DIR="`pwd`"

if [ "$(id -u)" = "0" ]; then
  echo "This script must not be run as root" 1>&2
  exit 1
fi

# Utils
APTITUDE="`which aptitude`"
APT_CACHE="`which apt-cache`"
DPKG="`which dpkg`"

if [ ! -e "$APTITUDE" ]; then
  echo "Aptitude missing. Install aptitude first." 1>&2
  exit 1
fi

touch $TB_UI_CONF

# Pkgs
packs="build-essential curl git-core hostname libcurl4-openssl-dev libpcre3-dev libxml2-dev libtool libglib2.0-dev libreadline-dev libssl-dev libxslt-dev ncurses-dev openjdk-6-jdk unzip wget zip"

echo
echo "Base Packages:"

pack_arr=""
for p in $packs; do
  if $DPKG -S "$p" >/dev/null 2>&1; then
     printf "%50s%30s\n" "'$p'" "Y"
  else
     printf "%50s%30s\n" "'$p'" "N"
    pack_arr="$pack_arr $p"
  fi
done

if [ -n "$pack_arr" ]; then
  echo 
  echo "Checking availablity:"
  sudo $APTITUDE update -y >/dev/null 2>&1
#  sudo $APTITUDE upgrade -y >/dev/null 2>&1
fi

for p in $pack_arr; do
  if [ -n "`$APT_CACHE search $p`" ] ; then
     printf "%50s%30s\n" "'$p'" "Y"
  else
    printf "%50s%30s\n" "'$p'" "N"
    pack_fail="$pack_fail $p"
  fi
done

if [ -n "$pack_fail" ]; then
  echo 
  echo "WARNING: At least one missing package has no suitable installation candidate."
  echo "Press <Ctrl+C> to abort (5 sec)."
  sleep 5
fi

echo
if [ -n "$pack_arr" ]; then 
  echo "Installing missing packages:"
fi

for p in $pack_arr; do
  cmd="sudo $APTITUDE -y install $p" && run_cmd "$cmd" "$p"
done

cd "$DIR"

