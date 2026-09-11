# Ağsız Makinede Kurulum — Adım Adım

İnternet erişimi olmayan hedef makinede projeyi ayağa kaldırmak için bu adımları
sırayla takip edin. Ayrıntılı arka plan, tüm bağımlılıklar ve paketin nasıl
üretildiği için
[DataProcessingManagement/docs/air_gapped_deployment.md](DataProcessingManagement/docs/air_gapped_deployment.md)
dosyasına bakın; bu dosya sadece **çalıştırılacak adımların** özetidir.

İnternet erişimi **olan** bir makinede kurulum yapıyorsanız bu dosyayı değil,
[KURULUM_STANDART.md](KURULUM_STANDART.md) dosyasını kullanın (daha basittir).

## Ön gereksinimler

| Gereksinim | Not |
|---|---|
| **Docker Desktop** | İnternetli bir makinede önceden kurulmuş/hazırlanmış olmalı — air-gapped makinede internetten indirilemez. Kurulumda **WSL2 / Linux container** modu seçili olmalı. |
| **~15 GB boş disk** | `airgap-bundle` (~12 GB) + parçalar birleştirildikten sonra oluşan tam dosyalar + container volume'ları için. |
| **Bu repo'nun tamamı** | `~12 GB` (kod + air-gapped kurulum paketi) hedef makineye kopyalanmış olmalı (USB/harici disk vb. ile — internet üzerinden değil). |

Docker Desktop ayarlarından "Check for updates" ve "Send usage statistics"
kapatın, oturum açmadan ("skip sign-in") kullanın.

> Bu repo iki bölümden oluşur: [DataProcessingManagement/](DataProcessingManagement/)
> (uygulama kaynak kodu — git repo olarak kalmalı, bkz. adım 2) ve
> [airgap-bundle/](airgap-bundle/) (internet gerektirmeyen kurulum paketi:
> docker image'ları, Ollama modeli, opsiyonel Python/JDK runtime'ları).
> GitHub'ın 100 MB dosya sınırı nedeniyle `airgap-bundle/` içindeki 4 büyük
> dosya (`images/dpm-images.tar`, ollama model blob'u, `pyspark` wheel'i, JDK
> zip'i) `.partNNNN` parçalarına bölünmüş halde tutulur — adım 1 bunları
> yeniden birleştirir.

---

## [ ] 1) Parçaları birleştir ve bütünlüğü doğrula

```powershell
cd airgap-bundle
.\scripts\Reassemble-Bundle.ps1
```
Bölünmüş her dosyayı (`images\dpm-images.tar`, ollama model blob'u,
`wheelhouse\pyspark-4.1.1.tar.gz`, `jdk\...zip`) diskte yeniden birleştirir ve
SHA256'sını `SHA256SUMS.txt` ile karşılaştırır. Hepsi `OK` çıkmalı; `HATA`
çıkarsa transfer sırasında bozulma olmuştur, ilgili `airgap-bundle` klasörünü
yeniden kopyalayın. Disk yeri kazanmak için `-DeleteParts` ile parçalar
silinebilir (birleştirilmiş dosya doğrulandıktan sonra).

## [ ] 2) Repo hazır — sadece kontrol edin

`DataProcessingManagement/` bu repo içinde zaten bir alt klasör olarak
bulunuyor, ayrıca açmaya gerek yok:
```powershell
cd ..\DataProcessingManagement
git status
```
`git status` bazı dosyaları "değişmiş" gösterirse normaldir (air-gapped
hazırlığı sırasında yapılan düzenlemeler). **Bu klasör bir git deposu olarak
kalmalı** — `dagster/postgres_catalog.py` pipeline kimliğini git'ten okur,
bulamazsa run hata ile durur.

## [ ] 3) Docker image'larını yükle

```powershell
docker load -i ..\airgap-bundle\images\dpm-images.tar
docker images
```
7 satır beklenir: `postgres:16`, `clickhouse/clickhouse-server:25.8`,
`minio/minio:RELEASE.2025-09-07T16-13-09Z`, `ollama/ollama:latest`,
`dpm-minio-local:latest`, `dagster-local:latest`, `dpm-dashboard-local:latest`.
İnternet gerektirmez; sadece diskten yükler (birkaç dakika, ~6.5 GB).

## [ ] 4) (Opsiyonel) Eski veriyi geri yükle

Yalnızca `airgap-bundle\volumes\*.tgz` dosyaları hazırlandıysa gereklidir:
```powershell
foreach ($v in "dpm_postgres_data","dpm_clickhouse_data","dpm_minio_data","dpm_dvc_cache") {
  docker volume create $v | Out-Null
  docker run --rm -v ${v}:/v -v ${PWD}\..\airgap-bundle\volumes:/b busybox tar xzf /b/$v.tgz -C /v
}
```
Atlanırsa stack boş başlar — `auair_generator.py` ile pipeline sıfırdan veri üretir.

## [ ] 5) Ollama modelini volume'a yükle — **stack'ten ÖNCE**

```powershell
docker volume create dpm_ollama_data | Out-Null

docker run --rm --entrypoint sh `
  -v dpm_ollama_data:/root/.ollama `
  -v ${PWD}\..\airgap-bundle\ollama\models:/src:ro `
  ollama/ollama:latest `
  -c "mkdir -p /root/.ollama/models && cp -r /src/. /root/.ollama/models/ && ls /root/.ollama/models"
```
Son satırda `blobs` ve `manifests` klasörlerinin listelenmesi kopyanın
başarılı olduğunu gösterir.

## [ ] 6) Stack'i başlat

```powershell
docker compose up -d --no-build
docker compose ps
```
`--no-build`, image'ları yeniden derlemeye (internete) çıkmayı engeller.
Birkaç saniye sonra 6 servis (`minio`, `postgres`, `clickhouse`, `dagster`,
`dashboard`, `ollama`) `running`/`healthy` olmalı.

> **"ports are not available" hatası alırsanız:** host'ta `11434` portu
> zaten kullanımda demektir (ör. o makinede native Ollama kuruluysa).
> `ollama` servisinin host portu `11435`'tir (container-içi `dashboard↔ollama`
> iletişimini etkilemez) — yine de çakışırsa
> `$env:OLLAMA_HOST_PORT="11436"; docker compose up -d --no-build` ile farklı
> bir host portu verin. Hata sonrası bazı servisler (özellikle `ollama`'ya
> bağımlı `dagster`/`dashboard`) başlamamış olabilir; `docker compose ps` ile
> kontrol edip aynı `docker compose up -d --no-build` komutunu tekrar
> çalıştırmak yeterlidir (zaten çalışanlara dokunmaz, eksikleri tamamlar).

