# syntax=docker/dockerfile:1
# Layers jq + moreutils on top of the upstream O3 frontend image.
# The upstream image already has the full assembled SPA, importmap.json,
# and routes.registry.json. We only add the tools startup.sh needs to
# patch the import map with the GCHMIS customizations module at runtime.
FROM openmrs/openmrs-reference-application-3-frontend:${TAG:-3.5.0}

RUN apk add --no-cache moreutils jq

COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

CMD ["/usr/local/bin/startup.sh"]
