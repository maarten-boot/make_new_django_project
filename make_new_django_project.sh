#! /usr/bin/env bash
# ==============================

THIS=$( basename "$0" ".sh" )
DATE=$( date +%Y%m%d-%H%M%S )

LOG_DIR="."
LOG_FILE="${LOG_DIR}/${THIS}-${DATE}.log"

# ==============================

PY_VERSION="3.12"
WITH_ERASE_PREVIOUS="1"

export HERE=$( realpath .)
export WITH_REST="0"
export WITH_LDAP="1"
export WITH_FORMATTING="0"
export VENV="xdev"
export PROJECT_NAME="project" # the django project name
export PG_USER="xdev"
export PG_DB="xdevdb"

USER=$( id -u -n)
GROUP=$( id -g -n )

TESTPORT=8888
NGINX_PORT="83"
GUNICORN_NAME="gunicorn003"

export PG_DATABASE_EXISTS=0

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

    (
        cd "${VENV}"
        pip3 freeze > requirements.txt
    )

    [ "${WITH_FORMATTING}" = "1" ] && {
        pip3 install black
        pip3 install pylama
        pip3 install mypy
    }
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

    local pw=$(
        pwgen -s 8 1 |
        tee "${VENV}/.db_pw"
    )

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

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY","")
DEBUG = bool(os.getenv("DJANGO_DEBUG", False))

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

AUTHENTICATION_BACKENDS = [
    "django.contrib.auth.backends.ModelBackend",
]

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "mail_admins": {
            "level": "ERROR",
            "class": "django.utils.log.AdminEmailHandler",
        },
        "stream_to_console": {
            "level": "DEBUG",
            "class": "logging.StreamHandler",
        },
    },
    "loggers": {
        "django.request": {
            "handlers": [
                "mail_admins",
            ],
            "level": os.getenv("DJANGO_LOG_LEVEL","WARNING"),
            "propagate": True,
        },
    },
}

if ${WITH_LDAP}:
    LOGGING["loggers"]["django_auth_ldap"] = {
        "handlers": [
            "stream_to_console",
        ],
        "level": os.getenv("DJANGO_LOG_LEVEL","WARNING"),
        "propagate": True,
    }

LANGUAGE_CODE = os.getenv("DJANGO_LANGUAGE_CODE","en-us")
TIME_ZONE = os.getenv("DJANGO_TIME_ZONE", "UTC")
USE_I18N = bool(os.getenv("DJANGO_USE_I18N", True))
USE_L10N = bool(os.getenv("DJANGO_USE_L10N", True))
USE_TZ = bool(os.getenv("DJANGO_USE_TZ", True))

TEMPLATES[0]["DIRS"] = [
    f"{BASE_DIR}/templates",
]

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

if ${WITH_LDAP}:
    # this is a Active Directory ldap config

    import ldap
    from django_auth_ldap.config import (
        LDAPSearch,
        ActiveDirectoryGroupType,
    )

    AUTHENTICATION_BACKENDS = [
        "django_auth_ldap.backend.LDAPBackend",
        "django.contrib.auth.backends.ModelBackend",
    ]

    AUTH_LDAP_SERVER_URI = ",".join([os.getenv("LDAP_SERVER_URL")])
    AUTH_LDAP_START_TLS = True
    LDAP_IGNORE_CERT_ERRORS = True

    AUTH_LDAP_CONNECTION_OPTIONS = {
        ldap.OPT_REFERRALS: 0,  # int
        ldap.OPT_X_TLS_REQUIRE_CERT: ldap.OPT_X_TLS_ALLOW,  # do not enfoce a valid Cert
    }

    AUTH_LDAP_GLOBAL_OPTIONS = {
        ldap.OPT_X_TLS_REQUIRE_CERT: ldap.OPT_X_TLS_ALLOW,  # do not enfoce a valid Cert
        ldap.OPT_REFERRALS: 0,  # int
    }

    AUTH_LDAP_BIND_DN = os.getenv("LDAP_BIND_DN")
    AUTH_LDAP_BIND_PASSWORD = os.getenv("LDAP_BIND_PW")

    XLDAP_BASE = os.getenv("LDAP_BASE")

    AUTH_LDAP_USER_SEARCH = LDAPSearch(
        os.getenv("LDAP_BASE"),
        ldap.SCOPE_SUBTREE,
        "(&(objectClass=user)(sAMAccountName=%(user)s))",
    )

    # Set up the basic group parameters.
    AUTH_LDAP_GROUP_SEARCH = LDAPSearch(
        os.getenv("LDAP_BASE"),
        ldap.SCOPE_SUBTREE,
        "(objectClass=group)",
    )

    AUTH_LDAP_GROUP_TYPE = ActiveDirectoryGroupType()

    AUTH_LDAP_USER_FLAGS_BY_GROUP = {
        "is_staff": os.getenv("LDAP_IS_STAFF_GROUP"),
        "is_active": os.getenv("LDAP_IS_ACTIVE_GROUP"),
    }

    AUTH_LDAP_USER_ATTR_MAP = {
        "username": "sAMAccountName",
        "first_name": "givenName",
        "last_name": "sn",
        "email": "mail",  # other fields as needed
    }

    # To ensure user object is updated each time on login
    AUTH_LDAP_ALWAYS_UPDATE_USER = True
    AUTH_LDAP_FIND_GROUP_PERMS = True
    AUTH_LDAP_CACHE_GROUPS = True
    AUTH_LDAP_CACHE_TIMEOUT = 60 * 20  # 20 minutes
    AUTH_LDAP_MIRROR_GROUPS = True

