#!/bin/bash
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <sleep_time> <num_iterations> <image>"
    exit 1
fi

SLEEP_TIME=$1
NUM_ITERATIONS=$2
IMAGE=$3
COMMAND="docker run -m500m --memory-swap=500m --kernel-memory=500m --memory-reservation=456m --rm -v $HOME/log:/debug:rw  $IMAGE"
LOG_FILE="loop_log_$(date +%Y%m%d_%H%M%S).log"
NETTRACE_FILE="trace_$(date +%Y%m%d_%H%M%S)"

{
echo "Starting loop..."
echo "Logging output to: $LOG_FILE"

for ((i=1; i<=NUM_ITERATIONS; i++))
do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    NETTRACE_FILE_INTERPOLATED="/debug/${NETTRACE_FILE}_iteration_${i}.nettrace"
    
    COMMAND_ENTRYPOINT="docker run -m500m --memory-swap=500m --kernel-memory=500m --memory-reservation=456m --rm -v $HOME/log:/debug:rw --env DOTNET_TRACE_OUTPUT='$NETTRACE_FILE_INTERPOLATED' $IMAGE"
    echo "[$TIMESTAMP] Iteration $i: Running command: $COMMAND_ENTRYPOINT"   
    # Execute command and append output to log
    eval "$COMMAND_ENTRYPOINT" 2>&1
    wait

    # Sleep before next iteration
    if [ "$i" -lt "$NUM_ITERATIONS" ]; then
        echo "sleeping"
        sleep "$SLEEP_TIME"
    fi
done

} | tee -a "$LOG_FILE"