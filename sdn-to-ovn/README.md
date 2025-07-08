
# Migration from SDN to OVN-K

## Assumptions

`setup-ovs.service` calls `/var/init-interfaces.sh` which creates the nmconnections

The `slb` NNCP creates the `brcnv` bridge with a `bond0` `balance-slb` bond.


## Usage

## check for /usr/local/bin/nmstate-configuration.sh


### 1. Prepare the nmstate for each host.


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
* hardcode the MTU because DHCP MTU might not propagate
* delete old `brcnv` interface with IP, `state: absent`
* always disable DHCP on all other interfaces
* since we know the PRIMARY MAC, don't use `copy-from-mac:` for br-ex, hardcode
* `auto-route-metric: 48` to ensure OVN-K default route always wins.


### 2. Delete the SLB NNCP


```shell
oc get nncp
oc delete nncp slb

```


### 3. Disable old services without reboot


Write `"primary"` and `"secondary"` somewhere in  `/etc/NetworkManager/system-connections/` so the `init-interfaces.sh`  `grep` catches it

[disable-init-interfaces.sh](disable-init-interfaces.sh)



### 4. Patch MTU Migration

until https://issues.redhat.com//browse/OCPBUGS-53425 is backported add a systemd override to make mtu-migration service wait for an IP.


```ini
# /etc/systemd/system/mtu-migration.service.d/override.conf
[Unit]
After=wait-for-primary-ip.service
```

[patch-mtu-migration.sh](patch-mtu-migration.sh)


### 5. Apply `/etc/nmstate/openshift` MachineConfigs


Apply each MachineConfig.  Writes to `/etc/nmstate/openshift` will not cause a reboot.

```shell

oc apply -f 20-br-ex-master-0.yaml
oc apply -f 20-br-ex-master-1.yaml
...
oc apply -f 20-br-ex-worker-9.yaml


```

Wait for MachineConfigs to be applied

### 5. Start migration.

https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/networking/ovn-kubernetes-network-plugin#initiating-limited-live-migration_migrate-from-openshift-sdn

```shell

oc patch Network.config.openshift.io cluster --type='merge' --patch '{"metadata":{"annotations":{"network.openshift.io/network-type-migration":""}},"spec":{"networkType":"OVNKubernetes"}}'

```

### 6. Remove OpenShiftSDN `br0` bridge

Delete the old OpenShiftSDN `br0` bridge from all the nodes.

`ovs-vsctl --timeout=30 --if-exists del-br br0`

[delete-br0.sh](delete-br0.sh)


### 7. Delete old MachineConfigs.

TBD

Disable capture-macs.service ?  No-op?

Remove /boot/mac_addresses ?  Probably not.


This is still required, so make a new MC to keep it before deleting the old MC.

```ini
[root@master-2 core]# cat /etc/systemd/network/50-ovs-mac-policy-none.link
[Match]
Driver=openvswitch
[Link]

```
