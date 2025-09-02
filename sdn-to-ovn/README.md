
# Migration from SDN to OVN-K

## Assumptions

`init-interfaces.service` calls `/var/init-interfaces.sh` which creates the nmconnections

The `slb` NNCP creates the `brcnv` bridge with a `bond0` `balance-slb` bond.


Recommended practice to follow before Openshift SDN network plugin migration to OVNKubernetes plugin. 
https://access.redhat.com/solutions/7070870



## Usage

## check for /usr/local/bin/nmstate-configuration.sh

### 1. Prepare the nmstate for each host


- Create the nmstate


This will generate one MC per node.  For flexibility.

For example.
`path: /etc/nmstate/openshift/${HOSTNAME}.yml`


```shell
function usage() {
    echo "Usage: $0 HOSTNAME ROLE MTU PRIMARY_MAC PRIMARY SECONDARY EXTRA_DHCP_DISABLE"
    echo
    echo "Arguments:"
    echo "  HOSTNAME            The exact hostname for  /etc/nmstate/openshift/HOSTNAME.yaml"
    echo "  ROLE                The MachineConfig role of the host"
    echo "  MTU                 Hardcode MTU for all bond interfaces to ensure bond MTU is correct"
    echo "  PRIMARY_MAC         The primary MAC address 00:11:22:33:44:55"
    echo "  PRIMARY             The primary bond port name, enx001122334455"
    echo "  SECONDARY           The secondary bond port name"
    echo "  EXTRA_DHCP_DISABLE  All the other interfaces that must have DHCP disabled"
    exit 1
}

```

[make-br-ex-nmstate.sh](make-br-ex-nmstate.sh)

```shell

# only use 'hostname -s'

make-br-ex-nmstate.sh master-0 master 1500  00:11:22:33:44:55 enx001122334455 enx101122334455 enx201122334455 enx301122334455 enx401122334455 enx501122334455

```

Notes:

- hardcode the MTU because DHCP MTU might not propagate
- delete old `brcnv` interface with IP, `state: absent`
- always disable DHCP on all other interfaces
- since we know the PRIMARY MAC, don't use `copy-from-mac:` for br-ex, hardcode
- `auto-route-metric: 48` to ensure OVN-K default route always wins.


### 2. Delete the SLB NNCP


```shell
oc get nncp
oc delete nncp slb

```

### 3. Pause MCP

```shell
oc patch mcp worker --type merge --patch '{"spec":{"paused":true}}'
oc patch mcp master --type merge --patch '{"spec":{"paused":true}}'
```

### 4. Apply `/etc/nmstate/openshift` MachineConfigs


Apply each MachineConfig.  Writes to `/etc/nmstate/openshift` will not cause a reboot.

```shell

oc apply -f 20-br-ex-master-0.yaml
oc apply -f 20-br-ex-master-1.yaml
...
oc apply -f 20-br-ex-worker-9.yaml


```

### 5. Install new nmstate-configuration.sh to remove old OpenShiftSDN `br0` bridge

until <https://issues.redhat.com//browse/OCPBUGS-57484> is backported add a custom nmstates-configuraion script to delete the leftover
OpenShiftSDN `br0`

```shell

oc apply -f 20-nmstate-configuration-master.yaml
oc apply -f 20-nmstate-configuration-worker.yaml

```

### 6. Disable old services without reboot

Disable `init-interfaces.sh` by matching the grep check for `primary` and `secondary`.

```shell

oc apply -f 30-disable-init-interfaces-master.yaml
oc apply -f 30-disable-init-interfaces-worker.yaml

```

### 7. Patch MTU Migration

until <https://issues.redhat.com/browse/OCPBUGS-53425> is backported add a systemd override to make mtu-migration service wait for an IP.

```ini
# /etc/systemd/system/mtu-migration.service.d/override.conf
[Unit]
After=wait-for-primary-ip.service
```

```shell

oc apply -f 20-mtu-migration-master.yaml
oc apply -f 20-mtu-migration-worker.yaml

```

### 8. Start migration

<https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/networking/ovn-kubernetes-network-plugin#initiating-limited-live-migration_migrate-from-openshift-sdn>

```shell

oc patch Network.config.openshift.io cluster --type='merge' --patch '{"metadata":{"annotations":{"network.openshift.io/network-type-migration":""}},"spec":{"networkType":"OVNKubernetes"}}'

```

### 9. Unpause MCP

```shell
oc patch mcp worker --type merge --patch '{"spec":{"paused":false}}'
oc patch mcp master --type merge --patch '{"spec":{"paused":false}}'
```

### 10. Disable old scripts

`/etc/systemd/system/init-interfaces.service` is installed by ignition, so we can just delete it.

`*-ovs-mac-policy-none-link-worker` is a separate MachineConfig so it can be left in place.



