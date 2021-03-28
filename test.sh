#!/bin/bash

echo "##################配置映射###########################"
host_ip=`ifconfig | grep 'inet' | grep '192' | cut -d ' ' -f10`
#host_ip=`ifconfig |grep -w inet|awk 'NR==1{print$2}'`
host_name=contrall
ADMIN_PASS=123456
echo " $host_ip  $host_name" >> /etc/hosts
cat /etc/hosts
echo "##################配置映射完成###########################"
sleep 3
echo "##################关闭防火墙###########################"
systemctl stop firewalld.service
systemctl disable firewalld.service
systemctl status firewalld.service
setenforce 0
getenforce
sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/sysconfig/selinux
grep SELINUX=disabled /etc/sysconfig/selinux
echo "##################配置源###########################"
rm -rf /etc/yum.repos.d/
mkdir /etc/yum.repos.d/
cp yum.repos.d/* /etc/yum.repos.d/
echo "##################配置完成###########################"
sleep 3
echo "##################更新配置###########################"
yum clean all
yum makecache
echo "OK"
sleep 3
echo "##################设置时区###########################"
yum install chrony -y
mv /etc/chrony.conf /etc/chrony.conf.back
grep -v '^server' /etc/chrony.conf.back > /etc/chrony.conf
echo "server ntp1.aliyun.com iburst" >>/etc/chrony.conf
echo "server ntp2.aliyun.com iburst" >>/etc/chrony.conf
echo "allow `ifconfig | grep 'inet' | grep '192' | cut -d ' ' -f10|cut -d'.' -f1,2,3`.0/24" >>/etc/chrony.conf
rm -rf /etc/chrony.conf.back
systemctl restart chronyd.service
systemctl status chronyd.service
systemctl enable chronyd.service
systemctl list-unit-files |grep chronyd.service
timedatectl set-timezone Asia/Shanghai
chronyc sources
timedatectl status
echo "OK"
echo "##################数据库设置###########################"
yum install python-openstackclient openstack-selinux -y
yum install mariadb mariadb-server MySQL-python python2-PyMySQL -y
echo "[mysqld]"
echo "bind-address = 0.0.0.0" >> /etc/my.cnf.d/mariadb_openstack.cnf
echo "default-storage-engine = innodb" >> /etc/my.cnf.d/mariadb_openstack.cnf
echo "innodb_file_per_table = on" >> /etc/my.cnf.d/mariadb_openstack.cnf
echo "max_connections = 4096" >> /etc/my.cnf.d/mariadb_openstack.cnf
echo "collation-server = utf8_general_ci" >> /etc/my.cnf.d/mariadb_openstack.cnf
echo "character-set-server = utf8" >> /etc/my.cnf.d/mariadb_openstack.cnf
echo "init-connect = 'SET NAMES utf8'" >> /etc/my.cnf.d/mariadb_openstack.cnf
systemctl restart mariadb.service
systemctl status mariadb.service 
systemctl enable mariadb.service 
systemctl list-unit-files |grep mariadb.service
echo "配置数据库 先回车，接着输入默认密码123456（2次），一直点Y"
/usr/bin/mysql_secure_installation
echo "OK"
echo "安装消息队列"
sleep 5
systemctl restart mariadb.service
yum install rabbitmq-server -y
systemctl start rabbitmq-server.service
systemctl status rabbitmq-server.service
systemctl enable rabbitmq-server.service
systemctl list-unit-files |grep rabbitmq-server.service
rabbitmqctl add_user openstack openstack
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
rabbitmqctl set_permissions -p "/" openstack ".*" ".*" ".*"
rabbitmq-plugins enable rabbitmq_management
systemctl restart rabbitmq-server.service
rabbitmq-plugins list
echo "OK"
echo "安装Memcached"
yum install memcached python-memcached -y
mv /etc/sysconfig/memcached /etc/sysconfig/memcached.back
grep -v '^OP' /etc/sysconfig/memcached.back >> /etc/sysconfig/memcached
echo 'OPTIONS="-l 127.0.0.1,controller"' >> /etc/sysconfig/memcached
systemctl start memcached.service
systemctl status memcached.service
netstat -anptl|grep memcached
systemctl enable memcached.service
systemctl list-unit-files |grep memcached.service
echo "OK"
echo "安装etcd"
sleep 5
yum install etcd -y
echo '#[Member]' >> /etc/etcd/etcd.conf
echo 'ETCD_DATA_DIR="/var/lib/etcd/default.etcd"' >> /etc/etcd/etcd.conf
echo 'ETCD_LISTEN_PEER_URLS="'$host_ip':2380"' >> /etc/etcd/etcd.conf
echo 'ETCD_LISTEN_CLIENT_URLS="'$host_ip':2379"' >> /etc/etcd/etcd.conf
echo 'ETCD_NAME="controller"' >> /etc/etcd/etcd.conf
echo '#[Clustering]' >> /etc/etcd/etcd.conf
echo 'ETCD_INITIAL_ADVERTISE_PEER_URLS="'$host_ip':2380"' >> /etc/etcd/etcd.conf
echo 'ETCD_ADVERTISE_CLIENT_URLS="'$host_ip':2379"' >> /etc/etcd/etcd.conf
echo 'ETCD_INITIAL_CLUSTER="controller='$host_ip':2380"' >> /etc/etcd/etcd.conf
echo 'ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"' >> /etc/etcd/etcd.conf
echo 'ETCD_INITIAL_CLUSTER_STATE="new"' >> /etc/etcd/etcd.conf
systemctl start etcd.service
systemctl status etcd.service
netstat -anptl|grep etcd
systemctl enable etcd.service
systemctl list-unit-files |grep etcd.service
echo "______________________________________________________________________________________________"
echo "--------------------------------openstake环境准备工作完成---------------------------------------"
echo "______________________________________________________________________________________________"
sleep 5
echo "-------------------------------keystone组件安装—————————————————————————————————————————————————"
mysql -uroot -p123456 <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone';
flush privileges;
show databases;
select user,host from mysql.user;
exit
EOF
yum install openstack-keystone httpd mod_wsgi -y
yum install openstack-keystone python-keystoneclient openstack-utils -y
yum install -y python2-openstackclient   
openstack-config --set /etc/keystone/keystone.conf database connection mysql+pymysql://keystone:keystone@$host_name/keystone
openstack-config --set /etc/keystone/keystone.conf token provider fernet
su -s /bin/sh -c "keystone-manage db_sync" keystone
if [ "45" = `mysql -h"$host_ip" -ukeystone -pkeystone -e "use keystone;show tables;"|wc -l ` ]
then echo "数据库导入成功"
else  sleep 15;echo "数据库导入失败"
fi
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
mv /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.back
grep -v 'ServerName' /etc/httpd/conf/httpd.conf.back >> /etc/httpd/conf/httpd.conf
rm -rf /etc/httpd/conf/httpd.conf.back
echo "ServerName $host_name" >> /etc/httpd/conf/httpd.conf
ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
systemctl start httpd.service
systemctl status httpd.service
netstat -anptl|grep httpd
systemctl enable httpd.service
systemctl list-unit-files |grep httpd.service

keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
  --bootstrap-admin-url http://$host_name:5000/v3/ \
  --bootstrap-internal-url http://$host_name:5000/v3/ \
  --bootstrap-public-url http://$host_name:5000/v3/ \
  --bootstrap-region-id RegionOne

echo "export OS_PROJECT_DOMAIN_NAME=Default" >>/etc/profile
echo "export OS_PROJECT_NAME=admin" >>/etc/profile
echo "export OS_USER_DOMAIN_NAME=Default" >>/etc/profile
echo "export OS_USERNAME=admin" >>/etc/profile
echo "export OS_PASSWORD=123456" >>/etc/profile
echo "export OS_AUTH_URL=http://$host_name:5000/v3" >>/etc/profile
echo "export OS_IDENTITY_API_VERSION=3" >>/etc/profile
source /etc/profile
openstack endpoint list
openstack project list 
openstack user list 














