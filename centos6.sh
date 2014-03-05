#!/usr/bin/env bash

# GitLab installer for CentOS 6.4 (64bit)

if [ $(whoami) != "root" ]; then
    echo "You must be root to do!" 1>&2
    exit 1
fi

[[ "$MYSQL_PASSWORD" == "" ]] && MYSQL_PASSWORD="Myp@ssword"

HOSTNAME=$(hostname)

set -x

#
# 1. Packages / Dependencies
#
yum -y update

[[ ! -d /usr/local/rpm ]] && mkdir -p /usr/local/rpm

cd /usr/local/rpm
if [ ! -f epel-release-6-8.noarch.rpm ]; then
    curl -O http://ftp-srv2.kddilabs.jp/Linux/distributions/fedora/epel/6/x86_64/epel-release-6-8.noarch.rpm || exit 1
fi
rpm -ivh epel-release-6-8.noarch.rpm
sed -i "s/enabled=1/enabled=0/" /etc/yum.repos.d/epel.repo

yum -y groupinstall "development tools"
yum -y --enablerepo=epel install zlib-devel openssl-devel gdbm-devel readline-devel ncurses-devel libffi-devel libxml2-devel libxslt-devel libcurl-devel libicu-devel libyaml-devel logrotate expect

if [ ! -f rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm ]; then
    curl -OL http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm || exit 1
fi
rpm -ivh rpmforge-release-0.5.3-1.el6.rf.x86_64.rpm
sed -i "s/enabled\s*=\s*1/enabled=0/" /etc/yum.repos.d/rpmforge.repo

yum -y --enablerepo=rpmforge-extras install git

#
# 2. Ruby
#
if [ ! -x /usr/bin/ruby ]; then
    cd /usr/local/src
    curl -O http://ftp.ruby-lang.org/pub/ruby/ruby-2.0.0-p353.tar.gz || exit 1
    tar xvzf ruby-2.0.0-p353.tar.gz
    cd ruby-2.0.0-p353
    ./configure || exit 1
    make || exit 1
    make install || exit 1
    ln -sv /usr/local/bin/ruby /usr/bin
fi

if [ ! -x /usr/bin/gem ]; then
    cd /usr/local/src
    curl -OL http://production.cf.rubygems.org/rubygems/rubygems-2.1.11.tgz || exit 1
    tar xvzf rubygems-2.1.11.tgz
    cd rubygems-2.1.11
    ruby setup.rb || exit 1
    ln -sv /usr/local/bin/gem /usr/bin
fi

if [ ! -x /usr/bin/bundle ]; then
    gem install bundler || exit 1
    ln -sv /usr/local/bin/bundle /usr/bin
fi

if [ ! -x /usr/bin/ruby ]; then
    echo "Cannot install ruby!" 1>&2
    exit 1
elif [ ! -x /usr/bin/gem ]; then
    echo "Cannot install gem!" 1>&2
    exit 1
elif [ ! -x /usr/bin/bundle ]; then
    echo "Cannot install bundle!" 1>&2
    exit 1
fi

#
# 3. System Users
#
if [ ! -d /home/git ]; then
    useradd git
    chmod 755 /home/git
    mkdir /home/git/.ssh
    touch /home/git/.ssh/authorized_keys
    chown -R git /home/git/.ssh
    chmod -R g-rwx,o-rwx /home/git/.ssh
fi

#
# 4. GitLab shell
#
cd /home/git
if [ ! -d gitlab-shell ]; then
    sudo -u git git clone https://github.com/gitlabhq/gitlab-shell.git
    cd gitlab-shell
    sudo -u git git checkout v1.8.0
    sudo -u git cp -v /home/git/gitlab-shell/config.yml.example /home/git/gitlab-shell/config.yml
    sed -i 's#^gitlab_url: "http://localhost/"$#gitlab_url: "http://127.0.0.1/"#' /home/git/gitlab-shell/config.yml
    sudo -u git ./bin/install
fi

#
# 5. Database
#
cd /usr/local/rpm
if [ ! -f remi-release-6.rpm ]; then
    curl -O http://rpms.famillecollet.com/enterprise/remi-release-6.rpm || exit 1
