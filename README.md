# swiftbar-vpn

All your VPNs behind one menu bar icon on macOS. Cisco AnyConnect and FortiClient SSL VPN, with Duo push or an SMS code as the second factor.

This is a starting point, not a product. It's the generic version of the setup I use every day, published so you don't have to begin from an empty file. Put your VPNs into `vpn.conf`, keep what fits, change what doesn't. The write-up is on [rebjak.com](https://rebjak.com/en/blog/all-vpns-in-the-macos-menu-bar/).

```text
 Connected to Work
   AnyConnect · Work · Employees · 2FA Duo
   vpn.example.com
   10.20.30.40  (click to copy)
   Connected for 01:12:09
 ──────────────────────────────
 AnyConnect
 ✓ Work  ·  Employees  ·  2FA Duo
   Uni   ·  External   ·  2FA SMS
 ──────────────────────────────
 FortiClient
   Work  ·  2FA Duo
 ──────────────────────────────
 Disconnect
 Show last log
```

What you get:

- one click per VPN; while connecting the menu shows what it's waiting for (Duo push, SMS code, browser sign-in) and offers Cancel
- notifications when Duo needs approval, when you're connected, why a connection failed, and when it drops (with Reconnect)
- passwords only in Keychain; SMS codes read from Messages if you allow it
- one VPN and one connection attempt at a time
- VPN servers pinned in `/etc/hosts`, so a broken DNS doesn't lock you out

## Requirements

