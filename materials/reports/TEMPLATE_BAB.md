# Template Per-Bab + Locked Chain

Dokumen ini menyimpan panduan template tiap bab yang sebelumnya tertulis langsung di dalam `chapters/Bab_*.tex`. Setelah isi sebenarnya ditulis, panduan asli tetap dapat ditelusuri di sini sehingga revisi berikutnya tidak kehilangan kerangka instruksi dari Prodi STI ITB. Baca dokumen ini bersama `WRITING_GUIDE.md` dan `README.md`.

## 1. Locked Chain (Rumusan Masalah → Tujuan → Bab IV → Bab V → Kesimpulan)

Platform Tugas Akhir ini bersifat domain-agnostic. *Use case* kripto hanya berperan sebagai kasus uji; semua rumusan masalah, tujuan, perancangan, dan implementasi berbicara pada level platform. Rantai berikut harus tetap sinkron pada setiap revisi.

| No | Rumusan Masalah (RM) | Tujuan (T) | Subbab Bab IV | Subbab Bab V | Poin Kesimpulan |
|----|----------------------|------------|---------------|--------------|------------------|
| 1  | Fragmentasi *tool* MLOps/DataOps menimbulkan biaya integrasi, duplikasi *pipeline*, dan ketidakkonsistenan antara fase data dan fase model. | Merancang arsitektur platform DataOps dan MLOps terintegrasi di atas Kubernetes yang menyatukan komponen data dan model pada satu *control plane*. | IV.4 Perancangan Arsitektur Terintegrasi | V.2 Implementasi Arsitektur Terintegrasi | K1 |
| 2  | Tata kelola data sulit ditegakkan lintas siklus data–fitur–model sehingga *lineage*, kualitas, dan kepemilikan sulit ditelusuri. | Membangun *sub-sistem* tata kelola data (katalog, *lineage*, kualitas) yang berjalan otomatis di seluruh *pipeline*. | IV.5 *Sub-sistem* Tata Kelola Data | V.3 Implementasi *Sub-sistem* Tata Kelola | K2 |
| 3  | *Drift* data dan *concept drift* terjadi tanpa terdeteksi, sementara *feature serving* lintas mode *batch* dan *streaming* rentan terhadap kebocoran temporal (*temporal leakage*). | Mengimplementasikan mekanisme deteksi *drift* terotomasi dengan *retraining* berbasis kebijakan dan menjamin *point-in-time correctness* pada *feature serving*. | IV.6 *Sub-sistem* Deteksi *Drift* dan *Continuous Training* | V.4 Implementasi Deteksi *Drift* dan *Continuous Training* | K3 |
| 4  | Fitur multimodal (vektor berdimensi tinggi, fitur agregat, fitur waktu nyata) sulit dilayani konsisten dengan SLA berbeda dari satu sumber kebenaran. | Mengembangkan layanan fitur *dual-store* (*offline* + *online*) yang melayani *tabular feature* maupun *vector feature* melalui satu kontrak API. | IV.7 *Sub-sistem* Layanan Fitur *Dual-Store* | V.5 Implementasi Layanan Fitur *Dual-Store* | K4 |

Subbab pengikat berada di kepala dan ekor tiap bab dan tidak masuk ke dalam rantai 1-1 di atas, tetapi wajib ada. Di kepala: IV.1 (Gambaran Umum Platform) dan V.1 (Lingkungan Implementasi, termasuk V.1.1 Batasan Implementasi BI-1..BI-2) yang membuka konteks sebelum subbab rantai. Bab IV juga memuat dua subbab pendukung di luar rantai sesudah IV.1 (revisi 2026-07, alur layanan → alat → arsitektur): IV.2 Analisis Layanan DataOps dan MLOps pada Praktik Industri (`sec:layanan-industri`, klasifikasi sembilan kelompok layanan bersumber, tabel `layanan_industri`) dan IV.3 Analisis Pemilihan Open Source Tools (`sec:pemilihan-tools`, dipindah utuh dari Bab III karena pemilihan komponen adalah aktivitas perancangan DSRM, bukan analisis masalah). Di ekor: IV.8 (Alur Kerja *End-to-End*) yang menyatukan keempat sub-sistem menjadi satu siklus *after* sebagai pasangan dari diagram *before* pada Bab III, dan V.6 (Verifikasi Implementasi) yang menjembatani ke evaluasi kuantitatif pada Bab VI. Panduan rinci pada `WRITING_GUIDE.md` §3.2.