!

}

make_dot_env()
{
    touch .env

    (
        cat <<!
# centralize configuration
ENVIRONMENT="DEV"

DJANGO_LOG_LEVEL="WARNING"
DJANGO_LOGGERS_HANDLERS="console"
DJANGO_LOGGERS_HANDLERS_ROOT="console"
DJANGO_LOGGERS_HANDLERS_APP="console"

# SECURITY WARNING: don't run with debug turned on in production!
DJANGO_DEBUG=True

# SECURITY WARNING: keep the secret key used in production secret!
DJANGO_SECRET_KEY="$(pwgen -s 32)"

PG_DB="${PG_DB}"
PG_USER="${PG_USER}"
PG_PASSWORD=$( cat .db_pw )
PG_HOST="localhost"
PG_PORT=5432"

DJANGO_LANGUAGE_CODE="en-us"
DJANGO_TIME_ZONE="Europe/Zagreb"
DJANGO_USE_I18N=1
DJANGO_USE_L10N=1
DJANGO_USE_TZ=1

LDAP_BIND_DN="your bind DN"
LDAP_BIND_PW="your bind password"
LDAP_SERVER_URL="ldap://your-ldap-fqdns-name"
LDAP_BASE="DC=AAA,DC=BBB"
LDAP_IS_STAFF_GROUP="cn of group to use for staff"
LDAP_IS_ACTIVE_GROUP="cn of group to use for active"

!
    ) >> .env
}


make_app_Main()
{
    local name="aMain"

    # we are at:
    # pushd "${VENV}"
    # pushd "${PROJECT_NAME}"

    ./manage.py startapp "${name}" # abstract models

    # ------------------------------------------------
    pushd "${name}"

    mkdir -p "templates/${name}"

    # ------------------------------------------------
    cat <<! >"templates/${name}/index.html"

{% extends "base_generic.html" %}

{% block title %} {{ section.title }} {% endblock %}

{% block sidebar %}
  <ul class="sidebar-nav">
    <li><a href="{% url 'index' %}">Home</a></li>
    {% for item in navigation %}
      <li><a href="{{item.url }}">{{ item.label }}</a></li>
    {% endfor %}
  </ul>
{% endblock %}

{% block content %}
    some dummy content
{% endblock %}

!

    # ------------------------------------------------
    cat <<! >views.py
from django.shortcuts import (
    render,
    redirect,
)

def empty(request):
    return redirect("index")

def index(request):
    section = {"title": "${name}"}
    context = {
        "section": section,
        "navigation": [
            {
                "url": "/admin",
                "label": "Admin",
            },
        ],
        "content": "",
    }
    return render(request, "${name}/index.html", context)
!

    # ------------------------------------------------
    cat <<! >urls.py
from django.urls import path

from . import views

urlpatterns = [
    path("", views.index, name="index"),
]
!

    popd

    # ------------------------------------------------
    pushd "${PROJECT_NAME}"

    cat <<! >>urls.py
from django.urls import include

urlpatterns.append(
    path("", include("aMain.urls")),
)
!

    cat <<! >> settings.py

INSTALLED_APPS.append("aMain.apps.AmainConfig")

!
    popd
}

make_base_template()
{
    cat <<! > base_generic.html
<!DOCTYPE html>
<html lang="en">

<head>
  <title>{% block title %}{% endblock %}</title>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />

  <link
    href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css"
    rel="stylesheet"
    integrity="sha384-T3c6CoIi6uLrA9TneNEoa7RxnatzjcDSCmG1MXxSR1GAsXEV/Dwwykc2MPK8M2HN"
    crossorigin="anonymous"
  />

  <!-- Add additional CSS in static file -->
  {% load static %}

  <link
    rel="stylesheet"
    href="{% static 'css/styles.css' %}"
  />

</head>

<body>
  <div class="container-fluid">

    <div class="row">
      <div class="col">
        {% block top %}just a top line{% endblock %}
        <hr style="background-color: black; height: 2px; border: 0;"/>
      </div>
    </div>

    <div class="row">

      <div class="col-sm-auto">
      {% block sidebar %}
        <ul class="sidebar-nav">
          <li><a href="{% url 'index' %}">Home</a></li>
        </ul>
      {% endblock %}
      </div>

      <div class="col">
        {% block content %}
        {% endblock %}
      </div>

    </div>

  </div>
</body>

</html>
!

}

make_global_templates()
{
    mkdir templates
    pushd templates
        make_base_template
    popd
}

make_app_abstract()
{
   ./manage.py startapp aAbstract # abstract models

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

            make_global_templates

            make_app_abstract
            make_app_Main

            ./manage.py migrate
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
