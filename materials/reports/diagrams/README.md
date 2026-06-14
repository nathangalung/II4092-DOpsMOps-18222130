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

## Render ulang

1. Buka https://app.eraser.io lalu buat *diagram-as-code* baru.
2. Tempel isi berkas `.eraser`.
3. Ekspor PNG, timpa berkas padanannya di `figures/`.
4. Bangun ulang PDF (`make` di `materials/reports/`).

Konvensi lengkap: `WRITING_GUIDE.md` bagian 1.7 dan `TEMPLATE_BAB.md`.

## Isi saat ini

- `Fragment_General_Arch.eraser` — pandangan umum fragmentasi (Gambar III.1),
  status quo pra-platform: empat peran + tumpukan ad hoc generik, tanpa
  menamai komponen platform.
- `Fragment_BusUs_Arch.eraser` — fragmentasi peran *business user* (Gambar C.1),
  tumpukan pelaporan ad hoc yang terputus dari sistem data dan model.
- `Fragment_DatEng_Arch.eraser` — fragmentasi peran *data engineer* (Gambar C.2),
  ingestasi, transformasi, penyimpanan, dan katalog yang dirakit manual.
- `Fragment_DatSci_Arch.eraser` — fragmentasi peran *data scientist* (Gambar C.3),
  eksperimen dan rekayasa fitur pada lingkungan lokal yang terisolasi.
- `Fragment_MLEng_Arch.eraser` — fragmentasi peran *ML engineer* (Gambar C.4),
  penyajian dan pemantauan model manual tanpa registri dan rollback konsisten.
- `Integrate_General_Arch.eraser` — arsitektur umum platform (Gambar IV.1),
  tujuh lapisan Bab IV + empat peran pengguna + rantai GitOps.
- `Layer_Infra_Control.eraser` — rincian Lapisan Infrastruktur dan Bidang
  Kendali (Subbab IV.2.1): orkestrasi, mesh, keamanan, operasional, dan GitOps.
- `Layer_Data.eraser` — rincian Lapisan Ingestasi, Pemrosesan, dan Penyimpanan
  Fitur (Subbab IV.2.2): dua jalur batch dan stream menuju lakehouse dan fitur.
- `Layer_Model.eraser` — rincian Lapisan Siklus Hidup Model dan Penyajian
  (Subbab IV.2.3): eksperimen, pelatihan, registri, penyajian, retrain otomatis.
- `Layer_Govern_Obs.eraser` — rincian Lapisan Tata Kelola dan Observabilitas
  (Subbab IV.2.4): katalog dan lineage berdampingan dengan tiga pilar observabilitas.
