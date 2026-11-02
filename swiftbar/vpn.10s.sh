#!/bin/zsh
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
VPN=/opt/cisco/secureclient/bin/vpn
SCRIPT=$HOME/bin/vpn-connect
CONF=${0:A:h:h}/vpn.conf
STATE_DIR=$HOME/bin
CURRENT=$STATE_DIR/.vpn-current    # written by vpn-connect after connect, removed by "off"
STATUS=$STATE_DIR/.vpn-status      # "<profile> <phase>" while vpn-connect runs
DROPPED=$STATE_DIR/.vpn-dropped    # "connection lost" already notified

if [[ ! -f $CONF ]]; then
  echo "VPN | sfimage=lock.open"
  echo "---"
  echo "No vpn.conf – copy vpn.conf.example and edit it | disabled=true"
  echo "Open the repo folder | bash=/usr/bin/open param1=${CONF:h} terminal=false"
  exit 0
fi

typeset -A TYPE LABEL HOSTS GROUP AUTH BYUSER
IDS=()
while read -r id type label host group user auth match; do
  [[ -z $id || $id == \#* ]] && continue
  IDS+=$id; TYPE[$id]=$type; LABEL[$id]=$label; HOSTS[$id]=$host; GROUP[$id]=$group; AUTH[$id]=$auth
  [[ $type == anyconnect ]] && BYUSER[$user]=$id
done < $CONF

client() { case $1 in anyconnect) echo "AnyConnect";; forticlient) echo "FortiClient";; openvpn) echo "OpenVPN";; wireguard) echo "WireGuard";; *) echo $1;; esac }
twofa()  { case $1 in duo) echo "2FA Duo";; sms) echo "2FA SMS";; -|'') echo "no 2FA";; *) echo "2FA ${(U)1}";; esac }
detail() { # $1=profile -> "Work · Employees · 2FA Duo" (group omitted when "-")
  local g=${GROUP[$1]:#-}
  echo "${LABEL[$1]}${g:+  ·  $g}  ·  $(twofa ${AUTH[$1]})"
}

STATE=$($VPN state 2>/dev/null | grep -o 'state: [A-Za-z]*' | tail -1 | cut -d' ' -f2)

# FortiClient profiles run as openfortivpn (root helper) with a ppp interface
CPROF=""; CHOST=""
[[ -f $CURRENT ]] && read CPROF CHOST < $CURRENT
FORTI_UP=""; PPP_IP=""
if pgrep -qf '^/usr/local/libexec/swiftbar-vpn/openfortivpn '; then
  FORTI_UP=1
  PPP_IP=$(ifconfig 2>/dev/null | awk '/^ppp[0-9]+:/ {p=1; next} /^[a-z]/ {p=0} p && $1 == "inet" {print $2; exit}')
fi
since() { # seconds since file mtime -> HH:MM:SS
  local s=$(( $(date +%s) - $(stat -f %m $1) ))
  printf '%02d:%02d:%02d' $((s/3600)) $((s%3600/60)) $((s%60))
}

PROFILE=""; HOST=""; PHASE=""; MODE=idle
FRESH=($STATUS(N.mm-3))   # status younger than 3 min = vpn-connect still running
if [[ ${TYPE[$CPROF]} == forticlient && -n $FORTI_UP && -n $PPP_IP ]]; then
  MODE=connected
  rm -f $DROPPED
  PROFILE=$CPROF HOST=$CHOST IP=$PPP_IP TIME=$(since $CURRENT)
elif (( $#FRESH )); then
  MODE=connecting
  read PROFILE PHASE < $STATUS
elif [[ ${TYPE[$CPROF]} == forticlient ]]; then   # tunnel gone without "Disconnect"
  MODE=dropped
  PROFILE=$CPROF HOST=$CHOST
elif [[ $STATE == Connected ]]; then
  MODE=connected
  rm -f $DROPPED
  PROFILE=$CPROF HOST=$CHOST
  if [[ -z $PROFILE ]]; then   # connected outside vpn-connect: last user Secure Client remembers
    U=$(grep -o '<DefaultUser>[^<]*' ~/.vpn/.anyconnect 2>/dev/null | cut -d'>' -f2)
    [[ -n $U ]] && PROFILE=${BYUSER[$U]}
  fi
  STATS=$($VPN stats 2>/dev/null)
  [[ -z $HOST ]] && HOST=$(echo "$STATS" | grep -m1 'Server Address:' | sed -E 's/^[^:]*: *//' | xargs)
  IP=$(echo "$STATS"   | grep -m1 'Client Address (IPv4):' | sed -E 's/^[^:]*: *//' | xargs)
  TIME=$(echo "$STATS" | grep -m1 -E 'Duration:|Time Connected:' | sed -E 's/^[^:]*: *//' | xargs)
elif [[ -f $CURRENT && $STATE == Disconnected ]]; then   # dropped without "Disconnect"
  MODE=dropped
  PROFILE=$CPROF HOST=$CHOST
elif [[ -n $STATE && $STATE != Disconnected ]]; then
  MODE=busy   # Reconnecting etc. – Secure Client handles it
fi
if [[ $MODE == dropped && ! -f $DROPPED ]]; then
  touch $DROPPED
  /usr/bin/open -g "swiftbar://notify?plugin=vpn&title=VPN%20${LABEL[$PROFILE]// /%20}&body=Connection%20lost"
fi

NAME=${LABEL[$PROFILE]:-VPN}

# menu bar title
case $MODE in
  connected)  echo "$NAME | sfimage=lock.shield.fill sfcolor=#34C759" ;;
  connecting) echo "$NAME… | sfimage=lock.rotation sfcolor=#FF9F0A" ;;
  busy)       echo "VPN | sfimage=lock.rotation sfcolor=#FF9F0A" ;;
  dropped)    echo "$NAME | sfimage=exclamationmark.shield.fill sfcolor=#FF3B30" ;;
  *)          echo "VPN | sfimage=lock.open" ;;
