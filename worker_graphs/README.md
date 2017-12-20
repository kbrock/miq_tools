# processing workers

### setup configuration

```
cd ${HOME}/src/gems/miq_tools/worker_graphs
export PATH=$PATH:`pwd`
. process_logs.bash # get some aliases
```


### Get the files you need:

```
export HOST=10.9.x.x
mkdir tmp/${HOST}/scenario1 ; cd it

scp root@${HOST}:/var/www/miq/vmdb/log/{vmstat,evm,top_output,production}* .
mv evm.log evm.log-201801.... (so it is for the next day) - things work better this way
```

### describe the log contents (and messages)
```bash
describe_log.rb --group --details --messages evm.log-201801*
```

```text
ManageIQ::Providers::Vmware::InfraManager::MetricsCollectorWorker (1)
     29797 [8144257] 2018-01-18T15:41:47 -- 2018-01-23T09:57:48
           [1568175] Storage.perf_capture_historical
           [ 138881] Storage.perf_capture_hourly
           [  81567] ManageIQ::Providers::Vmware::InfraManager::Vm.perf_capture_realtime
           [   8358] ManageIQ::Providers::Vmware::InfraManager::HostEsx.perf_capture_realtime
           [   2073] ManageIQ::Providers::Vmware::InfraManager::Vm.perf_capture_historical
           [     45] ManageIQ::Providers::Vmware::InfraManager::HostEsx.perf_capture_historical
MiqEmsMetricsProcessorWorker (1)
     29807 [ 886107] 2018-01-18T15:41:47 -- 2018-01-23T09:52:13
           [   2883] EmsCluster.perf_rollup_range
```

### split up the logs

```bash
split_logs.rb --dl evm.log-2018*
add_worker_names evm.log*_pid_*
```

### graph the logs

```bash
# most worker names start with M
for i in evm.data-M*_pid_* ; do sp $i ; done
```

#### deep dive graph
```bash
sp evm.data_MiqEmsMetricsProcessorWorker_pid_29807 2018-01-18T23:00 23:55
```
