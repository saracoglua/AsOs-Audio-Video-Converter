## 📝 Geliştirici Notu & Açık Kaynak Daveti
> **Selamlar!** Bu proje benim **ilk açık kaynak geliştirme projemdir.** >
Bu proje, asıl mesleği profesyonel yazılım geliştiricilik/mühendislik olan değerli üstadların ve arkadaşların affına sığınarak tamamen deneme, pratik yapma ve günlük işleri kolaylaştırma amacıyla geliştirilmiştir. 
> 
> Projenin arkasında devasa bir C# (.NET), Python veya C++ mimarisi **yoktur.** Bu araç, doğası gereği aslında bir script dili olan **PowerShell** mimarisi ve temel WinForms kütüphanesi kullanılarak en basit ve yalın yapıda ayağa kaldırılmıştır. Dolayısıyla kod organizasyonu, performans optimizasyonları veya arayüz tasarımı açısından profesyonel yazılım standartlarına göre eksikleri, kusurları veya "daha jilet gibi yapılabilir" denilecek yüzlerce noktası olabilir. Haddimi bilerek, bunun ticari ya da kusursuz bir yazılım iddiası olmadığını en baştan belirtmek isterim.
>
> > Kodlar tamamen **açık kaynaklı ve özgürdür.** Projeyi geliştirmek, hataları düzeltmek, kendi ihtiyaçlarınıza göre eğip bükmek veya 
> arayüze yeni özellikler eklemek konusunda **tamamen özgürsünüz.**

# 🎬 🖼️ Asos Converter V2.0

Asos Converter, bilgisayarınızdaki video, ses ve fotoğraf dosyalarını toplu olarak işlemek, boyutlandırmak ve formatlarını değiştirmek amacıyla PowerShell GUI mimarisiyle geliştirilmiş gelişmiş bir açık kaynak stüdyo aracıdır.

---

## 📌 1. Program Nedir ve Ne İşe Yarar?
Asos Converter V2.0, iki ana temel motor üzerine inşa edilmiştir:
1. **Medya Motoru (FFmpeg):** Videoları dönüştürür, boyutlandırır veya seslerini ayırır.
2. **Görsel Motoru (System.Drawing):** Fotoğrafları en-boy oranını bozmadan milimetrik olarak yeniden boyutlandırır, kalitesini ayarlar ve baskı çözünürlüklerini (DPI) değiştirir.

Klasör içindeki yüzlerce dosyayı **TEK TIKLA** bulup, alt klasörleriyle birlikte tarayarak toplu işlem gerçekleştirebilir.

---

## 🎮 2. Ekran Yapısı ve Arayüz Elemanları

### A) Çalışma Modu Seçici (En Üst Alan)
* Buradan programı hangi modda kullanacağınızı seçersiniz: `🎬 VİDEO & SES İŞLEME` veya `🖼️ FOTOĞRAF BOYUTLANDIRMA & DPI`.
* Sisteminizde FFmpeg yüklü değilse, bu alanda **⚙️ FFmpeg Kur** butonu belirir. Bu butona tıklayarak video motorunu tek tıkla otomatik olarak bilgisayarınıza kurabilirsiniz.

### B) Taranacak Formatlar (Sol Liste Paneli)
* Seçtiğiniz kaynak klasör içerisinde "yalnızca hangi uzantıya sahip dosyaların" işleme alınacağını belirler. 
* "Tümünü Seç" ve "Temizle" butonları ile hızlıca seçim yapabilirsiniz.

### C) Klasör Seçimleri (Üst/Orta Alan)
* **Kaynak Giriş Klasörü (X):** İşlenecek orijinal dosyalarınızın bulunduğu klasördür.
* **Hedef Çıktı Klasörü (Y):** İşlem bittikten sonra yeni dosyaların kaydedileceği klasördür.