esac
echo "---"

GREEN=#34C759 ORANGE=#FF9F0A RED=#FF3B30
info() { echo "$1 | sfimage=$2 disabled=true size=12" }   # grey detail line with icon

# status block
case $MODE in
  connected)
    echo "Connected to $NAME | sfimage=checkmark.shield.fill sfcolor=$GREEN color=$GREEN"
    [[ -n $PROFILE ]] && info "$(client ${TYPE[$PROFILE]})  ·  $(detail $PROFILE)" lock.shield
    [[ -n $HOST ]] && info "$HOST" server.rack
    [[ -n $IP ]]   && echo "$IP  (click to copy) | sfimage=network size=12 bash=/bin/zsh param1=-c param2=\"printf $IP|pbcopy\" terminal=false"
    [[ -n $TIME ]] && info "Connected for $TIME" clock ;;
  connecting)
    case $PHASE in
      duo) echo "Approve the Duo push on your phone | sfimage=iphone.radiowaves.left.and.right sfcolor=$ORANGE color=$ORANGE" ;;
      sms) echo "Waiting for the SMS code | sfimage=message sfcolor=$ORANGE color=$ORANGE" ;;
      browser) echo "Sign in in the browser and approve Duo | sfimage=safari sfcolor=$ORANGE color=$ORANGE" ;;
      *)   echo "Connecting to $NAME… | sfimage=hourglass sfcolor=$ORANGE color=$ORANGE" ;;
    esac
    info "$(client ${TYPE[$PROFILE]})  ·  $(detail $PROFILE)" lock.shield
    echo "Cancel | bash=$SCRIPT param1=off terminal=false refresh=true sfimage=xmark.circle" ;;
  busy)
    echo "$STATE… | sfimage=hourglass sfcolor=$ORANGE color=$ORANGE" ;;
  dropped)
    echo "Connection to $NAME lost | sfimage=exclamationmark.shield.fill sfcolor=$RED color=$RED"
    echo "Reconnect | bash=$SCRIPT param1=$PROFILE terminal=false refresh=true sfimage=arrow.clockwise"
    echo "Dismiss | bash=$SCRIPT param1=off terminal=false refresh=true sfimage=xmark" ;;
  *)
    echo "Not connected | sfimage=lock.open disabled=true" ;;
esac
echo "---"

# connect items grouped by VPN client – icon shows the 2FA, active one is checked,
# all disabled while connecting
SEEN=()
for id in $IDS; do
  t=${TYPE[$id]}
  (( ${SEEN[(Ie)$t]} )) && continue
  SEEN+=$t
  echo "$(client $t) | disabled=true size=11"
  for p in $IDS; do
    [[ ${TYPE[$p]} == $t ]] || continue
    case ${AUTH[$p]} in duo) ICON=iphone.radiowaves.left.and.right;; sms) ICON=message;; -|'') ICON=network;; *) ICON=key;; esac
    ITEM="$(detail $p) | sfimage=$ICON tooltip=${HOSTS[$p]}"
    if [[ $MODE == connected && $PROFILE == $p ]]; then
      echo "$ITEM checked=true disabled=true"
    elif [[ $MODE == connecting ]]; then
      echo "$ITEM disabled=true"
    else
      echo "$ITEM bash=$SCRIPT param1=$p terminal=false refresh=true"
    fi
  done
  echo "---"
done
[[ $MODE == connected ]] && echo "Disconnect | bash=$SCRIPT param1=off terminal=false refresh=true sfimage=xmark.circle"
echo "Show last log | bash=/usr/bin/open param1=-t param2=$HOME/bin/vpn-connect.log terminal=false sfimage=doc.text"
