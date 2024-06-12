#! /usr/bin/env bash
# ==============================

THIS=$( basename "$0" ".sh" )
DATE=$( date +%Y%m%d-%H%M%S )

LOG_DIR="."
LOG_FILE="${LOG_DIR}/${THIS}-${DATE}.log"

# ==============================

HERE=$( realpath .)

PY_VERSION="3.12"

WITH_ERASE_PREVIOUS="1"

WITH_REST="0"
WITH_LDAP="0"
WITH_FORMATTING="0"

VENV="xdev"

PROJECT_NAME="project" # the django project name
PG_USER="xdev"
PG_DB="xdevdb"

USER=$( id -u -n)
GROUP=$( id -g -n )

NGINX_PORT="83"
GUNICORN_NAME="gunicorn003"

TESTPORT=8888

PG_DATABASE_EXISTS=0

# ==============================

prep()
{
    [ "${WITH_ERASE_PREVIOUS}" == "1" ] && {
        rm -rf "${VENV}"
    }

    python3 -V | grep "${PY_VERSION}" || {
        echo "FATAL: you will need python with version ${PY_VERSION}"
        exit 101
    }

    [ -d "${VENV}" ] && {
        return
    }

    python3 -m venv "${VENV}"
    python3 -m venv --upgrade "${VENV}"

    ls -l "${VENV}"

    [ ! -f "${HERE}/${VENV}/bin/activate" ] && {
        echo "FATAL: cannot find activate."
        exit 101
    }
}

activate_proj()
{
    source "${HERE}/${VENV}/bin/activate"

    local f="${VENV}/.gitignore"
    [ ! -f "${f}" ] && {
        touch "{$f}"
    }

    for i in '*.log' '.db_pw' '.env'
    do
        grep "${i}" "${f}" || {
            echo "${i}" >>"${f}"
        }
    done
}

install_django()
{
    pip3 install --upgrade pip

    pip3 install psycopg2-binary
    pip3 install python-dotenv
    pip3 install "python-dotenv[cli]"
    pip3 install gunicorn
    pip3 install python-environ

    pip3 install Django
    pip3 install Django --upgrade

    [ "${WITH_LDAP}" = "1" ] && {
        pip3 install python-ldap
        pip3 install Django-ldap
        pip3 install django_auth_ldap
    }

    [ "${WITH_REST}" = "1" ] && {
        pip3 install djangorestframework
        pip3 install markdown       # Markdown support for the browsable API.
        pip3 install django-filter  # Filtering support
        pip3 install drf-spectacular
    }

    [ "${WITH_FORMATTING}" = "1" ] && {
        pip3 install black
        pip3 install pylama
        pip3 install mypy
    }

    (
        cd "${VENV}"
        pip3 freeze > requirements.txt
    )
}

mk_nginx_conf()
{
    # needs HERE
    # needs NGINX_PORT
    # needs GUNICORN_NAME

    cat <<!
server {
    listen ${NGINX_PORT} default_server;
    server_name _;

    # return 301 https://\$host\$request_uri;

    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location /static/ {
        root ${HERE}/pNic;
    }

    location / {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://unix:/run/${GUNICORN_NAME}.sock;
    }

    error_page 404 /404.html;
        location = /40x.html {
    }

    error_page 500 502 503 504 /50x.html;
        location = /50x.html {
    }
}
!

}

mk_gunicorn_systemd_service()
{
    # USER
    # GROUP
    # HERE
    # VENV
    # PROJECT_NAME
    # GUNICORN_NAME

    cat <<!
[Unit]
Description=${GUNICORN_NAME} daemon for ${VENV}/${PROJECT_NAME}
Requires=${GUNICORN_NAME}.socket
After=network.target

# set user and group
[Service]
Type=notify
User=${USER}
Group=${GROUP}
RuntimeDirectory=${GUNICORN_NAME}
WorkingDirectory=${HERE}/${PROJECT_NAME}
ExecStart=${HERE}/bin/gunicorn --access-logfile - --workers 3 --timeout 600 --bind unix:/run/${GUNICORN_NAME}.sock ${PROJECT_NAME}.wsgi:application
ExecReload=/bin/kill -s HUP
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
!
}

mk_gunicorn_systemd_socket()
{
    # GUNICORN_NAME

    cat <<!

[Unit]
Description=${GUNICORN_NAME} socket

[Socket]
ListenStream=/run/${GUNICORN_NAME}.sock

[Install]
WantedBy=sockets.target
!

}

prep_pg_db()
{
    echo
    local pw=$( pwgen -s 8 1 | tee "${VENV}/.db_pw" )

    # sudo su - postgres
    # psql

    cat <<!
-- DROP USER IF EXISTS $PG_USER;
-- DROP DATABASE IF EXISTS $PG_DB;
CREATE USER ${PG_USER} WITH PASSWORD '${pw}';
CREATE DATABASE ${PG_DB} OWNER ${PG_USER};
ALTER ROLE ${PG_USER} SET client_encoding TO 'utf8';
ALTER ROLE ${PG_USER} SET default_transaction_isolation TO 'read committed';
ALTER ROLE ${PG_USER} SET timezone TO 'UTC';
!
    echo
}

add_config_settings()
{
    cat <<!

# custom additions start

import os
import dotenv

dotenv.load_dotenv()

ALLOWED_HOSTS = [
    "localhost",
    "127.0.0.1",
]

if ${PG_DATABASE_EXISTS}: # the database must exist
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": os.getenv("PG_DB"),
            "USER": os.getenv("PG_USER"),
            "PASSWORD": os.getenv("PG_PASSWORD"), # from .env
            "HOST": os.getenv("PG_HOST","localhost"),
            "PORT": os.getenv("PG_PORT",""),
        }
    }

STATIC_ROOT = BASE_DIR/'static'

!
}

make_dot_env()
{
    touch .env

    (
        echo "PG_DB=${PG_DB}"
        echo "PG_USER=${PG_USER}"
        echo "PG_PASSWORD=$( cat .db_pw )" # on the same level as .env
        echo "PG_HOST=localhost"
        echo "PG_PORT=5432"
    ) >> .env
}

main()
{
    prep
    activate_proj

    install_django
    prep_pg_db # do not store it in a file it has a password embedded

    mk_nginx_conf >${VENV}/nginx.conf
    mk_gunicorn_systemd_service >${VENV}/${GUNICORN_NAME}.service
    mk_gunicorn_systemd_socket >${VENV}/${GUNICORN_NAME}.socket

    pushd "${VENV}"
        make_dot_env

        django-admin startproject "${PROJECT_NAME}"
        pushd "${PROJECT_NAME}"

            add_config_settings >>"${PROJECT_NAME}"/settings.py

            # static
            mkdir static

            ./manage.py migrate # this will use sqlite
            ./manage.py collectstatic
            ./manage.py createsuperuser --username admin --email admin@test.test

            echo "RUN THE SERVER on port ${TESTPORT}"
            ./manage.py runserver  "${TESTPORT}"
        popd
    popd
}

main 2>&1 |
tee "${LOG_FILE}"

exit 0
