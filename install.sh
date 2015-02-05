#!/bin/bash

# author: Dipl.-Inf. Christian Maier
# email: chris.maier@fau.de
# organization: Chair of Medical Informatics of University of Erlangen-Nuremberg
#
# description:
# this script installs transmart 1.2.4 on fresh Ubuntu 14.0.4 Server 64bit
# if you want to install a different version just search for 'release-1.2.4' and replace by other git branch name
# NOTE: other versions of transmart may need other version of grails, so replace 'gvm install grails 2.3.11' with the necessary version


if [[ $EUID -ne 0 ]]; then
  echo "You must be root to start this script! Exiting." 2>&1
  exit 1
fi

echo "Adding new r-base source to apt to be able to install R 3.1.0 at least"
echo "deb http://cran.rstudio.com/bin/linux/ubuntu trusty/" >> /etc/apt/sources.list
gpg --keyserver keyserver.ubuntu.com --recv-key E084DAB9
gpg -a --export E084DAB9 | apt-key add -
apt-get update

apt-get -y install r-base

echo "Installing necessary packages from Ubuntu repo"
apt-get -y install openssh-client openssh-server make openjdk-7-jre ant git php5 tomcat7 unzip curl libcairo2-dev libxt-dev postgresql-9.3 postgresql-contrib-9.3

echo "Removing tomcat7 from init runlevels"
# is started by grails run-app otherwise port 8080 would be already in use
update-rc.d -f tomcat7 remove 


echo "Setting env variables"
export ANT_HOME=/usr/share/ant
export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64/
export PATH=${PATH}:${ANT_HOME}/bin


echo "Installing grails"
curl -s get.gvmtool.net | bash
# activating gvm
[[ -s "/root/.gvm/bin/gvm-init.sh" ]] && source "/root/.gvm/bin/gvm-init.sh"
echo "gvm_auto_answer=true" > '/root/.gvm/etc/config'
gvm install grails 2.3.11


echo "Creating necessary folders /transmart_install and /transmart_etl"
sudo mkdir /transmart_install
sudo mkdir /transmart_etl

cd /transmart_install


echo "Installing R packages"
cat > install_R_packages.r <<EOF
#!/usr/bin/Rscript
install.packages(c('Rserve','drc','visreg','Cairo','MASS','stringr','rmeta','ggplot2','plyr','reshape2','gplots','data.table','matrixStats', 'Hmisc', 'foreach', 'doParallel', 'reshape', 'fastcluster', 'dynamicTreeCut', 'survival'), repos='http://cran.us.r-project.org')

source("http://bioconductor.org/biocLite.R")
biocLite(c('GO.db', 'preprocessCore', 'impute'))
install.packages('WGCNA', repos='http://cran.us.r-project.org')
biocLite(c('multtest','limma','snpStats','edgeR','nzr','CGHbase'))

library(Rserve)
Rserve()

EOF

chmod +x install_R_packages.r

./install_R_packages.r

rm install_R_packages.r

# installing CGHtest package which is not part of the R repos
wget http://www.few.vu.nl/~mavdwiel/CGHtest/CGHtest_1.1.tar.gz

Rscript -e "install.packages('CGHtest_1.1.tar.gz', repos = NULL)"



echo "Creating transmart and Rserve init scripts"
cat > /etc/init.d/transmart <<EOF
#! /bin/sh
### BEGIN INIT INFO
# Provides:
# Required-Start:
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Kurze Beschreibung
# Description:       Längere Bechreibung
### END INIT INFO
# Author: Name <email@domain.tld>

# Aktionen
case "$1" in
    start)
        /usr/bin/transmartStart
        ;;
    stop)

        ;;
    restart)
        ;;
esac

EOF

chmod +x /etc/init.d/transmart


cat > /usr/bin/transmartStart <<EOF
#!/bin/bash

export JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64
export PATH="$PATH:$JAVA_HOME/bin"
cd /transmart_install/transmartApp/
/root/.gvm/grails/current/bin/grails run-app