Aturan turunan:
1. Jumlah RM = jumlah T = jumlah subbab rantai Bab IV (di luar pengikat IV.1 dan IV.8 serta subbab pendukung IV.2 dan IV.3) = jumlah subbab rantai Bab V (di luar pengikat V.1 dan V.6) = jumlah poin Kesimpulan. Saat ini keempat angka tersebut bernilai 4, dengan rantai Bab IV menempati IV.4..IV.7.
2. Verba pada Tujuan tidak boleh berisi “mengevaluasi”, “menguji”, “mengukur”, atau “mendemonstrasikan”. Evaluasi adalah aktivitas metodologi, bukan tujuan.
3. Judul Bab IV menyebut nama artefak, bukan kata generik “Perancangan”. Judul yang digunakan: “Perancangan Arsitektur Platform DataOps dan MLOps”.
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

Catatan struktur (revisi 2026-07): Subbab I.4 hanya memuat batasan penelitian BP-1..BP-3 dengan enumerate polos bergaya Rumusan Masalah/Tujuan (tanpa judul tebal per butir), karena kontribusi utama Tugas Akhir adalah arsitektur yang dapat dipakai lintas *use case*. Batasan implementasi BI-1..BI-2 (lingkungan k3s satu node, patokan versi April 2026) dipindah ke Subbab V.1.1 Batasan Implementasi bersama lingkungan implementasi; paragraf penutup I.4 dan lead-in Bab I menunjuk ke Bab V untuk BI. Rujukan BI-x pada Bab II/III/VI/VII mengarah ke Bab~\ref{chap:implementasi}.

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

Catatan struktur (revisi 2026-06): Bab II tidak lagi memiliki subbab "Cakupan Studi Literatur". Cakupan ditulis sebagai 1–2 paragraf pembuka tanpa nomor langsung setelah judul bab, mengikuti aturan paragraf pembuka bab pada `WRITING_GUIDE.md` §3.8. Subbab pertama langsung masuk materi (DataOps dan MLOps). Aturan kedalaman subbab mengikuti `WRITING_GUIDE.md` §3.9 (revisi 2026-07): setiap subbab Bab II memiliki minimal dua sub-subbab bertopik KECUALI Penelitian Terkait yang dibiarkan datar, tiap sub-subbab minimal dua paragraf; aturan lama "subbab pendek dibiarkan tanpa pemecahan" tidak lagi berlaku untuk Bab II. Setiap subbab yang memiliki sub-subbab dibuka dengan satu paragraf pengantar singkat sebelum sub-subbab pertama, meniru pola proposal dan paragraf pembuka bab; kedalaman berhenti pada sub-subbab (tidak ada `\subsubsection`). Judul subbab 2.3 adalah "Manajemen Data: *Ingestion*, *Processing*, dan *Storage*" agar mencakup sub-subbab penyimpanan. Sejak revisi 2026-07, seluruh tabel perbandingan berskor berada pada Bab IV §IV.3 (Analisis Pemilihan Open Source Tools); Bab II hanya memperkenalkan konsep tiap *layer* dan menyebut kandidat alat sebagai contoh, sedangkan perbandingan berskor dan keputusan pemilihan berada di Bab IV. Legenda kematangan berada pada II.1.3: `tables/mlops_level_legend.tex` (karakteristik proses dan komponen MLOps level 0/1/2, googlecloud2024mlops) dan `tables/dataops_stage_legend.tex` (lima tahap model evolusi DataOps, munappy2020adhoc).

