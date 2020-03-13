export http_proxy=http://proxy.hcm.fpt.vn:80
export https_proxy=http://proxy.hcm.fpt.vn:80
yum -y install wget

wget http://repo.zabbix.com/zabbix/4.0/rhel/7/x86_64/zabbix-agent-4.0.5-1.el7.x86_64.rpm
yum  -y install zabbix-agent-4.0.5-1.el7.x86_64.rpm

sed -i 's/Server=127.0.0.1/Server=172.20.19.100/g' 	       /etc/zabbix/zabbix_agentd.conf
sed -i 's/ServerActive=127.0.0.1/ServerActive=172.20.19.100/g' /etc/zabbix/zabbix_agentd.conf
sed -i 's/Hostname=Zabbix server/Hostname='$HOSTNAME'/g'       /etc/zabbix/zabbix_agentd.conf

cd /etc/zabbix/zabbix_agentd.d/ 
wget https://raw.githubusercontent.com/tamtd4/Scripts/master/userparameter_diskstats_linux.conf

cd /usr/local/bin/ 
wget https://raw.githubusercontent.com/tamtd4/Scripts/master/lld-disks.py
chmod +x /usr/local/bin/lld-disks.py

cd /etc/zabbix/zabbix_agentd.d/
wget https://raw.githubusercontent.com/hungpt91/Scripts/master/userparameter_socket.conf

systemctl start zabbix-agent
systemctl enable zabbix-agent
systemctl restart zabbix-agent

iptables -I INPUT 1 -s 172.20.19.100/32 -p tcp -m tcp --dport 10050 -m comment --comment "Allow Zabbix" -j ACCEPT
iptables-save > /etc/sysconfig/iptables

cd /usr/local/bin 
wget https://raw.githubusercontent.com/tamtd4/Scripts/master/haproxy_stats.sh 
wget https://raw.githubusercontent.com/tamtd4/Scripts/master/haproxy_discovery.sh
chmod +x haproxy_stats.sh
chmod +x haproxy_discovery.sh

cd /etc/zabbix/zabbix_agentd.d/ 
wget https://raw.githubusercontent.com/tamtd4/Scripts/master/userparameter_haproxy.conf

systemctl restart zabbix-agent
