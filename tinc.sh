#!/usr/bin/env bash

# Defaults, can be overwritten using /etc/tinc-deploy/global.conf or on a per-network basis using /etc/tinc-deploy/net-{network-name}.conf
set_defaults() {
	tc_AddressFamily="ipv4"
	tc_DecrementTTL="no"
	tc_DirectOnly="no"
	tc_Forwarding="internal"
	tc_Hostnames="no"
	tc_IffOneQueue="no"
	tc_KeyExpire="3600"
	tc_LocalDiscovery="no"
	tc_MACExpire="600"
	tc_MaxTimeout="30"
	tc_PingInterval="60"
	tc_PingTimeout="5"
	tc_PriorityInheritance="no"
	tc_ProcessPriority="high"
	tc_ReplayWindow="128"
	tc_StrictSubnets="no"
	tc_TunnelServer="no"
	tc_Cipher="none"
	tc_ClampMSS="yes"
	tc_Compression="0"
	tc_Digest="none"
	tc_IndirectData="no"
	tc_MACLength="0"
	tc_PMTU="1514"
	tc_PMTUDiscovery="yes"
}

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
	mkdir -p "/etc/tinc/${netname}/hosts/"
	echo -n "Gathering data from ${hostname} (${ext}) / ${tincname} (${int}) ..."
	if test -s "/etc/tinc/${netname}/hosts/${tincname}" && cat "/etc/tinc/${netname}/hosts/${tincname}" | fgrep -q "BEGIN RSA PUBLIC KEY"; then
		echo "skipped"
		continue
	fi
	(
		echo "Address = ${ext} ${port}"
		echo ""
		ssh -n -F/dev/null -oPasswordAuthentication=no -oUseRoaming=no -oStrictHostKeyChecking=no -oConnectTimeout=30 "root@${ext}" "
			tincd --version > /dev/null 2> /dev/null || (apt-get update > /dev/null 2> /dev/null; apt-get -y install tinc > /dev/null 2> /dev/null;);
			tincd --version > /dev/null 2> /dev/null || exit 1;
			mkdir -p /etc/tinc/${netname}/hosts/ > /dev/null 2> /dev/null;
			test -f /etc/tinc/${netname}/rsa_key.pub > /dev/null 2> /dev/null || (echo; echo;) | tincd -n ${netname} -K4096 > /dev/null 2> /dev/null;
			test -f /etc/tinc/${netname}/.nodel > /dev/null 2> /dev/null || find /etc/tinc/${netname}/hosts/ -type f -delete > /dev/null 2> /dev/null;
			cat /etc/tinc/${netname}/rsa_key.pub 2> /dev/null
		"
	) > "/etc/tinc/${netname}/hosts/${tincname}"
	if cat "/etc/tinc/${netname}/hosts/${tincname}" | fgrep -q "BEGIN RSA PUBLIC KEY"; then
		echo done
	else
		echo failed
		rm "/etc/tinc/${netname}/hosts/${tincname}"
	fi
done