### D) Canlı Log Akış Paneli (En Alt Siyah Alan)
* Programın o an ne yaptığını, hangi dosyayı işlediğini milisaniyelik olarak yeşil yazılarla canlı gösterir.

---

## 🎬 3. Video & Ses İşleme Modu Nasıl Çalışır?

1. **Yapılacak İşlem (Mod):**
   * `donustur`: Videolarınızın formatını kalitesini bozmadan değiştirir (Örn: AVI -> MP4).
   * `cozunurluk`: Videolarınızı belirlediğiniz standart bir boyuta (1080p, 720p vb.) getirir.
   * `sesayir`: Videonun içindeki görüntüyü atar, sadece içindeki ses müziğini koparıp alır.
   * `sesdonustur`: Doğrudan ses dosyalarının (MP3, WAV vb.) formatını değiştirir.

2. **Donanım Motoru Seçimi (GPU Hızlandırma):**
   * Program açılırken ekran kartınızı otomatik analiz eder. 
   * **NVIDIA NVENC / INTEL QSV / AMD AMF:** Dönüştürme işlemini ekran kartı çipine yaptırarak işlemleri **5 ila 10 kat daha HIZLI** bitirir.
   * **Standart CPU (libx264):** İşlemciyi tam yükte çalıştırır ancak dosya boyutunu en küçük seviyeye sıkıştırır.

3. **Kritik Strateji Kutucukları:**
   * **"Zaten hedef formatta olan dosyaları atla":** Hedef formatla aynı olan dosyaları pas geçerek zaman kazandırır.
   * **"Aynı klasöre kaydet (X dizini)":** İşaretlendiğinde Hedef Klasör alanı kilitlenir ve yeni dosyalar kaynak dosyanın tam yanına kaydedilir.
   * **"İşlem bittiğinde orijinal kaynak dosyayı sil":** İşlemi başarıyla tamamlanan orijinal eski dosyayı diskten kalıcı olarak siler.

---

## 🖼️ 4. Fotoğraf Boyutlandırma & DPI Modu Nasıl Çalışır?

1. **Akıllı Boyutlandırma Algoritması (En-Boy Oranı Koruma):**
   * **Yatay Foto Genişlik px:** Fotoğraf YATAY ise, bu piksel değerini genişlik kabul eder ve yüksekliği otomatik ayarlar.
   * **Dikey Foto Yükseklik px:** Fotoğraf DİKEY ise, bu değeri yükseklik kabul eder ve genişliği otomatik ölçekler.
   * Fotoğraflarınız asla basık veya esnemiş görünmez.

2. **JPEG Kalite (1-100):**
   * `80` değeri, gözle görülür hiçbir kalite kaybı yaratmadan dosya boyutunu muazzam derecede düşüren en ideal dengedir.

3. **Gelişmiş Fotoğraf Seçenekleri:**
   * **Fotoğraf Çözünürlüğünü Sabitle (DPI Değiştir):** Matbaa veya dijital baskı makineleri için inç başına düşen nokta yoğunluğunu (Örn: 300 DPI) ayarlar.
   * **Tüm Formatları Doğrudan JPEG (.jpg) Formatına Zorla:** Klasördeki tüm PNG, BMP, GIF dosyalarını tek tıkla `.jpg` formatına dönüştürür.

---

## 🚀 5. Adım Adım İşlem Başlatma Rehberi

1. En üstten **Çalışma Modunu** seçin.
2. **Gözat...** butonunu kullanarak **Kaynak** klasörünüzü seçin.
3. Sol listeden taranmasını istediğiniz dosya uzantılarını işaretleyin.
4. Sağ alttaki büyük yeşil **⚡ STÜDYO İŞLEMİNİ BAŞLAT ⚡** butonuna basın.

---

## 📄 Lisans
Bu proje [MIT Lisansı](LICENSE) altında lisanslanmıştır. İstediğiniz gibi geliştirebilir, değiştirebilir ve kendi projelerinizde kullanabilirsiniz.
