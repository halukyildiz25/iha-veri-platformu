# Standart (İnternetli) Kurulum — Adım Adım

Bu doküman, **internet erişimi olan** bir Windows makinesinde projeyi sıfırdan
ayağa kaldırmak için gereken her şeyi anlatır. Projeyi hiç tanımayan biri için
yazılmıştır; sırayla uygulamanız yeterlidir.

İnternet erişimi **olmayan** bir makinede kurulum yapacaksanız bu dosyayı
değil, [KURULUM_AIRGAP.md](KURULUM_AIRGAP.md) dosyasını kullanın.

---

## Ön gereksinimler

| Gereksinim | Not |
|---|---|
| **Docker Desktop** | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) üzerinden kurun. Kurulumda **WSL2 / Linux container** modu seçili olmalı (Windows container modu değil). |
| **~10 GB boş disk** | Docker image'ları + container verisi (volume'lar) için. |
| **İnternet bağlantısı** | Docker image'larını indirmek/derlemek ve Ollama LLM modelini çekmek için gerekir (sadece ilk kurulumda). |
| **Git** (opsiyonel) | Repoyu klonlamak için; zaten elinizdeyse gerekmez. |

Docker Desktop'ı kurduktan sonra açın ve sistem tepsisindeki simgenin
"Docker Desktop is running" durumuna geldiğinden emin olun — sonraki adımlar
Docker çalışmıyorsa başarısız olur.

---

## [ ] 1) Repoyu edinin

Zaten bu repo elinizdeyse bu adımı atlayın. Değilse:
```powershell
git clone <repo-url> iha-veri-platformu
cd iha-veri-platformu
```

## [ ] 2) Uygulama dizinine geçin

Docker Compose dosyası `DataProcessingManagement/` içindedir:
```powershell
cd DataProcessingManagement
```
Bundan sonraki tüm komutlar bu dizinde çalıştırılır.

## [ ] 3) Servisleri derleyip başlatın

```powershell
docker compose up -d --build
```
İlk çalıştırmada bu komut:
- `postgres`, `clickhouse`, `ollama` image'larını internetten indirir,
- `minio`, `dagster`, `dashboard` image'larını bu repodaki Dockerfile'lardan
  yerel olarak derler (birkaç dakika sürebilir).

Bittiğinde durumu kontrol edin:
```powershell
docker compose ps
```
6 servis (`minio`, `postgres`, `clickhouse`, `dagster`, `dashboard`,
`ollama`) `running` / `healthy` görünmelidir.

## [ ] 4) Ollama LLM modelini indirin

Ollama container'ı boş başlar; dashboard'un "Doğal Dil Filtre" özelliği için
model bir kez indirilmelidir (internet gerekir, ~3 GB):
```powershell
docker compose exec ollama ollama pull qwen3.5:4b
docker compose exec ollama ollama list
# çıktıda "qwen3.5:4b" görünmeli
```
Bu adım atlanırsa geri kalan her şey çalışır, yalnız dashboard'daki LLM
sekmesi "model bulunamadı" hatası verir.

## [ ] 5) Erişim adresleri

| Servis | Adres |
|---|---|
| Dashboard (Streamlit) | http://localhost:8501 |
| Dagster UI | http://localhost:3000 |
| MinIO Console | http://localhost:9001 (minioadmin / minioadmin123) |
| ClickHouse | http://localhost:8123/ping |
| Postgres | `localhost:5432` (postgres / HalukPG123!) |
| Ollama (host'tan debug) | http://localhost:11435 (container-içi `:11434`) |

> Tüm varsayılan kullanıcı adı/şifreler `docker-compose.yml` içinde tanımlıdır
> ve ortam değişkenleriyle (`${MINIO_ROOT_PASSWORD}` vb.) değiştirilebilir —
> bunlar yalnızca yerel geliştirme içindir, üretimde kullanılmamalıdır.

## [ ] 6) Doğrulama

```powershell
curl http://localhost:8123/ping
# "Ok." dönmeli

docker compose exec dagster python /workspace/scripts/auair_generator.py --rows 5000 --cols 200 --chunk-size 100
```
Son komut MinIO'ya sentetik bir `.tab` dosyası yükler; Dagster sensörü
bunu yakalayıp `staged_auair_to_published_job` pipeline'ını otomatik
tetikler. Dagster UI'dan (`:3000`) run'ı izleyin — 5 asset `SUCCESS`
olduğunda dashboard'da (`:8501`) veri görünür hale gelir.

---

## Durdurma ve kaldırma

Servisleri durdurmanın/kaldırmanın üç seviyesi vardır; ihtiyacınıza göre seçin.

### Sadece durdur (veriler korunur)
```powershell
docker compose stop
```
Container'lar durur ama silinmez; `docker compose start` ile aynı veriyle
tekrar başlatılabilir.

### Container'ları kaldır, veriyi koru
```powershell
docker compose down
```
Container'lar silinir, adlandırılmış volume'lar (`dpm_postgres_data`,
`dpm_clickhouse_data`, `dpm_minio_data`, `dpm_ollama_data`, `dpm_dvc_cache`,
`dpm_dagster_home`) **korunur**. `docker compose up -d` ile veriler yerinde
şekilde tekrar başlar.

### Her şeyi tamamen kaldır (veri dahil)
```powershell
docker compose down -v
docker rmi dpm-minio-local dpm-dashboard-local dagster-local
```
`-v` bayrağı yukarıdaki adlandırılmış volume'ları da siler — **tüm
Postgres/ClickHouse/MinIO/Ollama verisi kalıcı olarak kaybolur**. İkinci
komut bu repodan yerel olarak derlenen 3 image'ı diskten siler
(`postgres`, `clickhouse/clickhouse-server`, `ollama/ollama` internetten
çekilen image'lar olduğu için ayrıca `docker rmi postgres:16
clickhouse/clickhouse-server:25.8 ollama/ollama:latest` ile silinebilir).

Docker Desktop'ın kendisini kaldırmak için Windows "Uygulamayı Kaldır" /
"Add or Remove Programs" menüsünü kullanın.

---

## Sorun giderme

- **"ports are not available" / `11434` hatası:** Host'ta native Ollama
  kuruluysa `11434` portu dolu olabilir. `ollama` servisinin host portu
  zaten `11435`'tir; yine de çakışırsa
  `$env:OLLAMA_HOST_PORT="11436"; docker compose up -d` ile farklı bir
  host portu verin.
- **`docker compose up` internet olmadan başarısız oluyor:** Bu doküman
  internetli kurulum içindir. İnternetsiz makinede
  [KURULUM_AIRGAP.md](KURULUM_AIRGAP.md) kullanın.
- **Bir servis `unhealthy` kalıyor:** `docker compose logs <servis-adı>`
  ile loglara bakın (`docker compose logs postgres` gibi).
