#!/bin/bash

#==================================
# SETUP 
#----------------------------------

USER_BRANCH=bfh
REGISTRY=ghcr.io 

#==================================

#set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PARENT_DIR=$(dirname "$(readlink -f "$SCRIPT_DIR")")

RESOURCES_DIR=$SCRIPT_DIR/resources 
CHECKOUT_DIR=$SCRIPT_DIR/code

#==================================
# Parsing which setup to run
#==================================

LONG_OPTIONS=git,pat,dev,download,skip,clean,clean-code,clean-images
OPTIONS=gpvdscoi

#--------------------------------------------------
# default arguments 
_git=true
_pat=true
_dev=true
_download=true 
_cleancode=false
_cleanimages=false

#---------------------------------------------------
# parsing input 

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONG_OPTIONS --name "setup" -- "$@")
if [[ $? -ne 0 ]]; then
    # getopt should have complained about wrong arguments to stdout
    exit 2
fi    

has_args=false
skip=false 

# skippable steps (with --skip arg)
git=false
pat=false
download=false
dev=false 

# modifiers
cleancode=$_cleancode
cleanimages=$_cleanimages

eval set -- "$PARSED"
while true; do
    case "$1" in
        -g|--git)
            git=true
            has_args=true
            shift
            ;;
        -p|--pat)
            pat=true
            has_args=true
            shift
            ;;
        -v|--dev)
            dev=true
            has_args=true
            shift
            ;;
        -d|--download)
            download=true
            has_args=true
            shift
            ;;
        -n|--skip)
            skip=true
            shift
            ;;
        -c|--clean)
            cleancode=true
            cleanimages=true
            shift 1
            ;;
        -o|--clean-code)
            cleancode=true
            shift 1
            ;;
        -i|--clean-images)
            cleanimages=true
            shift 1
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "unknown option $1"
            usage;
            exit 1
            ;;
    esac
done


if [[ "$has_args" = "false" ]]; then 
    # use default arguments 
    git=$_git
    pat=$_pat
    download=$_download 
elif [[ "$skip" = "true" ]]; then 
    git=$( $git && echo false || echo $_git )
    pat=$( $pat && echo false || echo $_pat )
    download=$( $download && echo false || echo $_download )
fi 

echo "running following setup steps:"

if [[ "$cleancode" = "true" ]]; then
    echo "- delete previous code repos"
fi 
if [[ "$pat" = "true" ]]; then
    echo "- PAT setup"
fi 
if [[ "$git" = "true" ]]; then
    echo "- Git checkout (directory $CHECKOUT_DIR)"
fi
if [[ "$dev" = "true" ]]; then
    echo "- platform requirement installation"
fi
if [[ "$cleanimages" = "true" ]]; then
    echo "- delete unused docker images"
fi 
if [[ "$download" = "true" ]]; then
    echo "- Download docker images"
fi

read -p "continue? [Y|n]" go
go=${go:-y}
if [ "${go,,}" != "y" ]; then 
    echo "aborting."
    exit 1 
fi 

#=====================================================================

check_docker() {
    while ! docker info >/dev/null 2>&1; do
        echo "docker is not running, please start the Docker engine"
        sleep 5
    done
    echo "docker is running"
}

start_time=$(date +%s)


#====================================
# GIT PERSONAL ACCESS TOKEN SETUP
#====================================

github_user_name="bfh-cell"
git_user_name=$(whoami)
git_user_email="acroba-cell.ti@bfh.ch"


