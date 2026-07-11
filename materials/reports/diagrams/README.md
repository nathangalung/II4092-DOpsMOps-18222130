# diagrams/ — diagram-as-code sources

Folder ini menampung seluruh sumber *diagram-as-code* laporan TA dalam format
eraser.io (`.eraser`), analog dengan `tables/` untuk tabel. PNG hasil render
tetap berada di `figures/` dan hanya berkas itu yang di-`\includegraphics` oleh
LaTeX; berkas `.eraser` di sini adalah sumber kebenarannya.

## Aturan

1. Satu berkas `.eraser` per gambar, nama sama dengan PNG padanannya di
   `figures/` (contoh: `Integrate_Service_Arch.eraser` ->
   `figures/Integrate_Service_Arch.png`).
2. PNG tidak boleh diubah tanpa memperbarui berkas `.eraser` lebih dulu.
3. **Setiap diagram wajib melebar (horizontal) dan disertakan pada LaTeX TANPA
   `\rotatebox`.** Konten yang terlalu besar dipecah menjadi beberapa diagram,
   bukan diputar 90 derajat. Pola sertaan seragam:
   `\includegraphics[width=\textwidth,height=0.42\textheight,keepaspectratio]{...}`.
   Di sumbernya pakai `direction right`, susun grup sebagai rantai kiri ke kanan,
   dan tata subgrup berdampingan (maksimum dua baris node per grup) agar aspek
   rasio melebar dan muat pada pita `0.42\textheight`.
4. Diagram tersusun dalam tiga seksi naratif:
   - **Seksi 1 — kondisi saat ini** (Subbab III.1.3): `Fragment_DataOps_Flow`
     dan `Fragment_MLOps_Flow`, hanya menampilkan LAYANAN (tanpa nama alat),
     sengaja tidak tersambung satu sama lain (keterputusan alur data dari alur
     model itulah pesannya), penanda MLOps level 0 + tahap awal evolusi DataOps.
   - **Seksi 2 — sasaran layanan** (Subbab IV.2, ditempatkan setelah klasifikasi
     dan sebelum pemilihan alat IV.3): `Integrate_Service_Arch` sebagai gambaran
     menyeluruh (sembilan kelompok layanan dari `tab:layanan_industri`, tanpa
     nama alat, penanda MLOps level 2 + tahap DataOps), lalu SEMBILAN berkas
     `Service_*` (Subbab IV.2.3, `subsec:rincian-kelompok`) yang memerinci satu
     kelompok per diagram mengikuti urutan baris tabel:
     `Service_Orchestration_Infra`, `Service_Ingestion_Processing`,
     `Service_Storage`, `Service_Feature`, `Service_Model_Lifecycle`,
     `Service_Data_Governance`, `Service_Observability`, `Service_GitOps_CD`,
     `Service_Security`. Node abu-abu pada tepinya menandai kelompok tetangga
     sebagai batas konteks.
   - **Seksi 3 — arsitektur dengan alat terpilih** (Subbab IV.4): kesembilan berkas
     `Layer_*` (dua untuk Infrastructure Layer, tiga untuk jalur data, dua untuk
     Model, dua untuk Governance and Observability), membawa anotasi kategori
     sumber pada label grup.
5. Aturan penamaan alat bergantung seksi. Pada diagram Seksi 3 (`Layer_*`) setiap
   node harus menamai tool yang benar-benar ada di `platform/components/`; jangan
   menghidupkan kembali node era proposal (Raystack, Kong, Redis Stack, Jaeger).
   Sebaliknya, diagram Seksi 1 dan Seksi 2 (`Fragment_*`,
   `Integrate_Service_Arch`, `Service_*`) BEBAS ALAT: node hanya
   menamai layanan atau komponen generik dan TIDAK menamai tool platform mana pun.
6. Diagram untuk bab mana pun (bukan hanya Bab III/IV) boleh ditaruh di sini
   selama mengikuti aturan penamaan di atas.
7. Penanda kematangan (grup legenda) kini hidup pada tiga berkas. Kedua berkas
   `Fragment_DataOps_Flow` dan `Fragment_MLOps_Flow` memuat grup
   `Ciri Kematangan Kondisi Saat Ini` (Fragment = MLOps level 0
   googlecloud2024mlops + tahap awal model evolusi DataOps munappy2020adhoc), dan
   `Integrate_Service_Arch` memuat grup `Pemetaan Kematangan Target`
   (MLOps level 2 + tahap DataOps). Grup legenda ini tidak boleh dihapus tanpa
   memperbarui caption dan prosa Bab III/IV yang mengutip landasan tersebut,
   konsisten dengan Subbab II.1.3 (`subsec:maturity`).
