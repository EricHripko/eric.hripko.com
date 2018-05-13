FROM jekyll/jekyll:3.8 AS build-env

# Copy everything and build
WORKDIR /site
RUN chmod 777 .
COPY . ./
RUN jekyll build --destination out

# Build runtime image
FROM nginx
WORKDIR /usr/share/nginx/html
COPY --from=build-env /site/out .
