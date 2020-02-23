---
title: 'Mission Impossible: importing Docker code in Go'
date: 2020-02-23T16:41:23Z
comments: true
categories:
  - Docker
tags:
  - docker
  - go
  - dep
  - mod
---

For one of my pet projects (Docker API
[shim](https://github.com/EricHripko/dipod) using
[podman](https://github.com/containers/libpod)), I needed to write the following
line of code:

```go
import "github.com/docker/docker"
```

Seems easy, doesn't it? Well - not so quick, dear reader! [docker/docker](https://github.com/docker/docker)
project depends on about **200** repositories and about **1000** packages. This
makes any Go dependency software choke from the sheer scale of the task. This
applies to both `dep`, which takes a huge amount of time due to the number of
releases on some Docker repositories, and the 'state of the art' `go mod`. Let's
see if we can get this dependency hell to freeze over with a `.lock` or a `.sum`
file.

# What's the deal?

First of all, the Docker project itself is a huge intertwined web of repositories
and there seems to be no golden copy on Github. That's a pretty big deal
for Go ecosystem, as it solely relies on developers keeping their repositories sane.
Without working too hard, I've found at least 3 'official' copies of the engine code:

- [github.com/docker/docker](https://github.com/moby/moby) (renamed to `moby/moby` to keep you on your toes!)
- [github.com/docker/engine](https://github.com/docker/engine) (the imports actually point to the project above)
- [github.com/docker/docker-ce/components/engine](https://github.com/docker/docker-ce/tree/master/components/engine) (same as above, but now in a sub-folder)

Wow! This, perhaps, explains why they haven't yet adopted any of the mainstream
dependency management tools. There must be some very creative symlink-ing going
on in their integration build.

Secondly, Docker has now created a bunch of micro-projects to complement the
main monorepo. Many of these require you to use a special configuration of
versions, like including a particular [RC release](https://github.com/opencontainers/runc/releases/tag/v1.0.0-rc10)
or a particular commit to make the build work.

Thirdly, `logrus`, a library which I love a bit less after all of this, decided to
rename themselves from `Sirupsen/logrus` to `sirupsen/logrus`. In one swift move,
this broke all the
[dependency managers](https://github.com/sirupsen/logrus/issues/451) and
triggered a wave of fixes for users on case-insensitive filesystems (hello Mac
& Windows 👋).

Finally, Docker codebase uses several forks of upstream projects (e.g., `pflag`,
`go-immutable-radix` and `vt100`). This further confuses the dependency resolvers
and users, as even when imports seem to work out, the code may still fail to build.

Seems hopeless? We shall see - let's dig in!

# Naїve approach: `go mod` 1.12

This rather quickly exploded due to problem #3:

```bash
go: github.com/Sirupsen/logrus@v1.4.2: parsing go.mod: unexpected module path "github.com/sirupsen/logrus"
go: github.com/tonistiigi/fifo@v0.0.0-20191213151349-ff969a566b00: parsing go.mod: unexpected module path "github.com/containerd/fifo"
```

What we also see is that some micro-projects 'graduate' from personal Github repos,
which again doesn't help the dependency management at all. Since I ran this with
**1.12** version of `go`, I also don't get any helpful error message or pointers
(like what packages are importing `logrus` under different casing?). Supposedly,
error messages are [better](https://github.com/golang/go/issues/28489) in a
newer version, so let's try that.

# Troubleshooting: `go mod` 1.13

With means to troubleshoot and fix the issues, I've carried on while encountering
a whole range of various roadblocks.

## Case-sensitive imports

This still exploded due to problem #3, but this time with a helpful error:

```bash
        github.com/docker/docker/api/server/router/system imports
        github.com/docker/docker/builder/builder-next imports
        github.com/docker/docker/builder imports
        github.com/docker/docker/container imports
        github.com/docker/swarmkit/agent/exec imports
        github.com/Sirupsen/logrus: github.com/Sirupsen/logrus@v1.4.2: parsing go.mod:
        module declares its path as: github.com/sirupsen/logrus
                but was required as: github.com/Sirupsen/logrus
```

If we check the **master** branch of [swarmkit](https://github.com/docker/swarmkit),
we will see that it actually imports `sirupsen` (the correct lower-case version).
Hold on, so what happened? The problem is that this project only has one versioned
release - [v1.12.0](https://github.com/docker/swarmkit/releases/tag/v1.12.0) from
2016! `go mod` blindly picks this up since it expects repositories to follow
semantic versioning. This means we got bitten by problem #2. In order to get
past this, we need `go mod` to pick up the latest version:

```bash
# go get -u github.com/docker/swarmkit@master
go: finding github.com/docker/swarmkit master
go: downloading github.com/docker/swarmkit v1.12.1-0.20200128161603-49e35619b182
go: extracting github.com/docker/swarmkit v1.12.1-0.20200128161603-49e35619b182
```

Despite the confusing name, this actually indeed points to the current (Feb 23)
**master** branch. And voilà - `go mod` invocation succeeds! If you get a failure,
this method can be rinsed and repeated until success.

## Negative patch number

```bash
go: github.com/docker/docker@v1.14.0-0.20190319215453-e7b5f7dbe98c: invalid pseudo-version: version before v1.14.0 would have negative patch number
```

This error seems to only show up on **1.13**. If you get an error like this,
you need to instruct module resolution to use the same version of the module
everywhere. This can be done by adding the following lines to `go.mod` (this may
need to be adjusted to your Docker/module version):

```go
replace github.com/docker/docker => github.com/docker/docker v1.4.2-0.20200204220554-5f6d6f3f2203
```

## Build errors

For example:

```bash
# github.com/docker/libnetwork/ipvs
C:\Go-Dev\pkg\mod\github.com\docker\libnetwork@v0.8.0-dev.2.0.20190604151032-3c26b4e7495e\ipvs\ipvs.go:107:32: cannot use &tv (type *syscall.Timeval) as type *unix.Timeval in argument to sock.SetSendTimeout
```

Checking the library version will likely yield the same issue as described earlier.
Thus, the solution is to install the **master** version of the library.

# Last-ditch Attempt

Fixing all dependencies by hand is cumbersome. I've been wrestling with it for
hours before giving up. So, assuming I have a new project
that will use Docker, is there any way to achieve this at all? Yes - by copying
the dependency list from
[Docker CLI](https://github.com/docker/docker-ce/blob/master/components/cli/vendor.conf)
and [Docker Engine](https://github.com/docker/docker-ce/blob/master/components/engine/vendor.conf).
While this list may not be complete by itself, it includes enough information for
`dep` to get started and not spend years on trying all permutations.

This means that you will likely add dependencies you don't need to your project.
However, this seems to be the only way to construct the list of dependencies
without going mad. Assuming that CI on Docker CE passes, we successfully reuse
a known 'good' configuration of dependencies put together by Docker team themselves.

I've created the following tiny Python script to (crudely) merge the dependencies
and translate them to `Gopkg.toml`. We use `override` stanza, since these are mostly
transitive dependencies and we don't want `dep` to discard them.

```python
deps = {}
srcs = {}

def process(file):
    global deps
    global srcs
    with open(file) as file:
        # Parse vendor.conf line by line
        for line in file:
            # Skip empty
            if not line.strip():
                continue
            # Skip comments
            if line.startswith("#"):
                continue
            args = line.split()
            # <import path> <commit SHA>
            deps[args[0]] = args[1]
            # <optional fork URL>
            if len(args) > 2 and not args[2].startswith("#"):
                srcs[args[0]] = args[2]

process("vendor.engine.conf")
process("vendor.cli.conf")

for name, revision in deps.items():
    print("""
[[override]]
name = "{}"
revision = "{}"
""".format(name, revision)
    )
    if name in srcs:
        print('source = "{}"'.format(srcs[name]))
```

You can generate the file by calling `python3 parse.py > Gopkg.toml`. Afterwards,
simply run `dep ensure` to generate a lock file and laminate our success! (note
that `dep` may suggest a few fixes before proceeding, simply follow the
instructions given).

```bash
  ✓ found solution with 557 packages from 92 projects

Solver wall times by segment:
         b-list-pkgs: 1m33.7068532s
              b-gmal: 1m23.4020423s
     b-list-versions:   54.5931506s
    b-rev-present-in:    8.7867179s
     b-source-exists:     1.743209s
         select-atom:    114.0317ms
             satisfy:     80.0019ms
            new-atom:     52.9854ms
            add-atom:      8.0208ms
  b-deduce-proj-root:      2.0032ms
         select-root:            0s
               other:            0s

  TOTAL: 4m2.489016s
```

If you don't have Python at hand or simply want the thing that definitely works,
have a look at [Gopkg.toml](https://gist.github.com/EricHripko/5e116b6d533b02ca19c08bff7c389db2)
I generated for Docker **19.03.06** SDK.

Tada! 🎉 This way you can, hopefully, include past and future Docker SDKs
with minimal effort. So get cracking on that Docker-based software you wanted to
make and see you again!

P.S.: All of this work was to describe the following dependency tree:
[![Dependency tree](/assets/mission-impossible-import-docker/deps.png)](/assets/mission-impossible-import-docker/deps.png)
