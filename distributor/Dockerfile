FROM openjdk:8
RUN wget https://product-dist.ballerina.io/downloads/1.0.3/ballerina-linux-installer-x64-1.0.3.deb
RUN dpkg -i ballerina-linux-installer-x64-1.0.3.deb
WORKDIR /usr/src/

ADD . /usr/src/

RUN ballerina build --skip-tests distributor

CMD ballerina run target/bin/distributor.jar --eclk.hub.db.url=jdbc:mysql://$DB_URL --eclk.hub.db.username=$DB_UN --eclk.hub.db.password=$DB_PW --eclk.hub.db.useSsl=$DB_USE_SSL --eclk.hub.db.encryptionkey=$DB_ENCRYPTION_KEY --eclk.sms.twilio.accountSid=$TWILIO_SID --eclk.sms.twilio.authToken=$TWILIO_AUTHTOKEN --eclk.sms.twilio.source=$TWILIO_SOURCE