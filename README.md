gitlab-installer
================

This script can install GitLab into your machine automatically.

Usage
-----

Set your GitLab's hostname.

    $ sudo hostname gitlab.example.com

Run script.

Ubuntu 12.04 or later:

    $ curl https://raw.githubusercontent.com/akagisho/gitlab-installer/master/ubuntu.sh \
        | sudo bash 2>&1 | tee gitlab-installer.log

CentOS 6.X:

    $ curl https://raw.githubusercontent.com/akagisho/gitlab-installer/master/centos6.sh \
        | sudo bash 2>&1 | tee gitlab-installer.log

Help
----

Get more information: http://blog.akagi.jp/archives/3235.html
