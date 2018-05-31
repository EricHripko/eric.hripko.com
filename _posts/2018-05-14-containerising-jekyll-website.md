---
layout:   post
title:    "Containerising Jekyll website"
date:     2018-05-14 08:45:00 +0100
category: Docker
tags:     docker jekyll ruby ci cd apt
---
I am a big fan of Docker as the tool to create predictable development, CI and
production environments. The ability to build and/or run pretty much any
software with just Docker installed is stunning and outstandingly useful. This
is why I utilise Docker for my private server to run all the required services.
In this blog post we will look at how I containerised this blog: applying
Docker for both building and execution.

# Building with Docker
When working with any automated build process, the aim of the developer is
to capture the build instructions. Docker provides a standardised way to
achieve this with `Dockerfile`. What makes it even more powerful is that Docker
enables you to capture the build environment as well - guaranteeing fast,
repeatable and predictable builds.

In order to capture the build environment, we will derive from
[jekyll/jekyll](https://github.com/jekyll/docker) Docker image. This will
provide us with a *nix system that has __Jekyll__ of the supplied version
installed. Build instructions can be easily picked up from the
[official Jekyll documentation](https://jekyllrb.com/docs/usage/) and
essentially boil down to the following.
{% highlight ruby %}
$ jekyll build --destination <destination>
# => The current folder will be generated into <destination>
{% endhighlight %}
The `destination` folder will contain a plain HTML static website that we can
then serve with any web server. Therefore, our `Dockerfile` would look
something like the following.
{% highlight docker %}
# Setup environment
FROM jekyll/jekyll:3.8
#...

# Build
COPY . ./
# ^- Copies current folder (with the Jekyll website) inside the container
RUN jekyll build --destination out
# ^- Generates a static website in the `out` folder
{% endhighlight %}
`jekyll serve` starts a built-in __development__ server and shouldn't be used
for delivering websites in production. Instead we should opt for a fully
featured standalone web server. Personally, I like to use __nginx__ due to its
performance and configurability. The question becomes: how exactly can we
utilise __nginx__ in the environment we defined?

# Multi-stage builds
Previously, I only ever containerised apps that don't require building. In such
cases, we can simply derive from a base production image and copy our app into
the container (as the example above does). This method, however, is not 
scalable when containerising an app that does require building, as you would
have to mould your container to support both building and execution. This
violates the 'separation of concerns' principle and blows up the size of your
Docker image unnecessarily.
{% highlight ruby %}
$ docker images | grep jekyll
jekyll/jekyll    3.8           db001a77ff97      31 hours ago      432MB
$ docker images | grep nginx
nginx            latest        ae513a47849c      13 days ago       109MB
{% endhighlight %}
For example, in our case this would mean taking `jekyll/jekyll` image with all
of its layers and installing __nginx__ web server on top of it. We would likely
have to install software manually losing any official support and updates. What
is more, we would drag at least __432MB__ of unnecessary layers to production.

Fortunately, a new feature in Docker 17.05 called
[Multi-stage Builds](https://docs.docker.com/develop/develop-images/multistage-build/)
comes to rescue. It enables us to utilise multiple containers throughout the
build process and this way produce lightweight images while taking advantage of
all the Docker features. Note that you might need to upgrade your Docker to
access this feature or you'll encounter `Error parsing reference` issue (looks
something like the one below). Also, if you are indeed on an older version, you
can read about my adventures while
[upgrading Docker on Ubuntu]({{ site.baseurl }}{% link _posts/2018-05-13-upgrading-docker-ubuntu.md %}).
{% highlight shell %}
Step 1/1 : FROM jekyll/jekyll:3.8 AS build-env
Error parsing reference: "jekyll/jekyll:3.8 AS build-env" is not a valid repository/tag: invalid reference format
{% endhighlight %}
With this feature, we can build our website in a `jekyll/jekyll` container and
then copy the result to an `nginx` container. Thus, our `Dockerfile` would look
something like the one below.
{% highlight docker %}
# Setup build environment
FROM jekyll/jekyll:3.8 AS build-env
# ^- Creates an alias for this container
#...

# Build
COPY . ./
RUN jekyll build --destination out

# Setup runtime environment
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env ./out .
# ^- Copies the static website from `jekyll/jekyll` container
#    Uses the alias we defined earlier
{% endhighlight %}

# Grappling with Jekyll image
Unfortunately, `jekyll/jekyll` image defines default working directory
`/srv/jekyll` as a volume. This effectively leads to the results of
`jekyll build` being wiped out (volumes get recreated after the command
completes). In order to fix this issue, I had to change the default working
directory to something else. This resulted in the following `Dockerfile`.
{% highlight docker %}
# Setup build environment
FROM jekyll/jekyll:3.8 AS build-env
...

# Build
WORKDIR /site
COPY . ./
RUN jekyll build --destination out

# Setup runtime environment
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env /site/out .
{% endhighlight %}
Unfortunately, this `Dockerfile` didn't work and failed with the following
error.
{% highlight shell %}
jekyll 3.8.1 | Error:  Permission denied @ dir_s_mkdir - /site/out
The command '/bin/sh -c jekyll build --destination out' returned a non-zero code: 1
{% endhighlight %}
Since `site` directory does not exist by default, it is being created with
wrong permissions. This prevents `jekyll build` from creating a destination
folder and fails the build as a whole. In order to fix this issue, we need to
change the permissions on this folder. After applying the fix, we get the
`Dockerfile` shown below.
{% highlight docker %}
# Setup build environment
FROM jekyll/jekyll:3.8 AS build-env
...

# Build
WORKDIR /site
RUN chmod 777 .
COPY . ./
RUN jekyll build --destination out

# Setup runtime environment
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env /site/out .
{% endhighlight %}
This is a fully functional example and it does exactly what we wanted: builds
the website in `jekyll/jekyll` container and produces a new container based on
`nginx`. Except... it is really slow! 

# Gotta go fast(er)
{% highlight shell %}
$ time docker build -t test .
Sending build context to Docker daemon    127kB
...
real	2m57.144s
user	0m0.260s
sys	0m0.040s
{% endhighlight %}
As you can see, it takes __2-3 minutes__ to build a container for my blog. This
is really slow compared to the performance you would get if building the
website locally. Looking at the output of the build daemon, we can see that
Docker spends most of the time installing dependencies for each build.
{% highlight docker %}
...
Step 6/9 : RUN jekyll build --destination out
 ---> Running in 23c8ab52e492
Fetching gem metadata from https://rubygems.org/..........
Fetching concurrent-ruby 1.0.5
...
Bundle complete! 4 Gemfile dependencies, 47 gems now installed.
Bundled gems are installed into `/usr/local/bundle`
...
{% endhighlight %}
Ideally, we would want this step to be cached, as Ruby dependencies of the
website will rarely change. `jekyll/jekyll` suggests to use 
[caching with a volume](https://github.com/envygeeks/jekyll-docker/blob/master/README.md#caching),
which (in my opinion) is a really bad idea. Implementing this method goes
against the 'predictable environment' idea and is, frankly speaking, an
anti-pattern. Instead, we should look at structuring our image better.

Current problem is that __restoring__ dependencies and performing a __build__
is combined in a single `RUN` statement after `COPY` is performed. This means
that Docker will need to re-create `RUN` image layer (perform __restore__ +
__build__) every time contents of the website changes. While this is desirable
for the __build__ action, we don't want this behaviour for the __restore__
action. We can achieve this by rewriting the `Dockerfile` as below.
{% highlight docker %}
# Setup build environment
FROM jekyll/jekyll:3.8 AS build-env
...

# Build
WORKDIR /site
RUN chmod 777 .
COPY Gemfile* ./
# ^- Copies the Gem definition from your website
#    This defines dependencies
RUN bundler install
# ^- Restores dependencies
COPY . ./
# ^- Copies files after dependencies are restored
#    Steps above `COPY` will be cached resulting in quicker builds
RUN jekyll build --destination out

# Setup runtime environment
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env /site/out .
{% endhighlight %}
Needless to say, the first build will still be slow since this is when the
cache is generated. Let's see how much quicker (if at all) our build became
after this optimisation was introduced.
{% highlight shell %}
$ time docker build -t test .
Sending build context to Docker daemon    127kB
...
Step 5/11 : COPY Gemfile* ./
 ---> Using cache
 ---> 5dc926c5b15f
Step 6/11 : RUN bundler install
 ---> Using cache
 ---> 78be295ea050
Step 7/11 : COPY . ./
 ---> 81acc868db39
Step 8/11 : RUN jekyll build --destination out
 ---> Running in 887818159d5f
ruby 2.5.1p57 (2018-03-29 revision 63029) [x86_64-linux-musl]
Configuration file: /site/_config.yml
            Source: /site
       Destination: out
 Incremental build: disabled. Enable with --incremental
      Generating... 
                    done in 10.52 seconds.
 Auto-regeneration: disabled. Use --watch to enable.
...
real	0m20.731s
user	0m0.210s
sys	0m0.070s
{% endhighlight %}
As we can see, we achieved almost __x10__ increase in speed reducing the time
to build an image to just __20 seconds__.

# Gotta go clean(er)
Given how much trouble `jekyll/jekyll` image caused us and the fact that we
already pull Jekyll itself using `bundler install`, we can replace our base
build image with something lower level. Since the original build image uses
Ruby 2.5, we can derive from `ruby:2.5` Docker image. Changing the base image
also enabled us to remove permission fix we introduced earlier.
{% highlight docker %}
# Setup build environment
FROM ruby:2.5 AS build-env
...

# Build
WORKDIR /usr/src/app
COPY Gemfile* ./
RUN bundler install
COPY . ./
RUN bundler exec jekyll build --destination out

# Setup runtime environment
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env /usr/src/app/out .
{% endhighlight %}
Unfortunately, this fails with `Could not find a JavaScript runtime` error,
which indicates that the new base image lacks a JavaScript runtime (something
that Jekyll apparently has a hard dependency on).
{% highlight shell %}
$ docker build -t test .
...
 ---> Running in 71eaa6f89bfc
Configuration file: /usr/src/app/_config.yml
jekyll 3.8.1 | Error:  Could not find a JavaScript runtime. See https://github.com/rails/execjs for a list of available runtimes.
{% endhighlight %}
We can fix this issue by installing a JavaScript runtime within our image,
which is as simple as running `apt-get` since the chosen base image is built
on top of Debian-based distribution. Following the
[Docker best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#run),
we updated the `Dockerfile` as seen below.
{% highlight docker %}
# Setup build environment
FROM ruby:2.5 AS build-env
...

# Install JS environment
RUN apt-get update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*
    # ^- 1) Cache busting: ensures latest package versions
    # ^- 2) Install node.js JavaScript environment
    # ^- 3) Remove `apt` cache to keep image size down

# Build
WORKDIR /usr/src/app
COPY Gemfile* ./
RUN bundler install
COPY . ./
RUN bundler exec jekyll build --destination out

# Setup runtime environment
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env /usr/src/app/out .
{% endhighlight %}
In the final result, I also added `ENV JEKYLL_ENV=production` that indicates to
Jekyll that a website must be built in __production__ mode. Voilà! This way you
can containerise your Jekyll website with ~10 simple lines of code. These
general principles can be applied to other software as well, so happy
Docker'ing and see you again!
