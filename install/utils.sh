#!/bin/sh

check_dest() 
{
  if ! [ -d "$TB_PREFIX" ]; then
    if ! mkdir -p "$TB_PREFIX"; then
      echo "Could not create target directory '$TB_PREFIX'! Aborting..."
      exit 1
    fi
  fi
}

run_cmd ()
{
  local cmd="$1"
  local title="$2"

  printf "%30s" "'$title'"
  if ! eval $cmd >>$LOG 2>&1 ; then  
    printf "%50s\n" "FAIL"
    echo "Last 10 lines of log:"
    tail -10 "$LOG"
    exit 1
  fi
  printf "%50s\n" "DONE"

}

abs_path()
{
  local path="$1"
  case "$path" in
     /*) absolute=1 ;;
      *) absolute=0 ;;
  esac
}

. "`pwd`/config.sh"
touch "$TB_UI_CONF"
. "$TB_UI_CONF"
check_dest
