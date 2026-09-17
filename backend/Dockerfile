FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

# AI modernization: copy project files first so dotnet restore layer is cached independently of source changes
COPY TickifyBackendOnly.sln .
COPY Tickify.csproj .

RUN dotnet restore TickifyBackendOnly.sln

COPY . .

RUN dotnet publish TickifyBackendOnly.sln -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final

WORKDIR /app

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080

EXPOSE 8080

# AI modernization: run as non-root — required for EKS security policies and container best practices
USER app

ENTRYPOINT ["dotnet", "Tickify.dll"]