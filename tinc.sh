#!/usr/bin/env bash

long2ip() {
	local ip=$1
	echo -n $((ip >> 24 & 255))"."$((ip >> 16 & 255))"."$((ip >> 8 & 255 ))"."$((ip & 255))
}

match="${1}"

cat /etc/hosts | awk '$3 == "#" && $4 == "tinc" {print $1, $2, $5, $6, $7, $8}' | while read int hostname netname netsize port ext; do
	tincname=$(echo -n "${hostname}" | tr -c '[:alnum:]' '_')
	if [ "x${match}" != "x" -a "x${match}" != "x${netname}" -a "x${match}" != "x${hostname}" -a "x${match}" != "x${tincname}" ]; then
		continue
	fi
	if [ "x${int}" == "x#auto" ]; then
		int=$(long2ip $(echo -n "${netname}"$'\t'"${hostname}"$'\t'"${ext}" | sha512sum | tr -d -c '[:digit:]' | sed -r 's/(.)/\1 /g' | tr " " "\n" | awk '{sum=(sum+1+NR)*($1+1+NR);}END{print((sum%16777215)+167772160);}'))
	fi
	mkdir -vp "/etc/tinc/${netname}/hosts/"
	echo -n "Gathering data from ${hostname} (${ext}) / ${tincname} (${int}) ..."
	if test -s "/etc/tinc/${netname}/hosts/${tincname}" && cat "/etc/tinc/${netname}/hosts/${tincname}" | fgrep -q "BEGIN RSA PUBLIC KEY"; then
		echo "skipped"
		continue
	fi
	(
		echo "Address = ${ext} ${port}"
		echo ""
		ssh -n -F/dev/null -oPasswordAuthentication=no -oUseRoaming=no -oStrictHostKeyChecking=no -oConnectTimeout=30 "root@${ext}" "tincd --version > /dev/null 2> /dev/null || apt -y install tinc; mkdir -p /etc/tinc/${netname}/hosts/; test -f /etc/tinc/${netname}/rsa_key.pub || (echo; echo;) | tincd -n ${netname} -K4096; test -f /etc/tinc/${netname}/.nodel || find /etc/tinc/${netname}/hosts/ -type f -delete > /dev/null; cat /etc/tinc/${netname}/rsa_key.pub"
	) > "/etc/tinc/${netname}/hosts/${tincname}"
	if cat "/etc/tinc/${netname}/hosts/${tincname}" | fgrep -q "BEGIN RSA PUBLIC KEY"; then
		echo done
	else
		echo failed
		rm "/etc/tinc/${netname}/hosts/${tincname}"
	fi
done

cat /etc/hosts | awk '$3 == "#" && $4 == "tinc" {print $1, $2, $5, $6, $7, $8}' | while read int hostname netname netsize port ext; do
	tincname=$(echo -n "${hostname}" | tr -c '[:alnum:]' '_')
	if [ "x${match}" != "x" -a "x${match}" != "x${netname}" -a "x${match}" != "x${hostname}" -a "x${match}" != "x${tincname}" ]; then
		continue
	fi
	if [ "x${int}" == "x#auto" ]; then
		int=$(long2ip $(echo -n "${netname}"$'\t'"${hostname}"$'\t'"${ext}" | sha512sum | tr -d -c '[:digit:]' | sed -r 's/(.)/\1 /g' | tr " " "\n" | awk '{sum=(sum+1+NR)*($1+1+NR);}END{print((sum%16777215)+167772160);}'))
	fi
	echo "Deploying ${hostname} (${ext}) / ${tincname} (${int}) ..."
	if [ "x${netsize}" == "x32" ]; then
		broadcast="no"
		devicetype="tun"
		subnet="${int}/32"
		mode="router"
		scripts="https://scr.meo.ws/files/tinc-scripts/tinc-up https://scr.meo.ws/files/tinc-scripts/tinc-down https://scr.meo.ws/files/tinc-scripts/subnet-up https://scr.meo.ws/files/tinc-scripts/subnet-down"
	else
		broadcast="mst"
		devicetype="tap"
		subnet=$(sipcalc "${int}/${netsize}" | grep -E '^Network address' | awk '{print $4}')
		mode="switch"
		scripts="https://scr.meo.ws/files/tinc-scripts/tinc-up https://scr.meo.ws/files/tinc-scripts/tinc-down"
	fi
	tar c /etc/tinc/${netname}/hosts/ 2> /dev/null | ssh "root@${ext}" "tar x -mC / -f /dev/stdin"
	(
cat << EOF
# myip = ${int}/${netsize}
AddressFamily = ipv4
Broadcast = ${broadcast}
DecrementTTL = no
DeviceType = ${devicetype}
DirectOnly = no
Forwarding = internal
Hostnames = no
IffOneQueue = no
Interface = ${netname}
KeyExpire = 3600
LocalDiscovery = no
MACExpire = 600
MaxTimeout = 30
Mode = ${mode}
Name = ${tincname}
PingInterval = 60
PingTimeout = 5
PriorityInheritance = no
ProcessPriority = high
ReplayWindow = 128
StrictSubnets = no
TunnelServer = no
Address = ${ext}
Cipher = none
ClampMSS = yes
Compression = 0
Digest = none
IndirectData = no
MACLength = 0
PMTU = 1514
PMTUDiscovery = yes
Port = ${port}
Subnet = ${subnet}
EOF
	for connectto in /etc/tinc/${netname}/hosts/*; do
		echo "ConnectTo = "$(basename "${connectto}")
	done
	) | ssh -F/dev/null -oPasswordAuthentication=no -oUseRoaming=no -oStrictHostKeyChecking=no -oConnectTimeout=30 "root@${ext}" "
	ls -d1 /etc/tinc/*/ | cut -d/ -f4 > /etc/tinc/nets.boot;
	cat > /etc/tinc/${netname}/tinc.conf;
	rm -f /etc/tinc/${netname}/tinc-down /etc/tinc/${netname}/tinc-up /etc/tinc/${netname}/subnet-down /etc/tinc/${netname}/subnet-up;
	wget -P /etc/tinc/${netname}/ -q ${scripts};
	chmod +x /etc/tinc/${netname}/tinc-up /etc/tinc/${netname}/tinc-down /etc/tinc/${netname}/subnet-up /etc/tinc/${netname}/subnet-down > /dev/null 2> /dev/null;
	systemctl enable tinc@${netname}.service > /dev/null 2> /dev/null && (
		systemctl stop tinc@${netname}.service;
		/usr/sbin/tincd -n ${netname} --kill=9;
		systemctl start tinc@${netname}.service;
		true
	) || (
		service tinc stop;
		pkill -9 -f '^/usr/sbin/tincd -n .*';
		service tinc restart
	)
"
done
