#!/bin/sh
set -e

# if we are using the $IMPORTMAP_URL environment variable, we have to make this useful,
# so we change "importmap.json" into "$IMPORTMAP_URL" allowing it to be changed by envsubst
if [ -n "${IMPORTMAP_URL}" ]; then
  if [ -n "$SPA_PATH" ]; then
    [ -f "/usr/share/nginx/html/index.html"  ] && \
      sed -i -e 's/\("|''\)$SPA_PATH\/importmap.json\("|''\)/\1$IMPORTMAP_URL\1/g' "/usr/share/nginx/html/index.html"

    [ -f "/usr/share/nginx/html/service-worker.js" ] && \
      sed -i -e 's/\("|''\)$SPA_PATH\/importmap.json\("|''\)/\1$IMPORTMAP_URL\1/g' "/usr/share/nginx/html/service-worker.js"
  else
    TIMESTAMP=$(date +%s)
    [ -f "/usr/share/nginx/html/index.html"  ] && \
      sed -i -e "s/importmap.json/importmap.json?v=$TIMESTAMP/g" "/usr/share/nginx/html/index.html"

    [ -f "/usr/share/nginx/html/service-worker.js" ] && \
      sed -i -e "s/importmap.json/importmap.json?v=$TIMESTAMP/g" "/usr/share/nginx/html/service-worker.js"
  fi
fi

# setting the config urls to "" causes an error reported in the console, so if we aren't using
# the SPA_CONFIG_URLS, we remove it from the source, leaving config urls as []
if [ -z "$SPA_CONFIG_URLS" ]; then
  sed -i -e 's/"$SPA_CONFIG_URLS"//' "/usr/share/nginx/html/index.html"
# otherwise convert the URLs into a Javascript list
# we support two formats, a comma-separated list or a space separated list
else
  old_IFS="$IFS"
  if echo "$SPA_CONFIG_URLS" | grep , >/dev/null; then
    IFS=","
  fi

  CONFIG_URLS=
  for url in $SPA_CONFIG_URLS;
  do
    if [ -z "$CONFIG_URLS" ]; then
      CONFIG_URLS="\"${url}\""
    else
      CONFIG_URLS="$CONFIG_URLS,\"${url}\""
    fi
  done

  IFS="$old_IFS"
  export SPA_CONFIG_URLS=$CONFIG_URLS
  sed -i -e 's/"$SPA_CONFIG_URLS"/$SPA_CONFIG_URLS/' "/usr/share/nginx/html/index.html"
fi

SPA_DEFAULT_LOCALE=${SPA_DEFAULT_LOCALE:-en_GB}

# Set custom browser tab title if provided
if [ -n "${SPA_PAGE_TITLE:-}" ]; then
  sed -i "s|<title>OpenMRS</title>|<title>$SPA_PAGE_TITLE</title>|" "/usr/share/nginx/html/index.html"
fi

# Substitute environment variables in the html file
# This allows us to override parts of the compiled file at runtime
if [ -f "/usr/share/nginx/html/index.html" ]; then
  envsubst '${IMPORTMAP_URL} ${SPA_PATH} ${API_URL} ${SPA_CONFIG_URLS} ${SPA_DEFAULT_LOCALE}' < "/usr/share/nginx/html/index.html" | sponge "/usr/share/nginx/html/index.html"

  if [ -f "/usr/share/nginx/html/assets/styles/gchmis-theme.css" ]; then
    SPA_THEME_PATH="${SPA_PATH%/}/assets/styles/gchmis-theme.css"
    if grep -q "${SPA_PATH%/}/gchmis-theme.css" "/usr/share/nginx/html/index.html"; then
      sed -i -e "s#${SPA_PATH%/}/gchmis-theme.css#$SPA_THEME_PATH#g" "/usr/share/nginx/html/index.html"
    elif ! grep -q 'assets/styles/gchmis-theme.css' "/usr/share/nginx/html/index.html"; then
      sed -i -e "s#</head>#  <link rel=\"stylesheet\" href=\"$SPA_THEME_PATH\">\\n</head>#" "/usr/share/nginx/html/index.html"
    fi
  fi
fi

if [ -f "/usr/share/nginx/html/service-worker.js" ]; then
  envsubst '${IMPORTMAP_URL} ${SPA_PATH} ${Ayarn start --backend=http://localhost:8080/openmrsPI_URL}' < "/usr/share/nginx/html/service-worker.js" | sponge "/usr/share/nginx/html/service-worker.js"
fi

# ── Patch importmap.json and routes.registry.json for @gchmis/esm-gchmis-assessments ──
TIMESTAMP=$(date +%s)
if [ -f "/usr/share/nginx/html/importmap.json" ] && [ -f "/usr/share/nginx/html/gchmis-routes.json" ] && [ -f "/usr/share/nginx/html/routes.registry.json" ]; then
  echo "Patching importmap.json with timestamp $TIMESTAMP..."
  jq ".imports[\"@gchmis/esm-gchmis-assessments\"] = \"./gchmis-esm-gchmis-assessments.js?v=$TIMESTAMP\"" /usr/share/nginx/html/importmap.json | sponge /usr/share/nginx/html/importmap.json

  echo "Patching routes.registry.json..."
  # Use explicit key assignment instead of recursive merge (*) to avoid overwriting nested arrays
  GCHMIS_ROUTES=$(cat /usr/share/nginx/html/gchmis-routes.json)
  jq --argjson gchmis "$GCHMIS_ROUTES" '. + $gchmis' /usr/share/nginx/html/routes.registry.json | sponge /usr/share/nginx/html/routes.registry.json

  echo "Verifying gchmis workspace registration..."
  jq '.["@gchmis/esm-gchmis-assessments"].workspaces' /usr/share/nginx/html/routes.registry.json
fi

# Substitute SPA_PATH in the web app manifest (icons reference $SPA_PATH)
manifest=$(find /usr/share/nginx/html -maxdepth 1 -name 'manifest.*.json' | head -1)
if [ -n "$manifest" ]; then
  envsubst '${SPA_PATH}' < "$manifest" | sponge "$manifest"
fi

exec nginx -g "daemon off;"
