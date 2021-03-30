#!/bin/bash

echo "##################配置映射###########################"
host_ip=`ifconfig | grep 'inet' | grep '192' | cut -d ' ' -f10`
#host_ip=`ifconfig |grep -w inet|awk 'NR==1{print$2}'`
host_name=contrall
ADMIN_PASS=1234
openstack user create --domain default --password-prompt swift
echo "创建用户"
sleep 3
openstack role add --project service --user swift admin
openstack service create --name swift --description "OpenStack Object Storage" object-store
openstack endpoint create --region RegionOne object-store public http://$host_ip:8080/v3/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store internal http://$host_ip:8080/v3/AUTH_%\(project_id\)s
openstack endpoint create --region RegionOne object-store admin http://$host_ip:8080/v3
yum install openstack-swift-proxy python-swiftclient python-keystoneclient python-keystonemiddleware memcached -y
# 从对象存储源存储库获取代理服务配置文件
curl -o /etc/swift/proxy-server.conf https://opendev.org/openstack/swift/raw/branch/stable/rocky/etc/proxy-server.conf-sample
cat /environment/proxy-server.conf >> /etc/swift/proxy-server.conf






