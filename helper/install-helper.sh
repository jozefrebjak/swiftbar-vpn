#!/bin/zsh -f
# Installs the root-owned swiftbar-vpn helper (FortiClient via openfortivpn, VPN servers in /etc/hosts).
# Hosts are taken from vpn.conf at install time and baked into the root-owned helper, so run it
# again after changing hosts in vpn.conf or after "brew upgrade openfortivpn":
#   sudo ./helper/install-helper.sh
#   sudo ./helper/install-helper.sh --uninstall
set -eu
setopt extendedglob

DIR=/usr/local/libexec/swiftbar-vpn
SUDOERS=/etc/sudoers.d/swiftbar-vpn
SRC=${0:A:h}
CONF=${SRC:h}/vpn.conf
BEGIN_RE='^# >>> swiftbar-vpn'
END_LINE='# <<< swiftbar-vpn'

[[ $EUID == 0 ]] || { print "run with sudo"; exit 1 }
USER_NAME=${SUDO_USER:?run via sudo from your account}

drop_hosts_block() {
  /usr/bin/awk -v e="$END_LINE" '/^# >>> swiftbar-vpn/ {f=1; next} f && $0 == e {f=0; next} !f' /etc/hosts > /etc/hosts.swiftbar-vpn.tmp
  /bin/chmod 644 /etc/hosts.swiftbar-vpn.tmp && /bin/mv -f /etc/hosts.swiftbar-vpn.tmp /etc/hosts
}

if [[ ${1:-} == --uninstall ]]; then
  rm -f $SUDOERS
  rm -rf $DIR
  grep -q $BEGIN_RE /etc/hosts && drop_hosts_block
  /usr/bin/dscacheutil -flushcache
  print "removed $DIR, $SUDOERS and the swiftbar-vpn block in /etc/hosts"; exit 0
fi

# hosts from vpn.conf (validated – they end up in a root-owned script and in sudoers)
FORTI_HOSTS=() VPN_HOSTS=()
while read -r id type label host rest; do
  [[ -z $id || $id == \#* ]] && continue
  [[ $host == [A-Za-z0-9.-]##(:[0-9]##)# ]] || { print "invalid host in vpn.conf: $host"; exit 1 }
  [[ $type == forticlient ]] && { [[ $host == *:* ]] || { print "forticlient host needs :port: $host"; exit 1 }; FORTI_HOSTS+=$host }
  VPN_HOSTS+=${host%%:*}
done < $CONF
VPN_HOSTS=(${(u)VPN_HOSTS}) FORTI_HOSTS=(${(u)FORTI_HOSTS})

# fresh root-owned directory (every path component is root-owned)
rm -rf $DIR
/usr/bin/install -d -o root -g wheel -m 755 /usr/local/libexec $DIR $DIR/lib $DIR/no-modules

if (( $#FORTI_HOSTS )); then
  OFV=/opt/homebrew/opt/openfortivpn/bin/openfortivpn
  [[ -x $OFV ]] || { print "FortiClient profiles need: brew install openfortivpn"; exit 1 }
  OFV=${OFV:A}   # resolve the Homebrew symlink

  # copy openfortivpn + its Homebrew libraries (Homebrew paths are writable by the user)
  brew_deps() { /usr/bin/otool -L $1 | awk 'NR > 1 && $1 ~ /^\/opt\/homebrew\// {print $1}' }
  LIBS=(${(u)$(brew_deps $OFV)})
  for l in $LIBS; do LIBS+=($(brew_deps $l)); done
  LIBS=(${(u)LIBS})

  /usr/bin/install -o root -g wheel -m 755 $OFV $DIR/openfortivpn
  for l in $LIBS; do
    /usr/bin/install -o root -g wheel -m 644 ${l:A} $DIR/lib/${l:t}
  done
  for f in $DIR/openfortivpn $DIR/lib/*.dylib; do
    [[ $f == *.dylib ]] && /usr/bin/install_name_tool -id $DIR/lib/${f:t} $f 2>/dev/null
    for l in $LIBS; do /usr/bin/install_name_tool -change $l $DIR/lib/${l:t} $f 2>/dev/null || true; done
    /usr/bin/codesign -f -s - $f 2>/dev/null
    if /usr/bin/otool -L $f | grep -q /opt/homebrew/; then print "still links to /opt/homebrew: $f"; exit 1; fi
  done

  # root-owned configs: system CA bundle, no user-writable OpenSSL config
  print "ca-file = /etc/ssl/cert.pem" > $DIR/openfortivpn.conf
  print "# empty on purpose – keeps OpenSSL from loading the Homebrew openssl.cnf" > $DIR/openssl.cnf
  chown root:wheel $DIR/openfortivpn.conf $DIR/openssl.cnf
  chmod 644 $DIR/openfortivpn.conf $DIR/openssl.cnf
fi

# helper with the hosts baked in
sed -e "s|@FORTI_HOSTS@|${(j: :)FORTI_HOSTS}|" -e "s|@VPN_HOSTS@|${(j: :)VPN_HOSTS}|" $SRC/swiftbar-vpn-helper > $DIR/helper
chown root:wheel $DIR/helper
chmod 755 $DIR/helper

# sudoers: only these exact commands, no password
TMP=$(mktemp)
{
  print "# swiftbar-vpn root helper – installed by helper/install-helper.sh"
  for h in $FORTI_HOSTS; do
    esc=${h//:/\\:}   # sudoers needs ":" escaped in arguments; print -r keeps the backslash
    print -r -- "$USER_NAME ALL=(root) NOPASSWD: $DIR/helper forti-connect $esc"
  done
  (( $#FORTI_HOSTS )) && print "$USER_NAME ALL=(root) NOPASSWD: $DIR/helper forti-stop"
  print "$USER_NAME ALL=(root) NOPASSWD: $DIR/helper hosts-update"
} > $TMP
/usr/sbin/visudo -cf $TMP >/dev/null || { print "sudoers check failed"; rm -f $TMP; exit 1 }
/usr/bin/install -o root -g wheel -m 440 $TMP $SUDOERS
rm -f $TMP

# first fill of the /etc/hosts block
$DIR/helper hosts-update

print "installed $DIR and $SUDOERS"
(( $#FORTI_HOSTS )) && print "openfortivpn $($DIR/openfortivpn --version 2>&1 | head -1), FortiClient hosts: $FORTI_HOSTS"
print "/etc/hosts:"; sed -n '/^# >>> swiftbar-vpn/,/^# <<< swiftbar-vpn/p' /etc/hosts
