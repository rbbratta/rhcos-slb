#!/usr/bin/env bash


for f in $(oc get pods -n openshift-machine-config-operator -l k8s-app=machine-config-daemon --no-headers -o custom-columns=N:.metadata.name); do
  echo $f
  oc exec -n openshift-machine-config-operator $f -c machine-config-daemon -- chroot /rootfs bash -c "printf '%s\n' '# primary' '# secondary' | tee /etc/NetworkManager/system-connections/disable-init-interfaces"
done



