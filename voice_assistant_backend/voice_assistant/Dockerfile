# Stage 1: Build the application
FROM maven:3.8.5-openjdk-17 AS build
COPY . .
RUN mvn clean package -DskipTests

# Stage 2: Run the application
FROM eclipse-temurin:17-jdk-alpine
# This line looks for the jar inside the target folder created during build
COPY --from=build /target/*.jar app.jar
ENTRYPOINT ["java","-jar","/app.jar"]