###################################################
FROM  maven:3.6.1 as target

WORKDIR /build

COPY loyalty-service/pom.xml .

RUN mvn dependency:go-offline

ADD   loyalty-service /build/

RUN unset MAVEN_CONFIG &&  chmod 775 mvnw \
&& ./mvnw clean verify

###################################################
FROM openjdk:8-jre-alpine

#COPY healthcheck /healthcheck

COPY --from=target  /build/target/*.jar /app/app.jar

#RUN chmod +x /app/app.jar /healthcheck

CMD java -Djava.security.egd=file:/staging/./urandom -jar /app/app.jar

RUN apk add curl
