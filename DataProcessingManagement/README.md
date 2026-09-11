# DataProcessingManagement

İHA telemetri verisini (`.ham` → `.tab`) MinIO + ClickHouse + Postgres +
Dagster pipeline'ına aktaran sistem. Tam mimari, kararlar ve gerekçeleri
için [docs/plan_dokumani.md](docs/plan_dokumani.md) dosyasına bakın (erken
dönem `.tab → .parquet` Rust/DuckDB araştırması dahil — o yaklaşım terk
edildi, üretim akışı ClickHouse'a doğrudan `.tab.zst` yükler, bkz. aşağıdaki
"AU-AIR sentetik raw veri üretimi" bölümü).

## Kapsam

Bu repo, dış bir exe'nin ürettiği `.ham → .tab` çıktısından başlayarak bu
verinin MinIO/ClickHouse/Postgres'e dağıtılmasını kapsar. `.ham → .tab`
dönüşümü bu reponun dışında.

## Yapı

| Yol | Ne |
|---|---|
| [docs/plan_dokumani.md](docs/plan_dokumani.md) | Mimari, alınan kararlar, açık sorular |
| [docs/postgres_manifest_schema.sql](docs/postgres_manifest_schema.sql) | Metadata katalog şeması |
| [dagster/](dagster/) | Üretim pipeline'ı: MinIO staging → Polars preprocess → Great Expectations validation → ClickHouse load → DVC publish |
| [dashboard/](dashboard/) | Streamlit izleme paneli |

## AU-AIR sentetik raw veri üretimi

AU-AIR benzeri 10.000-50.000 sütunlu sentetik `.tab` verisini üretip doğrudan
MinIO raw bucket'ına yüklemek için çalışan Dagster container'ında:

```sh
docker compose exec dagster python /workspace/scripts/auair_generator.py --rows 100000 --cols 10000 --chunk-size 500
```

50.000 sütun hedefinde generator belleğini sınırlamak için daha küçük üretim
chunk'ı kullanılabilir: `--cols 50000 --chunk-size 100`.

Varsayılan hedef `s3://data-raw/auair-tab/inbox/` yoludur. Yüklenen dosyanın
boyutu MinIO üzerinden doğrulanır; doğrulama başarılıysa yerel geçici dosya
silinir. Yerel kopyayı korumak için `--keep-local`, aynı isimli nesneyi
değiştirmek için `--overwrite` kullanılabilir. Tüm seçenekler için `--help`
çalıştırılabilir.

Dagster'ın AU-AIR sensorleri bu yolu otomatik olarak izler ve veriyi şu akıştan
geçirir:

```text
data-raw/auair-tab/inbox
  → data-staged/auair-tab (.tab.zst)
  → Spark preprocess (dinamik kolonlar korunur)
  → Great Expectations validation raporu
  → ClickHouse s3() bulk load (auair_telemetry, run bazlı pending kayıtlar)
  → DVC add + MinIO DVC remote push
  → Run SUCCESS: auair_telemetry_committed view'ında görünürlük
```

Son iki adım sıralıdır: ClickHouse yazımı başarıyla tamamlanmadan DVC publish
asset'i başlamaz. ClickHouse loader, 10K-50K kolonlu veriyi Yusuf'un yüksek
kolon stratejisiyle yaklaşık 1 milyar hücrelik fiziksel satır parçalarına
ayırır. Parçalar yalnız taşıma amacıyla geçici MinIO objeleri olarak oluşturulur,
ClickHouse tarafından `s3()` ile bulk okunur ve yükleme denemesinin sonunda
silinir; kalıcı MinIO dataset yayını sonraki DVC asset'ine aittir.

ClickHouse'a yazılan satırlar `dagster_run_id` ile workflow tamamlanana kadar
pending tutulur. Dashboard fiziksel tabloyu değil yalnız committed view'ı
okur. Workflow `FAILURE` veya `CANCELED` olursa ilgili run satırları silinir;
PostgreSQL run ve materialization metadata'sı audit amacıyla korunur.

İlk validation profili bilinçli olarak basittir: dosyada en az 17 kolon,
beklenen satır/kolon sayısı, zorunlu `flight_id`/`time` ve temel AU-AIR
kolonlarının doluluğu, flight ID biçimi, koordinat/irtifa ve görüntü boyutu
aralıkları kontrol edilir. Profil adı `auair-placeholder-v1`'dir.

## PostgreSQL'den commit mesajı önerisi

Başarıyla tamamlanmış ve DVC'ye publish edilmiş bir Dagster run'ı için
commit mesajı PostgreSQL kataloğundan üretilebilir. Araç Git commit veya push
komutu çalıştırmaz.

Dagster container'ından:

```sh
docker compose exec dagster python /workspace/scripts/get_commit_message.py --run-id <RUN_ID>
```

Başlıksız, otomasyon dostu çıktı için `--raw` kullanılabilir. Python içinden
de `scripts.get_commit_message.get_commit_message(run_id)` fonksiyonu
çağrılabilir.

Pipeline kimliği monorepo içinde path-aware çözülür. Son `pipeline-v*`
tag'inden sonra yalnızca DVC/data dosyaları değiştiyse pipeline sürümü aynı
kalır; pipeline kapsamındaki bir dosya değiştiyse `unreleased-<sha>` kullanılır.
Commit önerisi hem pipeline revision'ını (`Pipeline-Git-SHA`) hem de run
anındaki gerçek repository HEAD'ini (`Repository-Git-SHA`) içerir.
