FROM ruby:2.5 AS builder
ENV JEKYLL_ENV=production

# Install JS environment
RUN apt-get update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Copy everything and build
WORKDIR /usr/src/app
COPY Gemfile* ./
RUN bundle install
COPY . ./
RUN bundle exec jekyll build --destination out

# Build runtime image
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=builder /usr/src/app/out .
COPY deployment/site.template /etc/nginx/conf.d/
CMD envsubst < /etc/nginx/conf.d/site.template > /etc/nginx/conf.d/default.conf && \
    exec nginx -g 'daemon off;'
