---
title: 'Accelerating Docker in Gitlab CI'
date: 2018-05-30T20:10:00+0100
comments: true
categories:
  - Docker
tags:
  - ci
  - cd
  - docker
  - gitlab
---

One thing you may notice when building Docker is that builds may take quite a
long time. This is especially true when Docker is used in CI/CD scenario, as it
often results in no image cache being present (since a different CI worker is
chosen on each build). Below you can see the typical time it takes to build a
Gitlab pipeline without any caching involved.

![Gitlab Pipeline: Before caching](/assets/accelerating-docker-in-gitlab-ci/gitlab-pipeline-before.png)

Docker allows to address this caching issue using [--cache-from option](https://docs.docker.com/edge/engine/reference/commandline/build/#options) that
enables us to load cached layers from an existing image. This way we can use
the previously built image as a cache for the next CI build. So, let's look at
how we can improve the build times with this approach.

# Simple builds

As you probably know, Gitlab uses YAML files in order to configure CI. A really
simple configuration `.gitlab-ci.yml` for Docker would look something like
below. This file mostly remains the same since the actual 'guts' of the build
are all neatly contained within a `Dockerfile` (isn't Docker beautiful?).

```yaml
build_image:
  image: docker:git
  services:
    - docker:dind
  script:
    - docker login -u gitlab-ci-token -p $CI_BUILD_TOKEN registry.gitlab.com
    - docker build -t registry.gitlab.com/hripko/myrepo .
    - docker push registry.gitlab.com/hripko/myrepo
  only:
    - master
```

As a brief step back, `image` setting instructs Gitlab Runner to execute the
build in an environment that has Docker installed. Meanwhile, `services`
instructs Gitlab Runner to enable Docker in Docker - allowing us to build new
Docker images from inside CI Docker container.

Ideally, adding the above-mentioned option should fix the caching issue and
deliver fast builds. Thus, we modify our Gitlab CI configuration as follows:

```yaml
build_image:
  image: docker:git
  services:
    - docker:dind
  script:
    - docker login -u gitlab-ci-token -p $CI_BUILD_TOKEN registry.gitlab.com
    - docker build --tag registry.gitlab.com/hripko/myrepo --cache-from registry.gitlab.com/hripko/myrepo .
    - docker push registry.gitlab.com/hripko/myrepo
  only:
    - master
```

However, if you do this, you will observe no cached layers being used and
absolutely no speed improvement. The reason for this is simple - your cache is
not populated. Even though Docker does attempt to use the cache from the image
we configure, it fails as the image is not available locally! Consequently, we
need to update our Gitlab CI configuration to also pull the image before the
build. This looks something like this:

```yaml
build_image:
  image: docker:git
  services:
    - docker:dind
  script:
    - docker login -u gitlab-ci-token -p $CI_BUILD_TOKEN registry.gitlab.com
    - docker pull registry.gitlab.com/hripko/myrepo
    - docker build --tag registry.gitlab.com/hripko/myrepo --cache-from registry.gitlab.com/hripko/myrepo .
    - docker push registry.gitlab.com/hripko/myrepo
  only:
    - master
```

Now, we are finally ready to experience the fruits of our labour. As you can
see, the build is now down to **30 seconds** from about **2 minutes**. While
the speed increase may seem trivial for this simple case, more complex build
processes can benefit greatly from this simple trick.

![Gitlab Pipeline: After caching](/assets/accelerating-docker-in-gitlab-ci/gitlab-pipeline-after.png)

As you may have noticed, this section is titled 'Simple builds'. The problem
with the approach described above is that it simply does not work for
multi-stage builds. Let's figure out why exactly that is the case.

# Multi-stage builds

There is a rather detailed explanation of what a multi-stage build is and why
it is beneficial in my article about
[containerising Jekyll website]({{< relref "/posts/containerising-jekyll-website.md" >}}).
In a nutshell, multi-stage build enables us to exclude unnecessary layers
(i.e., used only during build time) from the final image thereby keeping the
total size down. As a side effect, this also means that `--cache-from` option
simply does not have the build-time layers available. In most extreme
circumstances, this leads to a long build process that ultimately uses the
cached layers at the very end.

```bash
Step 7/11 : COPY . ./
 ---> 53f4944d92b0
Step 8/11 : RUN bundle exec jekyll build --destination out
 ---> Running in 4a53ca62b446
...
Removing intermediate container 4a53ca62b446
 ---> 537863099bed
Step 9/11 : FROM nginx
...
 ---> ae513a47849c
Step 10/11 : WORKDIR /usr/share/nginx/html
 ---> Using cache
```

We can fix this by pushing our first stage (build environment image) to the
registry alongside the final image. Luckily, Gitlab Regisry supports multiple
images being stored for the same repository.

![Gitlab Registry](/assets/accelerating-docker-in-gitlab-ci/gitlab-registry.png)

Therefore, we simply need to apply the same technique to each stage of the
multi-stage build process. The example `.gitlab-ci.yml` below shows exactly how
this can be achieved.

```yaml
build_image:
  image: docker:git
  services:
    - docker:dind
  script:
    - docker login -u gitlab-ci-token -p $CI_BUILD_TOKEN registry.gitlab.com
    - docker pull registry.gitlab.com/hripko/myrepo/build-env
    - docker pull registry.gitlab.com/hripko/myrepo
    - docker build --tag registry.gitlab.com/hripko/myrepo/build-env --target build-env --cache-from registry.gitlab.com/hripko/myrepo/build-env .
    - docker build --tag registry.gitlab.com/hripko/myrepo --cache-from registry.gitlab.com/hripko/myrepo --cache-from registry.gitlab.com/hripko/myrepo/build-env .
    - docker push registry.gitlab.com/hripko/myrepo/build-env
    - docker push registry.gitlab.com/hripko/myrepo
  only:
    - master
```

Now, we are again ready to experience the fruits of our labour. As you can
see, the build is now down to just **1 minute** from about **3 minutes** on
average.

![Gitlab Pipeline: Multi-stage with caching](/assets/accelerating-docker-in-gitlab-ci/gitlab-multistage.png)

Boom! This way you can accelerate your Docker builds for Gitlab CI with minimal
changes. These general principles can also be applied to other CI systems, so
happy Docker’ing and see you again!
