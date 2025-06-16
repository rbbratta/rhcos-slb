#!/usr/bin/env bash




function make_mc () {

  local MTU=$1; shift
  local PRIMARY_MAC=$1; shift
  local PRIMARY=$1; shift
  local SECONDARY=$1; shift


  cat << EOF
ovn:
  bridge-mappings:
    - localnet: localnet-network
      bridge: br-ex
      state: present
interfaces:
  - name: br-ex
    mtu: ${MTU}
    type: ovs-bridge
    state: up
    ipv4:
      enabled: false
      dhcp: false
    ipv6:
      enabled: false
      dhcp: false
    bridge:
      allow-extra-patch-ports: true
      port:
      - name: br-ex
      - name: patch-ex-to-cnv
    ovs-db:
      external_ids:
        bridge-uplink: "patch-ex-to-cnv"
  - name: br-ex
    type: ovs-interface
    state: up
    mac-address: ${PRIMARY_MAC}
    ipv4:
      enabled: true
      dhcp: true
      auto-route-metric: 48
    ipv6:
      enabled: false
      dhcp: false
  - name: br0
    type: ovs-interface
    state: absent
  - name: br0
    type: ovs-bridge
    state: absent
  - name: brcnv
    type: ovs-interface
    state: absent
  - name: brcnv
    type: ovs-bridge
    state: up
    ipv4:
      enabled: false
      dhcp: false
    ipv6:
      enabled: false
      dhcp: false
    bridge:
      options:
        stp: false
        mcast-snooping-enable: false
        rstp: false
      allow-extra-patch-ports: true
      port:
      - name: patch-cnv-to-ex
      - name: bond0
        link-aggregation:
          mode: balance-slb
          port:
          - name: ${PRIMARY}
          - name: ${SECONDARY}
  - name: patch-ex-to-cnv
    type: ovs-interface
    state: up
    patch:
      peer: patch-cnv-to-ex
  - name: patch-cnv-to-ex
    type: ovs-interface
    state: up
    patch:
      peer: patch-ex-to-cnv
  - name: ${PRIMARY}
    description: primary
    type: ethernet
    state: up
    mtu: ${MTU}
    ipv4:
      enabled: false
    ipv6:
      enabled: false
  - name: ${SECONDARY}
    description: secondary
    type: ethernet
    state: up
    mtu: ${MTU}
    ipv4:
      enabled: false
    ipv6:
      enabled: false
EOF


# DHCP disable all additional interfaces
for intf in "$@"; do
  cat <<EOF
  - name: $intf
    type: ethernet
    state: up
    ipv4:
      enabled: false
    ipv6:
      enabled: false
EOF
done

}

function usage() {
    echo "Usage: $0 HOSTNAME ROLE MTU PRIMARY_MAC PRIMARY SECONDARY EXTRA_DHCP_DISABLE"
    echo
    echo "Arguments:"
    echo "  HOSTNAME            The exact hostname for  /etc/nmstate/openshift/HOSTNAME.yaml"
    echo "  ROLE                The MachineConfig role of the host."
    echo "  MTU                 Hardcode MTU for all bond interfaces to ensure bond MTU is correct"
    echo "  PRIMARY_MAC         The primary MAC address 00:11:22:33:44:55"
    echo "  PRIMARY             The primary bond port name, enx001122334455"
    echo "  SECONDARY           The secondary bond port name"
    echo "  EXTRA_DHCP_DISABLE  All the other interfaces that must have DHCP disabled"
    exit 1
}

# Example usage within the script:
if [ "$#" -le 6 ]; then
    usage
fi

HOSTNAME=$1; shift
ROLE=$1; shift

BASE64_YAML=$(make_mc "$@" | yq | tee nmstate-"${ROLE}"-"${HOSTNAME}".yml | base64 -w0)

cat <<EOF | tee 10-br-ex-"${ROLE}"-"${HOSTNAME}".yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${ROLE}
  name: 10-br-ex-${ROLE}-${HOSTNAME}
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,${BASE64_YAML}
        mode: 420
        overwrite: true
        path: /etc/nmstate/openshift/${HOSTNAME}.yml


EOF

# decode rendered MC for HOSTNAME
#oc get mc -o yaml rendered-master-.... | yq  '.spec.config.storage.files[] | select(.path == "/etc/nmstate/openshift/${HOSTNAME}.yml") | .contents.source'  | python3 -c 'import sys ; from urllib.request import urlopen ;  sys.stdout.buffer.write(urlopen(sys.stdin.read()).read())'
