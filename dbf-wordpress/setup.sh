#!/usr/bin/env bash
# DBF Learning Lab, Assignments 03-06 in one run.
# Run on the AWS server as: sudo bash setup.sh
set -euo pipefail

SITE_TITLE="My Company"
ADMIN_USER="admin"
ADMIN_PASS="ChangeMe-2026!"
ADMIN_EMAIL="team@example.com"

IP=$(curl -s http://checkip.amazonaws.com)
DIR=/home/ubuntu/wordpress

# Assignment 03: Ubuntu update + Docker
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
command -v docker >/dev/null || curl -sSL https://get.docker.com | sh
usermod -aG docker ubuntu

mkdir -p "$DIR" && cd "$DIR"

cat > uploads.ini <<'INI'
upload_max_filesize = 512M
post_max_size = 512M
memory_limit = 512M
max_execution_time = 300
INI

cat > compose.yml <<'YML'
services:
  db:
    image: mariadb:11
    restart: always
    environment:
      MARIADB_DATABASE: wordpress
      MARIADB_USER: wp
      MARIADB_PASSWORD: wpsecret
      MARIADB_ROOT_PASSWORD: wordpressroot
    volumes:
      - ./database:/var/lib/mysql
  wordpress:
    image: wordpress:latest
    restart: always
    depends_on: [db]
    ports: ["80:80"]
    environment: &wpenv
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wp
      WORDPRESS_DB_PASSWORD: wpsecret
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - ./html:/var/www/html
      - ./uploads.ini:/usr/local/etc/php/conf.d/uploads.ini
  cli:
    image: wordpress:cli
    profiles: [cli]
    user: "33:33"
    depends_on: [db]
    environment: *wpenv
    volumes:
      - ./html:/var/www/html
YML

docker compose up -d
wp() { docker compose run --rm -T cli wp "$@"; }

echo "Waiting for WordPress and the database..."
until wp db query "SELECT 1" >/dev/null 2>&1; do sleep 3; done

# Assignment 04: install + theme
wp core is-installed || wp core install --url="http://$IP" --title="$SITE_TITLE" \
  --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" \
  --admin_email="$ADMIN_EMAIL" --skip-email
wp theme install twentyseventeen --activate

# Assignment 05: post, page, menu, calendar widget in footer 1
wp post create --post_type=post --post_status=publish \
  --post_title="Welcome to $SITE_TITLE" \
  --post_content="This is our business idea. (Placeholder, replace with your own text.)"
ABOUT=$(wp post create --post_type=page --post_status=publish --porcelain \
  --post_title="About us" --post_content="Who we are. (Placeholder)")

# Assignment 06: plugins (+ backup plugin for Assignment 07)
wp plugin install contact-form-7 click-to-chat-for-whatsapp all-in-one-wp-migration --activate
CF7=$(wp post list --post_type=wpcf7_contact_form --field=ID --posts_per_page=1 | tr -d '\r')
CONTACT=$(wp post create --post_type=page --post_status=publish --porcelain \
  --post_title="Contact" \
  --post_content="<!-- wp:shortcode -->[contact-form-7 id=\"$CF7\" title=\"Contact form 1\"]<!-- /wp:shortcode -->
<!-- wp:shortcode -->[ht-ctc-chat]<!-- /wp:shortcode -->")

wp menu create "Top Menu" >/dev/null 2>&1 || true
wp menu item add-custom top-menu "Home" "http://$IP/"
wp menu item add-post top-menu "$ABOUT"
wp menu item add-post top-menu "$CONTACT"
wp menu location assign top-menu top
wp widget add calendar sidebar-2 || true

echo
echo "Done: http://$IP   Admin: http://$IP/wp-admin   ($ADMIN_USER / $ADMIN_PASS)"
