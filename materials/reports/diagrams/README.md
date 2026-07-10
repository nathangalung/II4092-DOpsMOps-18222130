# diagrams/ — diagram-as-code sources

Folder ini menampung seluruh sumber *diagram-as-code* laporan TA dalam format
eraser.io (`.eraser`), analog dengan `tables/` untuk tabel. PNG hasil render
tetap berada di `figures/` dan hanya berkas itu yang di-`\includegraphics` oleh
LaTeX; berkas `.eraser` di sini adalah sumber kebenarannya.

## Aturan

1. Satu berkas `.eraser` per gambar, nama sama dengan PNG padanannya di
   `figures/` (contoh: `Integrate_General_Arch.eraser` ->
   `figures/Integrate_General_Arch.png`).
2. PNG tidak boleh diubah tanpa memperbarui berkas `.eraser` lebih dulu.
3. Setiap node pada diagram arsitektur harus menamai tool yang benar-benar ada
   di `platform/components/`; jangan menghidupkan kembali node era proposal
   (Raystack, Kong, Redis Stack, Jaeger).
4. Diagram untuk bab mana pun (bukan hanya Bab III/IV) boleh ditaruh di sini
   selama mengikuti aturan penamaan di atas.
5. Gambar III.1 dan IV.1 membawa penanda kematangan yang harus tetap konsisten
   dengan Subbab II.1.3 (`subsec:maturity`): Fragment = MLOps level 0
   (googlecloud2024mlops) + tahap awal model evolusi DataOps (munappy2020adhoc);
   Integrate = MLOps level 2 + tahap DataOps. Grup legenda pada kedua berkas
   (`Ciri Kematangan Kondisi Saat Ini`, `Pemetaan Kematangan Target`) tidak
   boleh dihapus tanpa memperbarui caption dan prosa Bab III/IV yang
   mengutip landasan tersebut.
6. Label grup layer pada `Integrate_General_Arch` dan keempat berkas
   `Layer_*` membawa kategori komponen sumbernya sesuai derivasi Subbab IV.2
   (najafabadi2024analysis + kreuzberger2023mlops): GitOps = kategori CI/CD,
   Infrastructure Layer = infrastructure and supporting services,
   Data Ingestion Layer = data curation: data collector, Processing Layer =
   data curation: data preprocessor, Storage and Feature Store Layer =
   storage and versioning, Model Lifecycle Layer = ML training + model
   registry + ML metadata, Model Serving Layer = inference, Governance and
   Observability Layer = monitoring + DataOps governance. Jangan
   mengubah anotasi ini tanpa menyunting prosa derivasi IV.2.

## Render ulang

1. Buka https://app.eraser.io lalu buat *diagram-as-code* baru.
2. Tempel isi berkas `.eraser`.
3. Ekspor PNG, timpa berkas padanannya di `figures/`.
4. Bangun ulang PDF (`make` di `materials/reports/`).

Konvensi lengkap: `WRITING_GUIDE.md` bagian 1.7 dan `TEMPLATE_BAB.md`.

## Isi saat ini

- `Fragment_General_Arch.eraser` — pandangan umum fragmentasi (Gambar III.1),
  status quo pra-platform: empat peran + tumpukan ad hoc generik, tanpa
  menamai komponen platform; grup `Ciri Kematangan Kondisi Saat Ini`
  merender penanda MLOps level 0 + tahap awal evolusi DataOps.
- `Integrate_General_Arch.eraser` — arsitektur umum platform (Gambar IV.1),
  tujuh layer Bab IV + empat peran pengguna + rantai GitOps; grup
  `Pemetaan Kematangan Target` merender penanda MLOps level 2 (tujuh
  komponen wajib) + tahap DataOps.
- `Layer_Infra_Control.eraser` — rincian Infrastructure Layer dan Control
  Plane (Subbab IV.2.1): orkestrasi, mesh, keamanan, operasional, dan GitOps.
- `Layer_Data.eraser` — rincian Data Ingestion Layer, Processing Layer, dan
  Storage and Feature Store Layer (Subbab IV.2.2): dua jalur batch dan stream
  menuju lakehouse dan feature store.
- `Layer_Model.eraser` — rincian Model Lifecycle Layer dan Model Serving
  Layer (Subbab IV.2.3): eksperimen, training, registri, serving, retrain otomatis.
- `Layer_Govern_Obs.eraser` — rincian Governance and Observability Layer
  (Subbab IV.2.4): katalog dan lineage berdampingan dengan tiga pilar observabilitas.
