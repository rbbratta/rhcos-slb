
# Migration from SDN to OVN-K


OVN-K live migration is essentially a double-upgrade.  Each node will reboot twice.


The live migration workflow is described here: https://github.com/openshift/enhancements/blob/master/enhancements/network/sdn-live-migration.md#workflow-description


## Assumptions

`init-interfaces.service` calls `/var/init-interfaces.sh` which creates the nmconnections

The `slb` NNCP creates the `brcnv` bridge with a `bond0` `balance-slb` bond.



## Prerequisites

Recommended practice to follow before Openshift SDN network plugin migration to OVNKubernetes plugin. 
https://access.redhat.com/solutions/7070870


> If running OpenShift Data Foundations (ODF), refer to [this KCS for health checking prior to migration](https://access.redhat.com/articles/4870821).
> 
> Please open a [proactive case prior to your migration](https://access.redhat.com/solutions/3521621) for Red Hat assistance and (as applicable) mention that you use ODF storage for additional validation of storage pools.


## Conditions


If you use ODF and Ceph, ensure you have enough available nodes in each MachineConfigPool to maintain a ceph-mon quorum during the node drain and reboot cycle.


## Usage


### 1. Prepare the nmstate for each host


- Create the nmstate


This will generate one MC per node for flexibility.

For example:
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
    echo "  LOCALNET_NAME       The name of the localnet network"
    echo "  EXTRA_DHCP_DISABLE  (Optional) All the other interfaces that must have DHCP disabled"
    exit 1
}

```

[make-br-ex-nmstate.sh](make-br-ex-nmstate.sh)

```shell

# only use 'hostname -s'

make-br-ex-nmstate.sh master-0 master 1500  00:11:22:33:44:55 enx001122334455 enx101122334455 localnet-1234 enx201122334455 enx301122334455 enx401122334455 enx501122334455


```

The script will generate:
- `nmstate-"${ROLE}"-"${HOSTNAME}".yml` raw NMstate
- `20-br-ex-"${ROLE}"-"${HOSTNAME}".yaml` MachineConfig

Verify the `nmstate-"${ROLE}"-"${HOSTNAME}".yml` syntax and `.nmconnections` with:

 ```shell
 nmstatectl gc nmstate-"${ROLE}"-"${HOSTNAME}".yml
 ```


We generate a single MachineConfig per node to enable per-node MachineConfig modifications.
The NMstate files are copied to every machine in the role. However, writes to `/etc/nmstate/openshift` will not trigger a reboot, allowing these configurations to be adjusted without reboot.

The MachineConfigs can be merged into logical groups if required.


Notes:

- Hard-code the MTU because the DHCP MTU might not propagate
- Delete the old `brcnv` interface with IP; use `state: absent`
- Delete the old `brcnv-if` interface with IP; use `state: absent`
- Always disable DHCP on all other interfaces
- Since we know the PRIMARY MAC, don't use `copy-from-mac:` for br-ex; hard-code it
- `auto-route-metric: 48` to ensure the OVN-K default route always wins.


**Double-check the NMstate**




### 2. Delete the SLB NNCP

Deleting the NNCP should not change the network because the configuration has already been applied.

Make sure the NNCP is already applied
```shell
oc get nncp
oc delete nncp slb
```

### 3. Pause MCP

Pause all the MCPs

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

### 5. Install a new `nmstate-configuration.sh` to remove the old OpenShift SDN `br0` bridge

Until <https://issues.redhat.com/browse/OCPBUGS-57484> is backported, add a custom nmstate-configuration script to delete the leftover OpenShift SDN `br0`.

```shell

oc apply -f 20-nmstate-configuration-master.yaml
oc apply -f 20-nmstate-configuration-worker.yaml

```

Source: [nmstate-configuration.sh](./nmstate-configuration.sh)

### 6. Disable old services without reboot

Disable `init-interfaces.sh` by matching the grep check for `primary` and `secondary`.

```shell

oc apply -f 30-disable-init-interfaces-master.yaml
oc apply -f 30-disable-init-interfaces-worker.yaml

```

### 7. Patch MTU migration

Until <https://issues.redhat.com/browse/OCPBUGS-53425> is backported, add a systemd override to make the `mtu-migration` service wait for an IP.

First fixed in 4.16.41.
<https://github.com/openshift/machine-config-operator/commits/19d2a0275bf5e566dff786fbc88fe97c69d131d9>


Not needed in 4.16.41 or later.

```ini
# /etc/systemd/system/mtu-migration.service.d/override.conf
[Unit]
After=wait-for-primary-ip.service
```

```shell

oc apply -f 20-mtu-migration-master.yaml
oc apply -f 20-mtu-migration-worker.yaml

```

### 8.  Optional:  Verify the new rendered MachineConfigs.  


*Difficult*

Iterate over all the MachineConfig paths and extract the base64-encoded files and manually inspect.

```shell
for HOSTNAME in "" ; do oc get mc -o yaml rendered-master-.... | yq ".spec.config.storage.files[] | select(.path == \"/etc/nmstate/openshift/${HOSTNAME}.yml\") | .contents.source" | python3 -c 'import sys ; from urllib.request import urlopen ;  sys.stdout.buffer.write(urlopen(sys.stdin.read()).read())' ; done
```

More complex: per-role check [check_rendered_role_mc.sh](./check_rendered_role_mc.sh)

### 9. Start migration

<https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/networking/ovn-kubernetes-network-plugin#initiating-limited-live-migration_migrate-from-openshift-sdn>

```shell

oc patch Network.config.openshift.io cluster --type='merge' --patch '{"metadata":{"annotations":{"network.openshift.io/network-type-migration":""}},"spec":{"networkType":"OVNKubernetes"}}'

```

### 10. Unpause MCP

Follow your standard upgrade sequencing and procedures for unpausing MachineConfigPools.


```shell
oc patch mcp worker --type merge --patch '{"spec":{"paused":false}}'
oc patch mcp master --type merge --patch '{"spec":{"paused":false}}'
```

### 11. Monitor the migration


Monitor the `NetworkTypeMigration` conditions

```shell
$ oc get network.config.openshift.io cluster -o jsonpath='{.status.conditions}' | jq -r '.[] | select(.type | contains("NetworkTypeMigration")) | "  \(.type): \(.status) (\(.reason))"'

  NetworkTypeMigrationMTUReady: Unknown (NetworkTypeMigrationNotInProgress)
  NetworkTypeMigrationTargetCNIAvailable: Unknown (NetworkTypeMigrationNotInProgress)
  NetworkTypeMigrationTargetCNIInUse: Unknown (NetworkTypeMigrationNotInProgress)
  NetworkTypeMigrationOriginalCNIPurged: Unknown (NetworkTypeMigrationNotInProgress)
  NetworkTypeMigrationInProgress: False (NetworkTypeMigrationCompleted)
```

Watch the OVN-K pods appear and the SDN pods disappear

```shell
oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node -o wide
oc get pods -n openshift-sdn -l app=sdn -o wide


```



### 12. Replacing the OVS bridge CNI with ovn-k8s-cni-overlay


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

```shell
cat > localnet-nad.YAML <<EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: $NAME
  namespace: virtualmachines
spec:
  config: |-
    {
        "cniVersion": "0.3.1",
        "name": "$LOCALNET_NAME",
        "physicalNetworkName": "$LOCALNET_NAME",
        "type": "ovn-k8s-cni-overlay",
        "topology": "localnet",
        "vlanID": 200,
        "mtu": 1500,
        "netAttachDefName": "virtualmachines/$NAME"

    }
EOF

```

### 13. Disable old scripts

`/etc/systemd/system/init-interfaces.service` is installed by Ignition, so we can just delete it.

`*-ovs-mac-policy-none-link-worker` is a separate MachineConfig so it can be left in place.