Catatan alur konsep-dahulu (revisi 2026-07): setiap subbab dan sub-subbab Bab II wajib membuka dengan paragraf konsep dari literatur dan baru menyebut alat *open source* sebagai contoh pada paragraf terakhirnya, karena pemilihan alat baru terjadi pada Bab IV §IV.3. Alur laporan tidak boleh terbaca seperti *reverse engineering*: Bab I gambaran umum tugas akhir, Bab II menjelaskan konsep per layanan dari literatur, Bab III memecah masalah per layanan, lalu Bab IV mengklasifikasikan layanan (§IV.2) dan membandingkan serta memilih alat per kelompok layanan (§IV.3) sebelum merancang arsitektur (§IV.4). Kalimat bergaya keputusan ("Pada platform ini, X dipakai") tidak boleh membuka unit Bab II; paragraf penutup memakai frasa contoh ("Contoh perwujudan *open source* ..."), dan detail operasional implementasi (mode autentikasi, topologi *topic*, tata letak *bucket*, dan sejenisnya) berada pada Bab V, bukan Bab II. Judul subbab Bab II memakai nama konsep, bukan nama alat: "*Message Broker* dan *Data Ingestion*" (bukan Apache Kafka), "*Stream Processing*" (bukan Apache Flink), "*Batch Processing* dan Transformasi SQL" (bukan Apache Spark dan dbt); label LaTeX (subsec:kafka, subsec:flink, subsec:spark) tidak diubah.

Catatan tabel perbandingan (revisi 2026-06, lokasi diperbarui 2026-07): seluruh tabel evaluasi alternatif pada Bab IV §IV.3 memakai skor 0–2 per kriteria (0 = tidak dipenuhi, 1 = parsial, 2 = penuh; Total maksimum 8) yang legendanya didefinisikan satu kali di awal §IV.3 (Bab IV) dan parameter penilaian per kriteria dirinci pada Lampiran A (`appx:rubrik`) yang dirujuk makro `\skorlegendtools` di bawah tiap tabel berskor, ditambah satu kolom tekstual **Lisensi (Yayasan)** di antara kriteria terakhir dan kolom Total, misalnya `Apache 2.0 (CNCF)`, `MPL 2.0 (LF)`, `BUSL 1.1 (mandiri)`. Kolom ini bersifat informasional sebagai bukti tata kelola *open source* (OSI + yayasan netral seperti ASF/CNCF/LF) dan tidak mengubah Total; `mandiri` berarti tanpa yayasan netral, `komunitas` khusus pgvector/PostgreSQL. Tata letak baku tujuh kolom (lebar, `\footnotesize`, `\tabcolsep`) didefinisikan pada `WRITING_GUIDE.md` §2.1 dan wajib identik di seluruh 24 tabel berskor (termasuk perbandingan distribusi Kubernetes, tabel berskor pertama pada §IV.3 yang didahului legenda rubrik).

### 3.1 Format Gambar, Tabel, Rumus, dan Kode Program

