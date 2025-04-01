# Introduction

This document describes howto force coreclr memory starvation on a developer machine.

# Pre requisites

* Linux or Windows (WSL cgroups2 enabled) with Docker 


# Steps to build
docker build . -t dotnethelloworld-9-ubuntu -f Dockerfile.ubuntu

# Steps to run


```console
docker run --cap-add=SYS_PTRACE -m1g --memory-swap=1g --kernel-memory=1g --memory-reservation=768m --cpuset-cpus=0 -v $HOME/log:/log:rw -it --entrypoint bash dotnethelloworld-9-ubuntu
```

Inside the attached container console run
```console
app@200345bd9af9:/app$ strace /app/dotnetapp 2>&1 | tee -a /log/helloworld-9-ubuntu-strace.log
app@200345bd9af9:/app$ strace /app/dotnetapp 2>&1 | tee -a /log/helloworld-9-ubuntu-strace.log
app@200345bd9af9:/app$ exit
```

# Analysis
strace log will be output to $HOME/log

We've executed the application twice to see the pattern. The pattern can also be seen running load test with "normal" container behavior. For simplyfication we are not doing this.

within helloworld-9-ubuntu-strace.log search for the following, take notes if needed.
## DotNet start and stop lines
Below marks start and stop, there should be a totalt count of 4.
```console

execve("/app/dotnetapp", ["/app/dotnetapp"], 0x7ffcafefc940 /* 12 vars */) = 0 
+++ exited with 0 +++ marks begin end of application run

```
## DotNet CGroup support
Below line is where dotnet Coreclr's CGroup support check for activation. 

```console
statfs("/sys/fs/cgroup"
```

Uppon CGroup discovery, version and magic bit etc. Limits are read.
```console
openat(AT_FDCWD, "/sys/fs/cgroup//memory.max" 
read(13, "1073741824\n", 4096)          = 11
```

## Memory limity discrepancy

It seems there are some kind of discrepancy that aflicts dotnet core clr execution.

It seems to be closely related to sysinfo calls along with a subseqvent call to prlimit64 to which it sometimes use for discovering memory limits.

find the second entry of
**sysinfo**
and then **prlimit64(0, RLIMIT_AS** the following line should be a mmap call with an out of bounds request.

Similar to this
```console
mmap(NULL, 4026535936, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fcff3fff000
munmap(0x7fcff3fff000, 4096)            = 0
madvise(0x7fcff4000000, 4026531840, MADV_DONTDUMP) = 0
```

The remaining mmap of 7FCFF4000000 are never released.





# Additional notes

Running docker with "--env DOTNET_GCHeapHardLimit=C800000" gives an race condition on this, which is also out of bounds.

Running docker with "--env DOTNET_GCHeapHardLimitPercent=1E" gives an race condition on this, which is also out of bounds.

There seems to be design flaw, either prlimit64 or cgroups should be used not a mix. Anyhow, even with ulimit defined for virtual memory ("ulimit -Hv 1048576"). Coreclr incorrectly calculates size needed and causes a oom.


This could be related to Docker ulimit as has been deprecated along with stale dotnet clr code.
https://docs.docker.com/reference/cli/docker/container/run/#supported-options-for---ulimit