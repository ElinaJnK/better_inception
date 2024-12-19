#!/usr/bin/env bash

set -eo pipefail

_error() {
	echo "$@" >&2
	exit 1
}

main() {
	if [ ! -s "/var/www/html/wp-config.php" ]; then
		local var

		for var in DB_HOST DB_NAME DB_USER DB_PASSWORD_FILE \
			REDIS_USER REDIS_PASSWORD_FILE \
			URL TITLE ADMIN_USER ADMIN_EMAIL ADMIN_PASSWORD_FILE \
			USER_LOGIN USER_EMAIL USER_PASSWORD_FILE; do
			eval wp_var="\$WORDPRESS_"$var

			if [ -z "$wp_var" ]; then
				_error "Undefined variable WORDPRESS_"$var
			fi
		done

		if wp core download \
			&& wp config create --dbhost="$WORDPRESS_DB_HOST" \
			--dbname="$WORDPRESS_DB_NAME" --dbuser="$WORDPRESS_DB_USER" \
			--prompt=dbpass < $WORDPRESS_DB_PASSWORD_FILE > /dev/null; then
			echo "WordPress wp-config.php file created successfully"
		else
			_error "Failed to create WordPress wp-config.php file"
		fi

		if wp config set FORCE_SSL_ADMIN "true" --raw \
			&& wp config set WP_REDIS_HOST "redis" > /dev/null \
			&& wp config set WP_REDIS_PORT "6379" --raw > /dev/null \
			&& wp config set WP_REDIS_PASSWORD \
		"['$WORDPRESS_REDIS_USER', '$(cat $WORDPRESS_REDIS_PASSWORD_FILE)']" \
				--raw > /dev/null; then
			echo "WordPress configured successfully"
		else
			_error "Failed to configure WordPress"
		fi

		if wp core install --url=$WORDPRESS_URL --title=$WORDPRESS_TITLE \
			--admin_user=$WORDPRESS_ADMIN_USER --prompt=admin_password \
			--admin_email=$WORDPRESS_ADMIN_EMAIL --skip-email \
			< $WORDPRESS_ADMIN_PASSWORD_FILE > /dev/null \
			&& chown -R www-data:www-data /var/www/html \
			&& chmod 1777 /var/www/html; then
			echo "WordPress installed successfully"
		else
			_error "Failed to install WordPress"
		fi

		echo "Replacing http scheme with https within the WordPress database"
		wp search-replace "http://$WORDPRESS_URL" "https://$WORDPRESS_URL" \
			--skip-columns=guid \
			&& wp theme install twentytwentytwo --activate \
			&& wp theme delete --all \
			&& wp plugin uninstall --all \
			&& wp plugin install redis-cache --activate \
			&& wp redis enable

		if wp user create $WORDPRESS_USER_LOGIN $WORDPRESS_USER_EMAIL \
			--role=contributor \
			--prompt=user_pass < $WORDPRESS_USER_PASSWORD_FILE > /dev/null; then
			echo "WordPress user created successfully"
		else
			_error "Failed to create WordPress user"
		fi
	fi

	exec "$@"
}

main "$@"

exit $?
