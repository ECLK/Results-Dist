FROM openjdk:8
RUN wget https://product-dist.ballerina.io/downloads/1.0.1/ballerina-linux-installer-x64-1.0.1.deb
RUN dpkg -i ballerina-linux-installer-x64-1.0.1.deb
WORKDIR /usr/src/
ADD . /usr/src/

RUN ballerina build --skip-tests -a

CMD ballerina run target/bin/resultpubexposer.jar