Gambar:
- Diletakkan di posisi `[t]` (top) atau `[b]` (bottom).
- Judul (caption) berada di bawah gambar, ditengahkan secara horizontal, huruf kecil kecuali huruf pertama.
- Nomor gambar tidak diakhiri tanda baca.
- Resolusi cukup tinggi; hindari *screenshot*; gunakan re-draw (draw.io, PowerPoint, Figma, Canva) dengan zoom ekspor ≥ 300%.
- Diagram arsitektur dikelola sebagai *diagram-as-code* di folder `diagrams/` (satu berkas `.eraser` per gambar, nama sama dengan PNG padanannya di `figures/`; lihat `diagrams/README.md` dan `WRITING_GUIDE.md` §1.7). Sumber kebenaran Gambar III.1 dan IV.1: `diagrams/Fragment_General_Arch.eraser` dan `diagrams/Integrate_General_Arch.eraser`. PNG tidak boleh diubah tanpa memperbarui berkas `.eraser` lebih dulu; render ulang manual di https://app.eraser.io lalu ekspor PNG menimpa berkas lama.
- Landasan kematangan diagram (revisi 2026-07): pasangan *before/after* diikat ke kerangka terbit yang sama dengan Subbab II.1.3 (`subsec:maturity`, berjudul "Tingkat Kematangan MLOps dan DataOps"). `Fragment_General_Arch` memuat grup penanda MLOps level 0 dari googlecloud2024mlops (proses manual berbasis skrip, model diserahkan satu arah, tanpa CI/CD, tanpa pemantauan kinerja aktif) ditambah tahap awal model evolusi DataOps dari munappy2020adhoc (silo data, pemantauan *pipeline* manual). `Integrate_General_Arch` memuat grup pemetaan MLOps level 2 (tujuh komponen wajib: *source control* Gitea, *test/build* Tekton, *deployment* Argo CD, *model registry* MLflow, *feature store* Feast, metadata ML MLflow+MLMD, orkestrator *pipeline* Kubeflow Pipelines) ditambah tahap DataOps (CI/CD data, orkestrasi, pengujian dan pemantauan berkelanjutan). Model evolusi DataOps lima tahap (ad hoc, semi-otomatis, *agile data science*, pengujian dan pemantauan berkelanjutan, DataOps) diperkenalkan pada paragraf penutup Subbab II.1.3. Caption Gambar III.1/IV.1 mengutip kedua sumber; perubahan pada salah satu dari tiga tampilan (berkas `.eraser`, caption, prosa Subbab II.1.3/III.1.3/IV.1) wajib disinkronkan ke dua lainnya.

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

(Disalin dari Bab_3.tex versi template + revisi 2026-05.)

Pembagian subbab tidak rigid. Bab III minimal berisi:

1. Analisis kebutuhan fungsional dan nonfungsional.
2. Analisis berbagai alternatif solusi yang dapat ditawarkan.
3. Metode pemilihan solusi yang diusulkan.

Struktur yang dipakai pada laporan ini (revisi 2026-05; subbab Beban Operasional sebelumnya dilebur menjadi sub-sub-subbab di dalam III.1 agar Analisis Masalah berfokus pada satu rantai tekanan yang sejalan dengan urutan pemicu pada Bab I Latar Belakang):

- III.1 Analisis Kondisi Saat Ini (tiga sumber tekanan yang diurutkan sesuai pemicu pada Bab I Latar Belakang).
  - III.1.1 Beban Konfigurasi Platform dari Nol (configure-from-0).
  - III.1.2 Biaya Berlangganan Layanan Terkelola (cloud subscription + trade-off waktu lawan anggaran).
  - III.1.3 Efek Domino Fragmentasi Lintas Peran (pandangan umum fragmentasi DataOps + MLOps; cukup pandangan umum pada Gambar III.1, tanpa rincian per peran, agar bab tetap ramping dan fragmentasi tetap menjadi tekanan ketiga yang lebih ringan).
- III.2 Analisis Kebutuhan (identifikasi masalah pengguna, kebutuhan fungsional KF-1..KF-n, kebutuhan nonfungsional KNF-1..KNF-n).
- III.3 Analisis Pemilihan Solusi (alternatif solusi, analisis penentuan solusi; menutup bab).
- (Analisis Pemilihan Open Source Tools dipindah ke Bab IV §IV.3 per revisi 2026-07: pemilihan komponen adalah aktivitas perancangan pada DSRM Design and Development, bukan analisis masalah, dan penilaiannya berpijak pada klasifikasi layanan IV.2.)

## 5. Bab IV Perancangan – Panduan Template Asli

(Disalin dari Bab_4.tex versi template + `WRITING_GUIDE.md` §3.2.)

Ilustrasikan desain konsep solusi dalam bentuk model konseptual beserta penjelasan ringkas. Ilustrasi harus dapat dibandingkan (*before* dan *after*) terhadap kondisi sistem saat ini yang digambar di awal Bab III.

