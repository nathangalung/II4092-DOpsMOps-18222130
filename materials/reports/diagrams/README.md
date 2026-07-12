# diagrams/ — diagram-as-code sources

Folder ini menampung seluruh sumber *diagram-as-code* laporan TA dalam format
eraser.io (`.eraser`), analog dengan `tables/` untuk tabel. PNG hasil render
tetap berada di `figures/` dan hanya berkas itu yang di-`\includegraphics` oleh
LaTeX; berkas `.eraser` di sini adalah sumber kebenarannya.

## Aturan

1. Satu berkas `.eraser` per gambar, nama sama dengan PNG padanannya di
   `figures/` (contoh: `DataOps_MLOps_Flow.eraser` ->
   `figures/DataOps_MLOps_Flow.png`).
2. PNG tidak boleh diubah tanpa memperbarui berkas `.eraser` lebih dulu.
3. **Setiap diagram wajib melebar (horizontal) dan disertakan pada LaTeX TANPA
   `\rotatebox`.** Konten yang terlalu besar dipecah menjadi beberapa diagram,
   bukan diputar 90 derajat. Pola sertaan seragam:
   `\includegraphics[width=\textwidth,height=0.42\textheight,keepaspectratio]{...}`.
   Di sumbernya pakai `direction right`, susun grup sebagai rantai kiri ke kanan,
   dan tata subgrup berdampingan (maksimum dua baris node per grup) agar aspek
   rasio melebar dan muat pada pita `0.42\textheight`.
4. Diagram tersusun dalam tiga seksi naratif dengan SATU taksonomi sembilan
   *layer* (revisi 2026-07-11, taksonomi tunggal; pemisahan tujuh *layer* dan
   berkas `Service_*` sudah dihapus):
   - **Seksi 1 — kondisi saat ini** (Subbab III.1.3): `Fragment_DataOps_Flow`
     dan `Fragment_MLOps_Flow`, hanya menampilkan LAYANAN (tanpa nama alat),
     sengaja tidak tersambung satu sama lain (keterputusan alur data dari alur
     model itulah pesannya), penanda MLOps level 0 + tahap awal evolusi DataOps.
   - **Seksi 2 — sasaran layanan** (Subbab IV.1, setelah klasifikasi dan
     sebelum pemilihan alat IV.2): `DataOps_MLOps_Flow`, kesembilan *layer*
     dari `tab:layanan_industri` pada satu *control plane* Kubernetes, tanpa
     nama alat, penanda MLOps level 2 + tahap DataOps.
   - **Seksi 3 — arsitektur dengan alat terpilih** (Subbab IV.3, sembilan
     subbab satu-per-layer): SEPULUH berkas `Layer_*`, satu per *layer* dalam
     urutan baris tabel, dengan *layer* kelima (Model Lifecycle, memuat *model
     serving component* + *inference service*) dipecah menjadi dua gambar:
     `Layer_Orchestration_Infra`, `Layer_Ingestion_Processing`,
     `Layer_Data_Storage`, `Layer_Feature_Service`, `Layer_Model_Lifecycle` +
     `Layer_Model_Serving` (dua gambar satu *layer*), `Layer_Data_Governance`,
     `Layer_Observability`, `Layer_GitOps_CD`, `Layer_Security`.
5. Aturan penamaan alat bergantung seksi. Pada diagram Seksi 3 (`Layer_*`)
   setiap node harus menamai tool yang benar-benar ada di `platform/components/`;
   jangan menghidupkan kembali node era proposal (Raystack, Kong, Redis Stack,
   Jaeger). Sebaliknya, diagram Seksi 1 dan Seksi 2 (`Fragment_*`,
   `DataOps_MLOps_Flow`) BEBAS ALAT: node hanya menamai layanan atau
   komponen generik dan TIDAK menamai tool platform mana pun.
6. Diagram untuk bab mana pun (bukan hanya Bab III/IV) boleh ditaruh di sini
   selama mengikuti aturan penamaan di atas.
7. Penanda kematangan (grup legenda) hidup pada tiga berkas. Kedua berkas
   `Fragment_DataOps_Flow` dan `Fragment_MLOps_Flow` memuat grup
   `Ciri Kematangan Kondisi Saat Ini` (MLOps level 0 googlecloud2024mlops +
   tahap awal model evolusi DataOps munappy2020adhoc), dan
   `DataOps_MLOps_Flow` memuat grup `Pemetaan Kematangan Target`
   (MLOps level 2 + tahap DataOps). Grup legenda ini tidak boleh dihapus tanpa
   memperbarui caption dan prosa Bab III/IV yang mengutip landasan tersebut,
   konsisten dengan Subbab II.1.3 (`subsec:maturity`).
