
# Migration from SDN to OVN-K

## Assumptions

`setup-ovs.service` calls `/var/init-interfaces` with creates the nmconnections

`slb` NNCP creates the `brcnv` bridge.


## Usage


### 1. Prepare the files


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
make-br-ex-nmstate.sh master-0 master 1500 30:d0:42:56:66:af enx30d0425666af enx30d0425666b0 enx30d0425666ae enx30d0425666af enx30d0425666b0 enx30d0425666b1
```

Notes:
* hardcode the MTU because DHCP MTU might not propogate
* delete old `brcnv` interface with IP, `state: absent`
* always disable DHCP on all other interfaces
* since we know the PRIMARY MAC, don't use `copy-from-mac:` for br-ex, hardcode
* `auto-route-metric: 48` to ensure OVN-K default route always wins.


### 2. Delete the SLB NNCP

**TODO**: does this cause reboot?

In testing my NNCP failed to apply due to bug, so not a valid test.  https://issues.redhat.com/browse/RHEL-86035

Untested
```shell
oc get nncp
oc delete nncp slb

```


### 3. Disable old services without reboot

**TODO**: simplify


Write `"primary"` and `"secondary"` somewhere in  `/etc/NetworkManager/system-connections/` so the `init-interfaces.sh`  `grep` catches it


MCD hack.
```shell

for f in $(oc get pods -n openshift-machine-config-operator  -l k8s-app=machine-config-daemon --no-headers -o custom-columns=N:.metadata.name) ; do echo $f ; oc exec -n openshift-machine-config-operator $f -c machine-config-daemon -- chroot /rootfs bash -c "printf '%s\n' '# primary' '# secondary' > /etc/NetworkManager/system-connections/disable-init-interfaces" ; done

```

OR disable the `ExecStart` with systemd override.

```ini
# /etc/systemd/system/setup-ovs.service.d/override.conf
[Service]
ExecStart=
ExecStart=echo setup-ovs disabled
```



```shell

for f in $(oc get pods -n openshift-machine-config-operator  -l k8s-app=machine-config-daemon --no-headers -o custom-columns=N:.metadata.name) ; do echo $f ; oc exec -n openshift-machine-config-operator $f -c machine-config-daemon -- chroot /rootfs bash -c "mkdir -p /etc/systemd/system/setup-ovs.service.d && printf '%s\n' '[Service]' 'ExecStart=' 'ExecStart=echo setup-ovs disabled' > /etc/systemd/system/setup-ovs.service.d/override.conf && systemctl daemon-reload" ; done

```


### 4. Patch MTU Migration

until https://github.com/openshift/machine-config-operator/pull/4932 is merged

Untested, check systemd syntax


```ini
# /etc/systemd/system/mtu-migration.service.d/override.conf
[Unit]
After=wait-for-primary-ip.service
```


```shell

for f in $(oc get pods -n openshift-machine-config-operator  -l k8s-app=machine-config-daemon --no-headers -o custom-columns=N:.metadata.name) ; do echo $f ; oc exec -n openshift-machine-config-operator $f -c machine-config-daemon -- chroot /rootfs bash -c "mkdir -p /etc/systemd/system/mtu-migration.service.d && printf '%s\n' '[Unit]' 'After=wait-for-primary-ip.service' > /etc/systemd/system/mtu-migration.service.d/override.conf && systemctl daemon-reload" ; done

```

### 5. Start migration.



### 6. delete old MachineConfigs.

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
