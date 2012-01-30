# Some useful scripts to put in your ~/.bashrc in case you are using bash (assuming OT_PREFIX is '~/toxbank-investigation'):
# USE ONLY IF YOUR NGINX PORT IS less or equal to 1024 (PRIVILEGED)

# Load server config
tbconfig() {
  source $HOME/.toxbank-ui.sh
}

# Update the version
tbupdate() {
  START_DIR=`pwd`
  tbconfig
  cd $HOME/toxbank-investigation
  for d in `find -not -name "." -type d -maxdepth 1 2>/dev/null`; do echo ; echo $d ; cd $d ; MYBRANCH=`git branch | grep "*" | sed 's/.*\ //g'`; git pull origin $MYBRANCH ; cd - ;  done
}

# Start the server
tbstart() {
  tbconfig
  tbkill
  sudo bash -c "source $HOME/.toxbank-ui.sh; nohup nginx -c $HOME/toxbank-investigation/services/nginx/conf/nginx.conf >/dev/null 2>&1 &"
  sleep 2
  if ! pgrep -u root nginx>/dev/null 2>&1; then echo "Failed to start nginx."; fi
  bash -c "4s-backend ToxBank"
}

# Display log
alias tbless='less $HOME/.toxbank/log/production.log'

# Tail log
alias tbtail='tail -f $HOME/.toxbank/log/production.log'

# Reload the server
tbreload() {
  sudo bash -c "source $HOME/.toxbank-ui.sh; nginx -s reload"
  sudo killall 4s-backend >/dev/null 2>&1
  sudo bash -c "4s-backend ToxBank"
}

# Kill the server
tbkill() {
  sudo killall -u root nginx >/dev/null 2>&1
  sudo bash -c "source $HOME/.toxbank-ui.sh; $OHM_PORT shutdown >/dev/null 2>&1"
  sudo killall 4s-backend >/dev/null 2>&1
  while sudo ps x | grep PassengerWatchdog | grep -v grep >/dev/null 2>&1; do sleep 1; done
  for p in `pgrep -u root R 2>/dev/null`; do sudo kill -9 $p; done
}
