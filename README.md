# Git hosting on OpenShift

Private Git hosting "solution" for OpenShift.

## Status

Work in progress, please report issues.

## Features

* git push and pull
* auto-creation of repositories on demand

## ToDo

* security
* management

## Installation

Create OpenShift application

	rhc app create -a $name -t diy-0.1

and enter the directory

	cd $name

Add repositories as new remotes

	git remote add githosting -m master git://github.com/openshift-quickstart/githosting-openshift-quickstart.git
	git remote add template -m master git://github.com/openshift-quickstart/jruby-openshift-quickstart.git

and pull them locally

    git pull -s recursive -X theirs githosting master
	git pull -s recursive -X theirs template master

configure your JRuby environment

    cp .openshift/config.example .openshift/config
    $EDITOR .openshift/config

and deploy to OpenShift

	git push origin master

Now is your private Git hosting available at

	http://$name-$namespace.rhcloud.com

## Configuration

### Git

If you have problem pushing big repositories, configure git's HTTP buffer to allow bigger payloads (run this command in your local repository)

	git config http.postBuffer 524288000
