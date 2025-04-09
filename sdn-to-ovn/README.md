
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

**TODO**: simplify, one or the other.


Untested, check systemd syntax

```shell
ansible-playbook -v -i inventory.json patch_setup_ovs.yaml
ansible-playbook -v -i inventory.json disable-init-interfaces.yaml

```

- [patch_setup_ovs.yaml](patch_setup_ovs.yaml)
- [disable-init-interfaces.yaml](disable-init-interfaces.yaml)


### 4. Patch MTU Migration

until https://github.com/openshift/machine-config-operator/pull/4932 is merged

Untested, check systemd syntax

```yaml
- name: Create override configuration file for mtu-migration.service
  copy:
    dest: /etc/systemd/system/mtu-migration.service.d/override.conf
    content: |
      [Unit]
      After=wait-for-primary-ip.service
```


```shell
ansible-playbook -v -i inventory.json patch_mtu_migration.yaml

```

- [patch_mtu_migration.yaml](patch_mtu_migration.yaml)

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
