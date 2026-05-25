# Template Per-Bab + Locked Chain

Dokumen ini menyimpan panduan template tiap bab yang sebelumnya tertulis langsung di dalam `chapters/Bab_*.tex`. Setelah isi sebenarnya ditulis, panduan asli tetap dapat ditelusuri di sini sehingga revisi berikutnya tidak kehilangan kerangka instruksi dari Prodi STI ITB. Baca dokumen ini bersama `WRITING_GUIDE.md` dan `README.md`.

## 1. Locked Chain (Rumusan Masalah → Tujuan → Bab IV → Bab V → Kesimpulan)

Platform Tugas Akhir ini bersifat domain-agnostic. *Use case* kripto hanya berperan sebagai instans uji; semua rumusan masalah, tujuan, perancangan, dan implementasi berbicara pada level platform. Rantai berikut harus tetap sinkron pada setiap revisi.

| No | Rumusan Masalah (RM) | Tujuan (T) | Subbab Bab IV | Subbab Bab V | Poin Kesimpulan |
|----|----------------------|------------|---------------|--------------|------------------|
| 1  | Fragmentasi *tool* MLOps/DataOps menimbulkan biaya integrasi, duplikasi *pipeline*, dan ketidakkonsistenan antara fase data dan fase model. | Merancang arsitektur platform DataOps dan MLOps terintegrasi di atas Kubernetes yang menyatukan komponen data dan model pada satu bidang kendali. | IV.2 Arsitektur Platform Terintegrasi | V.2 Implementasi Arsitektur Terintegrasi | K1 |
| 2  | Tata kelola data sulit ditegakkan lintas siklus data–fitur–model sehingga *lineage*, kualitas, dan kepemilikan sulit ditelusuri. | Membangun *sub-sistem* tata kelola data (katalog, *lineage*, kualitas) yang berjalan otomatis di seluruh *pipeline*. | IV.3 *Sub-sistem* Tata Kelola Data | V.3 Implementasi *Sub-sistem* Tata Kelola | K2 |
| 3  | *Drift* data dan *concept drift* terjadi tanpa terdeteksi, sementara penyajian fitur lintas mode *batch* dan *streaming* rentan terhadap kebocoran temporal (*temporal leakage*). | Mengimplementasikan mekanisme deteksi *drift* terotomasi dengan *retraining* berbasis kebijakan dan menjamin *point-in-time correctness* pada penyajian fitur. | IV.4 *Sub-sistem* Deteksi *Drift* dan *Continuous Training* | V.4 Implementasi Deteksi *Drift* dan *Continuous Training* | K3 |
| 4  | Fitur multimoda (vektor berdimensi tinggi, fitur agregat, fitur waktu nyata) sulit dilayani konsisten dengan SLA berbeda dari satu sumber kebenaran. | Mengembangkan layanan fitur *dual-store* (*offline* + *online*) yang melayani fitur tabular maupun vektor melalui satu kontrak API. | IV.5 *Sub-sistem* Layanan Fitur *Dual-Store* | V.5 Implementasi Layanan Fitur *Dual-Store* | K4 |

Subbab IV.1 (Gambaran Umum Platform) dan V.1 (Lingkungan Implementasi) berfungsi sebagai pengikat; subbab ini tidak masuk ke dalam rantai 1-1 di atas, tetapi wajib ada (lihat panduan Bab IV pada `WRITING_GUIDE.md` §3.2).

Aturan turunan:
1. Jumlah RM = jumlah T = jumlah subbab Bab IV (di luar IV.1) = jumlah subbab Bab V (di luar V.1) = jumlah poin Kesimpulan.
2. Verba pada Tujuan tidak boleh berisi “mengevaluasi”, “menguji”, “mengukur”, atau “mendemonstrasikan”. Evaluasi adalah aktivitas metodologi, bukan tujuan.
3. Judul Bab IV menyebut nama artefak, bukan kata generik “Perancangan”. Judul yang digunakan: “Perancangan Arsitektur Platform DataOps dan MLOps Terintegrasi”.
4. Setiap subbab Bab V membuka dengan referensi balik ke subbab Bab IV yang dipenuhi.
5. Setiap poin Kesimpulan menjawab tepat satu Tujuan.

## 2. Bab I Pendahuluan – Panduan Template Asli

(Disalin dari Bab_1.tex versi template.)

### 2.1 Latar Belakang

Subbab ini menjelaskan dasar pemikiran, motivasi, kebutuhan, alasan, atau urgensi pemilihan masalah Tugas Akhir. Subbab ini berisi penjelasan ringkas tentang kondisi atau situasi yang ada saat ini terkait dengan topik yang dibahas. Penulis perlu memuat:

