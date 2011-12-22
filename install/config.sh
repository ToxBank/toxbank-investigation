#!/bin/sh
#
# Configuration file for ToxBank-Investigation installer.
# Author: Christoph Helma, Andreas Maunz, Denis Gebele.
#

# 1) Base setup
TB_DIST="debian"       # Linux distribution    (debian)
TB_INSTALL="local"     # Type                  (local)
TB_BRANCH="master"     # Maturity              (master)

# 2) Where all binaries are installed.
TB_PREFIX="$HOME/toxbank-investigation/services"
TB_HOME="$HOME/toxbank-investigation"

# 3) What versions to install.
RUBY_NUM_VER="1.8.7-2011.03"

# 4) Server settings.
NGINX_SERVERNAME="localhost"
WWW_DEST="$TB_HOME/public"
PORT=":8080" # set to empty string ("") for port 80 otherwise set to port *using colon* e.g. ":8080"
OHM_PORT="6379" # set to port (no colon)

# Done.


### Nothing to gain from changes below this line.
RUBY_CONF="$TB_PREFIX/.sh_ruby_tb"
NGINX_CONF="$TB_PREFIX/.sh_nginx_tb"

RUBY_VER="ruby-enterprise-$RUBY_NUM_VER"

RUBY_DEST="$TB_PREFIX/$RUBY_VER"
NGINX_DEST="$TB_PREFIX/nginx"

TB_UI_CONF="$HOME/.toxbank-ui.sh"
