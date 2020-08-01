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
ADD ./web web

CMD java -jar target/bin/distributor.jar --eclk.distributor.db.url=jdbc:mysql://$DB_URL --eclk.distributor.db.username=$DB_UN --eclk.distributor.db.password=$DB_PW --eclk.distributor.db.useSsl=$DB_USE_SSL --eclk.distributor.w1=$W1 --eclk.distributor.w2=$W2 --eclk.distributor.w3=$W3 --eclk.distributor.w4=$W4 --eclk.distributor.w5=$W5 --eclk.govsms.username=$SMS_USER  --eclk.govsms.password=$SMS_PASSWORD --eclk.govsms.source=$SMS_SOURCE
