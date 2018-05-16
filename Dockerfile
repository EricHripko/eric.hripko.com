FROM ruby:2.5 AS build-env
ENV JEKYLL_ENV=production

# Install JS environment
RUN apt-get update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Copy everything and build
WORKDIR /usr/src/app
COPY Gemfile* ./
RUN bundler install
COPY . ./
RUN bundler exec jekyll build --destination out

# Build runtime image
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env /usr/src/app/out .
