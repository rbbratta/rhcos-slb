
# Migration from SDN to OVN-K

## Assumptions

`init-interfaces.service` calls `/var/init-interfaces.sh` which creates the nmconnections

The `slb` NNCP creates the `brcnv` bridge with a `bond0` `balance-slb` bond.



## Prerequisites

Recommended practice to follow before Openshift SDN network plugin migration to OVNKubernetes plugin. 
https://access.redhat.com/solutions/7070870


> If running OpenShift Data Foundations (ODF), refer to [this KCS for health checking prior to migration](https://access.redhat.com/articles/4870821).
> 
> Please open a [proactive case prior to your migration](https://access.redhat.com/solutions/3521621) for Red Hat assistance and (as applicable) mention that you use ODF storage for additional validation of storage pools.



## Usage


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
    echo "  HOSTNAME            The exact short hostname for  /etc/nmstate/openshift/HOSTNAME.yaml"
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

The script will generate:
- `nmstate-"${ROLE}"-"${HOSTNAME}".yml ` raw NMstate
- `20-br-ex-"${ROLE}"-"${HOSTNAME}".yaml` MachinConfig

Verify the `nmstate-"${ROLE}"-"${HOSTNAME}".yml` syntax and `.nmconnections` with:

 ```shell
 nmstatectl gc nmstate-"${ROLE}"-"${HOSTNAME}".yml
 ```


We generate a single MachineConfig per node to enable per-node MachineConfig modifications.
The NMstate files are copied to every machine in the role. However, writes to `/etc/nmstate/openshift` will not trigger a reboot, allowing these configurations to be adjusted without reboout.

The MachineConfigs can be merged into logical groups if required.


Notes:

- Hardcode the MTU because DHCP MTU might not propagate
- Delete old `brcnv` interface with IP, `state: absent`
- Delete old `brcnv-if` interface with IP, `state: absent`
- Always disable DHCP on all other interfaces
- Since we know the PRIMARY MAC, don't use `copy-from-mac:` for br-ex, hardcode
- `auto-route-metric: 48` to ensure OVN-K default route always wins.


**Double-check the NMstate**




### 2. Delete the SLB NNCP

Deleting the NNCP should not change the network, the network config is already applied.

Make sure the NNCP is already applied
```shell
oc get nncp

```shell
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

source: [nmstate-configuration.sh](./nmstate-configuration.sh)

### 6. Disable old services without reboot

Disable `init-interfaces.sh` by matching the grep check for `primary` and `secondary`.

```shell

oc apply -f 30-disable-init-interfaces-master.yaml
oc apply -f 30-disable-init-interfaces-worker.yaml

```

### 7. Patch MTU Migration

until <https://issues.redhat.com/browse/OCPBUGS-53425> is backported add a systemd override to make mtu-migration service wait for an IP.

First in 4.16.41
<https://github.com/openshift/machine-config-operator/commits/19d2a0275bf5e566dff786fbc88fe97c69d131d9>


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




### 11. Replacing the OVS bridge CNI with ovn-k8s-cni-overlay


Delete the old net-attach-def and add the new net-attach-def and reboot the VMs.

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: <name>
  namespace: virtualmachines
spec:
  config: |-
    {
        "cniVersion":"0.3.1",
        "bridge":"brcnv",
        "type":"ovs",
        "vlan":200
    }
```

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: <name>
  namespace: virtualmachines
spec:
  config: |-
    {
        "cniVersion": "0.3.1",
        "name": "localnet-network",
        "type": "ovn-k8s-cni-overlay",
        "topology": "localnet",
        "vlanID": 200
    }

```
