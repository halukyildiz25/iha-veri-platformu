# Air-Gapped (İnternetsiz) Kurulum ve Çalıştırma

Bu doküman, projeyi **internet erişimi olmayan** bir Windows 11 + Docker Desktop
makinesinde kurup çalıştırmak için gereken her şeyi anlatır.

İki bölüm var:
- **Bölüm A — Hazırlık makinesinde** (internet VAR): transfer paketinin üretimi.
- **Bölüm B — Air-gapped makinede** (internet YOK): kurulum, çalıştırma, doğrulama.

> Yardımcı betikler: `scripts/airgap_download_wheels.sh` (wheelhouse),
> `scripts/airgap_export_ollama_model.sh` (model export). Aşağıda tüm komutlar
> tek tek verilmiştir.

> **Repo yapısı notu:** Bu proje artık `iha-veri-platformu` reposunun bir alt
> klasörüdür ve `airgap-bundle/` ile aynı repoda kardeş klasör olarak durur
> (`iha-veri-platformu/DataProcessingManagement/`, `iha-veri-platformu/airgap-bundle/`).
> Aşağıdaki **Bölüm A** (hazırlık makinesi) `D:\airgap-bundle`, `D:\dpm\...` gibi
> mutlak yollar üretim anına ait tarihsel kayıttır, değiştirilmedi. **Bölüm B**
> (air-gapped makine) adımları güncel repo yapısına göre göreli yollarla
> yazılmıştır. Ayrıca GitHub'ın 100 MB dosya sınırı nedeniyle `airgap-bundle/`
> içindeki 4 büyük dosya `.partNNNN` parçalarına bölünmüştür — Bölüm B'ye
> başlamadan önce kısa özet için repo kökündeki
> [KURULUM_AIRGAP.md](../../KURULUM_AIRGAP.md) adım 1'i (`Reassemble-Bundle.ps1`)
> çalıştırın.

---

## Yapılan repo değişiklikleri (air-gapped hardening)

| Dosya | Değişiklik | Neden |
|---|---|---|
| `minio/Dockerfile` | `FROM minio/minio:latest` → `RELEASE.2025-09-07T16-13-09Z` | Hazırlık ve hedef aynı MinIO sürümünü alsın |
| `dagster/dagster.yaml` | `telemetry: { enabled: false }` | telemetry.dagster.io'ya giden bağlantı internetsiz makinede takılır |
| `docker-compose.yml` (dagster) | `GX_ANALYTICS_ENABLED: "false"` | Great Expectations 1.x PostHog analytics'i kapatır |
| `docker-compose.yml` (dagster) | `./dagster/dagster.yaml:/app/dagster/dagster.yaml:ro` mount | Telemetry-kapalı yaml'ı image'ı yeniden build etmeden uygular |
| `docker-compose.yml` (dashboard) | `STREAMLIT_BROWSER_GATHER_USAGE_STATS: "false"` | Streamlit kullanım istatistiği/sürüm kontrolünü kapatır |
| `docker-compose.yml` (yeni `ollama` servisi) | `ollama/ollama:latest` container'ı + `dpm_ollama_data` volume + `:11434` | Ollama host'a kurulmuyor; LLM özelliği container'da çalışır |
| `docker-compose.yml` (dashboard) | `OLLAMA_HOST` default `http://host.docker.internal:11434` → `http://ollama:11434` | Dashboard artık container'daki Ollama'ya bağlanır |
| `docker-compose.yml` (build + ollama servisleri) | `pull_policy: never` | Kazara registry pull denemesini engeller |
| `dagster/requirements.lock.txt` (yeni) | Çalışan image'dan `pip freeze` | Birebir sürüm kaydı (ileride yeniden build için) |
| `dashboard/requirements.lock.txt` (yeni) | Çalışan image'dan `pip freeze` | Aynı |

DVC analytics zaten kapalı (`.dvc/config` → `analytics = false`).

---

