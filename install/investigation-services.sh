#!/bin/sh
#
# Installs Opentox Webservices.
# Author: Christoph Helma, Andreas Maunz, Denis Gebele.
#

. "`pwd`/utils.sh"
DIR=`pwd`

if [ "$(id -u)" = "0" ]; then
  echo "This script must be run as non-root." 1>&2
  exit 1
fi

# Utils
WGET="`which wget`"
if [ ! -e "$WGET" ]; then
  echo "'wget' missing. Install 'wget' first. Aborting..."
  exit 1
fi

GIT="`which git`"
if [ ! -e "$GIT" ]; then
  echo "'git' missing. Install 'git' first. Aborting..."
  exit 1
fi

RUBY="`which ruby`"
if [ ! -e "$RUBY" ]; then
  echo "'ruby' missing. Install 'ruby' first. Aborting..."
  exit 1
fi

LOG="/tmp/`basename $0`-log.txt"

echo
echo "services ('$LOG'):"

#mkdir -p "$WWW_DEST" >>$LOG 2>&1
#cd "$WWW_DEST" >>$LOG 2>&1
#for s in $HOME; do
    #rm -rf "$s" >>$LOG 2>&1
    #$GIT clone "git://github.com/ToxBank/toxbank-investigation/$s.git" "$s" >>$LOG 2>&1
    #cd "$s" >>$LOG 2>&1
    #$GIT checkout -b $TB_BRANCH origin/$TB_BRANCH >>$LOG 2>&1
    #rm -rf public >>$LOG 2>&1
    #mkdir public >>$LOG 2>&1
    #mypath_from="$WWW_DEST/public"
    #mypath_to="$WWW_DEST/$s"
    #cmd="ln -sf \"$mypath_from\" \"$mypath_to\"" && run_cmd "$cmd" "Linking $s"
    #cd - >>$LOG 2>&1
#done

cd "$DIR"

