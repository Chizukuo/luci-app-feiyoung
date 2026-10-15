#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
COLLECTOR="$ROOT/root/usr/bin/feiyoung-diagnose"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/feiyoung-diagnostics.XXXXXX")
TEST_PARENT=${TEST_ROOT%/*}
TMP=$TEST_ROOT
TMP_PARENT=$TEST_PARENT
FEIYOUNG_TEST_CALLS=$TEST_ROOT/calls
export FEIYOUNG_TEST_CALLS
cleanup() {
	case "$TEST_ROOT" in
		"$TEST_PARENT"/*) : ;;
		*) exit 1 ;;
	esac
	[ -d "$TEST_ROOT" ] || exit 1
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/sys/class/net/eth0/statistics" "$TEST_ROOT/etc"

for command in ifup ifdown curl wifi login service; do
	cat > "$TMP/bin/$command" <<EOF
#!/bin/sh
printf '%s %s\\n' '$command' "\$*" >> "\$FEIYOUNG_TEST_CALLS"
EOF
done
cat > "$TMP/bin/curl" <<'EOF'
#!/bin/sh
body= headers=
is_mobile=0
printf '%s' "curl $*" >> "$FEIYOUNG_TEST_CALLS"
echo "$*" | grep -q Android && is_mobile=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o|-D|-w) [ "$#" -ge 2 ] || exit 2; [ "$1" = '-o' ] && body="$2"; [ "$1" = '-D' ] && headers="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ "$is_mobile" -eq 1 ]; then
    printf '%s' '<input value="false" name="vfcodeflg"><form><input name="hiddenpassword" value="secret"><input value="2" name="pwdType"><input name="UserType" value="1"><input value="false" name="aidcauthtype"></form>' > "$body"
else
    printf '%s' '<form action="/login?secret=query"><input data-name="bad" name = "UserType" value = "1&extra=secret"><input name="pwdType" value="1"><input value="false" name="aidcauthtype"><input name="vfcodeflg" value="true"></form>' > "$body"
fi
printf '%s' 'HTTP/1.1 200 OK
Content-Type: text/html

' > "$headers"
case "$is_mobile" in 1) printf '%s' 'http://58.53.199.144:8001/style/school_hbct/mobile/index.jsp?paramStr=secretquery' ;; *) printf '%s' 'http://58.53.199.144:8001/?next=/mobile/secret' ;; esac
EOF
chmod +x "$TMP/bin/curl"

# ip/nft 只允许只读查询，其余调用仍记为危险操作
cat > "$TMP/bin/ip" <<'EOF'
#!/bin/sh
case "$*" in
  rule) printf '0:\tfrom all lookup local\n101:\tfrom 100.64.1.2 lookup 101\n1000:\tfrom all lookup main suppress_prefixlength 0\n32766:\tfrom all lookup main\n' ;;
  *) printf 'ip %s\n' "$*" >> "$FEIYOUNG_TEST_CALLS" ;;
esac
EOF
cat > "$TMP/bin/nft" <<'EOF'
#!/bin/sh
case "$*" in
  'list table inet feiyoung_mwan') exit 0 ;;
  *) printf 'nft %s\n' "$*" >> "$FEIYOUNG_TEST_CALLS" ;;
esac
EOF
chmod +x "$TMP/bin/ip" "$TMP/bin/nft"

cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
if [ "${FEIYOUNG_TEST_CONFIG_MISSING:-0}" = 1 ]; then
  case "$*" in
    *'general.passType'|*'show feiyoung') exit 1 ;;
  esac
fi
case "$*" in
  *'sqm.@queue[0]') printf 'queue0\n' ;;
  *'sqm.@queue[1]') exit 1 ;;
  *'general.enabled') printf '1\n' ;;
  *'general.passType') printf '1\n' ;;
  *'general.pause_enabled') printf '0\n' ;;
  *'general.pause_disconnect_wan') printf '0\n' ;;
  *'general.check_interval') printf '30\n' ;;
  *'general.connect_timeout') printf '5\n' ;;
  *'general.total_timeout') printf '10\n' ;;
  *'show feiyoung') printf 'feiyoung.general=global\nfeiyoung.a1=account\nfeiyoung.a2=account\nfeiyoung.a3=account\n' ;;
  *'a1.username'|*'a3.username') printf '18900001111\n' ;;
  *'a2.username') printf '13800001234\n' ;;
  *'a2.enabled') printf '0\n' ;;
  *'a3.client_type') printf 'mobile\n' ;;
  *) exit 1 ;;
esac
EOF
cat > "$TMP/bin/ubus" <<'EOF'
#!/bin/sh
case "$*" in
  *'system board'*) printf '{"model":"stub","release":{"version":"21.02","target":"stub/target"}}\n' ;;
  *'network.interface.wan status'*) printf '{"up":true,"proto":"dhcp","device":"eth0","l3_device":"eth0"}\n' ;;
esac
EOF
cat > "$TMP/bin/jsonfilter" <<'EOF'
#!/bin/sh
input=$(sed -n '1p')
case "$*:$input" in
  *'@.model'* ) printf 'stub\n' ;;
  *'@.release.version'* ) printf '21.02\n' ;;
  *'@.release.target'* ) printf 'stub/target\n' ;;
  *'@.up'* ) printf 'true\n' ;;
  *'@.proto'* ) printf 'dhcp\n' ;;
  *'@.device'*|*'@.l3_device'*) printf 'eth0\n' ;;
esac
EOF
cat > "$TMP/bin/tc" <<'EOF'
#!/bin/sh
case "$1" in
  qdisc) printf 'qdisc cake 1: root bandwidth 100Mbit\n' ;;
  class) printf 'class cake 1:1 root rate 10Mbit ceil 20Mbit\n' ;;
esac
EOF
cat > "$TMP/bin/logread" <<'EOF'
#!/bin/sh
printf 'old user=should_not_appear https://secret.invalid/x\n'
printf 'FEIYOUNG_DIAG build=2.2.0-1 state=online user=123456 password=secret https://secret.invalid/x\n'
EOF
chmod +x "$TMP/bin"/*
printf 'ok\n' > "$TMP/sys/class/net/eth0/operstate"
printf '1000\n' > "$TMP/sys/class/net/eth0/speed"
printf 'full\n' > "$TMP/sys/class/net/eth0/duplex"
for f in rx_bytes tx_bytes rx_errors tx_errors rx_dropped tx_dropped; do printf '0\n' > "$TMP/sys/class/net/eth0/statistics/$f"; done
printf '0\n' > "$TMP/loadavg"
printf 'cpu  1 2 3 4\n' > "$TMP/stat"
printf 'status\n' > "$TMP/feiyoung_status"

output=$(PATH="$TMP/bin:$PATH" \
  SYSFS="$TMP/sys" PROCFS="$TMP" \
  STATUS_FILE="$TMP/feiyoung_status" \
  "$COLLECTOR" 2>&1)
printf '%s\n' "$output" | grep -q '^board.model=stub$'
printf '%s\n' "$output" | grep -q '^wan.proto=dhcp$'
printf '%s\n' "$output" | grep -q '^config.pause_enabled=0$'
printf '%s\n' "$output" | grep -q '^account.1.user=189\*\*\*\*1111 type=pc enabled=1$'
printf '%s\n' "$output" | grep -q '^account.2.user=189\*\*\*\*1111 type=mobile enabled=1$'
if printf '%s\n' "$output" | grep -q '138\*\*\*\*1234'; then printf '%s\n' 'disabled account listed' >&2; exit 1; fi
printf '%s\n' "$output" | grep -q '^mwan.table=present$'
printf '%s\n' "$output" | grep -q '^rule 101:.*from <ip> lookup 101$'
printf '%s\n' "$output" | grep -q '^rule 1000:.*lookup main suppress_prefixlength 0$'
if printf '%s\n' "$output" | grep -q '100\.64\.1\.2'; then printf '%s\n' 'rule ip not redacted' >&2; exit 1; fi
printf '%s\n' "$output" | grep -q '^feiyoung.status=status$'
printf '%s\n' "$output" | grep -q '^tc.qdisc:$'
if printf '%s\n' "$output" | grep -Eiq 'should_not_appear|secret|123456|https?://'; then
	printf '%s\n' 'sensitive output detected' >&2
	exit 1
fi
if printf '%s\n' "$output" | grep -Eiq 'ifup|ifdown|curl|login|restart|uci commit|iptables|nft'; then
	printf '%s\n' 'dangerous operation marker detected' >&2
	exit 1
fi
if [ -s "$FEIYOUNG_TEST_CALLS" ]; then
	printf '%s\n' 'dangerous command executed' >&2
	exit 1
fi
printf '%s\n' 'collector isolation test: PASS'
missing_output=$(PATH="$TMP/bin:$PATH" FEIYOUNG_TEST_CONFIG_MISSING=1 SYSFS="$TMP/sys" PROCFS="$TMP" STATUS_FILE="$TMP/feiyoung_status" "$COLLECTOR" 2>&1)
printf '%s\n' "$missing_output" | grep -q '^config.passType=unknown$'
if printf '%s\n' "$missing_output" | grep -q '^account\.'; then printf '%s\n' 'phantom account listed' >&2; exit 1; fi
printf '123.5 0\n' > "$TMP/uptime"
output=$(PATH="$TMP/bin:$PATH" SYSFS="$TMP/sys" PROCFS="$TMP" STATUS_FILE="$TMP/feiyoung_status" "$COLLECTOR" 2>&1)
printf '%s\n' "$output" | grep -q '^uptime.seconds=123.5$'
portal_output=$(PATH="$TMP/bin:$PATH" TMPDIR="$TMP" "$COLLECTOR" --portal 2>&1)
printf '%s\n' "$portal_output" | grep -q '^portal.pc_root template=pc curl_rc=0 http_code=200$'
printf '%s\n' "$portal_output" | grep -q '^portal.mobile_root template=mobile curl_rc=0 http_code=200$'
printf '%s\n' "$portal_output" | grep -q '^portal.mobile_template template=mobile curl_rc=0 http_code=200$'
printf '%s\n' "$portal_output" | grep -q '^portal.pc_root.UserType=unknown$'
printf '%s\n' "$portal_output" | grep -q '^portal.mobile_template.pwdType=2$'
if printf '%s\n' "$portal_output" | grep -Eiq 'secret|query|https?://|=paramStr|=password'; then
	printf '%s\n' 'portal sensitive output detected' >&2
	exit 1
fi
if ! grep -q '^curl ' "$FEIYOUNG_TEST_CALLS" || grep '^curl ' "$FEIYOUNG_TEST_CALLS" | grep -Eq -- '(^| )(--data|-X|POST)($| )'; then
	printf '%s\n' 'portal call contract failed' >&2
	exit 1
fi
[ "$(grep -o 'curl ' "$FEIYOUNG_TEST_CALLS" | wc -l | tr -d ' ')" -eq 3 ]
printf '%s\n' 'portal isolation test: PASS'
