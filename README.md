# iha-veri-platformu

İHA (insansız hava aracı) telemetri verisini işleyen platformun **soğuk
depolama / arşiv reposu**: uygulamanın kaynak kodunu ve bu kaynak kodun
**internet erişimi olmayan (air-gapped) bir Windows makinesinde** sıfırdan
ayağa kaldırılmasını sağlayan tüm ikili bağımlılıkları (Docker image'ları,
LLM modeli, opsiyonel Python/JDK runtime'ları) tek bir repoda birleştirir.

## Kuruluma buradan başlayın

Projeyi hiç tanımıyorsanız aşağıdaki **iki dosyadan birini** baştan sona takip
edin — hangisi olduğu hedef makinenin internet erişimine bağlıdır:

| Durum | Dosya |
|---|---|
| Makinede **internet var** | **[KURULUM_STANDART.md](KURULUM_STANDART.md)** — Docker Desktop kurulumundan servislerin ayağa kalkmasına ve gerektiğinde tamamen kaldırılmasına kadar her adım. |
| Makinede **internet yok** (air-gapped) | **[KURULUM_AIRGAP.md](KURULUM_AIRGAP.md)** — aynı sonucu, önceden hazırlanmış `airgap-bundle/` paketiyle internetsiz sağlar. |

Her iki doküman da servisleri **durdurma/kaldırma (Docker teardown)**
adımlarını içerir.

## Yapı

| Yol | Ne |
|---|---|
| [DataProcessingManagement/](DataProcessingManagement/) | Uygulamanın kaynak kodu: MinIO + ClickHouse + Postgres + Dagster + Streamlit dashboard pipeline'ı. Geliştirici odaklı ayrıntılar için kendi [README.md](DataProcessingManagement/README.md)'sine bakın. |
| [airgap-bundle/](airgap-bundle/) | İnternetsiz kurulum paketi: Docker image'ları, Ollama LLM modeli, opsiyonel Python 3.12/JDK 17/uv runtime'ları, pip wheelhouse. Sadece [KURULUM_AIRGAP.md](KURULUM_AIRGAP.md) kullanıyorsanız gerekir. |
| [KURULUM_STANDART.md](KURULUM_STANDART.md) | İnternetli makinede kurulum + çalıştırma + kaldırma. |
| [KURULUM_AIRGAP.md](KURULUM_AIRGAP.md) | İnternetsiz (air-gapped) makinede kurulum + çalıştırma + kaldırma. |

## Büyük dosyalar hakkında not

GitHub tek dosya için 100 MB sınırı koyduğundan, `airgap-bundle/` içindeki
100 MB'ı aşan 4 dosya (Docker image tar'ı, Ollama model blob'u, PySpark
wheel'i, JDK zip'i) `.partNNNN` uzantılı parçalara bölünmüş halde tutulur.
Kullanmadan önce:

```powershell
cd airgap-bundle
.\scripts\Reassemble-Bundle.ps1
```

çalıştırarak parçaları orijinal dosyalarında birleştirin; script SHA256
bütünlük kontrolünü de otomatik yapar (`SHA256SUMS.txt`).

## Bu repo neden bu şekilde kuruldu

- `DataProcessingManagement/` kendi git geçmişine sahip ayrı bir repoydu
  (`github.com/ykyking1/DataProcessingManagement`); buraya güncel çalışma
  durumu (air-gapped hazırlık değişiklikleri dahil) tek bir enstantane olarak
  aktarıldı, eski commit geçmişi taşınmadı.
- `airgap-bundle/` orijinalde `DataProcessingManagement/`'ın ürettiği ayrı bir
  transfer paketiydi (`D:\airgap-bundle`); `airgap-bundle/repo/repo-worktree.tar.gz`
  adlı iç içe repo kopyası kaldırıldı çünkü aynı kaynak artık doğrudan
  `DataProcessingManagement/` olarak bu repoda mevcut.
- Dagster'ın çalışma zamanı önbelleği (`dagster/data/raw`, ~7.7 GB) ve DVC ile
  yönetilen pipeline çıktısı (`data/processed`, ~4.5 GB) bilinçli olarak
  **dahil edilmedi** — bunlar yeniden üretilebilir; sadece DVC pointer'ı
  (`data/processed/auair.dvc`) ve pipeline tanımı (`dvc.yaml`/`dvc.lock`)
  korunur. Yeniden üretmek için `DataProcessingManagement/` içinde `dvc repro`.
