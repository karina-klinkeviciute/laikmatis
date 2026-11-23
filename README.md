# Masažo laikmatis

„Flutter“ programėlė „Android“ ir „iPhone“ telefonams. Lietuviška sąsaja, 75 lietuviški garsiniai pranešimai, pabaigos melodija, „TalkBack“ ir „VoiceOver“ pritaikyti valdikliai.

| Pusė | Masažas | Trukmė | Pranešimai |
|---|---|---|---|
| Kairė | Vienas | 30 min. | Kas minutę |
| Kairė | Du | 30 min. | Kas 5 minutes |
| Dešinė | Vienas | 60 min. | Kas minutę |
| Dešinė | Du | 60 min. | Kas 5 minutes |

Pasirinkite masažą ir paspauskite **Pradėti**. Pirmas pranešimas apie likusį laiką skamba praėjus pasirinktam intervalui. Pabaigoje skamba trijų natų melodija ir „Masažas baigtas“. Galima pristabdyti, tęsti, sustabdyti ir paprašyti pasakyti likusį laiką. Vienu metu veikia viena sesija.

## Valdymas balsu

Paspauskite **Kalbėti** ir sakykite:

- „Kairė pusė, masažas vienas“ arba „Dešinė pusė, masažas du“.
- „Pradėti“, „Pristabdyti“, „Tęsti“, „Sustabdyti“.
- „Kiek liko laiko?“

Masažo pasirinkimas balsu jo automatiškai nepradeda: po pasirinkimo sakykite „Pradėti“. Mikrofonas įjungiamas tik klausantis komandos. Nuolatinio klausymosi bei pažadinimo žodžio nėra. „Kalbėti“ naudojama atidarius programėlę; užrakintame ekrane pasiekiami sistemos laikmačio / garso valdikliai.

Kalbą atpažįsta telefono paslaugos. Joms gali reikėti interneto ir jos gali apdoroti balsą paslaugos teikėjo serveriuose. **Lietuviškų komandų palaikymas priklauso nuo konkretaus telefono, sistemos ir kalbos paslaugų.** Jei lietuvių kalba nepalaikoma, programėlė tai paaiškina; lieka mygtukai ir ekrano skaitytuvas.

Įgarsinti laiko pranešimai veikia be interneto ir be telefone įdiegto lietuviško sintezatoriaus. Įrašai sukurti šiame kompiuteryje įdiegtu „Regina“ balsu; pats sintezatorius ir jo duomenys neplatinami. Prieš naudojimą patikrinkite medijos garso stiprumą mygtuku **Pasakyti likusį laiką** jau pradėjus masažą.

## Veikimas užrakintame ekrane

**Android 8.0+.** Vietinė `mediaPlayback` foninė tarnyba su sistemos pranešimu valdo laiką ir garsą. Naudojamas monotoniškas laikrodis ir ribotos trukmės dalinis budrumo užraktas. Pristabdžius arba užbaigus masažą užraktas atleidžiamas. Pirmą kartą prašoma leisti pranešimus ir veikimą be baterijos taupymo apribojimų. Be pastarojo leidimo laikmatis nepradedamas, nes „Doze“ gali uždelsti minutinius pranešimus. Kai kuriuose telefonuose papildomai reikia gamintojo nustatymo „Veikimas fone / Be apribojimų“.

**iOS 15+.** Iš įgarsintų pranešimų paruošiamas vienas M4A masažo garso takelis su tiksliose vietose įterptais pranešimais ir melodija. Jį leidžia `AVAudioPlayer` su fono garso režimu. Pirmą kartą paruošiant pasirinkimą laikykite programėlę atidarytą ir palaukite „Masažas vyksta“. Takelis išsaugomas kitam kartui. Užrakinto ekrano garso valdikliais galima pristabdyti ir tęsti. Kalbant komandą garsas trumpam pristabdomas, o grįžus pozicija paslenkama pagal tikrą praėjusį laiką.

„iPhone“ skambutis arba atjungtos ausinės pristabdo sesiją; ją tęskite patys. Priverstinai nutraukus programėlę ar išjungus telefoną garsas tęstis negali. „Android“ atkuria sesiją, jei sistema iš naujo paleidžia tarnybą; po telefono perkrovimo ji atšaukiama. „iPhone“ po programėlės nutrūkimo siūlo tęsti paskutinę išsaugotą poziciją pristabdžius.

