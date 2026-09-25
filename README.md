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
echo "Waiting 30s for initial data to be collected..." && sleep 30
oc exec $COLLECT_POD -- ls /var/log/collectl/
```

### Get collectl `war.gz` files locally:
- Download files
```
mkdir -p collectl_out; oc get node -l collectl=true -o name -o json | jq '.items[].metadata.name' -r | while read NODE; do oc debug node/${NODE} -q --to-namespace=openshift-etcd -- chroot host sh -c 'cd /var/log/collectl; ls *.raw.gz' | while read FILE; do oc debug node/${NODE} -q --to-namespace=openshift-etcd -- chroot host sh -c "cd /var/log/collectl; cat $FILE" > collectl_out/${FILE}; done ; done
```
- Extract the `.raw` files:
```
ls  collectl_out | while read GZ; do cat collectl_out/${GZ} | zcat > collectl_out/$(printf $GZ | egrep -o ".*.raw"); done
```

### Analyze the data:
- Use a local collectl instance
```
podman run --rm -ti -v ${PWD}/collectl_out:/var/log/collectl:z quay.io/acancell-redhat/ocp_collectl_cpu:4.3.20-ubi9 sh
```

- Example query:
```
collectl -p ip-10-0-76-125-20260924-194328.raw -sZ -oT --top cpu,10 --procopts w



### RECORD   80 >>> ip-10-0-76-125 <<< (1790283840.001) (Thu Sep 24 21:04:00 2026) ###

# TOP PROCESSES sorted by cpu (counters are /sec) 21:04:00
# PID  User     PR  PPID THRD S   VSZ   RSS CP  SysT  UsrT Pct  AccuTime  RKB  WKB MajF MinF Command
    3  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_gp 
    4  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_par_gp 
    5  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 slub_flushwq 
    6  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 netns 
    8  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 kworker/0:0H-events_highpri 
   10  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 mm_percpu_wq 
   12  root     20     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_tasks_kthre 
   13  root     20     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_tasks_rude_ 
   14  root     20     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_tasks_trace 
   15  root     20     2    0 S     0     0  0  0.00  0.00   0  00:01.64    0    0    0    0 ksoftirqd/0 

### RECORD   81 >>> ip-10-0-76-125 <<< (1790283900.001) (Thu Sep 24 21:05:00 2026) ###

# TOP PROCESSES sorted by cpu (counters are /sec) 21:05:00
# PID  User     PR  PPID THRD S   VSZ   RSS CP  SysT  UsrT Pct  AccuTime  RKB  WKB MajF MinF Command
    1  root     20     0    0 S  175M   21M  0  0.07  0.15   0  02:06.03    0    0    0    0 /usr/lib/systemd/systemd --switched-root --system --deserialize 27
    3  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_gp 
    4  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_par_gp 
    5  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 slub_flushwq 
    6  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 netns 
    8  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 kworker/0:0H-events_highpri 
   10  root      0     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 mm_percpu_wq 
   12  root     20     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_tasks_kthre 
   13  root     20     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_tasks_rude_ 
   14  root     20     2    0 I     0     0  0  0.00  0.00   0  00:00.00    0    0    0    0 rcu_tasks_trace 
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