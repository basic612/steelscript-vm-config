#!/usr/bin/sh
export PROJECT_DEV_DIR={{ project_root_devel }}
export PROJECT_DEV_VENV={{ virtualenv_devel }}

export PROJECT_APACHE_DIR={{ project_root_apache }}
export PROJECT_APACHE_VENV={{ virtualenv_apache }}

APACHE_LOGDIR=/var/log/apache2
export ERROR_LOG=$APACHE_LOGDIR/error.log
export ACCESS_LOG=$APACHE_LOGDIR/other_vhosts_access.log
USERGROUP=www-data

export DEV_LOGDIR=$PROJECT_DEV_DIR/logs

alias view_err_log='less $ERROR_LOG'
alias view_access_log='less $ACCESS_LOG'
alias view_project_log='less $DEV_LOGDIR/log.txt'

alias cdproject='cd $PROJECT_DEV_DIR'
alias cdwww='cd $PROJECT_APACHE_DIR'
alias cdshared='cd /vagrant'

alias appfwk_dev_server='cdproject && $PROJECT_DEV_VENV/bin/python $PROJECT_DEV_DIR/manage.py runserver `facter ipaddress`:8000'
alias run_ipython_notebook='mkdir -p ~/ipython_notebooks && cd ~/ipython_notebooks && ipython notebook --ip=`facter ipaddress` --pylab=inline'

alias virtualenv_dev='deactivate &>/dev/null; source $PROJECT_DEV_VENV/bin/activate'
alias virtualenv_www='deactivate &>/dev/null; source $PROJECT_DEV_VENV/bin/activate'

# setup terminal options
export TERM=xterm-256color


# Activate virtual environment by default on login
virtualenv_dev

# Scheduler setup
export SCHEDULER_DIR=/steelscript/scheduler
alias start_scheduler='sudo supervisord -c /steelscript/scheduler/supervisord.conf'
alias stop_scheduler='sudo kill `cat /steelscript/scheduler/supervisord.pid`'

alias view_supervisor_log='sudo less $SCHEDULER_DIR/supervisord.log'
alias view_scheduler_log='sudo less $SCHEDULER_DIR/scheduler.log'

upgrade_packages_from_dir() {
    PKGDIR=$1

    for PKG in `ls $PKGDIR`; do
        /home/vagrant/virtualenv/bin/pip install -U --no-deps $PKGDIR/$PKG
    done
    sudo apachectl restart
}

convert_steelscript_site_links() {
    # update site symlinks to libary files from git repositories
    USER=$1
    SITE_DIR=$2

    cd $SITE_DIR
    sudo rm manage.py
    sudo -u $USER ln -s /home/vagrant/virtualenv/lib/python2.7/site-packages/steelscript/appfwk/manage.py
    sudo rm media
    sudo -u $USER ln -s /home/vagrant/virtualenv/lib/python2.7/site-packages/steelscript/appfwk/media
    sudo rm thirdparty
    sudo -u $USER ln -s /home/vagrant/virtualenv/lib/python2.7/site-packages/steelscript/appfwk/thirdparty

    sudo -u $USER /home/vagrant/virtualenv/bin/python manage.py collectstatic --noinput
    sudo apachectl restart
}

convert_steelscript_pkgs() {
    # this will migrate the developer-mode packages to sdist packages instead
    # needed in order to install updates from source packages rather than
    # github updates
    CURDIR=`pwd`
    PKGDIR=$1
    upgrade_packages_from_dir $PKGDIR

    convert_steelscript_site_links vagrant /home/vagrant/appfwk_project
    convert_steelscript_site_links www-data /steelscript/www

    cd $CURDIR
}

rotate_logs() {
    echo -n "Rotating apache logs ... "
    sudo logrotate -f /etc/logrotate.d/apache2
    echo "done."
}

appfwk_clean_perms() {
    # update all perms correctly in staging dir
    CURDIR=`pwd`
    echo -n "Updating app framework development ownership ... "
    cdproject
    sudo chown -R vagrant:vagrant *
    echo "done."
    echo -n "Updating app framework apache ownership ... "
    cdwww
    sudo chown -R www-data:www-data *
    echo "done."
    cd $CURDIR
}

appfwk_collect_logs() {
    echo -n "Collecting all log files and generating zipfile ... "
    cdwww
    sudo $PORTAL_DEPLOY_VENV/bin/python manage.py collect_logs &> /dev/null
    LOGFILE=`ls -tr1 | grep debug | tail -1`

    if [[ -e /vagrant ]]; then
        ZIPFILE=/vagrant/portal_logs_`date +%d%m%y-%H%M%S`.tar.gz
    else
        ZIPFILE=~/portal_logs_`date +%d%m%y-%H%M%S`.tar.gz
    fi

    tar czf $ZIPFILE $LOGFILE $ERROR_LOG $ACCESS_LOG $PORTAL_LOG
    cd -
    echo "done."
    echo "Zip file has been stored here: $ZIPFILE"
    if [[ -e /vagrant ]]; then
        echo "This file should also appear in your host system in the vagrant directory."
    fi
}
