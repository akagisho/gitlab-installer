#!/usr/bin/env bash

# GitLab installer for Ubuntu Server

if [ $(whoami) != "root" ]; then
    echo "You must be root to do!" 2>&1
    exit 1
fi

[[ "$MYSQL_PASSWORD" == "" ]] && MYSQL_PASSWORD="Myp@ssword"

HOSTNAME=$(hostname)

set -x

#
# 1. Packages / Dependencies
#
apt-get update
apt-get upgrade -y

apt-get install -y build-essential zlib1g-dev libyaml-dev libssl-dev libgdbm-dev libreadline-dev libncurses5-dev libffi-dev curl git-core openssh-server redis-server checkinstall libxml2-dev libxslt-dev libcurl4-openssl-dev libicu-dev logrotate expect

cat <<__EOT__ | debconf-set-selections
postfix postfix/root_address    string
postfix postfix/rfc1035_violation       boolean false
postfix postfix/relay_restrictions_warning      boolean
postfix postfix/mydomain_warning        boolean
postfix postfix/mynetworks      string  127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128
postfix postfix/mailname        string  $HOSTNAME
postfix postfix/tlsmgr_upgrade_warning  boolean
postfix postfix/recipient_delim string  +
postfix postfix/main_mailer_type        select  Internet Site
postfix postfix/destinations    string  $HOSTNAME, localhost.localdomain, localhost
postfix postfix/retry_upgrade_warning   boolean
postfix postfix/kernel_version_warning  boolean
postfix postfix/sqlite_warning  boolean
postfix postfix/mailbox_limit   string  0
postfix postfix/relayhost       string
postfix postfix/procmail        boolean false
postfix postfix/protocols       select  all
postfix postfix/chattr  boolean false
__EOT__

DEBIAN_FRONTEND=noninteractive apt-get install -y postfix

#
# 2. Ruby
#
apt-get install -y ruby1.9.3 ruby-dev rubygems
apt-get remove -y ruby1.8

gem install bundler --no-ri --no-rdoc || exit 1

#
# 3. System Users
#
adduser --disabled-login --gecos 'GitLab' git

#
# 4. GitLab shell
#
cd /home/git
if [ ! -d gitlab-shell ]; then
    sudo -H -u git -H git clone https://github.com/gitlabhq/gitlab-shell.git
    cd gitlab-shell
    sudo -H -u git -H git checkout v1.7.4
    sudo -H -u git -H cp -v config.yml.example config.yml
    sed -i 's#^gitlab_url: "http://localhost/"$#gitlab_url: "http://127.0.0.1/"#' /home/git/gitlab-shell/config.yml
    sudo -H -u git -H ./bin/install
fi

#
# 5. Database
#
cat <<__EOT__ | debconf-set-selections
mysql-server-5.5        mysql-server/root_password_again        password
mysql-server-5.5        mysql-server/root_password      password
mysql-server-5.5        mysql-server-5.5/postrm_remove_databases        boolean false
mysql-server-5.5        mysql-server-5.5/start_on_boot  boolean true
mysql-server-5.5        mysql-server-5.5/really_downgrade       boolean false
__EOT__

DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server mysql-client libmysqlclient-dev

mysql -u root -e "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u root -e 'CREATE DATABASE IF NOT EXISTS `gitlabhq_production` DEFAULT CHARACTER SET `utf8` COLLATE `utf8_unicode_ci`;'
mysql -u root -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, LOCK TABLES ON \`gitlabhq_production\`.* TO 'gitlab'@'localhost';"

#
# 6. Gitlab
#
cd /home/git
if [ ! -d gitlab ]; then
    sudo -H -u git git clone https://github.com/gitlabhq/gitlabhq.git gitlab
    cd gitlab
    sudo -H -u git git checkout 6-2-stable
 
    sudo -H -u git cp -v config/gitlab.yml.example config/gitlab.yml
    sudo -H -u git cp -v config/unicorn.rb.example config/unicorn.rb
    sudo -H -u git cp -v config/initializers/rack_attack.rb.example config/initializers/rack_attack.rb

    sed -i 's/# \(config.middleware.use Rack::Attack\)/\1/' config/application.rb
    sed -i "s/host: localhost/host: $HOSTNAME/" config/gitlab.yml
    sed -i "s/email_from: gitlab@localhost/email_from: gitlab@$HOSTNAME/" config/gitlab.yml
 
    chown -R git log
    chown -R git tmp
    chmod -R u+rwX  log
    chmod -R u+rwX  tmp
 
    sudo -H -u git mkdir /home/git/gitlab-satellites
 
    sudo -H -u git mkdir tmp/pids
    sudo -H -u git mkdir tmp/sockets
    sudo -H -u git mkdir public/uploads
    chmod -R u+rwX  tmp/pids
    chmod -R u+rwX  tmp/sockets
    chmod -R u+rwX  public/uploads
 
    sudo -H -u git git config --global user.name "GitLab"
    sudo -H -u git git config --global user.email "gitlab@$HOSTNAME"
 
    sudo -H -u git cp -v config/database.yml.mysql config/database.yml
    sed -i "s/\"secure password\"/\"$MYSQL_PASSWORD\"/" config/database.yml
    sed -i "s/username: root/username: gitlab/" config/database.yml
 
    cd /home/git/gitlab
    sudo -H -u git bundle install --deployment --without development test postgres || exit 1
fi

cd /home/git/gitlab
cp -v lib/support/logrotate/gitlab /etc/logrotate.d/gitlab
cp -v lib/support/init.d/gitlab /etc/init.d/gitlab
chmod +x /etc/init.d/gitlab
/etc/init.d/gitlab start
update-rc.d gitlab defaults 21

#
# 7. Nginx
#
apt-get install -y nginx
cp -v lib/support/nginx/gitlab /etc/nginx/sites-available/gitlab
ln -sv /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sed -i "s/listen YOUR_SERVER_IP:80 default_server/listen *:80/" /etc/nginx/sites-available/gitlab
sed -i "s/server_name YOUR_SERVER_FQDN/server_name ~.*/" /etc/nginx/sites-available/gitlab
/etc/init.d/nginx restart
update-rc.d gitlab defaults 21

cd /home/git/gitlab
sudo -u git bundle exec rake assets:precompile RAILS_ENV=production
expect -c "
set timeout -1
spawn sudo -H -u git bundle exec rake gitlab:setup RAILS_ENV=production
expect \"Do you want to continue (yes/no)?\" {
    send \"yes\n\"
    expect \"5iveL!fe\"
    send \"\n\"
}
"
