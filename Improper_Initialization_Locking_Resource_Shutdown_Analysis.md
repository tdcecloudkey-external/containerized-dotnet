
# Type of vulnerability 	
* CWE-665 (Improper Initialization)
* CWE-667 (Improper Locking) 
* CWE-404 (Improper Resource Shutdown or Release)

# Affected Component
dotnet runtime coreclr
* 8 
* 9 
* 10.0-preview-noble

# Affected target environment	
All Linux variants

Tested against containers runing in docker
* mcr.microsoft.com/dotnet/runtime:**-azurelinux3.0
* mcr.microsoft.com/dotnet/runtime:**-bookworm-slim
* mcr.microsoft.com/dotnet/runtime:**--noble

** = 8,9, preview 10


# Vulnerability reproduction output 

Running any https://github.com/dotnet/dotnet-docker/blob/main/README.samples.md
With docker run --cap-add=SYS_PTRACE -m1g --memory-swap=0 --kernel-memory=1g --memory-reservation=768m --cpuset-cpus=0 *dotnetapp:flavor*

On a high resource server (Intel cpu count 224, memory 512 GB  )

Yields the following pattern.  

<pre><code>
sched_getaffinity(13, 32, [0])          = 32
openat(AT_FDCWD, "/proc/self/maps", O_RDONLY|O_CLOEXEC) = 13
prlimit64(0, RLIMIT_STACK, NULL, {rlim_cur=8192*1024, rlim_max=RLIM64_INFINITY}) = 0
newfstatat(13, "", {st_mode=S_IFREG|0444, st_size=0, ...}, AT_EMPTY_PATH) = 0
read(13, "5603193a3000-5603193aa000 r--p 0"..., 1024) = 1024
read(13, "\n7f95c04d0000-7f95c04f0000 ---s "..., 1024) = 1024
read(13, "0 00:00 0 \n7f963ec64000-7f963f46"..., 1024) = 1024
read(13, "reclr.so\n7f963f612000-7f963fac90"..., 1024) = 1024
read(13, "Core.App/8.0.12/libhostpolicy.so"..., 1024) = 1024
read(13, "000 r--p 00215000 00:2f 4154857 "..., 1024) = 1024
read(13, "o.6\n7f963fed3000-7f963ff2e000 r-"..., 1024) = 1024
read(13, "/libstdc++.so.6.0.30\n7f964015900"..., 1024) = 1024
read(13, "              /usr/lib/x86_64-li"..., 1024) = 1024
close(13)                               = 0
sched_getaffinity(13, 32, [0])          = 32
<i><b>openat(AT_FDCWD, "/sys/fs/cgroup//memory.max", O_RDONLY) = 13</b></i>1️⃣
newfstatat(13, "", {st_mode=S_IFREG|0644, st_size=0, ...}, AT_EMPTY_PATH) = 0
<i><b>read(13, "1073741824\n", 4096)          = 11</b></i>2️⃣
close(13)                               = 0
prlimit64(0, RLIMIT_AS, NULL, {rlim_cur=RLIM64_INFINITY, rlim_max=RLIM64_INFINITY}) = 0
<i><b>sysinfo({uptime=1985545, loads=[96, 1152, 0], totalram=540552040448, freeram=515257712640, sharedram=4153344, bufferram=649236480, totalswap=0, freeswap=0, procs=2182, totalhigh=0, freehigh=0, mem_unit=1}) = 0</b></i>3️⃣
<i><b>mmap(NULL, 4026535936, PROT_NONE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f94bbfff000</b></i>4️⃣
munmap(0x7f94bbfff000, 4096)            = 05️⃣
madvise(0x7f94bc000000, 4026531840, MADV_DONTDUMP) = 0</b></i>6️⃣
openat(AT_FDCWD, "/sys/devices/system/cpu/cpu0/cache/index0/size", O_RDONLY) = 13
newfstatat(13, "", {st_mode=S_IFREG|0444, st_size=4096, ...}, AT_EMPTY_PATH) = 0
read(13, "48K\n", 4096)                 = 4
close(13)                               = 0
</code></pre>

Notice the syscall sysinfo3️⃣ directly followed by mmap call with ~4GB, followed with munmap of 4k. The rest of the mmap are never munmap'ed.

Previously in 2️⃣ CoreClr did read the limit of 1GB. 

It would seem that 3️⃣ 4️⃣ 5️⃣ 6️⃣ are fragments from an alternate aproach to discover system memory.


# Proof-of-concept	
In a container environment with memory restrictions applied, CoreClr uses sysinfo as an additional basis for reserving memory. On systems with less amount of memory the issue are hardly noticeable. However on **large memory capacity systems** the issue is **quite clear**. Efforts utilizing enviroment variables as memory (DOTNET_GCHeapHardLimit etc) restrictions have not had an impact.



# Reliable & minimized proof-of-concept 

Any dotnet 8,9,10 containerized applications should clearly exhibit the issue.

## Prepare image
From [this](https://github.com/dotnet/dotnet-docker/blob/main/samples/dotnetapp/Dockerfile.debian) container file, simply add the package strace
<code><pre>
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0-bookworm-slim AS build
ARG TARGETARCH
WORKDIR /source

COPY --link *.csproj .
RUN dotnet restore -a $TARGETARCH


COPY --link . .
RUN dotnet publish -a $TARGETARCH --no-restore -o /app

FROM mcr.microsoft.com/dotnet/runtime:9.0-bookworm-slim

<b><i>RUN apt-get update</b></i>
<b><i>RUN apt-get install strace -y</b></i>


WORKDIR /app
COPY --link --from=build /app .
USER $APP_UID
ENTRYPOINT ["./dotnetapp"]
</code></pre>

docker build . -t dotnetapp-9-debian -f Dockerfile.debian

## Run container

Run to start and enter container, change 1️⃣ to executing user and create the log dir with write permission for other users.

<code><pre>
docker run --cap-add=SYS_PTRACE -m1g --memory-swap=0 --kernel-memory=1g --memory-reservation=768m --cpuset-cpus=0 -v /home/USER1️⃣/log:/log:rw -it --entrypoint bash dotnetapp-9-debian
</code></pre>

Inside the attached container console run 
```console
app@200345bd9af9:/app$ strace /app/dotnetapp 2>&1 | tee -a /log/dotnetapp-9-debian-strace.log

```
strace log will be output to /home/USER1️⃣/log

within dotnetapp-9-debian-strace.log search for _**sysinfo**_ and observe the pattern

# Detailed analysis	

It's been hard pinpointing the root cause of this within coreCLR and no exact source line has been identified.

It could be related to

https://github.com/dotnet/runtime/blob/main/src/coreclr/gc/handletablecore.cpp#L568
https://github.com/dotnet/runtime/blob/main/src/coreclr/gc/unix/gcenv.unix.cpp#L558

# Summary

## Remote attacks

Exploiting the vulnerabilities in CWE-665 (Improper Initialization), CWE-667 (Improper Locking), and CWE-404 (Improper Resource Shutdown or Release) in a remote attack can vary depending on the system and its specific implementation, but here's a general overview of how an attacker might exploit each of these vulnerabilities:

CWE-665: Improper Initialization
Vulnerability: This occurs when a variable, data structure, or resource is used before it is initialized to a valid or safe state, which can result in unpredictable behavior or security flaws.

Exploitation Scenario:
Remote Attack: An attacker could send specially crafted data or input that causes the system to attempt to use uninitialized variables or resources over a network. For example, if a server receives input that causes certain buffers or structures to be accessed before they are properly initialized, the attacker could control the values of these uninitialized variables. This could lead to:

Remote Code Execution: The attacker might be able to inject malicious code or commands into an uninitialized memory location, potentially causing the system to execute arbitrary code.

Denial of Service: The attacker could trigger undefined behaviors or crashes by causing the system to access uninitialized memory, potentially leading to a crash or a state where the system becomes unresponsive.

CWE-667: Improper Locking
Vulnerability: This occurs when a program fails to implement proper synchronization mechanisms to prevent concurrent access to shared resources, resulting in potential data corruption or race conditions.

Exploitation Scenario:
Remote Attack: In a multi-threaded or multi-process environment, an attacker could exploit improper locking to manipulate or corrupt shared resources by sending multiple concurrent requests to a server or service.

Race Condition Exploit: An attacker could send multiple requests that attempt to access and modify shared resources (e.g., files, databases) simultaneously, without proper synchronization. This could lead to inconsistent or corrupted data, or the attacker might force the system into an unstable state.

Privilege Escalation: If the attacker can manipulate locking mechanisms (e.g., by forcing a deadlock or causing improper resource access), they might gain unauthorized access to higher privileges or sensitive data.

Denial of Service: Improper locking could cause deadlocks, where the system is stuck waiting for resources, making the system unresponsive or slow to a point where legitimate users cannot interact with it.

CWE-404: Improper Resource Shutdown or Release
Vulnerability: This issue arises when resources (e.g., memory, file handles, network sockets) are not properly released or shut down, potentially leading to resource leakage or the system remaining in a vulnerable state.

Exploitation Scenario:
Remote Attack: An attacker could exploit improper resource shutdown by sending requests that lead to the failure to properly release resources, particularly in a system with a high volume of incoming requests (e.g., web servers or databases).

Denial of Service (DoS): If resources like network connections, file handles, or database connections are not properly released, the system could run out of available resources, causing it to crash or become unresponsive to legitimate requests.

Memory Leaks: If an attacker sends repeated requests causing memory or resource leaks (e.g., failing to properly deallocate memory or close connections), the system could exhaust its available memory or other resources, leading to crashes or slowdowns.

Persistence of Vulnerabilities: If an attacker is able to leave certain resources in an unsafe state (e.g., a file handle that’s not closed or a network connection not properly shut down), they might be able to maintain a persistent foothold on the system or perform further attacks.

Combined Exploitation Example:
In some cases, an attacker could chain these vulnerabilities together for a more sophisticated attack:

Improper Initialization (CWE-665) could allow the attacker to inject malicious data that leads to improper behavior or memory corruption.

Improper Locking (CWE-667) could then be exploited to cause a race condition or deadlock, potentially allowing the attacker to escalate their privileges or gain access to sensitive information.

Improper Resource Shutdown (CWE-404) could then be exploited to keep certain resources open, maintaining access to the compromised system or causing the system to run out of resources, eventually leading to a denial of service.

## Cross container attacks
Vulnerabilities like CWE-665 (Improper Initialization), CWE-667 (Improper Locking), and CWE-404 (Improper Resource Shutdown or Release) can potentially be used as part of an attack to exploit cross-container leaks in containerized environments. Here’s how each vulnerability could potentially lead to such exploitation:

1. CWE-665: Improper Initialization
Improper initialization issues often result in uninitialized memory being accessed or used in unintended ways, which can lead to undefined behavior or even security vulnerabilities.

Potential Cross-Container Leak Exploitation:
Container Isolation Breach: In a containerized environment, improper initialization could result in a vulnerability where a container accesses shared or uninitialized memory that belongs to another container. For example, if two containers share a resource (e.g., a memory segment or a socket), and one container does not properly initialize its own memory or buffer, an attacker could craft an input to cause that memory to leak into another container’s address space.

Shared Memory Vulnerabilities: In containerized environments, some containers might use shared memory or inter-process communication (IPC). If a container is improperly initialized and exposes uninitialized memory, another container might be able to read or write to that uninitialized memory, potentially leaking sensitive data or gaining access to secrets.

2. CWE-667: Improper Locking
Improper locking vulnerabilities occur when a system fails to use synchronization mechanisms (like mutexes or semaphores) to properly manage access to shared resources, leading to race conditions, deadlocks, or inconsistent states.

Potential Cross-Container Leak Exploitation:
Race Conditions Across Containers: If containers are incorrectly configured to allow concurrent access to shared resources (such as files, database entries, or memory segments), an attacker might exploit improper locking to induce a race condition that causes one container to leak data to another. For example, two containers might simultaneously attempt to write to the same shared file, and without proper locking, data could be leaked from one container to another.

Exploiting Shared Resources: If containers share resources like network sockets, file handles, or databases without proper locking mechanisms, an attacker could manipulate the timing of actions across containers. They might cause data to be exposed across containers, either by causing a deadlock, by exploiting inconsistent states, or by bypassing security checks intended to isolate the containers.

3. CWE-404: Improper Resource Shutdown or Release
Improper resource shutdown or release occurs when resources such as memory, file handles, or network connections are not properly released when no longer needed, leading to potential resource leakage or improper access control.

Potential Cross-Container Leak Exploitation:
Unreleased Resources: Containers often interact with shared resources (e.g., shared memory, network connections, or file systems). If a container does not properly release a resource (like a file handle or a memory buffer), another container could potentially gain access to that resource. For example, if a file handle or memory segment is not properly closed or released, it may become accessible to other containers, leading to unintended data exposure.

Cross-Container Data Leakage: If one container leaves a file, socket, or memory resource open and improperly closed, another container might be able to access this resource and extract sensitive information or perform further attacks.

Persistent State Across Containers: Improper resource shutdown can leave state information in a resource that is shared between containers. This could allow an attacker to exploit residual data left in such resources to bridge isolation gaps between containers.

Combined Exploitation in Cross-Container Leaks
An attacker could potentially combine these vulnerabilities to exploit cross-container leaks:

Improper Initialization (CWE-665) could allow an attacker to inject malicious data into a shared memory resource that one container uses but another container accesses.

Improper Locking (CWE-667) could then be exploited by sending concurrent requests across containers to cause a race condition, allowing the attacker to manipulate shared resources and access sensitive data in a different container.

Improper Resource Shutdown (CWE-404) could allow an attacker to leave a resource open or improperly released, allowing another container to exploit it and access data that was supposed to be isolated.

Mitigation Measures:
To prevent these types of cross-container leaks, the following best practices can be adopted:

Container Isolation: Use robust container isolation mechanisms (e.g., namespaces, cgroups) to ensure that containers cannot easily access each other's resources.

Proper Locking: Implement strong synchronization mechanisms to ensure that containers don’t accidentally share or corrupt data through race conditions.

Resource Management: Ensure that resources (e.g., memory, file handles, network sockets) are properly released when no longer needed, and employ mechanisms like garbage collection or resource pooling to avoid resource leakage.

By addressing vulnerabilities in initialization, locking, and resource management, the risk of cross-container data leaks and other exploits can be significantly reduced.

