#!/bin/bash


set -oeu pipefail

# e.g. https://example.com/test -> /test
SERVER_RELATIVE_PATH=$(echo "$SERVER_URL_BASE" | sed -e 's@^\(http\|https\)://\([^/]\+\)\(.*\)@\3@' )

first () {
  echo "$1"
}
second () {
  echo "$2"
}
third () {
  echo "$3"
}

write_server_config () {
  SERVER_NAME="$1"
  SERVER_PORT="$2"
  SERVER_ALIAS="$3"

  # Basic proxy
  cat <<EOF
  location ~ ^/$SERVER_ALIAS\$ {
    return 301 $SERVER_URL_BASE/$SERVER_ALIAS/;
  }

  location ~ ^/$SERVER_ALIAS/static/(.*)\.min\.js\$ {
    resolver $RESOLVER;
    set \$target $SERVER_NAME;

    # Only pass the URI after /<SERVER_ALIAS> upstream
    rewrite ^/$SERVER_ALIAS(.*)\$ \$1 break;

    proxy_pass http://\$target:$SERVER_PORT\$uri\$is_args\$args;
  }

  location ~ ^/$SERVER_ALIAS/(.*)?$ {
    resolver $RESOLVER;
    set \$target $SERVER_NAME;

    # Only pass the URI after /<SERVER_ALIAS> upstream
    rewrite ^/$SERVER_ALIAS(.*)\$ \$1 break;

    proxy_pass http://\$target:$SERVER_PORT\$uri\$is_args\$args;
    proxy_set_header Accept-Encoding ''; # Because sub_filter won't work with compressed
EOF

  for SERVER in $SERVERS
  do
    REWRITE=$(echo $SERVER | tr ':@' '

')
    REWRITE_NAME=$(first $REWRITE)
    REWRITE_PORT=$(second $REWRITE)
    REWRITE_ALIAS=$(third $REWRITE)

    cat <<EOF
    # Rewrite references without the scheme, e.g. //google.com
    sub_filter 'src="//$REWRITE_NAME:$REWRITE_PORT' 'src="$SERVER_URL_BASE/$REWRITE_ALIAS';
    sub_filter 'href="//$REWRITE_NAME:$REWRITE_PORT' 'href="$SERVER_URL_BASE/$REWRITE_ALIAS';
    sub_filter 'href=\'//$REWRITE_NAME:$REWRITE_PORT' 'href=\'$SERVER_URL_BASE/$REWRITE_ALIAS';

    # Rewrite all absolute references, regardless of where
    # they appear in the page
    sub_filter 'http://$REWRITE_NAME:$REWRITE_PORT/' '$SERVER_URL_BASE/$REWRITE_ALIAS/';
    sub_filter 'http://$REWRITE_NAME:$REWRITE_PORT' '$SERVER_URL_BASE/$REWRITE_ALIAS';
    
    proxy_redirect http://$REWRITE_NAME:$REWRITE_PORT/ $SERVER_URL_BASE/$REWRITE_ALIAS/;
EOF
  done

  cat <<EOF
    # Rewrite relative references
    sub_filter 'src="/' 'src="$SERVER_URL_BASE/$SERVER_ALIAS/';
    sub_filter 'href="/' 'href="$SERVER_URL_BASE/$SERVER_ALIAS/';
    sub_filter 'href=\'/' 'href=\'$SERVER_URL_BASE/$SERVER_ALIAS/';

    # Allow multiple substitutions in the page
    sub_filter_once off;
  }
EOF
}


append_config () {
  cat >> /etc/nginx/conf.d/default.conf
}


echo > /etc/nginx/conf.d/default.conf

cat <<EOF | append_config
server {
    server_name null;
    listen 80;
    
EOF

for SERVER in $SERVERS
do
  SERVER=$(echo $SERVER | tr ':@' '

')
  SERVER_NAME=$(first $SERVER)
  SERVER_PORT=$(second $SERVER)
  SERVER_ALIAS=$(third $SERVER)
  write_server_config $SERVER_NAME $SERVER_PORT $SERVER_ALIAS | append_config
done

cat <<EOF | append_config
}
EOF

cat -n /etc/nginx/conf.d/default.conf

exec nginx -g 'daemon off;'