Aturan WRITING_GUIDE.md §3.2 yang berlaku:
- Judul bab tidak boleh “Perancangan” saja; sebut nama artefak.
- IV.1 selalu “Gambaran Umum” dengan diagram sistem secara keseluruhan.
- Subbab rantai IV.4..IV.7 memetakan satu lawan satu dengan Tujuan T-1..T-4; IV.2 (analisis layanan industri) dan IV.3 (pemilihan alat) adalah subbab pendukung di luar rantai dengan alur layanan → alat → arsitektur.
- Pemetaan peran pengguna ke antarmuka (tabel `peran_akses`) ditempatkan di IV.1 Gambaran Umum sebagai orientasi “siapa yang memakai platform”, bukan sebagai subbab tersendiri di bawah IV.4. Keputusan ini menurunkan bingkai per-peran dari rancangan ke orientasi: IV.4 berisi murni rancangan tujuh *layer* (T-1), tanpa subbab “Pandangan per Peran”. Identitas/SSO bersama dijelaskan sekali di IV.5.3 (identitas-akses), tidak diulang di IV.1. Tidak ada gambar penuh-halaman per peran di Bab IV. Lampiran fragmentasi per peran (dahulu Lampiran C) telah dihapus karena tesis konsisten bersifat *layer-centric*: masalah dirumuskan sebagai kontrak antar *layer*, KF/KNF dipetakan ke *layer*, rancangan Bab IV memuat tujuh *layer*, dan diagram *after* terorganisasi per *layer*, sehingga diagram *before* per peran menjadi satu-satunya artefak yang terorganisasi per peran dan menimbulkan ketaksesuaian taksonomi *before*/*after* yang rawan dipersoalkan penguji. Pandangan umum fragmentasi (Gambar III.1) sudah memuat keempat peran dalam satu tampilan sehingga rincian per peran tidak diperlukan. Bingkai per-peran pada Bab III ditulis kebutuhan-dahulu (peran sebagai tempat kebutuhan paling terasa), bukan peran-dahulu.

Landasan tujuh *layer* (revisi 2026-07): pengelompokan tujuh *layer* pada IV.4 bukan taksonomi baru, melainkan penataan ulang dua rujukan terbit, yaitu enam kategori komponen arsitektur MLOps hasil pemetaan sistematis najafabadi2024analysis (*data curation*, *storage and versioning*, *ML training*, CI/CD, *inference*, *infrastructure and supporting services*, disintesis dari 35 komponen pada 43 studi primer) dan sembilan komponen teknis kreuzberger2023mlops. Dua penataan ulang dinyatakan eksplisit pada prosa IV.4: kategori *data curation* dipecah menjadi *Data Ingestion Layer* dan *Processing Layer* (jalur *batch*/*stream*), dan komponen pemantauan dipindah dari kategori *inference* menjadi *Governance and Observability Layer* yang ditambah katalog, *lineage*, serta kualitas data (tuntutan integrasi DataOps, munappy2020adhoc). Jangan pernah menyebut tujuh *layer* sebagai standar industri; selalu sebagai penataan komponen bersumber yang dapat dirunut. Berkas `.eraser` (Integrate_General_Arch + keempat Layer_*) membawa anotasi kategori sumber pada label tiap grup layer, dan caption Gambar IV.1 mengutip najafabadi2024analysis untuk anotasi tersebut; perubahan derivasi wajib disinkronkan ke label diagram (daftar lengkap pada `diagrams/README.md` aturan 6). Bukti komponen dari kreuzberger2023mlops, amershi2019software, najafabadi2024analysis (termasuk frekuensi kemunculan komponen pada 43 studi: model repository 21, ML metadata repository 15, ML experiment pipeline 14; tanpa klaim mayoritas mutlak), dan googlecloud2024mlops beserta sisi data munappy2020adhoc, rella2022mlops, dan jain2025integrating kini disajikan pada IV.2 (`sec:layanan-industri`, tabel `layanan_industri`); lead-in IV.3 merujuk klasifikasi tersebut, dan sembilan kelompok penilaian alat pada IV.3 dikonsolidasikan menjadi tujuh *layer* pada IV.4. Justifikasi cakupan *use case* menunjuk kesembilan kelompok itu pada Bab V (`sec:verifikasi`) dan Bab VI (`subsec:instans-verifikasi`). Abstrak menyebut ketujuh *layer* dengan nama yang sama persis dengan IV.4, dan judul Subbab IV.4.2 adalah "*Data Ingestion Layer*, *Processing Layer*, dan *Storage and Feature Store Layer*" (tiga *layer* yang dicakupnya, sama dengan caption Gambar fig:layer-data). Sejak register round 8: seluruh nama layer memakai bentuk English penuh dengan urutan English (Infrastructure Layer, Data Ingestion Layer, Processing Layer, Storage and Feature Store Layer, Model Lifecycle Layer, Model Serving Layer, Governance and Observability Layer; subbab Bab V khusus penyimpanan memakai Storage Layer), bidang kendali menjadi *control plane*, ingestasi menjadi *ingestion*/*data ingestion*, penyajian model menjadi *model serving*, siklus hidup model menjadi *model lifecycle*, pelatihan ulang menjadi *retraining*; padanan lengkap ada pada `WRITING_GUIDE.md` blok Round 8.

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

Catatan revisi 2026-07 (Bab VI): bab evaluasi diakhiri seksi Perbandingan
Biaya Infrastruktur dan Tenaga Kerja sebelum Pembahasan. Seksi ini memuat
tiga artefak berurutan: tabel biaya bulanan tiga skenario (VPS multi-penyedia,
GKE, layanan terkelola) dengan harga daftar per 16 Juni 2026 yang setiap
barisnya bercatatan sumber, tabel ilustrasi biaya tiga tahun yang
menggabungkan infrastruktur dan tenaga kerja (gaji acuan bersumber panduan
gaji terbit, kurs JISDOR, alokasi FTE dinyatakan sebagai asumsi), dan gambar
proyeksi biaya kumulatif tiga puluh enam bulan. Seluruh angka harus punya sumber
atau dinyatakan eksplisit sebagai asumsi; tidak ada angka tanpa baseline.

## 8. Bab VII Kesimpulan dan Saran – Panduan Template Asli

Template tidak menyertakan rincian; gunakan aturan `WRITING_GUIDE.md` §3.4:

- Kesimpulan menjawab Tujuan satu per satu, dengan urutan yang sama.
- Tidak menambahkan klaim baru yang belum muncul di bab sebelumnya.
- Saran berisi arah pengembangan lanjutan, terutama untuk tujuan-tujuan yang belum tertutup penuh oleh evaluasi awal.

## 9. Daftar Berkas Pendukung

- `WRITING_GUIDE.md` – pedoman gambar/tabel/struktur bab.
- `README.md` – konvensi struktur direktori dan penamaan berkas.
- `daftar-pustaka.bib` – daftar pustaka BibLaTeX.
- `figures/` – semua *figure* berformat PNG/JPG (hasil render saja).
- `diagrams/` – sumber *diagram-as-code* (`.eraser`) untuk semua bab; dirender manual ke PNG di `figures/`.
- `tables/` – tabel yang di-`\input` dari berkas utama.
- `listings/` – kode program panjang.
- `algorithms/` – pseudocode algoritma.

## 10. Catatan Pemeliharaan

Apabila rantai pada §1 berubah (mis. tujuan diperluas atau dipersempit), perbarui:

1. Tabel rantai di §1 dokumen ini.
2. Daftar subbab pada Bab I (Rumusan Masalah, Tujuan, Sistematika).
3. Daftar subbab pada Bab IV dan Bab V.
4. Poin Kesimpulan pada Bab VII.

Sinkronisasi rantai diperiksa setiap kali revisi besar selesai. Setelah revisi yang memindahkan atau menambah istilah, audit ulang Daftar Singkatan (`frontmatter/14_Daftar_Singkatan.tex`): hanya akronim yang benar-benar muncul pada Bab 1–7, urut alfabetis, kolom pemakaian pertama mengikuti bab kemunculan pertama (periksa dengan `grep` per akronim berurutan Bab 1 → 2 → 3 → 4 → 5 → 6 → 7; seluruh tabel perbandingan berskor di-`\input` di Bab IV §IV.3).