## [ ] 7) Erişim adresleri

| Servis | Adres |
|---|---|
| MinIO Console | http://localhost:9001 (minioadmin / minioadmin123) |
| Dagster UI | http://localhost:3000 |
| Dashboard | http://localhost:8501 |
| ClickHouse | http://localhost:8123/ping |
| Ollama (host'tan debug) | http://localhost:11435 (container-içi `:11434`) |

## [ ] 8) Doğrulama

```powershell
docker compose exec ollama ollama list
# qwen3.5:4b listelenmeli

curl http://localhost:8123/ping
# "Ok." dönmeli

docker compose exec dagster python /workspace/scripts/auair_generator.py --rows 5000 --cols 200 --chunk-size 100
```
Son komut MinIO'ya sentetik bir `.tab` yükler; Dagster sensörü yakalayıp
`staged_auair_to_published_job`'ı tetikler. Dagster UI'dan (`:3000`) run'ı
izleyin — 5 asset SUCCESS olunca ClickHouse `auair_telemetry_committed`
view'ında satırlar, Postgres `pipeline_catalog.pipeline_job_runs`'da SUCCESS
kaydı görülür.

---

## Durdurma ve kaldırma

### Sadece durdur (veriler korunur)
```powershell
docker compose stop
```

### Container'ları kaldır, veriyi koru
```powershell
docker compose down
```
Adlandırılmış volume'lar (`dpm_postgres_data`, `dpm_clickhouse_data`,
`dpm_minio_data`, `dpm_ollama_data`, `dpm_dvc_cache`, `dpm_dagster_home`)
korunur; `docker compose up -d --no-build` ile veriler yerinde tekrar başlar.

### Her şeyi tamamen kaldır (veri dahil)
```powershell
docker compose down -v
docker rmi dpm-minio-local dpm-dashboard-local dagster-local `
  postgres:16 clickhouse/clickhouse-server:25.8 `
  minio/minio:RELEASE.2025-09-07T16-13-09Z ollama/ollama:latest
```
`-v` bayrağı adlandırılmış volume'ları da siler — **tüm Postgres/ClickHouse/
MinIO/Ollama verisi kalıcı olarak kaybolur**. İkinci komut `docker load` ile
yüklenen 7 image'ın tamamını diskten siler (~6.5 GB geri kazanılır).

Disk yerini tamamen geri almak için birleştirilmiş büyük dosyaları da silip
sadece `.partNNNN` parçalarını bırakabilirsiniz (tekrar kuruluma gerek
kalırsa `Reassemble-Bundle.ps1` yeniden birleştirir):
```powershell
cd airgap-bundle
Remove-Item images\dpm-images.tar, jdk\OpenJDK17U-jdk_x64_windows_hotspot.zip, `
  wheelhouse\pyspark-4.1.1.tar.gz, ollama\models\blobs\sha256-81fb60c7daa80fc1123380b98970b320ae233409f0f71a72ed7b9b0d62f40490 `
  -ErrorAction SilentlyContinue
```

Docker Desktop'ın kendisini kaldırmak için Windows "Uygulamayı Kaldır" /
"Add or Remove Programs" menüsünü kullanın.

---

## Bilinen kısıtlar

- **Harita sekmesi** (folium/streamlit-folium): dış tile servisine bağlı
  olduğu için internetsiz ortamda boş/eksik görünebilir.
- **Ollama container'ı**: GPU passthrough yapılmadıysa CPU'da çalışır —
  yanıtlar yavaş olabilir ama işlevseldir.

Ayrıntılar, tüm bağımlılık envanteri ve paketin (Bölüm A) nasıl üretildiği
için: [DataProcessingManagement/docs/air_gapped_deployment.md](DataProcessingManagement/docs/air_gapped_deployment.md).