## Bölüm A — Hazırlık makinesinde transfer paketi üretimi

Çıktı: `D:\airgap-bundle\`. Toplam ~11–13 GB (images tar ~5 GB + ollama modeli
~3.2 GB + opsiyonel wheelhouse/JDK/Python ~0.5 GB + repo ~25 MB).

### A.1 Docker image'larını kaydet

Repo'daki 3 image zaten build'li olmalı (`docker images` ile kontrol edin); değilse:
```powershell
docker compose build          # dpm-minio-local, dagster-local, dpm-dashboard-local
docker pull postgres:16
docker pull clickhouse/clickhouse-server:25.8
docker pull minio/minio:RELEASE.2025-09-07T16-13-09Z
docker pull ollama/ollama:latest
```

Hepsini tek tar'a:
```powershell
docker save `
  postgres:16 `
  clickhouse/clickhouse-server:25.8 `
  minio/minio:RELEASE.2025-09-07T16-13-09Z `
  ollama/ollama:latest `
  dpm-minio-local:latest `
  dagster-local:latest `
  dpm-dashboard-local:latest `
  -o D:\airgap-bundle\images\dpm-images.tar
```
> Docker 29 image store zstd sıkıştırdığı için tar ~5 GB çıkar (image'ların
> `docker images` SIZE toplamı çok daha büyük görünür — paylaşılan katmanlar
> tek sefer yazılır, katmanlar sıkıştırılır).

### A.2 Sürüm kilidi (image'lardan)
```powershell
docker run --rm --entrypoint sh dagster-local:latest        -c "pip freeze" > dagster\requirements.lock.txt
docker run --rm --entrypoint sh dpm-dashboard-local:latest  -c "pip freeze" > dashboard\requirements.lock.txt
```

### A.3 Host `.venv` için wheelhouse

Mevcut çalışan `.venv` (uv, Python 3.12) tam kapanışı:
```powershell
$env:VIRTUAL_ENV="D:\Haluk Yıldız\DataProcessingManagement\.venv"
uv pip freeze > D:\airgap-bundle\wheelhouse\venv-freeze.txt
```
uv'de `pip download` yok; pip'li geçici bir venv ile paket paket indir
(`scripts/airgap_download_wheels.sh` veya elle):
```powershell
"<uv-python-3.12>\python.exe" -m venv D:\tmp\pipenv
D:\tmp\pipenv\Scripts\python -m pip download --no-deps --prefer-binary `
  --retries 3 --timeout 30 -r D:\airgap-bundle\wheelhouse\venv-freeze.txt `
  -d D:\airgap-bundle\wheelhouse
# + build backend'leri:
D:\tmp\pipenv\Scripts\python -m pip download --prefer-binary `
  pip setuptools wheel hatchling flit-core poetry-core hatch-vcs setuptools-scm `
  -d D:\airgap-bundle\wheelhouse
```
> `--no-deps` kullanılıyor çünkü `venv-freeze.txt` zaten tam transitif kapanış.
> Windows schannel "revocation offline" hatası verirse `curl`'de `--ssl-no-revoke`,
> pip'te sorun olmaz (kendi CA bundle'ı).

### A.4 Python 3.12 runtime + uv
```powershell
# uv'nin yönettiği Python 3.12 klasörünü kopyala:
Copy-Item "$env:APPDATA\uv\python\cpython-3.12.13-windows-x86_64-none" `
  D:\airgap-bundle\python312\ -Recurse
Copy-Item "$env:USERPROFILE\.local\bin\uv.exe" D:\airgap-bundle\tools\uv.exe
```

### A.5 JDK 17 (host Spark için — JRE 8 yetmez, `javac` gerek)
```powershell
curl -sSL --ssl-no-revoke -o D:\airgap-bundle\jdk\OpenJDK17U-jdk_x64_windows_hotspot.zip `
  "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