8. Label grup layer pada kesembilan berkas `Layer_*` membawa kategori komponen
   sumbernya sesuai derivasi Subbab IV.4 (najafabadi2024analysis +
   kreuzberger2023mlops): GitOps = kategori CI/CD, Infrastructure Layer =
   infrastructure and supporting services (dibagi `Layer_Infra_Control` untuk
   control plane, autoscaling, cert-manager, dan rantai GitOps serta
   `Layer_Infra_Security` untuk bagian keamanan), Data Ingestion Layer =
   data curation: data collector (`Layer_Data_Ingestion`), Processing Layer =
   data curation: data preprocessor (`Layer_Processing`), Storage and Feature
   Store Layer = storage and versioning (`Layer_Storage_Feature`), Model Lifecycle
   Layer = ML training + model registry + ML metadata (`Layer_Model_Lifecycle`),
   Model Serving Layer = inference (`Layer_Model_Serving`), Governance and
   Observability Layer = monitoring + DataOps governance (dibagi `Layer_Governance`
   untuk tata kelola data dan `Layer_Observability` untuk observabilitas). Jangan
   mengubah anotasi ini tanpa menyunting prosa derivasi IV.4.
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

Ekspor **dua puluh satu** PNG: `Fragment_DataOps_Flow`, `Fragment_MLOps_Flow`,
`Integrate_Service_Arch`, `Service_Orchestration_Infra`,
`Service_Ingestion_Processing`, `Service_Storage`, `Service_Feature`,
`Service_Model_Lifecycle`, `Service_Data_Governance`, `Service_Observability`,
`Service_GitOps_CD`, `Service_Security`, `Layer_Infra_Control`,
`Layer_Infra_Security`, `Layer_Data_Ingestion`, `Layer_Processing`,
`Layer_Storage_Feature`, `Layer_Model_Lifecycle`, `Layer_Model_Serving`,
`Layer_Governance`, dan `Layer_Observability`. Berkas `Fragment_General_Arch.png`,
`Integrate_General_Arch.png`, `Layer_Data.png`, `Layer_Model.png`, dan
`Layer_Govern_Obs.png` sudah dipensiunkan dan DIHAPUS dari `figures/` bersama
sumber `.eraser` lamanya setelah kontennya dipecah ke berkas per-layer (tidak
lagi dirujuk LaTeX). Dua belas PNG diagram yang ada di `figures/` saat ini masih
berisi SALINAN PLACEHOLDER dari ekspor lama (konten tidak sesuai sumber
`.eraser` terbaru), sembilan PNG `Service_*` belum ada sama sekali (LaTeX
menampilkan kotak placeholder lewat pola `\IfFileExists` sampai berkasnya
tersedia), dan semuanya harus di-render dari sumber `.eraser` masing-masing.

Konvensi lengkap: `WRITING_GUIDE.md` bagian 1.7 dan `TEMPLATE_BAB.md`.

## Isi saat ini

- `Fragment_DataOps_Flow.eraser` — Seksi 1, alur data terfragmentasi (Gambar
  III.1, `fig:fragment-dataops`): rantai Sumber Data Eksternal hingga
  Ad Hoc Reporting yang dikelola *data engineer* dan diterima *business user*,
  hanya layanan tanpa nama alat; grup `Ciri Kematangan Kondisi Saat Ini`
  merender penanda tahap awal model evolusi DataOps.
- `Fragment_MLOps_Flow.eraser` — Seksi 1, alur model terfragmentasi (Gambar
  III.2, `fig:fragment-mlops`): rantai Scattered Feature Engineering hingga
  Basic Monitoring yang ditangani *data scientist* dan *machine learning
  engineer*, dengan penyerahan model satu arah; grup `Ciri Kematangan Kondisi
  Saat Ini` merender penanda MLOps level 0. Sengaja TIDAK berbagi satu edge pun
  dengan `Fragment_DataOps_Flow` (keterputusan itulah pesannya).
- `Integrate_Service_Arch.eraser` — Seksi 2, arsitektur layanan terintegrasi
  (Gambar IV.1, `fig:integrate-service`): dua band mendatar berisi sembilan
  kelompok layanan dari `tab:layanan_industri` di atas satu *control plane*
  Kubernetes, tanpa nama alat, setiap node dalam ber-ikon; grup `Pemetaan
  Kematangan Target` merender penanda MLOps level 2 + tahap DataOps.
