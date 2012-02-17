#!/bin/sh
#
# Installs Passenger.
# Author: Christoph Helma, Andreas Maunz.
#

. "`pwd`/utils.sh"
DIR="`pwd`"

if [ "$(id -u)" = "0" ]; then
  echo "This script must be run as non-root." 1>&2
  exit 1
fi

# Utils
PIN="`which passenger-install-nginx-module`"
if [ ! -e "$PIN" ]; then
  echo "'passenger-install-nginx-module' missing. Install 'passenger-install-nginx-module' first. Aborting..."
  exit 1
fi

GIT="`which git`"
if [ ! -e "$GIT" ]; then
  echo "'git' missing. Install 'git' first. Aborting..."
  exit 1
fi


LOG="/tmp/`basename $0`-log.txt"

echo
echo "Nginx ('$LOG'):"

NGINX_DONE=false
mkdir "$NGINX_DEST" >/dev/null 2>&1
if [ ! -d "$NGINX_DEST" ]; then
  echo "Install directory '$NGINX_DEST' is not available! Aborting..."
  exit 1
else
  if ! rmdir "$NGINX_DEST" >/dev/null 2>&1; then # if not empty this will fail
    NGINX_DONE=true
  fi
fi

if ! $NGINX_DONE; then
  cmd="$PIN --auto-download --auto --prefix=$NGINX_DEST" && run_cmd "$cmd" "Install"
fi

cd "$RUBY_DEST/lib/ruby/gems/1.9.1/gems/" >>$LOG 2>&1
passenger=`ls -d passenger*`
cd - >>$LOG 2>&1
servername=`hostname`
$GIT checkout nginx.conf>>$LOG 2>&1
cmd="sed -i -e \"s,PASSENGER,$passenger,;s,SERVERNAME,$servername,;s,RUBY_DEST,$RUBY_DEST,;s,NGINX_DEST,$NGINX_DEST,;s,WWW_DEST,$WWW_DEST,\" ./nginx.conf" && run_cmd "$cmd" "Config"
cmd="sed -i -e \"s,USER,`whoami`,\" ./nginx.conf" && run_cmd "$cmd" "User"

if [ -z "$NGINX_PORT" ]; then
  NGINX_PORT=80 # allow nginx to run as non-root user
else
  NGINX_PORT=`echo "$NGINX_PORT" | sed 's/^.//g'`
fi
cmd="sed -i -e \"s,NGINX_PORT,$NGINX_PORT,\" ./nginx.conf" && run_cmd "$cmd" "NGINX_PORT"
cmd="cp ./nginx.conf \"$NGINX_DEST/conf\"" && run_cmd "$cmd" "Copy"
$GIT checkout nginx.conf>>$LOG 2>&1

if [ ! -f $NGINX_CONF ]; then
  echo "if ! echo \"\$PATH\" | grep \"$NGINX_DEST\">/dev/null 2>&1; then export PATH=$NGINX_DEST/sbin:\$PATH; fi" >> "$NGINX_CONF"
  echo "Nginx configuration has been stored in '$NGINX_CONF'."

  if ! grep ". \"$NGINX_CONF\"" $TB_UI_CONF; then
    echo ". \"$NGINX_CONF\"" >> $TB_UI_CONF
  fi

fi


cd "$DIR"

