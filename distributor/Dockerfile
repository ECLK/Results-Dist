FROM openjdk:8 as ballerina_builder
RUN wget https://product-dist.ballerina.io/downloads/1.0.1/ballerina-linux-installer-x64-1.0.1.deb
RUN dpkg -i ballerina-linux-installer-x64-1.0.1.deb
WORKDIR /usr/src/
ADD deployment-utils/ /usr/lib/ballerina/ballerina-1.0.1/distributions/jballerina-1.0.1/
ADD . /usr/src/

RUN ballerina build --skip-tests distributor

FROM openjdk:8-jre-alpine
WORKDIR /usr/src/
COPY --from=ballerina_builder /usr/src/target/bin/distributor.jar .

CMD java -jar distributor.jar --eclk.hub.db.url=jdbc:mysql://$DB_URL --eclk.hub.db.username=$DB_UN --eclk.hub.db.password=$DB_PW --eclk.hub.db.useSsl=$DB_USE_SSL --eclk.hub.db.encryptionkey=$DB_ENCRYPTION_KEY