- `Service_Orchestration_Infra.eraser` — Seksi 2 rincian
  (`fig:service-orkestrasi-infra`): infrastruktur bersama menjalankan kedua
  orkestrator, penjadwalan pelatihan ke *model training infrastructure*.
- `Service_Ingestion_Processing.eraser` — Seksi 2 rincian
  (`fig:service-ingestion-processing`): rantai data collection > ingestion >
  cleaning > preprocessor menuju penyimpanan dan tata kelola.
- `Service_Storage.eraser` — Seksi 2 rincian (`fig:service-storage`): data
  storage > dataset repository > data versioning, keluar ke layanan fitur dan
  siklus model.
- `Service_Feature.eraser` — Seksi 2 rincian (`fig:service-feature`):
  materialisasi offline > online feature store untuk pelatihan dan inferensi.
- `Service_Model_Lifecycle.eraser` — Seksi 2 rincian
  (`fig:service-model-lifecycle`): feature engineering sampai inference
  service dengan registry dan metadata, plus rilis dari GitOps.
- `Service_Data_Governance.eraser` — Seksi 2 rincian
  (`fig:service-governance`): governance menetapkan standar, testing
  menghasilkan skor kualitas, metrik ke observability.
- `Service_Observability.eraser` — Seksi 2 rincian
  (`fig:service-observability`): konsolidasi model + data monitoring dan umpan
  balik pemicu retraining otomatis.
- `Service_GitOps_CD.eraser` — Seksi 2 rincian (`fig:service-gitops-cd`):
  rantai source repo > CI/CD > deployment services > model deployment.
- `Service_Security.eraser` — Seksi 2 rincian (`fig:service-security`): API
  gateway menegakkan akses terkendali di bawah kepatuhan bagi seluruh kelompok.
- `Layer_Infra_Control.eraser` — Seksi 3, Infrastructure Layer bagian control
  plane (Subbab IV.4.1, `fig:layer-infra-control`): orkestrasi k3s, autoscaling
  HPA/VPA/KEDA/Kueue, cert-manager, dan rantai GitOps Gitea/Tekton/registry/Argo
  CD/Argo Rollouts.
- `Layer_Infra_Security.eraser` — Seksi 3, Infrastructure Layer bagian keamanan
  (Subbab IV.4.1, `fig:layer-infra-security`): Dex/oauth2-proxy/SpiceDB,
  OpenBao/ESO, Istio/APISIX, Kyverno/Falco/Trivy Operator/Chaos Mesh, dan Velero
  ke MinIO.
- `Layer_Data_Ingestion.eraser` — Seksi 3, Data Ingestion Layer (Subbab IV.4.2,
  `fig:layer-ingestion`): Kafka Connect + Debezium ke Apache Kafka (Strimzi),
  Karapace, dan Kafbat UI.
- `Layer_Processing.eraser` — Seksi 3, Processing Layer (Subbab IV.4.2,
  `fig:layer-processing`): jalur stream Flink dan jalur batch Airflow yang
  menjadwalkan Spark dan dbt, plus kueri federatif Trino.
- `Layer_Storage_Feature.eraser` — Seksi 3, Storage and Feature Store Layer
  (Subbab IV.4.2, `fig:layer-storage-feature`): subgrup lakehouse, basis data,
  dan layanan fitur berdampingan.
- `Layer_Model_Lifecycle.eraser` — Seksi 3, Model Lifecycle Layer (Subbab IV.4.3,
  `fig:layer-lifecycle`): Kubeflow Pipelines/Katib/Trainer, MLflow, serta retrain
  otomatis berbasis drift (Evidently, Prometheus, Argo CronWorkflow).
- `Layer_Model_Serving.eraser` — Seksi 3, Model Serving Layer (Subbab IV.4.3,
  `fig:layer-serving`): KServe di atas Knative, analisis canary Argo Rollouts, dan
  jembatan fitur Valkey/Qdrant.
- `Layer_Governance.eraser` — Seksi 3, bagian tata kelola data Governance and
  Observability Layer (Subbab IV.4.4, `fig:layer-governance`): DataHub menerima
  OpenLineage dan ingest sumber metadata, dengan Great Expectations.
- `Layer_Observability.eraser` — Seksi 3, bagian observabilitas Governance and
  Observability Layer (Subbab IV.4.4, `fig:layer-observability`): OpenTelemetry,
  tiga pilar Prometheus/Loki/Tempo pada Grafana, Sloth/Pyroscope/OpenCost, dan
  Superset.