1. Kondisi atau situasi topik yang dibahas beserta permasalahannya.
2. Urgensi atau pentingnya penyelesaian masalah tersebut.
3. Berbagai solusi yang telah diterapkan maupun yang memungkinkan untuk diterapkan.
4. Kelemahan atau kekurangan dari solusi yang telah/akan diterapkan sebagai dasar pemikiran rumusan masalah.

Panjang ideal 2–3 halaman. Hindari pernyataan yang terlalu umum atau terlalu luas. Sitasi mengikuti `biblatex` (`\textcite` naratif atau `\autocite` parentetik).

### 2.2 Rumusan Masalah

Berisi masalah utama yang dibahas. Struktur ideal:

1. Pokok persoalan dari kondisi atau situasi yang ada saat ini.
2. Elaborasi urgensi penyelesaian masalah (akibat jika tidak diselesaikan).
3. Usulan singkat solusi yang ditawarkan.

Hindari rumusan masalah yang terlalu umum (mis. “Bagaimana meningkatkan kualitas layanan kesehatan di Indonesia?”) dan yang merupakan keniscayaan TA (mis. “Bagaimana cara menguji sistem yang akan dibuat?”).

### 2.3 Tujuan

Tuliskan tujuan utama yang akan dicapai setelah Tugas Akhir selesai. Fokus pada hasil akhir, bukan kegiatan teknis. Sertakan kriteria keberhasilan.

### 2.4 Batasan Masalah

Batasan-batasan yang diambil. Opsional jika judul sudah cukup spesifik.

### 2.5 Metodologi

Tahapan pelaksanaan TA. Contoh tahapan dari template:

1. Investigasi pengumpulan fakta.
2. Studi literatur sistematis.
3. Analisis kebutuhan pengguna dan sistem.
4. Perancangan solusi.
5. Implementasi solusi.
6. Evaluasi solusi.
7. Penarikan kesimpulan dan saran.

### 2.6 Sistematika Penulisan

Gambaran umum isi setiap bab. Template menyebut Bab I s.d. Bab VII ditambah Daftar Pustaka dan Lampiran.

## 3. Bab II Studi Literatur – Panduan Template Asli

(Disalin dari Bab_2.tex versi template.)

Studi literatur berisi tinjauan pustaka, landasan teori, dan penelitian terdahulu yang relevan. Penulis menjelaskan:

1. Landasan teori dari literatur yang akan dipakai untuk menyelesaikan persoalan.
2. Pengetahuan tentang kasus yang dikaji.
3. Penelitian atau solusi terkait, untuk menentukan posisi persoalan dan ruang solusi.

Studi literatur bukan rangkuman; isi harus diolah secara sistematis. Alur penulisan yang dianjurkan: kasus → teori dasar → metode → penelitian terdahulu.

### 3.1 Format Gambar, Tabel, Rumus, dan Kode Program

Gambar:
- Diletakkan di posisi `[t]` (top) atau `[b]` (bottom).
- Judul (caption) berada di bawah gambar, ditengahkan secara horizontal, huruf kecil kecuali huruf pertama.
- Nomor gambar tidak diakhiri tanda baca.
- Resolusi cukup tinggi; hindari *screenshot*; gunakan re-draw (draw.io, PowerPoint, Figma, Canva) dengan zoom ekspor ≥ 300%.

Tabel:
- Judul (caption) berada di atas tabel.
- Tabel pendek: lingkungan `table` biasa, gunakan `tabularx`/`threeparttable` ketika butuh kolom fleksibel dan catatan kaki.
- Tabel panjang: paket `longtable` agar dapat terpenggal antar-halaman.
- Penyebutan di teks dengan `\ref` dan huruf kapital pada kata “Tabel”.

Rumus matematika:
- Persamaan tunggal: lingkungan `equation` dengan `\label{eq:...}`.
- Persamaan multi-baris bernomor: `align` (nomor hanya di baris terakhir) atau `multline` (rumus melebar).
- Persamaan multi-baris tanpa nomor: `align*`.

Kode program / *script*:
- Gunakan paket `listings`. Kode pendek inline; kode panjang dipindah ke lampiran.

Algoritma:
- Gunakan paket `algorithmic` (atau `algorithm2e`/`algpseudocode` jika lebih cocok).

## 4. Bab III Analisis Masalah – Panduan Template Asli

(Disalin dari Bab_3.tex versi template.)

Pembagian subbab tidak rigid. Bab III minimal berisi:

