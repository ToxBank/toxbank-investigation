#!/bin/sh
#
# Installs Ruby enterprise edition and passenger gem.
# A configuration file is created and included in your '$TB_UI_CONF'.
# Author: Christoph Helma, Andreas Maunz, Denis Gebele.
#

. "`pwd`/utils.sh"
DIR="`pwd`"

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

# Pkg
LOG="/tmp/`basename $0`-log.txt"

echo
echo "Ruby 1.9.3 ('$RUBY_DEST', '$LOG')."


mkdir "$RUBY_DEST" >/dev/null 2>&1
if [ ! -d "$RUBY_DEST" ]; then
  echo "Install directory '$RUBY_DEST' is not available! Aborting..."
  exit 1
else
  if ! rmdir "$RUBY_DEST" >/dev/null 2>&1; then # if not empty this will fail
    RUBY_DONE=true
  fi
fi

if [ ! $RUBY_DONE ]; then
  cd /tmp
  URI="http://ftp.ruby-lang.org/pub/ruby/1.9/$RUBY_VER.tar.gz"
  #URI="http://rubyenterpriseedition.googlecode.com/files/$RUBY_VER.tar.gz"
  if ! [ -d "/tmp/$RUBY_VER" ]; then
    cmd="$WGET $URI" && run_cmd "$cmd" "Download"
    cmd="tar xzf $RUBY_VER.tar.gz" && run_cmd "$cmd" "Unpack"
  fi
  cmd="cd /tmp/$RUBY_VER && ./configure --prefix=$RUBY_DEST" && run_cmd "$cmd" "Configure"
  cmd="cd /tmp/$RUBY_VER && make" && run_cmd "$cmd" "Make"
  cmd="cd /tmp/$RUBY_VER && make install" && run_cmd "$cmd" "Install"
  #cmd="sh /tmp/$RUBY_VER/installer  --dont-install-useful-gems --no-dev-docs --auto=$RUBY_DEST" && run_cmd "$cmd" "Install"
fi



if ! [ -f "$RUBY_CONF" ]; then
  echo "if echo \"\$PATH\" | grep -v \"$RUBY_DEST\">/dev/null 2>&1; then export PATH=\"$RUBY_DEST/bin:\$PATH\"; fi" >> "$RUBY_CONF"

  echo "Ruby configuration has been stored in '$RUBY_CONF'."
  if ! grep "$RUBY_CONF" $TB_UI_CONF >/dev/null 2>&1 ; then
    echo ". \"$RUBY_CONF\"" >> $TB_UI_CONF
  fi
fi
. "$RUBY_CONF"


GEM="`which gem`"
if [ ! -e "$GEM" ]; then
  echo "'gem' missing. Install 'gem' first. Aborting..."
  exit 1
fi

if [ "$PASSENGER_SKIP" != "s" ]; then
  export PATH="$RUBY_DEST/bin:$PATH"
  cmd="$GEM sources -a http://gemcutter.org" && run_cmd "$cmd" "Add Gemcutter"
  cmd="$GEM sources -a http://rubygems.org" && run_cmd "$cmd" "Add Rubygems"
  GEMCONF="gem: --no-ri --no-rdoc"
  if ! grep "$GEMCONF" $HOME/.gemrc >>$LOG 2>&1; then
    echo "$GEMCONF" | tee -a $HOME/.gemrc >>$LOG 2>&1 
  fi
  if ! $GEM list | grep passenger >/dev/null 2>&1; then
    cmd="$GEM install passenger" && run_cmd "$cmd" "Install Passenger"
  fi
  
fi

cd "$DIR"