8. Label grup pada kesepuluh berkas `Layer_*` membawa anotasi kategori
   sumbernya sesuai baris `tab:layanan_industri` dan derivasi Subbab IV.3
   (najafabadi2024analysis + kreuzberger2023mlops + munappy2020adhoc):
   Orchestration and Infrastructure = infrastructure and supporting services;
   Data Ingestion and Processing = data curation (collector + preprocessor);
   Data Storage = storage and versioning; Feature Service = feature store pada
   storage and versioning; Model Lifecycle = ML training + model registry +
   ML metadata + inference (bagian model serving); Data Governance = data
   quality + data testing + data governance; Observability = monitoring;
   GitOps and Continuous Delivery = kategori CI/CD; Platform Security = sisi
   keamanan infrastruktur + akses terkendali DataOps. Jangan mengubah anotasi
   ini tanpa menyunting prosa derivasi IV.3 dan tabel.
9. **Ikon wajib pada SETIAP node** (termasuk node dalam grup); node tanpa
   `icon:` merender kotak polos tanpa logo. Nama ikon HANYA dari daftar resmi
   https://docs.eraser.io/docs/icons (diverifikasi 2026-07-11; daftar berisi
   seksi AWS/GCP/Azure/Tech Logos/General). Diagram Seksi 3 memakai logo produk
   yang tersedia: `kafka`, `airflow`, `spark`, `flink`, `dbt`, `trino`,
   `clickhouse`, `postgres` (BUKAN `postgresql`), `mysql`, `opensearch`,
   `minio`, `qdrant`, `mlflow`, `argo`, `istio`, `trivy`, `tempo`, `grafana`,
   `prometheus`, `superset`, `kubernetes`, `git`, `docker`; tool tanpa logo
   memakai ikon generik. Nama `flame` dan `postgresql` TIDAK ada pada daftar.
   Fork tidak memakai logo induknya: Valkey bukan `redis`, OpenBao bukan
   `vault`. Diagram Seksi 1 dan 2 memakai ikon generik saja (aturan bebas-alat).
10. **Konektor mengikuti fakta sumber**: `>` atau `<` untuk alur berarah
    (urutan tahap pada paper untuk Seksi 1-2, arah aliran data atau kendali per
    dokumentasi tool dan implementasi `platform/components/` untuk Seksi 3);
    `<>` hanya untuk hubungan yang faktual dua arah (mTLS mutual, permintaan
    dan respons inferensi, AdmissionReview, kueri federatif, OpenCost dengan
    Prometheus, loop HPO KFP dan Katib); `--` (garis putus pada eraser) hanya
    untuk asosiasi non-alur seperti payung control plane. Grup legenda
    kematangan sengaja tanpa edge dan dikecualikan dari aturan konektivitas;
    semua node lain wajib punya minimal satu edge.
11. Sintaks cloud architecture eraser TIDAK mendukung baris `title`; judul
    kanvas diambil dari nama kanvas. Saat merender, buat kanvas BARU bernama
    sama dengan berkas `.eraser` (jangan menimpa kanvas lama berjudul lain,
    itulah sebab judul salah seperti "DataOps_MLOps_Flow" muncul pada ekspor).

## Render ulang

1. Buka https://app.eraser.io lalu buat kanvas *diagram-as-code* BARU bernama
   sama dengan berkas `.eraser` (lihat aturan 11).
2. Tempel isi berkas `.eraser`.
3. Ekspor PNG, timpa (atau buat) berkas padanannya di `figures/`.
4. Bangun ulang PDF (`make` di `materials/reports/`).

Ekspor **tiga belas** PNG: `Fragment_DataOps_Flow`, `Fragment_MLOps_Flow`,
`DataOps_MLOps_Flow`, `Layer_Orchestration_Infra`,
`Layer_Ingestion_Processing`, `Layer_Data_Storage`, `Layer_Feature_Service`,
`Layer_Model_Lifecycle`, `Layer_Model_Serving`, `Layer_Data_Governance`,
`Layer_Observability`, `Layer_GitOps_CD`, dan `Layer_Security`. Tujuh nama baru
belum punya PNG (LaTeX menampilkan kotak placeholder lewat pola `\IfFileExists`
sampai berkasnya tersedia); tiga PNG lama yang tersisa
(`Layer_Model_Lifecycle`, `Layer_Model_Serving`, `Layer_Observability`) plus
ketiga PNG Seksi 1-2 masih berisi SALINAN PLACEHOLDER dari ekspor lama, jadi
ketiga belasnya dirender dari sumber `.eraser` terbaru. Berkas era tujuh-layer
(`Layer_Infra_Control`, `Layer_Infra_Security`, `Layer_Data_Ingestion`,
`Layer_Processing`, `Layer_Storage_Feature`, `Layer_Governance`) dan kesembilan
`Service_*` sudah DIHAPUS dari `diagrams/` dan `figures/`.