1. Analisis kebutuhan fungsional dan nonfungsional.
2. Analisis berbagai alternatif solusi yang dapat ditawarkan.
3. Metode pemilihan solusi yang diusulkan.

Contoh struktur:

- Analisis Kondisi Saat Ini (model konseptual sistem yang ada + masalahnya).
- Analisis Kebutuhan (identifikasi masalah pengguna, kebutuhan fungsional, kebutuhan nonfungsional).
- Analisis Pemilihan Solusi (alternatif solusi, analisis penentuan solusi).

## 5. Bab IV Perancangan – Panduan Template Asli

(Disalin dari Bab_4.tex versi template + `WRITING_GUIDE.md` §3.2.)

Ilustrasikan desain konsep solusi dalam bentuk model konseptual beserta penjelasan ringkas. Ilustrasi harus dapat dibandingkan (*before* dan *after*) terhadap kondisi sistem saat ini yang digambar di awal Bab III.

Aturan WRITING_GUIDE.md §3.2 yang berlaku:
- Judul bab tidak boleh “Perancangan” saja; sebut nama artefak.
- IV.1 selalu “Gambaran Umum” dengan diagram sistem secara keseluruhan.
- IV.2..N memetakan satu lawan satu dengan Tujuan 1..N.

## 6. Bab V Implementasi – Panduan Template Asli

Template tidak menyertakan instruksi rinci untuk Bab V; gunakan aturan dari `WRITING_GUIDE.md` §3.3:

- Setiap subbab Bab V berpasangan satu lawan satu dengan subbab Bab IV.
- Setiap subbab merujuk balik pada subbab Bab IV yang dipenuhi.
- Implementasi dijelaskan apa adanya berdasarkan kondisi sistem yang sudah berjalan.

## 7. Bab VI Evaluasi – Panduan Template Asli

(Disalin dari Bab_6.tex versi template.)

Bab Evaluasi berisi metode evaluasi, hasil evaluasi, dan pembahasan hasil. Catatan gaya bahasa Indonesia ilmiah yang harus dijaga di seluruh laporan:

1. *“di mana”* / *“dimana”* tidak digunakan sebagai pengganti *which* dalam bahasa Inggris; ganti dengan “dengan”, “tempat”, atau “yang” sesuai konteks (referensi: Buku Praktis Bahasa Indonesia / BPBI).
2. Konjungsi *sedangkan* dan *sehingga* hanya boleh sebagai konjungsi intrakalimat, tidak diletakkan di awal kalimat. *sedangkan* didahului koma; *sehingga* tidak.
3. Istilah baku: analisa → analisis, eksisting → yang ada, bisnis proses → proses bisnis, user → pengguna, system → sistem, database → basis data, aktifitas → aktivitas, efektifitas → efektivitas, sosial media → media sosial.
4. Pemisah desimal memakai koma (50,6%), bukan titik.
5. Daftar memakai angka (1, 2, 3) atau huruf (a, b, c); hindari *bullet points*. Jika hanya satu *item*, tidak perlu nomor. Judul item dan penjelasannya tetap pada halaman yang sama.
6. *masing-masing* diletakkan di belakang kata yang diterangkan; *setiap*/*tiap-tiap* diletakkan di depannya.

## 8. Bab VII Kesimpulan dan Saran – Panduan Template Asli

Template tidak menyertakan rincian; gunakan aturan `WRITING_GUIDE.md` §3.4:

- Kesimpulan menjawab Tujuan satu per satu, dengan urutan yang sama.
- Tidak menambahkan klaim baru yang belum muncul di bab sebelumnya.
- Saran berisi arah pengembangan lanjutan, terutama untuk tujuan-tujuan yang belum tertutup penuh oleh evaluasi awal.

## 9. Daftar Berkas Pendukung

- `WRITING_GUIDE.md` – pedoman gambar/tabel/struktur bab.
- `README.md` – konvensi struktur direktori dan penamaan berkas.
- `daftar-pustaka.bib` – daftar pustaka BibLaTeX.
- `figures/` – semua *figure* berformat PNG/JPG.
- `tables/` – tabel yang di-`\input` dari berkas utama.
- `listings/` – kode program panjang.
- `algorithms/` – pseudocode algoritma.

## 10. Catatan Pemeliharaan

Apabila rantai pada §1 berubah (mis. tujuan diperluas atau dipersempit), perbarui:

1. Tabel rantai di §1 dokumen ini.
2. Daftar subbab pada Bab I (Rumusan Masalah, Tujuan, Sistematika).
3. Daftar subbab pada Bab IV dan Bab V.
4. Poin Kesimpulan pada Bab VII.

Sinkronisasi rantai diperiksa setiap kali revisi besar selesai.
