#!/bin/zsh
# Links the scripts from this repo into ~/bin so edits in the repo apply immediately.
set -e
REPO=${0:A:h}
mkdir -p ~/bin/swiftbar
for pair in "bin/vpn-connect:$HOME/bin/vpn-connect" "swiftbar/vpn.10s.sh:$HOME/bin/swiftbar/vpn.10s.sh"; do
  src=$REPO/${pair%%:*}; dst=${pair#*:}
  # Backups go to ~/bin, never into the SwiftBar folder (it would run them as plugins).
  bak=$HOME/bin/${dst:t}.bak
  if [[ -e $dst && ! -L $dst ]]; then mv "$dst" "$bak"; echo "backup: $bak"; fi
  ln -sfn "$src" "$dst"; echo "linked: $dst -> $src"
done

if [[ ! -f $REPO/vpn.conf ]]; then
  cp $REPO/vpn.conf.example $REPO/vpn.conf
  echo "created $REPO/vpn.conf from the example – edit it with your VPNs"
fi