| What | Needed for |
| --- | --- |
| macOS on Apple Silicon (Homebrew in `/opt/homebrew`) | everything |
| [SwiftBar](https://github.com/swiftbar/SwiftBar) | the menu bar icon |
| Cisco Secure Client 5.x (`/opt/cisco/secureclient/bin/vpn`) | `anyconnect` profiles, get it from your VPN portal |
| [openfortivpn](https://github.com/adrienverge/openfortivpn) | `forticlient` profiles, the FortiClient app isn't used |

## Getting started

Clone and link the scripts into `~/bin`. The installer also creates `vpn.conf` from the example:

```bash
git clone https://github.com/jozefrebjak/swiftbar-vpn.git ~/swiftbar-vpn
~/swiftbar-vpn/install.sh
```

Describe your VPNs:

```bash
$EDITOR ~/swiftbar-vpn/vpn.conf
```

Store one password per AnyConnect profile. Account is the user, service is the host, `-w` without a value prompts for it:

```bash
security add-generic-password -U -a jdoe -s vpn.example.com -w
```

Install the root helper. It's needed for FortiClient and for the `/etc/hosts` fallback:

```bash
brew install --cask swiftbar
brew install openfortivpn
sudo ~/swiftbar-vpn/helper/install-helper.sh
```

Finally point SwiftBar's **Plugin Folder** at `~/bin/swiftbar`. With `~/bin` in your `PATH` the same works from a terminal:

```console
$ vpn-connect work
$ vpn-connect off
```

## Configuration

`vpn.conf` has one VPN per line, columns separated by whitespace, `-` where a column doesn't apply.

```text
# id        type         label  host                  group      user  2fa  sms_match
work        anyconnect   Work   vpn.example.com       Employees  jdoe  duo  -
uni         anyconnect   Uni    ra.example.edu        External   jdoe  sms  -
work-forti  forticlient  Work   fw.example.com:10443  -          -     duo  -
```

| Column | Meaning |
| --- | --- |
| `id` | Argument for `vpn-connect`. Unique across clients, one company can run both gateways. |
| `type` | `anyconnect` or `forticlient`. Also the section in the menu. |
| `label` | Name shown in the menu. |
| `host` | Gateway. FortiClient needs `host:port`. |
| `group` | AnyConnect group. |
| `user` | AnyConnect username and Keychain account. |
| `2fa` | `duo`, `sms` or `-`. |
| `sms_match` | Text the SMS must contain, so a bank code arriving at the same moment isn't sent to the VPN. |

> [!IMPORTANT]
> The root helper copies the host list at install time. Run `sudo helper/install-helper.sh` again whenever you add or change a host.

## How it works

**AnyConnect.** `vpn-connect` drives the official `vpn` CLI with `expect` and answers the group, username, password and SMS prompts. The password is read from Keychain inside `expect`, right before it's sent, so it never sits in an environment variable where `ps -E` could see it. The SMS code comes from `~/Library/Messages/chat.db` when SwiftBar has Full Disk Access and the iPhone forwards SMS to the Mac. Otherwise a dialog asks for it.

**FortiClient.** openfortivpn runs with `--saml-login`. The FortiGate sign-in page opens in your default browser, you do SSO and Duo there, the login comes back to `127.0.0.1:8020` and openfortivpn brings up `ppp0`.

**Menu.** The plugin combines the VPN state with small files in `~/bin`: `.vpn-status` while connecting, `.vpn-current` once connected. `vpn-connect` refreshes it through `swiftbar://refreshplugin` instead of waiting for the 10-second timer.

## The root helper

openfortivpn needs root, and so does writing `/etc/hosts`. SwiftBar can't type a sudo password, so the installer sets up a passwordless sudo rule. The obvious version, `NOPASSWD: /opt/homebrew/bin/openfortivpn`, is a root shell for anything running as your user: Homebrew files are writable by you, and openfortivpn will load pppd plugins and OpenSSL modules from configs you control.

What `install-helper.sh` does instead:

- installs root-owned copies of openfortivpn and its OpenSSL libraries in `/usr/local/libexec/swiftbar-vpn/`, relinked with `install_name_tool` and re-signed
- bakes the hosts from `vpn.conf` (validated) into a root-owned `helper` that accepts only `forti-connect <host:port>`, `forti-stop` and `hosts-update`
- runs openfortivpn under `env -i` with a root-owned config, the system CA bundle and an empty `OPENSSL_CONF`
- writes `/etc/sudoers.d/swiftbar-vpn` with exactly those commands, checked by `visudo` before it's installed

`hosts-update` runs before every connect. It asks DNS with `dig`, which ignores `/etc/hosts`, rewrites a managed block when an address changed and keeps the last known one when DNS doesn't answer. Hostnames stay the same, so certificate checks still pass.

> [!WARNING]
> The installed helper is a snapshot and doesn't follow Homebrew. After `brew upgrade openfortivpn` or `openssl@4` it keeps running the old copy until you run the installer again. Compare versions with:
>
> ```bash
> /usr/local/libexec/swiftbar-vpn/openfortivpn --version; openfortivpn --version
> ```

Remove everything, including the `/etc/hosts` block:

```bash
sudo ~/swiftbar-vpn/helper/install-helper.sh --uninstall
```

## Traps

<details>
<summary>Things that cost real time and break easily when you adapt the scripts</summary>

<br>

**The CLI won't connect while the GUI runs.** Even hidden, Secure Client answers `Connect capability is unavailable`. Quitting via AppleScript isn't enough, `pkill -f "Cisco Secure Client.app"` is.

**Don't pipe into the CLI.** With `vpn -s` some gateways try a client certificate first and fail with `Certificate Validation Failure`. Drive the interactive `vpn connect` with `expect`.

**Anchor prompts and answer each once.** The CLI echoes lines like `Group: Employees`. Unanchored patterns match them again and the group ends up in the username field.

**Pick groups by number.** When the gateway lists groups, press Enter if the default is right, otherwise send its number. Typing the name can make the server reconnect and reject the login.

**Wait before the password.** About 0.5 s. The CLI flushes input when it turns echo off.

**Never debug `expect` with `exp_internal`.** It logs the password in clear text.

**SMS text is often NULL.** In `chat.db` the body frequently lives in `attributedBody`, so read both.

**SwiftBar runs every executable in its folder.** A `plugin.sh.bak` next to the plugin is a second icon.

**Small macOS shell things.** `zsystem flock` doesn't create the lock file. `sudo -n -l <cmd>` says yes for an admin even when a password would be required, so test with `sudo -k; sudo -n <cmd>`. sudoers wants `:` escaped in arguments.

</details>

## Extending

New clients follow the same shape: a `type` branch in `bin/vpn-connect` that connects through the root helper, writes the phase to `.vpn-status` and `.vpn-current` once the tunnel is up, plus a state check in the plugin. OpenVPN (`openvpn` or Tunnelblick via AppleScript) and WireGuard (`wg-quick`) are the obvious next ones.

## License

[MIT](LICENSE)
