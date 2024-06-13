# make_new_django_project


## Basic

 - create a basic django project (project) in a venv (xdev), tested with django 5.0.x
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

 - add a system file for gunicorn: VENV/gunicorn<n>.service
 - add a socket file for gunicorn: VENV/gunicorn<n>.socket

these files can be added to /etc/systemd/system/ (make sure you dont accidentally overwite anything)

## postgres

 - provide instructions to create a postgres database instance for the project

## Tested with

 - Fedora 40
 - Python 3.12
 - Django 5