```

### A.6 Ollama modeli (Ollama artık container — kurulum yok)

Ollama `ollama/ollama:latest` container'ı olarak çalışacak (A.1'de save edildi).
Sadece **model dosyaları** taşınır. Bu makinede model zaten çekili
(`ollama list` → `qwen3.5:4b`); yalnız o modelin manifest'i + katman blob'ları:
```bash
bash scripts/airgap_export_ollama_model.sh qwen3.5:4b D:/airgap-bundle/ollama/models
# çıktı:
#   ollama/models/manifests/registry.ollama.ai/library/qwen3.5/4b
#   ollama/models/blobs/sha256-<config + 3 layer digest>   (~3.2 GB)
```
> `OllamaSetup.exe` **gerekmiyor** — hedefte native Ollama kurulmayacak.

### A.7 Repo
```powershell
# .git dahil, ağır/üretilen klasörler hariç working-tree kopyası:
tar -czf D:\airgap-bundle\repo\repo-worktree.tar.gz `
  --exclude=./.venv --exclude=./data --exclude=./dagster/data `
  --exclude=./local_data --exclude=./.dvc/cache `
  --exclude=./1000_10000_flight_1_2019-08-29.tab --exclude=*.parquet `
  --exclude=__pycache__ --exclude=./tmp .
```
> Phase 0 değişiklikleri commit edilmediyse working-tree kopyasında "dirty"
> olarak taşınır (pipeline çalışır; `Pipeline-Git-Dirty: true` olarak işaretlenir).
> İstenirse hedefte veya burada `git add -A && git commit` yapılabilir.

### A.8 (Opsiyonel) Mevcut veriyi taşı
Hedef "sıfırdan" başlamayacaksa, dev makinesindeki named volume'ları dışa aktar:
```powershell
foreach ($v in "dpm_postgres_data","dpm_clickhouse_data","dpm_minio_data","dpm_dvc_cache") {
  docker run --rm -v ${v}:/v -v D:\airgap-bundle\volumes:/b busybox tar czf /b/$v.tgz -C /v .
}
```
Atlanırsa stack boş başlar; `auair_generator.py` ilk `.tab`'ı üretince pipeline akar.

### A.9 Sağlama
```powershell
Get-ChildItem D:\airgap-bundle -Recurse -File |
  Get-FileHash -Algorithm SHA256 |
  ForEach-Object { "{0}  {1}" -f $_.Hash, $_.Path } |
  Out-File D:\airgap-bundle\SHA256SUMS.txt
