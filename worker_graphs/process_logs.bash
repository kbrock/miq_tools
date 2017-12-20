
# source me please

# sp tmp/MiqGenericWorker/evm.data-20171024
# sp tmp/MiqGenericWorker/evm.data-20171024 2017-10-23T6:33 2017-10-23T8:38
# sp tmp/MiqGenericWorker/evm.data-20171024 2017-10-23T6:33 8:38

# input tmp/MiqGenericWorker/evm.data-20171024
# output tmp/MiqGenericWorker/evm-20171024-6-8.png

function sp {
  local src=$1
  shift

  if [ $# -gt 0 ] ; then          # dates given
    # 2017-10-20Thh:mm
    local dt2=${1}                # start date T time
    local d2=${dt2%T*}            # start date
    local t2=${dt2#*T}            # start hour
          t2=${t2%%:*}

    local dt3=${2}                # end   date T time
    if [[ ${dt3} != *T* ]] ; then # amend date to end date
      dt3="${d2}T${dt3}"
    fi
    local d3=${dt3%T*}            # end   date
    local t3=${dt3#*T}            # end   hour (>24 if span days)
          t3=${t3%%:*}
          t3="$(( (${d3//-/} - ${d2//-/}) *24 + ${t3}))"

    local dt="${t2}-${t3}"        # filename portion to add
    if [ ${t2} == ${t3} ] ; then
      dt="${t2}"
    fi
    tgt="${src/.data/}-${dt}.png"
  else
    tgt="${src/.data/}.png"
  fi

  # used by all
  if [ ! -f "${src/evm/queue}" ] ; then
    echo "queue_message: ${src} => ${src/evm/queue}"
    grep queue_message "${src}" > "${src/evm/queue}"                                               # queue messages
  fi

  # used by GenericWorker (capture_timer - not sure if relevant)
  local greptgt=${src/evm/capture}
  if [ ! -f "${greptgt}" ] ; then
    echo "capture_timer: ${src} => ${greptgt}"
    grep '\(perf_capture_timer\|perf_collect_all_metrics\)'     "${src}" > "${greptgt}"    # capture queue messages
    [ -s ${greptgt} ] || rm ${greptgt}
  fi
  # used by MetricsCollector
  local greptgt=${src/evm/vm}
  if [ ! -f "${greptgt}" ] ; then
    echo "vm capture: ${src} => ${greptgt}"
    grep 'Vm.perf_capture_realtime'                             "${src}" > "${greptgt}"    # vm queue messages
    [ -s ${greptgt} ] || rm ${greptgt}
  fi

  greptgt=${src/evm/host}
  if [ ! -f "${greptgt}" ] ; then
    echo "host capture: ${src} => ${greptgt}"
    grep 'HostEsx.perf_capture_realtime'                        "${src}" > "${greptgt}"    # host queue messages
    [ -s ${greptgt} ] || rm ${greptgt}
  fi

  greptgt=${src/evm/storage}
  if [ ! -f "${greptgt}" ] ; then
    echo "Storage.perf_capture_hourly: ${src} => ${greptgt}"
    grep 'Storage.perf_capture_hourly'                          "${src}" > "${greptgt}"    # storage queue messages
    [ -s ${greptgt} ] || rm ${greptgt}
  fi

  greptgt=${src/evm/message}
  if [ ! -f "${greptgt}" ] ; then
    echo "process_message: ${src} => ${greptgt}"
    grep 'process_message'                                      "${src}" > "${greptgt}"    # heartbeat process message
    [ -s ${greptgt} ] || rm ${greptgt}
  fi

  [ -z "$TITLE" ] && TITLE=${src#*data}
  echo size_plot.gnup ${src} ${tgt} ${dt2} ${dt3}
  size_plot.gnup ${src} ${tgt} ${dt2} ${dt3} && open ${tgt}
}

function add_worker_names {
  # evm.log-201*-[1-9]*
  for i in $@ ; do
    wk=$(grep -m 1 ::Runner# $i |sed 's/[^(]*MIQ(\([^[D[D[A)]*\)::Runner#.*$/\1/' | sed 's/.*://')
    if [ -n "$wk" ] ; then
      mv $i ${i/pid/${wk}_pid}

      # add name onto data file as well
      # wish we didn't need the datafile
      # not perfect but...
      datafile="${i/log/data}"
      if [ -f "${datafile}" ] ; then
        mv ${datafile} ${datafile/pid/${wk}_pid}
      fi
    # else
    # nop
    fi
  done
}
