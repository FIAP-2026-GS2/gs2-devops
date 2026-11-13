# Imagem da API SampaTech (.NET 8).
# Contexto do build: a pasta gs2-dotnet/. Na raiz do repositório:
#   docker build -f dockerfiles/Dockerfile -t sampatech-api gs2-dotnet
# O .dockerignore deste build é o Dockerfile.dockerignore, ao lado deste arquivo.

# ---------- Etapa 1: compilar e publicar (imagem com o SDK) ----------
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Primeiro só os .csproj: o restore fica em cache enquanto as dependências não mudam.
COPY global.json SampaTech.sln ./
COPY src/SampaTech.Domain/SampaTech.Domain.csproj src/SampaTech.Domain/
COPY src/SampaTech.Application/SampaTech.Application.csproj src/SampaTech.Application/
COPY src/SampaTech.Infrastructure/SampaTech.Infrastructure.csproj src/SampaTech.Infrastructure/
COPY src/SampaTech.Api/SampaTech.Api.csproj src/SampaTech.Api/
RUN dotnet restore src/SampaTech.Api/SampaTech.Api.csproj

# Depois o código. Os testes não entram na imagem: eles rodam no CI, antes do build dela.
COPY src/ src/
RUN dotnet publish src/SampaTech.Api/SampaTech.Api.csproj -c Release -o /app/publish \
    --no-restore /p:UseAppHost=false

# ---------- Etapa 2: rodar (imagem só com o runtime) ----------
# A aspnet:8.0 padrão (Debian) já tem os fusos horários e o ICU que a API usa
# (America/Sao_Paulo e cultura pt-BR). As variantes chiseled e Alpine não têm.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8080

COPY --from=build /app/publish .

# Usuário sem privilégio de root, que a imagem oficial já traz (UID 1654).
USER $APP_UID

ENTRYPOINT ["dotnet", "SampaTech.Api.dll"]
