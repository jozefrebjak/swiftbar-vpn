#!/bin/zsh
# Demo menu with fake VPNs, e.g. for screenshots. No real VPN client is touched
# and menu clicks do nothing.
#   demo.sh              connected to "Work"
#   demo.sh connecting   waiting for the Duo push (for 3 minutes)
#   demo.sh remove       remove the demo icon
set -e
HERE=${0:A:h}
REPO=${HERE:h:h}
DEMO=${TMPDIR:-/tmp}/swiftbar-vpn-demo
PLUGIN_DIR=$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null) || { echo "SwiftBar plugin folder is not set"; exit 1; }
LINK=$PLUGIN_DIR/vpn-demo.10s.sh
refresh() { /usr/bin/open -g "swiftbar://refreshallplugins" }

case ${1:-connected} in
  remove) rm -f $LINK; rm -rf $DEMO; refresh; exit 0 ;;
  connected|connecting) ;;
  *) echo "usage: ${0:t} [connected|connecting|remove]"; exit 1 ;;
esac

mkdir -p $DEMO/state
sed -e "s|^VPN=.*|VPN=$HERE/fake-vpn|" \
    -e "s|^CONF=.*|CONF=$HERE/vpn.conf|" \
    -e "s|^STATE_DIR=.*|STATE_DIR=$DEMO/state|" \
    -e "s|^SCRIPT=.*|SCRIPT=/usr/bin/true|" \
    $REPO/swiftbar/vpn.10s.sh > $DEMO/vpn-demo.10s.sh
chmod +x $DEMO/vpn-demo.10s.sh
print "work vpn.example.com" > $DEMO/state/.vpn-current
rm -f $DEMO/state/.vpn-status
[[ ${1:-connected} == connecting ]] && print "work duo" > $DEMO/state/.vpn-status
ln -sf $DEMO/vpn-demo.10s.sh $LINK
refresh
echo "Demo icon added to the menu bar. Remove it with: ${0:t} remove"