Konvensi lengkap: `WRITING_GUIDE.md` bagian 1.7 dan `TEMPLATE_BAB.md`.

## Isi saat ini

- `Fragment_DataOps_Flow.eraser` — Seksi 1, alur data terfragmentasi (Gambar
  III.1, `fig:fragment-dataops`): rantai Sumber Data Eksternal hingga
  Ad Hoc Reporting yang dikelola *data engineer* dan diterima *business user*,
  hanya layanan tanpa nama alat; grup `Ciri Kematangan Kondisi Saat Ini`
  merender penanda tahap awal model evolusi DataOps.
- `Fragment_MLOps_Flow.eraser` — Seksi 1, alur model terfragmentasi (Gambar
  III.2, `fig:fragment-mlops`): rantai Scattered Feature Engineering hingga
  Basic Monitoring dengan penyerahan model satu arah; grup `Ciri Kematangan
  Kondisi Saat Ini` merender penanda MLOps level 0. Sengaja TIDAK berbagi satu
  edge pun dengan `Fragment_DataOps_Flow` (keterputusan itulah pesannya).
- `DataOps_MLOps_Flow.eraser` — Seksi 2, arsitektur layanan terintegrasi
  (Gambar IV.1, `fig:integrate-service`): dua band mendatar berisi sembilan
  *layer* dari `tab:layanan_industri` di atas satu *control plane* Kubernetes,
  tanpa nama alat, setiap node dalam ber-ikon; grup `Pemetaan Kematangan
  Target` merender penanda MLOps level 2 + tahap DataOps.
- `Layer_Orchestration_Infra.eraser` — Seksi 3 layer 1
  (`fig:layer-orkestrasi-infra`): k3s/Kubernetes, metrics-server,
  HPA/VPA/KEDA, Kueue, cert-manager.
- `Layer_Ingestion_Processing.eraser` — Seksi 3 layer 2
  (`fig:layer-ingestion-processing`): jalur masuk Kafka Connect+Debezium >
  Kafka (Strimzi) + Karapace + Kafbat UI, jalur stream Flink, jalur batch
  Airflow > Spark/dbt, kueri federatif Trino.
- `Layer_Data_Storage.eraser` — Seksi 3 layer 3 (`fig:layer-storage`):
  lakehouse MinIO/KES + lakeFS + Iceberg + Lakekeeper dan basis data
  ClickHouse/PostgreSQL/MySQL/OpenSearch.
- `Layer_Feature_Service.eraser` — Seksi 3 layer 4 (`fig:layer-feature`):
  Feast dengan sumber offline ClickHouse, online Valkey, vektor Qdrant,
  registry berkas MinIO, fitur stream dari Flink.
- `Layer_Model_Lifecycle.eraser` — Seksi 3 layer 5 gambar pertama
  (`fig:layer-lifecycle`): Kubeflow Pipelines/Notebooks/Katib/Trainer, MLflow,
  retrain otomatis berbasis drift (Evidently, Prometheus, Argo CronWorkflow).
- `Layer_Model_Serving.eraser` — Seksi 3 layer 5 gambar kedua, bagian *model
  serving* (`fig:layer-serving`): KServe di atas Knative, canary Argo
  Rollouts, jembatan fitur Valkey/Qdrant.
- `Layer_Data_Governance.eraser` — Seksi 3 layer 6 (`fig:layer-governance`):
  DataHub menerima OpenLineage dan ingest sumber metadata, Great Expectations,
  indeks OpenSearch.
- `Layer_Observability.eraser` — Seksi 3 layer 7 (`fig:layer-observability`):
  OpenTelemetry, tiga pilar Prometheus/Loki/Tempo pada Grafana,
  Sloth/Pyroscope/OpenCost, Superset.
- `Layer_GitOps_CD.eraser` — Seksi 3 layer 8 (`fig:layer-gitops`): Gitea >
  Tekton > registry > Argo CD, Argo Rollouts.
- `Layer_Security.eraser` — Seksi 3 layer 9 (`fig:layer-security`):
  Dex/oauth2-proxy/SpiceDB, OpenBao/ESO, Istio/APISIX,
  Kyverno/Falco/Trivy/Chaos Mesh, Velero ke MinIO.