EOF

chmod +x /usr/bin/transmartStart


cat > /etc/init.d/Rserved <<EOF
#! /bin/sh
### BEGIN INIT INFO
# Provides:          
# Required-Start:
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Kurze Beschreibung
# Description:       Längere Bechreibung
### END INIT INFO
# Author: Name <email@domain.tld>

# Aktionen
case "$1" in
    start)
        /usr/lib/R/bin/R CMD /usr/local/lib/R/site-library/Rserve/libs/Rserve
        ;;
    stop)

        ;;
    restart)
        ;;
esac

EOF

chmod +x /etc/init.d/Rserved


echo "Registering init scripts to runlevels"
update-rc.d -f Rserved defaults 
update-rc.d -f transmart defaults


echo "Setting postgres user password"
sudo -i -u postgres /usr/bin/psql -c "alter user postgres password 'postgres';"


cd /transmart_install
echo "Checking out transmart packages from git repos"
git clone https://github.com/transmart/tranSMART-ETL.git
cd tranSMART-ETL
git fetch --tags
git checkout release-1.2.4

cd ..

git clone https://github.com/transmart/transmart-data.git
cd transmart-data
git fetch --tags
git checkout release-1.2.4

cd ..

# necessary as "make -C env ubuntu_deps_regular" is faulty cloning tranSMART-ETL -> otherwise always timeout when downloading
mv tranSMART-ETL transmart-data/env/

wget http://downloads.sourceforge.net/project/pentaho/Data%20Integration/5.1/pdi-ce-5.1.0.0-752.zip
unzip pdi-ce-5.1.0.0-752.zip
mv data-integration transmart-data/env/

cd transmart-data

make -C env ubuntu_deps_root
make -C env ubuntu_deps_regular

cd ..


git clone https://github.com/transmart/transmartApp.git
cd transmartApp
git fetch --tags
git checkout release-1.2.4

cd ..

git clone https://github.com/transmart/transmart-core-api.git
cd transmart-core-api
git fetch --tags
git checkout release-1.2.4

cd ..

echo "Setting env variables for loading transmart-data"

# see Troubleshooting database connections
# https://github.com/thehyve/transmartAppInstaller

export PGHOST=127.0.0.1
export PGPORT=5432
export PGDATABASE=transmart
export PGUSER=postgres
export PGPASSWORD=postgres
export TSUSER_HOME=$HOME/
export PGSQL_BIN="sudo -E -u postgres /usr/bin/"
export TABLESPACES=/var/lib/postgresql/tablespaces/
export KETTLE_JOBS_PSQL=/transmart_install/transmart-data/env/tranSMART-ETL/Postgres/GPL-1.0/Kettle/Kettle-ETL/
export KITCHEN=/transmart_install/transmart-data/env/data-integration/kitchen.sh
export PATH=/transmart_install/transmart-data/env:$PATH


echo "Creating database structure"
cd transmart-data
make postgres_drop
make -j4 postgres
make -C config install


echo "Running transmart and exiting..."

# stopping tomcat as blocking port 8080 if running
service tomcat7 stop

cd ../transmartApp
[[ -s "/root/.gvm/bin/gvm-init.sh" ]] && source "/root/.gvm/bin/gvm-init.sh"
# always runs into error as wrong grails version but needs to be started with grails 2.3.11 first time to compile files
grails run-app

# removing grails 2.3.11 again as transmartApp needs to be started with different version for compiling source files with different versions of grails
gvm rm grails 2.3.11
gvm install grails 2.3.7
[[ -s "/root/.gvm/bin/gvm-init.sh" ]] && source "/root/.gvm/bin/gvm-init.sh"
grails run-app

# installing grails 2.3.11 again to finally start transmart
gvm rm grails 2.3.7
gvm install grails 2.3.11
[[ -s "/root/.gvm/bin/gvm-init.sh" ]] && source "/root/.gvm/bin/gvm-init.sh"
grails run-app