```

**Paket içeriği:**
```
airgap-bundle/
├─ images/dpm-images.tar                       7 Docker image (ollama/ollama dahil)
├─ ollama/models/                              qwen3.5:4b (manifests/ + blobs/, ~3.2 GB)
├─ repo/repo-worktree.tar.gz                   (.git dahil)
├─ wheelhouse/*.whl + venv-freeze.txt          OPSİYONEL — host .venv bağımlılıkları
├─ python312/cpython-3.12.13-windows-x86_64-none/   OPSİYONEL
├─ tools/uv.exe                                OPSİYONEL
├─ jdk/OpenJDK17U-jdk_x64_windows_hotspot.zip  OPSİYONEL — host Spark için
├─ volumes/*.tgz                               OPSİYONEL — mevcut veri
└─ SHA256SUMS.txt
```
> `wheelhouse/`, `python312/`, `tools/`, `jdk/` yalnızca host'tan (container
> dışında) `dvc`/`dagster dev` çalıştırılacaksa gerekir. Container stack'i
> bunlar olmadan tam çalışır.

---

## Bölüm B — Air-gapped makinede kurulum

Ön koşul: Docker Desktop kurulu ve **çalışır** durumda (Linux container modu).
Docker Desktop ayarlarında "Check for updates" ve "Send usage statistics" kapatın,
oturum açmadan ("skip sign-in") kullanın.

### B.1 Repo'yu yerleştir, parçaları birleştir + sağlama
```powershell
# iha-veri-platformu reposunun tamamını (DataProcessingManagement/ + airgap-bundle/) hedef makineye kopyala
cd iha-veri-platformu\airgap-bundle
.\scripts\Reassemble-Bundle.ps1   # .partNNNN parçalarını birleştirir + SHA256SUMS.txt ile doğrular
```
> GitHub'ın 100 MB dosya sınırı nedeniyle `images/dpm-images.tar`, ollama model
> blob'u, `pyspark` wheel'i ve JDK zip'i `.partNNNN` parçalarına bölünmüş
> halde repoda durur; `Reassemble-Bundle.ps1` bunları orijinal dosyada
> birleştirip hash doğrular. Ayrıntı: repo kökündeki `KURULUM_AIRGAP.md`.

### B.2 Repo zaten hazır
```powershell
cd ..\DataProcessingManagement
git status          # Phase 0 değişiklikleri dirty görünebilir — normal
```
`DataProcessingManagement/` bu repo içinde zaten bir git deposu olarak
bulunuyor, ayrıca açmaya/tar'dan çıkarmaya gerek yok. Repo'nun bir **git
deposu** olarak kalması şart: `dagster/postgres_catalog.py` pipeline
kimliğini git'ten çözüyor, çözemezse run hata ile durur.

### B.3 Docker image'larını yükle
```powershell
docker load -i ..\airgap-bundle\images\dpm-images.tar
docker images
# Beklenen 7 satır:
#   postgres:16
#   clickhouse/clickhouse-server:25.8
#   minio/minio:RELEASE.2025-09-07T16-13-09Z
#   ollama/ollama:latest
#   dpm-minio-local:latest
#   dagster-local:latest
#   dpm-dashboard-local:latest
```

### B.4 (Opsiyonel) Mevcut veriyi geri yükle
```powershell
foreach ($v in "dpm_postgres_data","dpm_clickhouse_data","dpm_minio_data","dpm_dvc_cache") {
  docker volume create $v | Out-Null
  docker run --rm -v ${v}:/v -v ${PWD}\..\airgap-bundle\volumes:/b busybox tar xzf /b/$v.tgz -C /v
}
```
> `busybox` image'ı da air-gapped'te yoksa: bu adımı atlayın (boş başlayın) veya
> `busybox` image'ını da Bölüm A.1'deki tar'a ekleyin.

### B.5 Ollama modelini volume'a yükle (stack'ten ÖNCE)

Ollama container'ı boş `dpm_ollama_data` volume'uyla başlar ve air-gapped'te
model çekemez. Model dosyalarını volume'a bir kere elle koyun:
```powershell
docker volume create dpm_ollama_data | Out-Null
# models/ (manifests + blobs) -> volume içindeki /root/.ollama/models
docker run --rm --entrypoint sh `
  -v dpm_ollama_data:/root/.ollama `
  -v ${PWD}\..\airgap-bundle\ollama\models:/src:ro `
  ollama/ollama:latest `
  -c "mkdir -p /root/.ollama/models && cp -r /src/. /root/.ollama/models/ && ls /root/.ollama/models"
```
> `ollama/ollama` image'ının entrypoint'i `/bin/ollama` olduğu için
> `--entrypoint sh` ile ezmek gerekir.

### B.6 Stack'i başlat
```powershell
# DataProcessingManagement/ dizininde
docker compose up -d --no-build
docker compose ps
docker compose exec ollama ollama list     # "qwen3.5:4b" görünmeli
```
İlk açılışta:
- Postgres, `docs/postgres_pipeline_catalog_schema.sql`'i uygular (yalnız volume boşsa).
- ClickHouse, `clickhouse/config.d` + `users.d` bellek XML'lerini yükler.
- MinIO bucket'ları uygulama kodu tarafından ilk ihtiyaçta otomatik yaratılır.
- Dashboard, `OLLAMA_HOST=http://ollama:11434` ile container'daki Ollama'ya bağlanır.

Servisler ve portlar (hepsi `127.0.0.1`):
| Servis | URL |
|---|---|
| MinIO API / Console | `:9000` / `:9001` (minioadmin / minioadmin123) |
| Postgres | `:5432` (postgres / HalukPG123!) |
| ClickHouse HTTP / native | `:8123` / `:9002` (default / clickhouse123) |
| Dagster UI | `:3000` |
| Dashboard (Streamlit) | `:8501` |
| Ollama (host'tan debug) | `:11435` (container-içi hâlâ `:11434`) |

> **Port çakışması:** Hedef makinede host'a native Ollama kuruluysa (ör. bu
> repoyu geliştiren makine) `11434` portu zaten dolu olabilir; compose bu
> yüzden host tarafında `11435` kullanır (`OLLAMA_HOST_PORT` ile değiştirilebilir).
> Container-içi iletişim (dashboard→ollama) `http://ollama:11434` üzerinden
> gittiği için bu değişiklik dashboard'u etkilemez, sadece host'tan
> `curl http://localhost:11435/...` ile debug erişimini değiştirir. "ports are
> not available" hatası alırsanız `.env`'de veya kabukta
> `$env:OLLAMA_HOST_PORT="11436"` gibi farklı bir host portu verin.
>
> **GPU:** Docker Desktop'ta `ollama` container'ı varsayılan olarak **CPU**
> çalışır. `qwen3.5:4b` CPU'da çalışır ama yavaştır. NVIDIA GPU passthrough
> yapılacaksa compose'daki `ollama` servisine `deploy.resources.reservations.devices`
> (veya `gpus: all`) eklenir ve Docker Desktop'ta WSL2 GPU desteği açık olmalıdır.

### B.7 Host `.venv` (OPSİYONEL — Dagster'ı/DVC'yi host'tan çalıştıracaksanız)

Container'lı stack bu adım olmadan da çalışır. Host `.venv` yalnızca
`dvc` komutlarını veya `dagster dev`'i host'tan koşmak içindir.

```powershell
# 1) Python 3.12'yi uv'nin beklediği yola koy: (airgap-bundle/ ile kardeş DataProcessingManagement/ içinden)
robocopy ..\airgap-bundle\python312\cpython-3.12.13-windows-x86_64-none `
  "$env:APPDATA\uv\python\cpython-3.12.13-windows-x86_64-none" /E
# junction (uv bunu arar):
cmd /c mklink /J "$env:APPDATA\uv\python\cpython-3.12-windows-x86_64-none" `
  "$env:APPDATA\uv\python\cpython-3.12.13-windows-x86_64-none"
Copy-Item ..\airgap-bundle\tools\uv.exe "$env:USERPROFILE\.local\bin\uv.exe"

# 2) JDK 17:
Expand-Archive ..\airgap-bundle\jdk\OpenJDK17U-jdk_x64_windows_hotspot.zip C:\tools\
#   → C:\tools\jdk-17.0.x+y
setx JAVA_HOME "C:\tools\jdk-17.0.x+y"
setx PATH "$env:PATH;C:\tools\jdk-17.0.x+y\bin"
#   yeni terminal: `javac -version` çalışmalı (Spark adapter derlemesi için şart)

# 3) venv + bağımlılıklar (offline, DataProcessingManagement/ dizininde):
"$env:APPDATA\uv\python\cpython-3.12.13-windows-x86_64-none\python.exe" -m venv .venv
# pip'siz uv venv yerine stdlib venv (pip'li) kullanmak offline kurulumu kolaylaştırır:
.venv\Scripts\python -m pip install --no-index --find-links ..\airgap-bundle\wheelhouse `
  -r ..\airgap-bundle\wheelhouse\venv-freeze.txt
#   (pip yoksa: `python -m ensurepip` ya da wheelhouse'taki pip whl'i --target ile)

# 4) doğrula:
.venv\Scripts\python -c "import pyspark, great_expectations, dvc, zstandard; print('py ok')"
.venv\Scripts\python -c "import subprocess; subprocess.run(['javac','-version'], check=True)"
```

> `dvc repro` çalıştırmak istenirse: DVC verisi (`data/`) pakete dahil değil;
> önce MinIO `dvc-cache` bucket'ı geri yüklenip `dvc pull` yapılmalı.

---

## Bölüm C — Uçtan uca doğrulama

| # | Komut / kontrol | Beklenen |
|---|---|---|
| 1 | `docker compose ps` | 6 servis `running` / `healthy` (minio, postgres, clickhouse, dagster, dashboard, ollama) |
| 2 | tarayıcı `http://localhost:9001` | MinIO console login |
| 3 | `http://localhost:3000` | Dagster UI, kod konumu yüklü, 4 sensör RUNNING |
| 4 | `curl http://localhost:8123/ping` | `Ok.` |
| 5 | `docker compose exec ollama ollama list` | `qwen3.5:4b` listeleniyor |
| 6 | `http://localhost:8501` | Dashboard açılıyor, sekmeler hata vermiyor |
| 7 | `docker compose exec dagster python /workspace/scripts/auair_generator.py --rows 5000 --cols 200 --chunk-size 100` | MinIO `data-raw/auair-tab/inbox/` altına `.tab` yüklenir |
| 8 | Dagster UI | `staged_auair_to_published_job` otomatik başlar → 5 asset SUCCESS |
| 9 | ClickHouse | `auair_telemetry_committed` view'ında satırlar |
| 10 | MinIO | `pipeline-artifacts` altında GE raporu, `dvc-cache`'te DVC objesi |
| 11 | Postgres | `pipeline_catalog.pipeline_job_runs` → SUCCESS |
| 12 | Dashboard "Doğal Dil Filtre" | container `ollama`'ya istek gidiyor, filtre üretiliyor (CPU'da yavaş olabilir) |
| 13 | Dashboard harita sekmesi | ⚠ tile'lar yüklenmeyebilir (aşağı bkz.) |
| 14 | Host firewall/log | Giden internet bağlantı denemesi yok |

---

## Bilinen kısıtlar

1. **Harita (folium / streamlit-folium):** Leaflet JS/CSS ve OpenStreetMap tile'ları
   tarayıcıda CDN'den çekilir. İnternetsiz makinede harita sekmesi taban katman
   olmadan/boş açılır. Kalan dashboard etkilenmez. Çözüm istenirse: Leaflet
   asset'lerini Streamlit static ile yerelden servis edip `folium.Map(tiles=None)` +
   yerel XYZ/mbtiles tile paketi eklemek gerekir (ayrı iş kalemi).
2. **GE Data Docs HTML:** nadiren stil için CDN referansı içerebilir; veriyi
   etkilemez, yalnızca görünüm bozulabilir.
3. **`busybox` image'ı** volume export/import için gerekiyor; air-gapped'te yoksa
   Bölüm A.1 tar'ına eklenmeli veya veri taşıma adımı atlanmalı.
4. **`dvc repro` / `dvc pull`** için `data/` verisi ve MinIO `dvc-cache` içeriği
   ayrıca taşınmalı (pakete dahil değil).
5. **Docker Desktop güncelleme/oturum:** kurulu ve çalışır varsayıldı; güncelleme
   kontrolü ve telemetri kapatılmalı.
6. **Ollama container'ı CPU:** Docker Desktop'ta varsayılan CPU; `qwen3.5:4b`
   yanıtları yavaş olabilir. GPU için B.6 notuna bakın. Model dosyaları volume'a
   B.5'te yüklenmezse dashboard LLM sekmesi "model bulunamadı" verir.
7. **Rust `tab-to-parquet`:** kapsam dışı (aktif pipeline Polars kullanıyor).
   Gerekirse `cargo vendor` + önceden derlenmiş binary ile taşınır.