if [[ "$pat" = "true" ]]; then 

    echo -e "\n|-> git credential setup"
    if git config --list | grep credential.helper; then 
        echo "git credential helper already set, skipping"
    else
        echo "setting up simple git credential helper"
        git config --global credential.helper store
    fi         

    echo -e "\n |-> setting up git & container registry access"
    echo "checking '$RESOURCES_DIR/pat.gpg'"
    if [ -e "$RESOURCES_DIR/pat.gpg" ]; then 
        echo "pat found"
        gpg -o "$RESOURCES_DIR/pat" -d "$RESOURCES_DIR/pat.gpg"
        read -r PAT < "$RESOURCES_DIR/pat" || echo "$PAT"
        echo "saving git credentials"
        git ls-remote https://${github_user_name}:$PAT@$(git remote get-url origin | sed 's|https://||') > /dev/null
        if [ $? -eq 0 ]; then
            echo "git setup completed"
        else
            echo "git setup failed"
        fi
        # secret-tool store --label='Gitlab Bfh Credential' url=https://gitlab.ti.bfh.ch username=${git_user_name} password=$PAT
        echo "setting up container registry access"
        check_docker
        echo "using docker registry @ '$REGISTRY'"
        docker login $REGISTRY -u $github_user_name --password-stdin <<< "$PAT"
        rm "$RESOURCES_DIR/pat"
    else
         echo "!!! could not find the PAT file, skipping git access setup."   
    fi
fi

#==================================
# GIT REPOSITORIES CHECKOUT
# (platform + cell-config)
#==================================

if [[ "$cleancode" = "true" ]]; then 
    rm -rf $CHECKOUT_DIR/*
fi 

if [[ "$git" = "true" ]]; then 

    echo "Checking out git repositories"
    mkdir -p $CHECKOUT_DIR

    echo "Checking out Platform"
    if ! [ -d "$CHECKOUT_DIR/platform" ]; then 
        git -C $CHECKOUT_DIR clone https://${github_user_name}@github.com/acroba-hackathon/platform.git

        echo "setting up git config locally"
        git -C $CHECKOUT_DIR/platform config --local user.name $git_user_name
        git -C $CHECKOUT_DIR/platform config --local user.email $git_user_email
        git -C $CHECKOUT_DIR/platform checkout master
        make -C $CHECKOUT_DIR/platform checkout
        # git -C $CHECKOUT_DIR/platform checkout -b ${USER_BRANCH}-$git_user_name
        # git -C $CHECKOUT_DIR/platform/acroba-modules/skills checkout -b hack-$git_user_name
        # git -C $CHECKOUT_DIR/platform/acroba-modules/taskplanner checkout -b hack-$git_user_name
        # git -C $CHECKOUT_DIR/platform/ add acroba-modules/skills
        # git -C $CHECKOUT_DIR/platform/ add acroba-modules/taskplanner
        # git -C $CHECKOUT_DIR/platform/ commit -m "skills & tp branch update"
    else
        echo "directory $CHECKOUT_DIR/platform already exists, skipping."
    fi 

    
    echo "Checking out cell_config"
    if ! [ -d "$CHECKOUT_DIR/cell-bfh" ]; then 
        git -C $CHECKOUT_DIR clone https://${github_user_name}@github.com/ACROBA-Project/cell_config_bfh.git
        git -C $CHECKOUT_DIR/cell-bfh config --local user.name $git_user_name
        git -C $CHECKOUT_DIR/cell-bfh config --local user.email $git_user_email
        git -C $CHECKOUT_DIR/cell-bfh checkout
        git -C $CHECKOUT_DIR/cell-bfh checkout -b $USER_BRANCH-$git_user_name
    else 
        echo "directory $CHECKOUT_DIR/cell-bfh already exists, skipping."
    fi
fi

#==================================
# Running setup script
#==================================

if [[  "$dev" = "true" ]]; then
    echo "installing platform requirements"
    $CHECKOUT_DIR/platform/setup.sh --dck --dev
fi

#==================================
# 5. DOWNLOADING DOCKER IMAGES
#==================================


if [[ "$cleanimages" = "true" ]]; then 
    echo "removing unused docker images"
    check_docker
    docker system prune -a -f 
fi 

if [[ "$download" = "true" ]]; then 
    echo "Downloading the platform docker images"
    make -C "$CHECKOUT_DIR/platform/" pull TAG=latest

    echo "Downloading the cell-bfh image"
    make -C "$CHECKOUT_DIR/cell-bhf/" pull TAG=latest
    docker tag acroba/cell-config-bfh acroba-hackathon/cell-config-bfh
fi 

#==================================

end_time=$(date +%s)
duration=$((end_time - start_time))

echo "all set up :) ! took $duration seconds."

