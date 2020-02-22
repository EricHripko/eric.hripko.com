---
title: 'Upgrading Docker on Ubuntu'
date: 2018-05-13T20:20:00+0100
comments: true
categories:
  - Docker
tags:
  - docker
  - systemd
  - ubuntu
---

For one of my projects (this blog actually!), I needed to upgrade the Docker
engine running on my server. To be exact, my provider
[Scaleway](https://www.scaleway.com/) unfortunately only offers image for
**Docker 1.12.2**, which is extremely outdated in Docker terms.  
![Choosing image with Scaleway provider](/assets/upgrading-docker-ubuntu/scaleway-choosing-images.png)

Since the above-mentioned image is based on **Ubuntu** operating system, there
is plenty of guides to follow. Luckily, the [official Docker one](https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-docker-ce)
details the upgrade process rather well. When updating packages, you have to
make sure to keep all custom configuration in tact (use `O` response for
`apt-get` prompts). Otherwise you may risk losing your data, as upgrading from
an older Docker may trigger a change in active storage driver. What the guide
also fails to mention is the issues that stem from the upgrade, particularly
ones connected to the service startup. After upgrading, Docker refused to start
quoting the output below via `systemd`.
{{< highlight bash >}}
May 13 13:42:14 scw-35eb3f systemd[1]: Started Docker Application Container Engine.
May 13 13:43:15 scw-35eb3f docker[3236]: unknown flag: --storage-driver
May 13 13:43:15 scw-35eb3f docker[3236]: See 'docker --help'.
May 13 13:43:15 scw-35eb3f docker[3236]: Usage: docker COMMAND
May 13 13:43:15 scw-35eb3f docker[3236]: A self-sufficient runtime for containers
...
May 13 13:43:15 scw-35eb3f docker[3236]: wait Block until one or more containers stop, then print their exit codes
May 13 13:43:15 scw-35eb3f docker[3236]: Run 'docker COMMAND --help' for more information on a command.
May 13 13:43:15 scw-35eb3f systemd[1]: docker.service: Main process exited, code=exited, status=125/n/a
May 13 13:43:15 scw-35eb3f systemd[1]: docker.service: Unit entered failed state.
May 13 13:43:15 scw-35eb3f systemd[1]: docker.service: Failed with result 'exit-code'.
{{< / highlight >}}

Taking a step back, `systemd` is a set of utilities for bootstrapping and
managing a Linux system. It is used in our case and we are particularly
interested in the first part, as `systemd` is failing to start a service.
Despite the error log output suggesting that the issue might be
`unknown flag: --storage-driver`, this is **not the root cause**. We can
confirm this by inspecting the service status.
{{< highlight bash >}}
$ service docker status
● docker.service - Docker Application Container Engine
   Loaded: loaded (/etc/systemd/system/docker.service; enabled; vendor preset: enabled)
   Active: failed (Result: exit-code) since Sun 2018-05-13 21:51:31 UTC; 4s ago
     Docs: https://docs.docker.com
  Process: 29725 ExecStart=/usr/bin/docker daemon -H fd:// $DOCKER_OPTS (code=exited, status=125)
Main PID: 29725 (code=exited, status=125)
{{< / highlight >}}

As we can see, `systemd` is trying to start the service using an outdated
method (likely a remnant from an old version of Docker). While commands like
`docker -d` and `docker daemon` used to work in the previous versions,
`dockerd` is the only way to spawn a daemon on the more recent versions of
Docker. Fortunately, the status command points us to the path of the offending
`systemd` unit.

{{< highlight ini >}}
\$ cat /etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network.target docker.socket
Requires=docker.socket

[Service]
EnvironmentFile=-/etc/default/docker
EnvironmentFile=-/etc/default/docker.d/\*
EnvironmentFile=-/etc/sysconfig/docker
ExecStart=/usr/bin/docker daemon -H fd:// \$DOCKER_OPTS
MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
{{< / highlight >}}

This service file indeed defines the start command as `docker daemon`, which
confirms our suspicion. Thus, we have to fix our setup to pick up the correct
startup script and Docker shall be restored. Having made a backup of the
`systemd` unit, we simply removed it from the location mentioned earlier. Since
we changed the configuration, we also need to run `systemctl daemon-reload` in
order to apply changes.

{{< highlight bash >}}
\$ service docker start && service docker status
● docker.service - Docker Application Container Engine
Loaded: loaded (/lib/systemd/system/docker.service; enabled; vendor preset: enabled)
Active: active (running) since Sun 2018-05-13 22:14:06 UTC; 7s ago
Docs: https://docs.docker.com
Main PID: 30399 (dockerd)
Tasks: 105
Memory: 67.2M
CPU: 9.012s
CGroup: /system.slice/docker.service
{{< / highlight >}}

Voilà! `systemd` correctly picked up the new startup scripts and managed to
successfully start the service. This way, with a few bumps on the road, I
managed to upgrade my Docker and get the latest/greatest features (and possibly
bugs?). In any case, happy Docker'ing and see you again!