## Paleidimas kūrėjai

### Codemagic nemokama asmeninė paskyra

Įtrauktas `codemagic.yaml`: darbo eiga **iPhone – surinkimas be Apple narystės** naudoja `mac_mini_m2` ir paleidžiama rankiniu būdu. Įkelkite šio aplanko turinį į savo GitHub / GitLab / Bitbucket saugyklos šaknį ir prijunkite ją „Codemagic“. Pasirinkite YAML konfigūraciją ir darbo eigą `ios-unsigned`, tada **Start new build**.

Sėkmingai surinkus, skiltyje **Artifacts** bus `Masazo-laikmatis-nepasirasyta.ipa`. Tai nepasirašytas failas: jo negalima tiesiog atidaryti ir įdiegti „iPhone“. Asmeniniam bandymui jį dar reikia pasirašyti, pavyzdžiui, per „AltStore Classic“ su „Windows“; šis diegimo kelias projektui dar neišbandytas. „TestFlight“ naudojimui reikės mokamos „Apple Developer“ narystės ir atskiro pasirašymo nustatymo. Ši darbo eiga paskyrų duomenų neprašo ir nieko parduotuvėse neskelbia.

Nemokamos „Codemagic“ minutės skiriamos asmeninėms paskyroms pagal dabartines paslaugos sąlygas. Prieš paleidžiant patikrinkite savo paskyros minučių likutį. Nuotolinis surinkimas šiame projekte dar nepaleistas.

Paruošta su **Flutter 3.50.1 / Dart 3.14.0**. Reikalinga ši arba naujesnė suderinama „Flutter“ versija; naudojamas atskiras `material_ui` paketas. Įtrauktas `pubspec.lock`.

```sh
flutter pub get
flutter run
```

„Android“ surinkimui reikia Android SDK ir JDK 21:

```sh
flutter build apk --debug
# Mažesniam optimizuotam bandomajam failui:
flutter build apk --release
```

`release` konfigūracija kol kas naudoja bandomąjį `debug` pasirašymą. Prieš platinimą „Google Play“ nustatykite savo pasirašymo raktą ir patikrinkite foninio garso bei baterijos leidimų deklaracijas.

„iPhone“ surinkimui reikia **Mac, Xcode ir Apple pasirašymo komandos**. Atidarykite `ios/Runner.xcworkspace`, pasirinkite savo „Team“ bei unikalų identifikatorių. Fono `audio` režimas ir mikrofono / kalbos atpažinimo leidimų tekstai įtraukti.

```sh
flutter pub get
flutter run -d <iphone-id>
# Platinimui su tinkamu pasirašymu:
flutter build ipa
```

„App Store“ peržiūrai paaiškinkite, kad masažo garsiniai pranešimai yra pagrindinė fone leidžiamo garso takelio funkcija. Parduotuvėse programėlė nepaskelbta.

## Patikra

```sh
flutter analyze
flutter test
# Android aplanke:
./gradlew :app:testDebugUnitTest
```

„Flutter“ testai tikrina komandas, dviprasmiškų pasirinkimų atmetimą, keturių pasirinkimų prieinamumą, pradėjimą / pauzę / tęsimą / sustabdymą ir didelį tekstą siaurame ekrane. „Android“ testai tikrina visų intervalų ribas, vienkartinę pabaigą, pauzę, uždelstą patikrą ir lietuvišką gramatiką.

**„iOS“ kodas šioje „Windows“ aplinkoje nesurinktas ir nevykdytas.** Būtinas surinkimas „Mac“ ir abiejų platformų tikrų telefonų bandymai: visas 30 / 60 min. seansas užrakintu ekranu, kita programėlė, ekrano skaitytuvas, Bluetooth, skambučiai, leidimų atmetimas, pabaigos melodija. „Android“ papildomai patikrinkite „Doze“.

Techninės nuorodos: [Android Doze](https://developer.android.com/training/monitoring-device-state/doze-standby), [Android foninės tarnybos](https://developer.android.com/develop/background-work/services/fgs/service-types), [Apple foninis garsas](https://developer.apple.com/documentation/AVFAudio/AVAudioSession/Category-swift.struct/playback).
