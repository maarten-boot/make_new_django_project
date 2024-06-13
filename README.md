# make_new_django_project


## Basic

 - create a basic django project (project) in a venv (xdev)
 - create a app for abstract models aAbstract (AbsBase, AbsCommonName)
 - create a app for the main entry point aMain
 - setup the routing to use the initial view for the aMain app
 - use a global base template

## Options

 - optionally add ldap support in the settings
 - optionally add rest framwork (untested)
 - optionally add typing (mypy), formatting (black) and code quality (pylama)
    - installed items will not be added to requirements.txt

## Nginx

 - add a basic config file for nginx: VENV/nginx.conf with a custom port

This file can be installed in /etc/nginx/conf.d/ (on fedora 40+)

## systemd

Multiple gunicorn<n> services can coexist, just change the number in: GUNICORN_NAME

 - add a system file for gunicorn: VENV/gunicorn<n>.service
 - add a socket file for gunicorn: VENV/gunicorn<n>.socket

these files can be added to /etc/systemd/system/
(make sure you dont accidentally overwite anything)

## postgres

 - provide instructions to create a postgres database instance for the project

## Configuration

Configuration is done in the `make_new_django_project.sh` in the `configMe()` function

    configMe()
    {
        # ==============================
        ## START CONFIG

        PY_VERSION="3.12" # this [python version must exist on this platform

        # Will we erase any existing VENV yes=1
        WITH_ERASE_PREVIOUS="1"

        export HERE=$( realpath . ) # where will we create the venv and run all commands

        # OPTIONAL LDAP AND REST
        export WITH_REST="0"
        export WITH_LDAP="1"

        # OPTIONAL formatting tools
        export WITH_FORMATTING="0"

        # VENV AND PROJECT
        export VENV="xdev"
        export PROJECT_NAME="project" # the django project name

        # POSTGRES DATABASE
        export PG_USER="xdev"
        export PG_DB="xdevdb"
        export PG_DATABASE_EXISTS=0 # initially it does not exist

        export SYSTEMD_USER=$( id -u -n)
        export SYSTEMD_GROUP=$( id -g -n )

        export DJANGO_TESTPORT=8888
        export NGINX_PORT="83"
        export GUNICORN_NAME="gunicorn003"

        # END CONFIG
        # ==============================
    }

## Tested with

 - Fedora 40
 - Python 3.12
 - Django 5
 - Postgresql 16
