#!/bin/bash

rm -rf *.ldif 


read -p "Enter ip 1st master server:" ip1
read -p "Enter ip 1nd master server Hostname:" host1

read -p "Enter ip 2st master server ip :" ip2
read -p "Enter ip 2nd master server Hostname:" host2


echo "$ip1 $host1" > hosts
echo -n "$ip2 $host1" >> hosts

read -p "Enter the DC(Domain Contorl) i.e nsm:" domainc

read -p "Enter the password for manager:" password


read -p "Enter the OU(Organization Unit):" ounit



cat <<EOT >syncprov_mod.ldif
dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulePath: /usr/lib64/openldap
olcModuleLoad: syncprov.la
EOT

scp syncprov_mod.ldif $ip2:/root



cat <<EOT >olcserverid.ldif
dn: cn=config
changetype: modify
add: olcServerID
olcServerID: 1
EOT

cat <<EOT >olcserverid2.ldif
dn: cn=config
changetype: modify
add: olcServerID
olcServerID: 2
EOT


scp olcserverid2.ldif $ip2:/root

a=`slappasswd -h {SHA} -s $password`

cat <<EOT >olcdatabase.ldif
dn: olcDatabase={0}config,cn=config
add: olcRootPW
olcRootPW: $a
EOT

scp olcdatabase.ldif $ip2:/root

cat <<EOT >configrep.ldif
dn: cn=config
changetype: modify
replace: olcServerID
olcServerID: 1 ldap://$host1
olcServerID: 2 ldap://$host2

dn: olcOverlay=syncprov,olcDatabase={0}config,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov

dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcSyncRepl
olcSyncRepl: rid=001 provider=ldap://$host1 binddn="cn=config"
  bindmethod=simple credentials=$password searchbase="cn=config"
  type=refreshAndPersist retry="5 5 300 5" timeout=1
olcSyncRepl: rid=002 provider=ldap://$host2 binddn="cn=config"
  bindmethod=simple credentials=$pasword searchbase="cn=config"
  type=refreshAndPersist retry="5 5 300 5" timeout=1
-
add: olcMirrorMode
olcMirrorMode: TRUE
EOT

scp configrep.ldif $ip2:/root



cat <<EOT >syncprov.ldif
dn: olcOverlay=syncprov,olcDatabase={2}hdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
EOT


cat <<EOT >olcdatabasehdb.ldif
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=$domainc,dc=in
-
replace: olcRootDN
olcRootDN: cn=Manager,dc=$domainc,dc=in
-
replace: olcRootPW
olcRootPW: $a
-
add: olcSyncRepl
olcSyncRepl: rid=004 provider=ldap://$host1 binddn="cn=Manager,dc=$domainc,dc=in" bindmethod=simple
  credentials=$password searchbase="dc=$domainc,dc=in" type=refreshOnly
  interval=00:00:00:10 retry="5 5 300 5" timeout=1
olcSyncRepl: rid=005 provider=ldap://$host2 binddn="cn=Manager,dc=$domainc,dc=in" bindmethod=simple
  credentials=$password searchbase="dc=$domainc,dc=in" type=refreshOnly
  interval=00:00:00:10 retry="5 5 300 5" timeout=1
-
add: olcDbIndex
olcDbIndex: entryUUID  eq
-
add: olcDbIndex
olcDbIndex: entryCSN  eq
-
add: olcMirrorMode
olcMirrorMode: TRUE
EOT

cat <<EOT >monitor.ldif
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external, cn=auth" read by dn.base="cn=Manager,dc=$domainc,dc=in" read by * none
EOT

cat <<EOT >base.ldif
dn: dc=$domainc,dc=in
dc: $domainc
objectClass: top
objectClass: domain

dn: cn=Manager ,dc=$domainc,dc=in
objectClass: organizationalRole
cn: Manager
description: LDAP Manager

dn: ou=$ounit,dc=$domainc,dc=in
objectClass: organizationalUnit
ou: $ounit

dn: ou=Group,dc=$domainc,dc=in
objectClass: organizationalUnit
ou: Group
EOT

systemctl start slapd.service  
ssh $ip2 "systemctl start slapd.service" 


cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG 
ssh $ip2 "cp  -v /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG" 

chown ldap:ldap /var/lib/ldap/* 

ssh $ip2 "chown ldap:ldap /var/lib/ldap/*"

ldapadd -Y EXTERNAL -H ldapi:/// -f syncprov_mod.ldif 
ssh $ip2 "ldapadd -Y EXTERNAL -H ldapi:/// -f /root/syncprov_mod.ldif" 


ldapmodify -Y EXTERNAL -H ldapi:/// -f olcserverid.ldif  

ssh $ip2 "ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/olcserverid2.ldif" 


ldapmodify -Y EXTERNAL -H ldapi:/// -f olcdatabase.ldif

ssh $ip2 "ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/olcdatabase.ldif"


ldapmodify -Y EXTERNAL -H ldapi:/// -f configrep.ldif

ssh $ip2 "ldapmodify -Y EXTERNAL -H ldapi:/// -f /root/configrep.ldif"


ldapmodify -Y EXTERNAL -H ldapi:/// -f syncprov.ldif -h $ip1
ldapmodify -Y EXTERNAL  -H ldapi:/// -f olcdatabasehdb.ldif -h $ip1
ldapmodify -Y EXTERNAL  -H ldapi:/// -f monitor.ldif -h $ip1

ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif



ldapadd -x -W -D "cn=Manager,dc=$domainc,dc=in" -f base.ldif -h $ip1




















