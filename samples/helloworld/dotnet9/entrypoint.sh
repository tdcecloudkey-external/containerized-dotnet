#!/usr/bin/env bash
ulimit -Sv ${ULIMIT_AS_SOFT}
ulimit -Hv ${ULIMIT_AS_HARD}
#/usr/bin/strace /app/dotnet-trace collect --output ${DOTNET_TRACE_OUTPUT} -- dotnetapp
/usr/bin/strace /app/dotnetapp
