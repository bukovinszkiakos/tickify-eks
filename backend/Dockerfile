FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

COPY TickifyBackendOnly.sln .
COPY Tickify.csproj .

RUN dotnet restore Tickify.csproj

COPY . .

RUN dotnet publish Tickify.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final

WORKDIR /app

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080

EXPOSE 8080

USER app

ENTRYPOINT ["dotnet", "Tickify.dll"]