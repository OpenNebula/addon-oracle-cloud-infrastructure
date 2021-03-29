#!/bin/bash

usage() {
 echo
 echo "Usage: install.sh [-u install_user] [-g install_group]"
 echo "                  [-d ONE_LOCATION] [-h]"
 echo
 echo "-d: target installation directory, if not defined it will be root. Must be"
 echo "    an absolute path."
 echo "-h: prints this help"
}

do_file() {
    echo $1 $2
    #cp -R $SRC_DIR/$1 $2
    
}

copy_files() {
    FILES=$1
    DST=$DESTDIR$2
    
    cp -R src/$1 $DST
    if [[ "$ONEADMIN_USER" != "0" || "$ONEADMIN_GROUP" != "0" ]]; then
        chown -R $ONEADMIN_USER:$ONEADMIN_GROUP $2
    fi
}

ARGS=$*

PARAMETERS="hu:g:d:"

if [ $(getopt --version | tr -d " ") = "--" ]; then
    TEMP_OPT=`getopt $PARAMETERS "$@"`
else
    TEMP_OPT=`getopt -o $PARAMETERS -n 'install.sh' -- "$@"`
fi

if [ $? != 0 ] ; then
    usage
    exit 1
fi

eval set -- "$TEMP_OPT"

ONEADMIN_USER=`id -u`
ONEADMIN_GROUP=`id -g`
SRC_DIR=$PWD

while true ; do
    case "$1" in
        -h) usage; exit 0;;
        -d) ROOT="$2" ; shift 2 ;;
        -u) ONEADMIN_USER="$2" ; shift 2;;
        -g) ONEADMIN_GROUP="$2"; shift 2;;
        --) shift ; break ;;
        *)  usage; exit 1 ;;
    esac
done

export ROOT

if [ -z "$ROOT" ]; then
    VAR_LOCATION="/var/lib/one"
    REMOTES_LOCATION="$VAR_LOCATION/remotes"
    ETC_LOCATION="/etc/one"
    RUBY_LIB_LOCATION="/usr/lib/one/ruby"
else
    VAR_LOCATION="$ROOT/var"
    REMOTES_LOCATION="$VAR_LOCATION/remotes"
    ETC_LOCATION="$ROOT/etc"
    RUBY_LIB_LOCATION=ONE_LOCATION+"/lib/ruby"
fi

copy_files "im/" "$REMOTES_LOCATION/im/"
copy_files "vmm/" "$REMOTES_LOCATION/vmm/"
copy_files "oci_driver.rb" "$RUBY_LIB_LOCATION"
copy_files "etc/" "$ETC_LOCATION"