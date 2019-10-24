FROM openjdk:8
RUN wget https://product-dist.ballerina.io/downloads/1.0.1/ballerina-linux-installer-x64-1.0.1.deb
RUN dpkg -i ballerina-linux-installer-x64-1.0.1.deb
WORKDIR /usr/src/distributor
ADD deployment-utils/ /usr/lib/ballerina/ballerina-1.0.1/distributions/jballerina-1.0.1/
ADD distributor /usr/src/distributor
ADD subscriber /usr/src/subscriber

RUN ballerina build pubhub --eclk.hub.db.url=jdbc:mysql://$DB_URL --eclk.hub.db.username=$DB_UN --eclk.hub.db.password=$DB_PW --eclk.hub.db.useSsl=$DB_USE_SSL --eclk.hub.db.encryptionkey=$DB_ENCRYPTION_KEY

CMD ballerina run target/bin/pubhub.jar --eclk.hub.db.url=jdbc:mysql://$DB_URL --eclk.hub.db.username=$DB_UN --eclk.hub.db.password=$DB_PW --eclk.hub.db.useSsl=$DB_USE_SSL --eclk.hub.db.encryptionkey=$DB_ENCRYPTION_KEY