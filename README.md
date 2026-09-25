# Execute `collectl` on RHOCP4

### Run
- Label the node you want to monitor
```
NODE=XXXX
oc label node/$NODE collectl=true
```
- Create the `Namespace/collectl`, `ClusterRoleBinding/collectl-privileged`, `ConfigMap/collectl-conf` and `DaemonSet/collectl` resources:
```
oc apply -k https://github.com/acancell-redhat/ocp_collectl_cpu.git
```

- Check the pod has started and it is collecting data
```
oc project collectl
oc wait --for=condition=Ready pod -l app=collectl --timeout=60s && \
  COLLECT_POD=$(oc get pod -l app=collectl --no-headers -o custom-columns=NAME:.metadata.name)
sleep 60
oc exec $COLLECT_POD -- ls /var/log/collectl/
```

### Get collectl `war.gz` files locally:
```
mkdir -p collectl_out; oc get node -l collectl=true -o name -o json | jq '.items[].metadata.name' -r | while read NODE; do oc debug node/${NODE} -q --to-namespace=openshift-etcd -- chroot host sh -c 'cd /var/log/collectl; ls *.raw.gz' | while read FILE; do oc debug node/${NODE} -q --to-namespace=openshift-etcd -- chroot host sh -c "cd /var/log/collectl; cat $FILE" > collectl_out/${FILE}; done ; done
```
#### Extract the `.raw` files:
```
ls  collectl_out | while read GZ; do cat collectl_out/${GZ} | zcat > collectl_out/$(printf $GZ | egrep -o ".*.raw"); done
```
### Analyze the data:
```
podman run --rm -ti -v ${PWD}/collectl_out:/var/log/collectl quay.io/acancell-redhat/ocp_collectl_cpu:4.3.20-ubi9 sh
```

### Cleanup

- Remove installed respources
```
oc delete -k https://github.com/acancell-redhat/ocp_collectl_cpu.git
```

- Un-label the node
```
oc label node/$NODE collectl-
```

### Sources:

1. [Installing and executing collectl in RHOCP 4 ](https://access.redhat.com/solutions/6989124)
2. [Modify debug collectl config deployed in Openshift 4](https://access.redhat.com/solutions/7095759) 
3. [How to use the collectl utility to troubleshoot performance issues in Red Hat Enterprise Linux](https://access.redhat.com/articles/351143)
4. [How to analyze collectl raw log files collected from RHOCP 4?](https://access.redhat.com/articles/7118258)
5. [Command Equivalence Matrix](https://collectl.sourceforge.net/Matrix.html)