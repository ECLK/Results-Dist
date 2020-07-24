FROM openjdk:8 AS build
RUN wget https://dist.ballerina.io/downloads/1.2.4/ballerina-linux-installer-x64-1.2.4.deb
RUN dpkg -i ballerina-linux-installer-x64-1.2.4.deb
WORKDIR /usr/src/

ENV TZ=Asia/Colombo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ADD . /usr/src/

RUN ballerina build --skip-tests distributor

FROM openjdk:8

ENV TZ=Asia/Colombo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

COPY  --from=build /usr/src/target /usr/src/target
WORKDIR /usr/src/

CMD java -jar target/bin/distributor.jar --eclk.hub.db.url=jdbc:mysql://$DB_URL --eclk.hub.db.username=$DB_UN --eclk.hub.db.password=$DB_PW --eclk.hub.db.useSsl=$DB_USE_SSL --eclk.hub.db.encryptionkey=$DB_ENCRYPTION_KEY --eclk.govsms.username=$SMS_USER  --eclk.govsms.password=$SMS_PASSWORD --eclk.govsms.source=$SMS_SOURCE