cat /etc/hosts | awk '$3 == "#" && $4 == "tinc" {print $1, $2, $5, $6, $7, $8}' | while read int hostname netname netsize port ext; do
	set_defaults
	test -f "/etc/tinc-deploy/global.conf" && source "/etc/tinc-deploy/global.conf"
	tincname=$(echo -n "${hostname}" | tr -c '[:alnum:]' '_')
	if [ "x${match}" != "x" -a "x${match}" != "x${netname}" -a "x${match}" != "x${hostname}" -a "x${match}" != "x${tincname}" ]; then
		continue
	fi
	if [ "x${int}" == "x#auto" ]; then
		int=$(long2ip $(echo -n "${netname}"$'\t'"${hostname}"$'\t'"${ext}" | sha512sum | tr -d -c '[:digit:]' | sed -r 's/(.)/\1 /g' | tr " " "\n" | awk '{sum=(sum+1+NR)*($1+1+NR);}END{print((sum%16777215)+167772160);}'))
	fi
	echo -n "Deploying ${hostname} (${ext}) / ${tincname} (${int}) ..."
	tc_Interface="${netname}"
	tc_Name="${tincname}"
	tc_Address="${ext}"
	tc_Port="${port}"
	if [ "x${netsize}" == "x32" ]; then
		tc_Broadcast="no"
		tc_DeviceType="tun"
		tc_Subnet="${int}/32"
		tc_Mode="router"
		scripts="https://scr.meo.ws/files/tinc-scripts/tinc-up https://scr.meo.ws/files/tinc-scripts/tinc-down https://scr.meo.ws/files/tinc-scripts/subnet-up https://scr.meo.ws/files/tinc-scripts/subnet-down"
	else
		tc_Broadcast="mst"
		tc_DeviceType="tap"
		tc_Subnet=$(sipcalc "${int}/${netsize}" | grep -E '^Network address' | awk '{print $4}')
		tc_Mode="switch"
		scripts="https://scr.meo.ws/files/tinc-scripts/tinc-up https://scr.meo.ws/files/tinc-scripts/tinc-down"
	fi
	echo -n "hosts..."
	tar c /etc/tinc/${netname}/hosts/ 2> /dev/null | ssh "root@${ext}" "tar x -mC / -f /dev/stdin"
	test -f "/etc/tinc-deploy/net-${netname}.conf" && source "/etc/tinc-deploy/net-${netname}.conf"
	(
cat << EOF
##################################################
# Auto-generated tinc network configuration file #
# date=$(TZ=Etc/UTC date -Is)                  #
# time=$(date +%s)                                #
##################################################
# myip = ${int}/${netsize}
AddressFamily = ${tc_AddressFamily}
Broadcast = ${tc_Broadcast}
DecrementTTL = ${tc_DecrementTTL}
DeviceType = ${tc_DeviceType}
DirectOnly = ${tc_DirectOnly}
Forwarding = ${tc_Forwarding}
Hostnames = ${tc_Hostnames}
IffOneQueue = ${tc_IffOneQueue}
Interface = ${tc_Interface}
KeyExpire = ${tc_KeyExpire}
LocalDiscovery = ${tc_LocalDiscovery}
MACExpire = ${tc_MACExpire}
MaxTimeout = ${tc_MaxTimeout}
Mode = ${tc_Mode}
Name = ${tc_Name}
PingInterval = ${tc_PingInterval}
PingTimeout = ${tc_PingTimeout}
PriorityInheritance = ${tc_PriorityInheritance}
ProcessPriority = ${tc_ProcessPriority}
ReplayWindow = ${tc_ReplayWindow}
StrictSubnets = ${tc_StrictSubnets}
TunnelServer = ${tc_TunnelServer}
Address = ${tc_Address}
Cipher = ${tc_Cipher}
ClampMSS = ${tc_ClampMSS}
Compression = ${tc_Compression}
Digest = ${tc_Digest}
IndirectData = ${tc_IndirectData}
MACLength = ${tc_MACLength}
PMTU = ${tc_PMTU}
PMTUDiscovery = ${tc_PMTUDiscovery}
Port = ${tc_Port}
Subnet = ${tc_Subnet}
EOF
	for connectto in /etc/tinc/${netname}/hosts/*; do
		echo "ConnectTo = "$(basename "${connectto}")
	done
	) | ssh -F/dev/null -oPasswordAuthentication=no -oUseRoaming=no -oStrictHostKeyChecking=no -oConnectTimeout=30 "root@${ext}" "

	echo -n 'netsboot...'
	ls -d1 /etc/tinc/*/ | cut -d/ -f4 > /etc/tinc/nets.boot;
	echo -n 'config...'
	cat > /etc/tinc/${netname}/tinc.conf;

	echo -n 'scripts...'
	rm -f /etc/tinc/${netname}/tinc-down /etc/tinc/${netname}/tinc-up /etc/tinc/${netname}/subnet-down /etc/tinc/${netname}/subnet-up;
	wget -qP /etc/tinc/${netname}/ ${scripts};
	chmod +x /etc/tinc/${netname}/tinc-up /etc/tinc/${netname}/tinc-down /etc/tinc/${netname}/subnet-up /etc/tinc/${netname}/subnet-down > /dev/null 2> /dev/null;

	echo -n 'restart:'
	systemctl enable tinc@${netname}.service > /dev/null 2> /dev/null && (
		echo -n 'systemd...'
		systemctl stop tinc@${netname}.service > /dev/null 2> /dev/null;
		/usr/sbin/tincd -n ${netname} --kill=9 > /dev/null 2> /dev/null;
		systemctl start tinc@${netname}.service > /dev/null 2> /dev/null;
		true
	) || (
		echo -n 'init...'
		service tinc stop > /dev/null 2> /dev/null;
		pkill -9 -f '^/usr/sbin/tincd -n .*' > /dev/null 2> /dev/null;
		service tinc restart > /dev/null 2> /dev/null;
	)
"
	echo done
done