fi
rpm -ivh remi-release-6.rpm
yum -y --enablerepo=remi install mysql mysql-server mysql-devel mysql-libs

/etc/init.d/mysqld start || exit 1
chkconfig mysqld on

mysql -u root -e "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u root -e 'CREATE DATABASE IF NOT EXISTS `gitlabhq_production` DEFAULT CHARACTER SET `utf8` COLLATE `utf8_unicode_ci`;'
mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, LOCK TABLES ON \`gitlabhq_production\`.* TO 'gitlab'@'localhost';"

yum -y --enablerepo=epel install redis
/etc/init.d/redis start || exit 1
chkconfig redis on

#
# 6. Gitlab
#
cd /home/git
if [ ! -d gitlab ]; then
    sudo -u git git clone https://github.com/gitlabhq/gitlabhq.git gitlab
    cd gitlab
    sudo -u git git checkout 6-5-stable

    sudo -u git cp -v config/gitlab.yml.example config/gitlab.yml
    sudo -u git cp -v config/unicorn.rb.example config/unicorn.rb
    sudo -u git cp -v config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb

    sed -i "s/host: localhost/host: $HOSTNAME/" config/gitlab.yml
    sed -i "s/email_from: gitlab@localhost/email_from: gitlab@$HOSTNAME/" config/gitlab.yml

    chown -R git log
    chown -R git tmp
    chmod -R u+rwX  log
    chmod -R u+rwX  tmp

    sudo -u git mkdir /home/git/gitlab-satellites

    sudo -u git mkdir tmp/pids
    sudo -u git mkdir tmp/sockets
    sudo -u git mkdir public/uploads
    chmod -R u+rwX  tmp/pids
    chmod -R u+rwX  tmp/sockets
    chmod -R u+rwX  public/uploads

    sudo -u git git config --global user.name "GitLab"
    sudo -u git git config --global user.email "gitlab@$HOSTNAME"

    sudo -u git cp -v config/database.yml.mysql config/database.yml
    sed -i "s/\"secure password\"/\"$MYSQL_PASSWORD\"/" config/database.yml
    sed -i 's/^\(\s*\)username: .*$/\1username: gitlab/' config/database.yml

    cd /home/git/gitlab
    sudo -u git bundle install --deployment --without development test postgres || exit 1
fi

cp -v /home/git/gitlab/lib/support/init.d/gitlab /etc/init.d/gitlab
sed -i "s/NAME=git/NAME=gitlab/" /etc/init.d/gitlab
chmod +x /etc/init.d/gitlab
/etc/init.d/gitlab start || exit 1
chkconfig gitlab on

cp -v /home/git/gitlab/lib/support/logrotate/gitlab /etc/logrotate.d/gitlab

#
# 7. Nginx
#
cd /usr/local/rpm
if [ ! -f nginx-release-centos-6-0.el6.ngx.noarch.rpm ]; then
    curl -O http://nginx.org/packages/centos/6/noarch/RPMS/nginx-release-centos-6-0.el6.ngx.noarch.rpm || exit 1
fi
rpm -ivh nginx-release-centos-6-0.el6.ngx.noarch.rpm
sed -i "s/enabled=1/enabled=0/" /etc/yum.repos.d/nginx.repo
yum -y --enablerepo=nginx install nginx

curl -o /etc/nginx/conf.d/gitlab.conf https://raw.github.com/akagisho/gitlab-installer/master/nginx.conf || exit 1
sed -i "s/listen YOUR_SERVER_IP:80 default_server/listen *:80/" /etc/nginx/conf.d/gitlab.conf
sed -i "s/server_name YOUR_SERVER_FQDN/server_name ~.*/" /etc/nginx/conf.d/gitlab.conf

/etc/init.d/nginx start || exit 1
chkconfig nginx on

/etc/init.d/iptables stop
chkconfig iptables off

cd /home/git/gitlab
sudo -u git bundle exec rake assets:precompile RAILS_ENV=production
expect -c "
set timeout -1
spawn sudo -u git bundle exec rake gitlab:setup RAILS_ENV=production
expect \"Do you want to continue (yes/no)?\" {
    send \"yes\n\"
    expect \"5iveL!fe\"
    send \"\n\"
}
"
